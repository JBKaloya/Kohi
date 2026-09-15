import Foundation
import Testing
@testable import Kohi

/// Regression for the card-creation crash that invalidated the first test
/// (parcours 2). The original suspects — force unwraps in the suggestion
/// chain — are already gone; these pin the edges that used to be able to
/// explode: empty kit, nil dose, repeated `[label]value`, empty notes, a
/// card with no mask.
struct CardCreationRegressionTests {
    @Test func aSuggestionDoesNotNeedAGrinder() {
        let card = CoffeeCard(name: "Chelbesa")
        let suggestion = RecipeRules.suggestion(
            for: card,
            mine: [],
            neighbours: []
        )
        #expect(suggestion != nil)
    }

    @Test func scalingARecipeWithNoDoseDoesNotTrap() {
        let recipe = Recipe(name: "Bare", method: .v60, dose: nil, water: 250)
        let scaled = RecipeScaling.scaled(recipe, to: .cup)
        #expect(scaled.recipe.dose == nil)
        #expect(!scaled.isScaled)
    }

    @Test func repeatedBracketLabelsSplit() {
        let segments = LabelValueParser.segments(
            in: "[Process]Washed [Variety]Heirloom"
        )
        #expect(segments.contains("Process: Washed"))
        #expect(segments.contains("Variety: Heirloom"))
    }

    @Test func anEmptyNoteProducesNoTags() {
        let match = FlavorMatcher.match("")
        #expect(match.tags.isEmpty)
        #expect(match.unmatched.isEmpty)
    }

    @Test func aCardWithoutAMaskStillOpens() {
        let card = CoffeeCard(name: "No mask", hasMask: false)
        #expect(card.hasMask == false)
        #expect(card.name == "No mask")
    }
}

struct SuggestedEligibilityTests {
    @Test func aCardWithNoBrewsIsEligible() {
        let card = CoffeeCard(name: "Kenya")
        let items = RecipeSuggestions.items(
            from: [card],
            method: .v60,
            mine: [],
            neighbours: []
        )
        #expect(items.contains { $0.card.id == card.id })
    }

    @Test func aWellRatedLastBrewDropsTheCard() {
        var card = CoffeeCard(name: "Kenya")
        card.brews = [
            Brew(date: Date(timeIntervalSince1970: 100), rating: 5),
            Brew(date: Date(timeIntervalSince1970: 10), rating: 1),
        ]
        let items = RecipeSuggestions.items(
            from: [card],
            method: .v60,
            mine: [],
            neighbours: []
        )
        #expect(!items.contains { $0.card.id == card.id })
    }

    @Test func lastBrewIsTheNewestByDateNotArrayOrder() {
        var card = CoffeeCard(name: "Kenya")
        card.brews = [
            Brew(date: Date(timeIntervalSince1970: 10), rating: 5),
            Brew(date: Date(timeIntervalSince1970: 100), rating: 1),
        ]
        #expect(card.lastBrew?.rating == 1)
        let items = RecipeSuggestions.items(
            from: [card],
            method: .v60,
            mine: [],
            neighbours: []
        )
        #expect(items.contains { $0.card.id == card.id })
    }
}
