import Foundation

/// The candidates a brew starts from, newest first.
nonisolated enum BrewFlow {
    static let searchThreshold = 8

    static func coffees(_ cards: [CoffeeCard], matching query: String = "") -> [CoffeeCard] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let sorted = cards.sorted { $0.createdAt > $1.createdAt }
        guard !trimmed.isEmpty else { return sorted }
        return sorted.filter { card in
            card.displayName.localizedCaseInsensitiveContains(trimmed)
                || card.roaster.localizedCaseInsensitiveContains(trimmed)
                || card.producer.localizedCaseInsensitiveContains(trimmed)
                || card.country.localizedCaseInsensitiveContains(trimmed)
        }
    }
}
