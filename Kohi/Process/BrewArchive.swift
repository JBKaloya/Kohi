import Foundation

/// One logged brew, still attached to the coffee it was made from.
struct LoggedBrew: Identifiable, Equatable, Sendable {
    var card: CoffeeCard
    var brew: Brew
    var id: UUID { brew.id }
}

/// Every home brew, across the archive, newest first.
enum BrewArchive {
    static func recent(in cards: [CoffeeCard]) -> [LoggedBrew] {
        cards
            .flatMap { card in card.brews.map { LoggedBrew(card: card, brew: $0) } }
            .sorted { lhs, rhs in
                if lhs.brew.date != rhs.brew.date { return lhs.brew.date > rhs.brew.date }
                return lhs.brew.id.uuidString < rhs.brew.id.uuidString
            }
    }
}
