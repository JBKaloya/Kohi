import Foundation

/// Cards that need a suggestion, one row each, brew-less first.
nonisolated enum RecipeSuggestions {
    /// Where the per-coffee block is drawn. All while the archive has no
    /// brew, Mine once one exists and a coffee still needs a recipe, hidden
    /// when every coffee already has a brew above 2.
    enum BlockHome: Equatable, Sendable {
        case all
        case mine
        case hidden
    }

    static func blockHome(hasBrew: Bool, count: Int) -> BlockHome {
        if !hasBrew { return .all }
        return count > 0 ? .mine : .hidden
    }

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
