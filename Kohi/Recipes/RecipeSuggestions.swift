import Foundation

/// Cards that need a suggestion, one row each, brew-less first.
nonisolated enum RecipeSuggestions {
    static let visibleCap = 6

    static func items(
        from cards: [CoffeeCard],
        method: BrewMethod?,
        mine: [Recipe],
        neighbours: [CoffeeCard]
    ) -> [(card: CoffeeCard, suggestion: RecipeSuggestion)] {
        let eligible = cards
            .filter { card in
                guard let last = card.lastBrew else { return true }
                return (last.rating ?? 0) <= 2
            }
            .sorted { a, b in
                let aEmpty = a.brews.isEmpty
                let bEmpty = b.brews.isEmpty
                if aEmpty != bEmpty { return aEmpty && !bEmpty }
                return a.createdAt > b.createdAt
            }

        var seen = Set<UUID>()
        var result: [(CoffeeCard, RecipeSuggestion)] = []
        for card in eligible {
            guard seen.insert(card.id).inserted else { continue }
            guard let suggestion = RecipeRules.suggestion(
                for: card,
                method: method,
                mine: mine,
                neighbours: neighbours
            ) else { continue }
            result.append((card, suggestion))
        }
        return result
    }
}
