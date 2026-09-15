import Foundation

/// Something the archive says about itself, or the reason it cannot say it yet.
///
/// The second half is the point. Three brews is not a trend, and an insight
/// that fires on one data point teaches you to distrust the section. So an
/// insight below its threshold is still rendered — as a count of what is
/// missing, which is both honest and a reason to log the next one.
nonisolated struct Insight: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case bestBrew
        case sweetSpot
        case water
        case trend

        var title: String {
            switch self {
            case .bestBrew: "Best brew"
            case .sweetSpot: "Your sweet spot"
            case .water: "Water"
            case .trend: "Trend"
            }
        }
    }

    var id: String { kind.rawValue + scope }

    var kind: Kind
    /// What it is about: a coffee's name, a grinder and method, a process.
    var scope: String
    /// The finding, in one line. Empty when the threshold is not met.
    var finding: String
    /// The parameters behind it, for the second line.
    var detail: String
    /// How many comparable brews it rests on.
    var sampleSize: Int
    /// How many it needs.
    var threshold: Int

    var isReady: Bool { sampleSize >= threshold }

    /// What to show when it is not ready. Names the gap rather than hiding.
    var waiting: String {
        let missing = threshold - sampleSize
        let plural = missing == 1 ? "brew" : "brews"
        return "\(missing) more \(plural) and this can be answered"
    }
}

/// A pure function from the archive to what can be said about it.
///
/// No network, no model, no stored state: it recomputes from the brews every
/// time, which is what lets it be tested exhaustively and what stops an
/// insight going stale behind your back. If it ever needs a server, the
/// feature was wrong.
nonisolated enum InsightsEngine {
    /// Three brews of the same thing before anything is claimed. Low enough to
    /// be reachable in a fortnight, high enough that one lucky cup does not
    /// become a finding.
    static let minimumSample = 3

    static func insights(
        for cards: [CoffeeCard],
        equipment: [Equipment] = [],
        water: [WaterProfile] = []
    ) -> [Insight] {
        [
            bestBrew(in: cards),
            sweetSpot(in: cards, equipment: equipment),
            waterInsight(in: cards, profiles: water),
            trend(in: cards),
        ].compactMap(\.self)
    }

    // MARK: - Best brew

    /// The best-rated brew across the archive, and what it was.
    ///
    /// Scoped to one coffee, because "the best brew you ever made" across
    /// different beans compares nothing. The threshold counts brews of that
    /// same coffee: a 5 out of 5 on a coffee brewed once says only that you
    /// liked it.
    static func bestBrew(in cards: [CoffeeCard]) -> Insight? {
        let rated = cards.compactMap { card -> (CoffeeCard, Brew)? in
            guard let best = card.brews
                .filter({ $0.rating != nil })
                .max(by: { ($0.rating ?? 0, $0.date) < ($1.rating ?? 0, $1.date) })
            else { return nil }
            return (card, best)
        }

        guard let (card, brew) = rated.max(by: { lhs, rhs in
            (lhs.1.rating ?? 0, lhs.0.brews.count) < (rhs.1.rating ?? 0, rhs.0.brews.count)
        }) else { return nil }

        let comparable = card.brews.filter { $0.rating != nil }.count

        return Insight(
            kind: .bestBrew,
            scope: card.name,
            finding: comparable >= minimumSample ? card.name : "",
            detail: comparable >= minimumSample ? brew.recipeLine : "",
            sampleSize: comparable,
            threshold: minimumSample
        )
    }

    // MARK: - Sweet spot

    /// The best-rated grind setting, per grinder and method.
    ///
    /// The median rather than the mean, so one distracted Tuesday does not
    /// move the answer. A setting brewed once has a median too — hence the
    /// threshold on top.
    static func sweetSpot(in cards: [CoffeeCard], equipment: [Equipment]) -> Insight? {
        struct Key: Hashable {
            let grinder: UUID?
            let method: BrewMethod
            let setting: Double
        }

        var ratings: [Key: [Int]] = [:]
        for card in cards {
            for brew in card.brews {
                guard let rating = brew.rating,
                      let method = brew.method,
                      let setting = BrewDiagnosis.setting(in: brew.grind)
                else { continue }
                let grinder = brew.equipmentIDs.first { id in
                    equipment.first { $0.id == id }?.kind == .grinder
                }
                ratings[Key(grinder: grinder, method: method, setting: setting), default: []]
                    .append(rating)
            }
        }
        guard !ratings.isEmpty else { return nil }

        // Group by grinder and method: the sweet spot is a setting within one
        // pairing, and the count that matters is how many settings were tried
        // for it. One setting tried five times is not a spot, it is a habit.
        struct Pairing: Hashable {
            let grinder: UUID?
            let method: BrewMethod
        }
        var byPairing: [Pairing: [(setting: Double, median: Double, count: Int)]] = [:]
        for (key, values) in ratings {
            byPairing[Pairing(grinder: key.grinder, method: key.method), default: []]
                .append((key.setting, median(values), values.count))
        }

        guard let (pairing, settings) = byPairing.max(by: { lhs, rhs in
            (lhs.value.count, lhs.value.map(\.count).reduce(0, +))
                < (rhs.value.count, rhs.value.map(\.count).reduce(0, +))
        }), let best = settings.max(by: { ($0.median, Double($0.count)) < ($1.median, Double($1.count)) })
        else { return nil }

        let grinderName = pairing.grinder
            .flatMap { id in equipment.first { $0.id == id } }?
            .displayName ?? "your grinder"
        let scope = "\(grinderName) · \(pairing.method.label)"
        let tried = settings.count

        return Insight(
            kind: .sweetSpot,
            scope: scope,
            finding: tried >= minimumSample ? "\(GrindRange.number(best.setting)) on \(grinderName)" : "",
            detail: tried >= minimumSample
                ? "\(pairing.method.label) · median \(GrindRange.number(best.median)) of 5 over \(tried) settings"
                : "",
            sampleSize: tried,
            threshold: minimumSample
        )
    }

    // MARK: - Water

    /// The best-rated water profile, segmented by whatever the archive
    /// actually knows about: the process, or the roast level, or nothing.
    ///
    /// Segmenting by something that is filled in on two cards would be a
    /// correlation drawn from noise, so the segment is chosen by coverage
    /// rather than by preference.
    static func waterInsight(in cards: [CoffeeCard], profiles: [WaterProfile]) -> Insight? {
        var byProfile: [UUID: [Int]] = [:]
        var processes: [UUID: Set<String>] = [:]
        var roasts: [UUID: Set<RoastLevel>] = [:]

        for card in cards {
            for brew in card.brews {
                guard let rating = brew.rating, let id = brew.waterProfileID else { continue }
                byProfile[id, default: []].append(rating)
                if !card.process.isEmpty { processes[id, default: []].insert(card.process) }
                if let roast = card.roastLevel { roasts[id, default: []].insert(roast) }
            }
        }
        guard !byProfile.isEmpty else { return nil }

        guard let (id, ratings) = byProfile.max(by: { lhs, rhs in
            (median(lhs.value), Double(lhs.value.count)) < (median(rhs.value), Double(rhs.value.count))
        }) else { return nil }

        let name = profiles.first { $0.id == id }?.displayName ?? "your water"
        let segment = segmentLabel(processes: processes[id] ?? [], roasts: roasts[id] ?? [])

        return Insight(
            kind: .water,
            scope: name,
            finding: ratings.count >= minimumSample ? name : "",
            detail: ratings.count >= minimumSample
                ? "median \(GrindRange.number(median(ratings))) of 5 over \(ratings.count) brews\(segment)"
                : "",
            sampleSize: ratings.count,
            threshold: minimumSample
        )
    }

    /// What the water was used on, when the archive knows enough to say. One
    /// process across every brew is a segment; four is just "your coffees".
    private static func segmentLabel(processes: Set<String>, roasts: Set<RoastLevel>) -> String {
        if processes.count == 1, let process = processes.first {
            return ", all \(process.lowercased())"
        }
        if roasts.count == 1, let roast = roasts.first {
            return ", all \(roast.label.lowercased()) roasts"
        }
        return ""
    }

    // MARK: - Trend

    /// The last three comparable brews of one coffee, spoken as a direction:
    /// "acidity ↓, body ↑".
    static func trend(in cards: [CoffeeCard]) -> Insight? {
        guard let card = cards.max(by: {
            $0.brews.filter(\.isComparable).count < $1.brews.filter(\.isComparable).count
        }) else { return nil }

        let comparable = card.brews.filter(\.isComparable).sorted { $0.date < $1.date }
        guard !comparable.isEmpty else { return nil }

        let recent = Array(comparable.suffix(minimumSample))
        let phrase = movementPhrase(recent)
        let ready = comparable.count >= minimumSample && phrase != nil

        return Insight(
            kind: .trend,
            scope: card.name,
            finding: ready ? "Your last three brews of \(card.name): \(phrase!)" : "",
            detail: ready ? phrase ?? "" : "",
            sampleSize: comparable.count,
            threshold: minimumSample
        )
    }

    private static func movementPhrase(_ brews: [Brew]) -> String? {
        guard brews.count >= 2 else { return nil }
        let first = brews.first?.taste
        let last = brews.last?.taste
        guard let first, let last else { return nil }
        var parts: [String] = []
        for axis in TasteAxis.allCases {
            guard let a = first[axis], let b = last[axis], abs(b - a) >= 2 else { continue }
            parts.append("\(axis.label.lowercased()) \(b > a ? "↑" : "↓")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // MARK: - Arithmetic

    /// The middle value, averaging the two middles for an even count. Chosen
    /// over the mean everywhere here: ratings are ordinal, and a single 1 out
    /// of 5 should not drag a good setting down.
    static func median(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return Double(sorted[middle - 1] + sorted[middle]) / 2
        }
        return Double(sorted[middle])
    }
}
