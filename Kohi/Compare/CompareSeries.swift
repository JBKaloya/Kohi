import Foundation

/// One shape on the comparison radar: a coffee (its median), a brew, or a
/// coffee-shop tasting. Kinds mix freely.
nonisolated struct CompareSeries: Identifiable, Equatable {
    enum Source: Hashable {
        case coffee(UUID)
        case brew(UUID)
        case tasting(UUID)
    }

    /// At most this many shapes on one radar.
    static let limit = 3

    let source: Source
    let title: String
    let detail: String
    let taste: TasteProfile
    /// The main colour of the card behind the series, when there is one.
    let cardInk: SIMD3<Double>?
    /// Set for a brew, to set its parameters side by side.
    let brew: Brew?

    var id: Source { source }

    static func coffee(_ card: CoffeeCard, tasted: [Tasting] = [], ink: SIMD3<Double>?) -> CompareSeries {
        let count = card.brews.count
        return CompareSeries(
            source: .coffee(card.id),
            title: card.displayName,
            detail: count == 1 ? "1 brew" : "\(count) brews",
            taste: CardProfileData.medianTaste(of: card, tasted: tasted),
            cardInk: ink,
            brew: nil
        )
    }

    static func brew(_ brew: Brew, on card: CoffeeCard, ink: SIMD3<Double>?) -> CompareSeries {
        CompareSeries(
            source: .brew(brew.id),
            title: card.displayName,
            detail: brew.date.formatted(.dateTime.day().month(.abbreviated)),
            taste: brew.taste,
            cardInk: ink,
            brew: brew
        )
    }

    static func tasting(_ tasting: Tasting, card: CoffeeCard?, ink: SIMD3<Double>?) -> CompareSeries {
        let place = tasting.place?.name ?? ""
        let date = tasting.date.formatted(.dateTime.day().month(.abbreviated))
        return CompareSeries(
            source: .tasting(tasting.id),
            title: tasting.coffeeName(fallback: card?.displayName ?? "A coffee"),
            detail: place.isEmpty ? date : "\(place) · \(date)",
            taste: tasting.taste,
            cardInk: card == nil ? nil : ink,
            brew: nil
        )
    }

    /// The main colour of a card, as its face draws its title.
    static func ink(of card: CoffeeCard) -> SIMD3<Double> {
        CardArt.make(card, ink: CardFiles.loadStampFile(card.id)).titleInk
    }
}

/// A selection in pick order: the order numbers the badges and the series.
/// It may grow past the limit for Delete; Compare only takes two to three.
nonisolated enum CompareSelection {
    static func toggling<ID: Equatable>(_ id: ID, in picked: [ID]) -> [ID] {
        if let index = picked.firstIndex(of: id) {
            var next = picked
            next.remove(at: index)
            return next
        }
        return picked + [id]
    }

    static func canCompare(_ count: Int, limit: Int = CompareSeries.limit) -> Bool {
        (2...limit).contains(count)
    }
}
