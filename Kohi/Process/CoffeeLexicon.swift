import Foundation

/// Words a dictated field should expect, handed to the recogniser as
/// `contextualStrings` before it listens. Unlike `SpokenLexicon`, which
/// respells a transcript afterwards, this biases what is heard in the first
/// place. Each field gets the vocabulary it is likely to hear, newest first,
/// because the list is clipped and a long one blurs recognition.
nonisolated enum CoffeeLexicon {
    /// Apple documents no hard limit. Past about a hundred phrases the bias
    /// stops helping, so the oldest terms are dropped.
    static let cap = 100

    /// Coffee names and roasters, for the notes on a card or a tasting.
    static func coffees(cards: [CoffeeCard], roasters: [String]) -> [String] {
        let recent = cards.sorted { $0.updatedAt > $1.updatedAt }
        var terms: [String] = []
        for card in recent {
            terms.append(card.name)
            terms.append(card.roaster)
        }
        terms.append(contentsOf: roasters)
        return clip(terms)
    }

    /// Recipe names and the methods they belong to, for naming a recipe.
    static func recipes(_ recipes: [Recipe]) -> [String] {
        let recent = recipes.sorted { $0.updatedAt > $1.updatedAt }
        return clip(recent.map(\.name) + BrewMethod.allCases.map(\.label))
    }

    /// Methods and kit, for the comment after a brew.
    static func brew(_ brew: Brew, recipe: Recipe?, equipment: [Equipment], filters: [FilterStock]) -> [String] {
        clip(SpokenLexicon.terms(brew: brew, recipe: recipe, equipment: equipment, filters: filters))
    }

    /// The flavour wheel, for tasting notes. Quick picks lead, as the likeliest.
    static func flavors(_ wheel: FlavorWheel = .shared) -> [String] {
        clip(wheel.quick.map(\.en) + wheel.nodes.map(\.en))
    }

    /// Trimmed, one of each regardless of case, at most `cap`.
    static func clip(_ terms: [String], cap: Int = cap) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in terms {
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard term.count >= 2, seen.insert(term.lowercased()).inserted else { continue }
            result.append(term)
            if result.count == cap { break }
        }
        return result
    }
}
