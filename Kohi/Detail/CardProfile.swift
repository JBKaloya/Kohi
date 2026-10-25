import SwiftUI

/// What this coffee gives at home: median radar, flavours found, ratings.
struct CardProfile: View {
    let card: CoffeeCard
    /// Coffee-shop tastings linked to this card, from the Tastings store.
    var tasted: [Tasting] = []

    @State private var selectedPlaceID: String?

    var body: some View {
        if let profile = CardProfileData.make(from: card, tasted: tasted) {
            let overlay = profile.byPlace.first { $0.id == selectedPlaceID }
            VStack(alignment: .leading, spacing: 14) {
                Text("Profile").catalogueLabel()

                HStack {
                    Spacer()
                    TasteRadar(
                        taste: profile.median,
                        previous: overlay?.median ?? profile.best,
                        currentColor: Palette.primary,
                        previousColor: Palette.secondary
                    )
                    Spacer()
                }
                Text(legend(profile, overlay: overlay))
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .frame(maxWidth: .infinity)

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

                if profile.byPlace.count >= 2 {
                    byPlace(profile.byPlace)
                }
            }
        }
    }

    private func legend(_ profile: CardProfileData, overlay: CardProfilePlace?) -> String {
        if let overlay { return "Median · \(overlay.name)" }
        if profile.best != nil { return "Median · Best" }
        return "Median"
    }

    private func byPlace(_ places: [CardProfilePlace]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Copy.byPlace).catalogueLabel()
            ForEach(places) { place in
                let selected = selectedPlaceID == place.id
                Button {
                    withAnimation(Motion.quick) {
                        selectedPlaceID = selected ? nil : place.id
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(place.name)
                                .font(Typography.value)
                                .foregroundStyle(selected ? Palette.primary : Palette.ink)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(place.scoreLine)
                                .font(Typography.tag)
                                .foregroundStyle(Palette.inkMuted)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Palette.hairline)
                                Capsule()
                                    .fill(selected ? Palette.primary : Palette.ink)
                                    .frame(width: proxy.size.width * place.bar)
                            }
                        }
                        .frame(height: 3)
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
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

nonisolated struct CardProfilePlace: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    /// Nil when none of the cups at this place were scored.
    var average: Double?
    var count: Int
    var median: TasteProfile

    var bar: CGFloat {
        CGFloat(min(1, max(0, (average ?? 0) / 5)))
    }

    var scoreLine: String {
        guard let average else { return "\(count)" }
        return "\(String(format: "%.1f", average)) · \(count)"
    }
}

nonisolated struct CardProfileData: Equatable, Sendable {
    var median: TasteProfile
    var best: TasteProfile?
    var found: [CardProfileFound]
    var summary: String
    var byMethod: [CardProfileMethod]
    var byPlace: [CardProfilePlace]

    /// `tasted` is the coffee-shop side, read from the Tastings store. The
    /// card's own array only contributes its legacy home notes: its out
    /// entries were lifted into the store with the same ids.
    static func make(from card: CoffeeCard, tasted out: [Tasting] = []) -> CardProfileData? {
        let comparable = card.brews.filter(\.isComparable)
        let out = out.filter { !$0.isDeleted && $0.place != nil }
        let byPlace = places(in: card, out: out)
        let tasted = (homeNotes(in: card) + out).filter { $0.rating != nil || !$0.taste.isEmpty }
        guard comparable.count >= 2 || byPlace.count >= 2 || tasted.count >= 2 else { return nil }

        let median = comparable.count >= 2
            ? medianTaste(comparable.map(\.taste))
            : medianTaste(tasted.map(\.taste) + card.brews.map(\.taste))

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
        let summary: String
        if comparable.count >= 2 {
            let avg = ratings.isEmpty ? 0 : Double(ratings.reduce(0, +)) / Double(ratings.count)
            let bestRating = ratings.max() ?? 0
            summary = "\(card.brews.count) brews · avg \(String(format: "%.1f", avg)) · best \(bestRating)/5"
        } else {
            let scores = tasted.compactMap(\.rating)
            let avg = scores.isEmpty ? 0 : Double(scores.reduce(0, +)) / Double(scores.count)
            summary = "\(tasted.count) tastings · avg \(String(format: "%.1f", avg))"
        }

        var byMethod: [CardProfileMethod] = []
        for method in BrewMethod.allCases {
            let scores = comparable.filter { $0.method == method }.compactMap(\.rating)
            if !scores.isEmpty {
                let mean = Double(scores.reduce(0, +)) / Double(scores.count)
                byMethod.append(CardProfileMethod(method: method.label, average: String(format: "%.1f/5", mean)))
            }
        }

        let bestTaste = bestBrew?.taste ?? tasted.max { ($0.rating ?? 0, $0.date) < ($1.rating ?? 0, $1.date) }?.taste

        return CardProfileData(
            median: median,
            best: bestTaste,
            found: found,
            summary: summary,
            byMethod: byMethod,
            byPlace: byPlace
        )
    }

    /// Card-era home notes with no brew behind them.
    private static func homeNotes(in card: CoffeeCard) -> [Tasting] {
        card.tastings.filter { tasting in
            guard case .home(let brewID) = tasting.context else { return false }
            if let brewID, card.brews.contains(where: { $0.id == brewID }) { return false }
            return true
        }
    }

    /// At home is the brews plus legacy notes that were not logged as a brew.
    /// A coffee shop is one group per venue, by `PlaceKey`.
    private static func places(in card: CoffeeCard, out: [Tasting]) -> [CardProfilePlace] {
        struct Bucket {
            var id: String
            var name: String
            var ratings: [Int] = []
            var tastes: [TasteProfile] = []
            var count = 0
        }

        var order: [String] = []
        var buckets: [String: Bucket] = [:]

        func bump(_ id: String, name: String, rating: Int?, taste: TasteProfile) {
            var bucket = buckets[id] ?? Bucket(id: id, name: name)
            if buckets[id] == nil { order.append(id) }
            bucket.count += 1
            if let rating { bucket.ratings.append(rating) }
            if !taste.isEmpty { bucket.tastes.append(taste) }
            buckets[id] = bucket
        }

        for brew in card.brews where brew.rating != nil || !brew.taste.isEmpty {
            bump("home", name: Copy.atHome, rating: brew.rating, taste: brew.taste)
        }
        for tasting in homeNotes(in: card) where tasting.rating != nil || !tasting.taste.isEmpty {
            bump("home", name: Copy.atHome, rating: tasting.rating, taste: tasting.taste)
        }
        for group in PlaceKey.group(out) {
            for tasting in group.tastings.reversed() {
                bump(group.id, name: group.place.name, rating: tasting.rating, taste: tasting.taste)
            }
        }

        return order.compactMap { key -> CardProfilePlace? in
            guard let bucket = buckets[key], bucket.count > 0 else { return nil }
            let average = bucket.ratings.isEmpty
                ? nil
                : Double(bucket.ratings.reduce(0, +)) / Double(bucket.ratings.count)
            return CardProfilePlace(
                id: bucket.id,
                name: bucket.name,
                average: average,
                count: bucket.count,
                median: medianTaste(bucket.tastes)
            )
        }
        .sorted { lhs, rhs in
            switch (lhs.average, rhs.average) {
            case let (left?, right?) where left != right:
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private static func medianTaste(_ profiles: [TasteProfile]) -> TasteProfile {
        var values: [TasteAxis: [Int]] = [:]
        for profile in profiles {
            for axis in TasteAxis.allCases {
                if let value = profile[axis] {
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
        return median
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
