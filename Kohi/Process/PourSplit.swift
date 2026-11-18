import Foundation

/// The water of a recipe read as services, each a part of the total.
///
/// The cumulative masses on the steps stay the only record — they are what
/// the scale reads. Parts are read off them and written back to them, never
/// stored, so a rescale keeps them and nothing new has to sync.
nonisolated enum PourSplit {
    struct Service: Equatable, Sendable {
        let stepID: UUID
        let action: StepAction
        /// Water this step adds.
        let grams: Double
        /// Part of the water being split, 0...1.
        let share: Double
    }

    struct Split: Equatable, Sendable {
        /// The services the parts are shared between.
        let services: [Service]
        /// The bloom when it is left out of the parts. Its grams come first.
        let bloom: Service?
        /// The water the parts are a share of: the total, less a bloom left out.
        let base: Double
        let total: Double

        var percents: [Int] { PourSplit.percents(of: services.map(\.share)) }
    }

    static let serviceRange = 2...5
    static let countsBloomKey = "kohi.recipes.splitCountsBloom"

    /// Steps that put water on the coffee. A rinse wets the paper, not the bed.
    static func carriesWater(_ action: StepAction) -> Bool {
        action == .bloom || action == .pour || action == .fill
    }

    // MARK: - Ratio

    static func water(dose: Double, ratio: Double) -> Double? {
        guard dose > 0, ratio > 0 else { return nil }
        return RecipeScaling.roundHalf(dose * ratio)
    }

    static func ratio(dose: Double?, water: Double?) -> Double? {
        guard let dose, dose > 0, let water, water > 0 else { return nil }
        return (water / dose * 10).rounded() / 10
    }

    // MARK: - Reading

    static func isSplittable(_ recipe: Recipe) -> Bool {
        guard recipe.method != .espresso, let total = RecipeScaling.liquid(of: recipe) else { return false }
        let all = services(in: recipe.steps)
        return all.count >= serviceRange.lowerBound && total > 0
    }

    static func split(of recipe: Recipe, countsBloom: Bool) -> Split? {
        guard let total = RecipeScaling.liquid(of: recipe) else { return nil }
        return split(steps: recipe.steps, total: total, countsBloom: countsBloom)
    }

    static func split(steps: [RecipeStep], total: Double, countsBloom: Bool) -> Split? {
        let all = services(in: steps)
        guard all.count >= serviceRange.lowerBound, total > 0 else { return nil }
        var bloom: (UUID, StepAction, Double)?
        var shared = all
        if !countsBloom, let first = all.first, first.1 == .bloom {
            bloom = first
            shared.removeFirst()
        }
        let base = total - (bloom?.2 ?? 0)
        guard base > 0, !shared.isEmpty else { return nil }
        return Split(
            services: shared.map { Service(stepID: $0.0, action: $0.1, grams: $0.2, share: $0.2 / base) },
            bloom: bloom.map { Service(stepID: $0.0, action: $0.1, grams: $0.2, share: $0.2 / total) },
            base: base,
            total: total
        )
    }

    /// Water each carrying step adds, in the order the steps run.
    private static func services(in steps: [RecipeStep]) -> [(UUID, StepAction, Double)] {
        var reached = 0.0
        var out: [(UUID, StepAction, Double)] = []
        for step in inTimeOrder(steps) where carriesWater(step.action) {
            guard let mass = step.targetMass else { continue }
            out.append((step.id, step.action, max(mass - reached, 0)))
            reached = max(reached, mass)
        }
        return out
    }

    /// The water the steps themselves reach, whatever the total says.
    static func reached(_ steps: [RecipeStep]) -> Double {
        services(in: steps).reduce(0) { $0 + $1.2 }
    }

    /// The steps as they run: by time, ties in list order. The list is only
    /// sorted on Save, so a step moved with the chevrons is read here.
    static func inTimeOrder(_ steps: [RecipeStep]) -> [RecipeStep] {
        steps.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
    }

    /// Whole percents that add up to 100: the last one takes what rounding
    /// left, and never reads below zero.
    static func percents(of shares: [Double]) -> [Int] {
        guard !shares.isEmpty else { return [] }
        var out = shares.dropLast().map { max(Int(($0 * 100).rounded()), 0) }
        out.append(max(100 - out.reduce(0, +), 0))
        return out
    }

    // MARK: - Writing

    /// Writes parts back as cumulative masses. Every service but the last
    /// gets its part, rounded to the half gram; the last takes the rest, so
    /// the sequence always ends on the total.
    static func applying(shares: [Double], to steps: [RecipeStep], total: Double, countsBloom: Bool) -> [RecipeStep] {
        guard let current = split(steps: steps, total: total, countsBloom: countsBloom),
              shares.count == current.services.count
        else { return steps }
        var grams = shares.dropLast().map { RecipeScaling.roundHalf(current.base * max($0, 0)) }
        grams.append(max(current.base - grams.reduce(0, +), 0))
        var added: [UUID: Double] = [:]
        for (service, value) in zip(current.services, grams) { added[service.stepID] = value }
        if let bloom = current.bloom { added[bloom.stepID] = bloom.grams }

        var cumulative: [UUID: Double] = [:]
        var reached = 0.0
        for step in inTimeOrder(steps) {
            guard let value = added[step.id] else { continue }
            reached += value
            cumulative[step.id] = reached
        }
        return steps.map { step in
            guard let mass = cumulative[step.id] else { return step }
            var next = step
            next.targetMass = mass
            return next
        }
    }

    /// The water changed: the parts hold and the grams follow, a bloom left
    /// out of the parts included. Measured from what the steps reach, so a
    /// sequence that had drifted from its total comes back to it.
    static func resizing(_ steps: [RecipeStep], to total: Double, shares: [Double]?, countsBloom: Bool) -> [RecipeStep] {
        guard total > 0 else { return steps }
        var next = steps
        let current = reached(steps)
        if current > 0, RecipeScaling.factorBounds.contains(total / current) {
            next = RecipeScaling.scalingSteps(steps, by: total / current)
        }
        guard let shares else { return next }
        return applying(shares: shares, to: next, total: total, countsBloom: countsBloom)
    }

    /// One part changed. The last service is the rest, so it moves; a part
    /// asking for more than there is gets what is left.
    static func setting(share: Double, at index: Int, in shares: [Double]) -> [Double] {
        guard shares.count >= 2, index >= 0, index < shares.count - 1 else { return shares }
        var next = shares
        let others = next.enumerated()
            .filter { $0.offset != index && $0.offset != next.count - 1 }
            .map(\.element)
            .reduce(0, +)
        next[index] = min(max(share, 0), max(1 - others, 0))
        next[next.count - 1] = max(1 - next.dropLast().reduce(0, +), 0)
        return next
    }

    // MARK: - A new sequence

    /// A fresh pour-over sequence for `count` services. A bloom at twice the
    /// dose opens it; the rest of the water is shared evenly between the
    /// pours. Times follow the default sequence's spread.
    static func steps(
        dose: Double?,
        water: Double,
        count: Int,
        countsBloom: Bool,
        targetTime: Int?
    ) -> [RecipeStep] {
        let count = min(max(count, serviceRange.lowerBound), serviceRange.upperBound)
        let dose = dose ?? RecipeCreation.blankDose
        let total = targetTime ?? max(180, Int((water / 250 * 180).rounded()))
        let bloomMass = RecipeScaling.roundHalf(min(water, dose * 2))
        let bloomEnd = 45
        let pours = countsBloom ? count - 1 : count
        let lastEnd = max(bloomEnd + 15 * pours, Int(Double(total) * 0.8))
        let window = Double(lastEnd - bloomEnd) / Double(max(pours, 1))

        var steps = [RecipeStep(at: 0, action: .bloom, targetMass: bloomMass, untilSeconds: bloomEnd, derived: true)]
        let rest = water - bloomMass
        var reached = bloomMass
        for index in 0..<pours {
            let start = bloomEnd + Int((Double(index) * window).rounded())
            let end = start + max(10, Int((window * 0.6).rounded()))
            let isLast = index == pours - 1
            reached = isLast ? water : reached + RecipeScaling.roundHalf(rest / Double(pours))
            steps.append(RecipeStep(at: start, action: .pour, targetMass: reached, untilSeconds: end, derived: true))
        }
        steps.append(RecipeStep(at: total, action: .wait, note: "Drawdown", derived: true))
        return steps
    }

    /// The number of services changed on a sequence already written. Only
    /// the pours move: waits, notes and the bloom as it was written stay.
    /// Pours kept keep their times; new ones follow the last. The rest of
    /// the water is shared evenly, as on a fresh sequence.
    static func restructuring(
        _ steps: [RecipeStep],
        dose: Double?,
        water: Double,
        count: Int,
        countsBloom: Bool,
        targetTime: Int?
    ) -> [RecipeStep] {
        let count = min(max(count, serviceRange.lowerBound), serviceRange.upperBound)
        let ordered = inTimeOrder(steps.filter { $0.action != .rinse })
        let others = ordered.filter { !carriesWater($0.action) }
        let existingBloom = ordered.first { $0.action == .bloom }
        let pours = ordered.filter { carriesWater($0.action) && $0.action != .bloom }
        guard existingBloom != nil || !pours.isEmpty else {
            let fresh = self.steps(dose: dose, water: water, count: count, countsBloom: countsBloom, targetTime: targetTime)
            return others.isEmpty ? fresh : inTimeOrder(others + fresh.filter { carriesWater($0.action) })
        }

        let dose = dose ?? RecipeCreation.blankDose
        let bloomEnd = 45
        var bloom = existingBloom
            ?? RecipeStep(at: 0, action: .bloom, untilSeconds: bloomEnd, derived: true)
        let bloomMass = RecipeScaling.roundHalf(min(bloom.targetMass ?? dose * 2, water))
        bloom.targetMass = bloomMass

        let wanted = countsBloom ? count - 1 : count
        var kept = Array(pours.prefix(wanted))
        if existingBloom == nil, let first = kept.first, first.at < bloomEnd {
            let shift = bloomEnd - first.at
            for index in kept.indices {
                kept[index].at += shift
                kept[index].untilSeconds = kept[index].untilSeconds.map { $0 + shift }
            }
        }
        var lastEnd = kept.last.map { $0.untilSeconds ?? $0.at } ?? (bloom.untilSeconds ?? bloomEnd)
        while kept.count < wanted {
            let start = lastEnd + 10
            kept.append(RecipeStep(at: start, action: .pour, untilSeconds: start + 20, derived: true))
            lastEnd = start + 20
        }
        let rest = water - bloomMass
        var reached = bloomMass
        for index in kept.indices {
            let isLast = index == kept.count - 1
            reached = isLast ? water : reached + RecipeScaling.roundHalf(rest / Double(kept.count))
            kept[index].targetMass = reached
        }
        return inTimeOrder([bloom] + kept + others)
    }
}
