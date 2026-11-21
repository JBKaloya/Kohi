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
/// It stops at the limit, Delete included: a pick past it is refused and the
/// selection comes back unchanged. Taking one out always works.
nonisolated enum CompareSelection {
    static func toggling<ID: Equatable>(_ id: ID, in picked: [ID], limit: Int = CompareSeries.limit) -> [ID] {
        if let index = picked.firstIndex(of: id) {
            var next = picked
            next.remove(at: index)
            return next
        }
        guard picked.count < limit else { return picked }
        return picked + [id]
    }

    /// True when adding `id` would go past the limit.
    static func refuses<ID: Equatable>(_ id: ID, in picked: [ID], limit: Int = CompareSeries.limit) -> Bool {
        !picked.contains(id) && picked.count >= limit
    }

    /// The tiles that can no longer be picked: everything else once the limit is reached.
    static func isMuted<ID: Equatable>(_ id: ID, in picked: [ID]?, limit: Int = CompareSeries.limit) -> Bool {
        guard let picked else { return false }
        return refuses(id, in: picked, limit: limit)
    }

    static func canCompare(_ count: Int, limit: Int = CompareSeries.limit) -> Bool {
        (2...limit).contains(count)
    }
}
