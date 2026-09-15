import SwiftUI

/// What this coffee gives at home: median radar, flavours found, ratings.
struct CardProfile: View {
    let card: CoffeeCard

    var body: some View {
        if let profile = CardProfileData.make(from: card) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Profile").catalogueLabel()

                HStack {
                    Spacer()
                    TasteRadar(taste: profile.median, previous: profile.best)
                    Spacer()
                }

                if !profile.found.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Found in your brews").catalogueLabel()
                        FlowLayout {
                            ForEach(profile.found) { item in
                                HStack(spacing: 4) {
                                    TagChip(text: item.tag.displayName, isSelected: false) {}
                                    if item.declared {
                                        Text("✓")
                                            .font(Typography.tag)
                                            .foregroundStyle(Palette.inkMuted)
                                    }
                                }
                            }
                        }
                    }
                }

                Text(profile.summary)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)

                if profile.byMethod.count >= 2 {
                    Text(profile.byMethod.map { "\($0.method) \($0.average)" }.joined(separator: " · "))
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
        }
    }
}

nonisolated struct CardProfileFound: Equatable, Sendable, Identifiable {
    var tag: FlavorTag
    var declared: Bool
    var id: String { tag.id }
}

nonisolated struct CardProfileMethod: Equatable, Sendable {
    var method: String
    var average: String
}

nonisolated struct CardProfileData: Equatable, Sendable {
    var median: TasteProfile
    var best: TasteProfile?
    var found: [CardProfileFound]
    var summary: String
    var byMethod: [CardProfileMethod]

    static func make(from card: CoffeeCard) -> CardProfileData? {
        let comparable = card.brews.filter(\.isComparable)
        guard comparable.count >= 2 else { return nil }

        var values: [TasteAxis: [Int]] = [:]
        for brew in comparable {
            for axis in TasteAxis.allCases {
                if let value = brew.taste[axis] {
                    values[axis, default: []].append(value)
                }
            }
        }
        var median = TasteProfile()
        for axis in TasteAxis.allCases {
            if let list = values[axis], !list.isEmpty {
                median[axis] = Int(medianOf(list).rounded())
            }
        }

        let bestBrew = comparable.max { ($0.rating ?? 0, $0.date) < ($1.rating ?? 0, $1.date) }
        let declaredIDs = Set(card.declaredFlavors.map(\.id))
        var counts: [String: (tag: FlavorTag, n: Int)] = [:]
        for brew in card.brews {
            for tag in brew.flavors {
                counts[tag.id, default: (tag, 0)].n += 1
                counts[tag.id]?.tag = tag
            }
        }
        let found = counts.values.sorted { $0.n > $1.n }.map {
            CardProfileFound(tag: $0.tag, declared: declaredIDs.contains($0.tag.id))
        }

        let ratings = comparable.compactMap(\.rating)
        let avg = ratings.isEmpty ? 0 : Double(ratings.reduce(0, +)) / Double(ratings.count)
        let bestRating = ratings.max() ?? 0
        let summary = "\(card.brews.count) brews · avg \(String(format: "%.1f", avg)) · best \(bestRating)/5"

        var byMethod: [CardProfileMethod] = []
        for method in BrewMethod.allCases {
            let scores = comparable.filter { $0.method == method }.compactMap(\.rating)
            if !scores.isEmpty {
                let mean = Double(scores.reduce(0, +)) / Double(scores.count)
                byMethod.append(CardProfileMethod(method: method.label, average: String(format: "%.1f/5", mean)))
            }
        }

        return CardProfileData(
            median: median,
            best: bestBrew?.taste,
            found: found,
            summary: summary,
            byMethod: byMethod
        )
    }

    private static func medianOf(_ values: [Int]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return Double(sorted[middle - 1] + sorted[middle]) / 2
        }
        return Double(sorted[middle])
    }
}
