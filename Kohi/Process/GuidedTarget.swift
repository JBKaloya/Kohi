import Foundation

/// Instantaneous mass target inside a pour: where the scale should read now.
nonisolated enum GuidedTarget {
    /// `now = start + (target − start) × (t − tStart) / (tTarget − tStart)`.
    static func massNow(
        startMass: Double,
        targetMass: Double,
        startTime: Double,
        targetTime: Double,
        at time: Double
    ) -> Double {
        let span = targetTime - startTime
        guard span > 0 else { return time >= targetTime ? targetMass : startMass }
        let t = min(max(time, startTime), targetTime)
        return startMass + (targetMass - startMass) * (t - startTime) / span
    }

    /// Previous pour's target mass, or zero at the first pour.
    static func startMass(for steps: [RecipeStep], at index: Int) -> Double {
        steps.prefix(index).reversed().first { $0.action != .rinse && $0.targetMass != nil }?.targetMass ?? 0
    }

    /// When this step should be done: `untilSeconds`, else the next step's `at`.
    static func targetTime(for steps: [RecipeStep], at index: Int, total: Int?) -> Double {
        let step = steps[index]
        if let until = step.untilSeconds { return Double(until) }
        if index + 1 < steps.count { return Double(steps[index + 1].at) }
        if let total { return Double(total) }
        return Double(step.at)
    }

    /// Scale reading for the tide: interpolates during a pour, holds on wait.
    static func currentMass(
        steps: [RecipeStep],
        index: Int,
        elapsed: Double,
        total: Int?
    ) -> Double {
        guard !steps.isEmpty else { return 0 }
        if index >= steps.count { return finalMass(steps: steps, water: nil) }
        if steps[index].action == .rinse { return 0 }
        let start = startMass(for: steps, at: index)
        guard let target = steps[index].targetMass else { return start }
        return massNow(
            startMass: start,
            targetMass: target,
            startTime: Double(steps[index].at),
            targetTime: targetTime(for: steps, at: index, total: total),
            at: elapsed
        )
    }

    static func finalMass(steps: [RecipeStep], water: Double?) -> Double {
        if let last = steps.reversed().first(where: { $0.action != .rinse })?.targetMass, last > 0 {
            return last
        }
        return water ?? 0
    }

    /// 0…1 of the cup. Never goes backwards: wait / drawdown / stir hold.
    static func fill(
        steps: [RecipeStep],
        index: Int,
        elapsed: Double,
        total: Int?,
        water: Double?
    ) -> Double {
        let end = finalMass(steps: steps, water: water)
        guard end > 0 else { return 0 }
        let now = currentMass(steps: steps, index: index, elapsed: elapsed, total: total)
        return min(max(now / end, 0), 1)
    }

    static func showsTide(_ method: BrewMethod?) -> Bool {
        switch method {
        case .v60, .filter, .aeropress, .frenchPress: true
        case .espresso, .moka, .coldBrew, .none: false
        }
    }

    static func showsRings(_ method: BrewMethod?) -> Bool {
        method == .v60
    }

    /// 0, 1 or 2 for the V60 circles. Holds on a non-pour step.
    static func activeRing(steps: [RecipeStep], index: Int) -> Int? {
        var rank = 0
        var last: Int?
        let lastIndex = min(max(index, 0), max(steps.count - 1, 0))
        for (offset, step) in steps.enumerated() {
            if offset > lastIndex { break }
            if isPour(step) {
                last = min(rank, 2)
                rank += 1
            }
        }
        return last
    }

    static func isPour(_ step: RecipeStep) -> Bool {
        step.targetMass != nil && (step.action == .bloom || step.action == .pour)
    }
}
