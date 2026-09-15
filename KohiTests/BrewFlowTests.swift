import Foundation
import Testing
@testable import Kohi

struct BrewFlowTests {
    @Test func anEmptyShelfOffersNothing() {
        #expect(BrewFlow.coffees([], matching: "").isEmpty)
    }

    @Test func theMostRecentCoffeeComesFirst() {
        let older = CoffeeCard(name: "Older", createdAt: Date(timeIntervalSince1970: 1))
        let newer = CoffeeCard(name: "Newer", createdAt: Date(timeIntervalSince1970: 2))
        #expect(BrewFlow.coffees([older, newer]).map(\.id) == [newer.id, older.id])
    }

    @Test func aSearchFiltersTheShelf() {
        let chelbesa = CoffeeCard(name: "Chelbesa", roaster: "Gardelli")
        let kenya = CoffeeCard(name: "Tekangu", roaster: "Coffee Collective")
        #expect(BrewFlow.coffees([chelbesa, kenya], matching: "Chel").map(\.id) == [chelbesa.id])
    }

    @Test func aRecipePickPairsWithTheChosenCoffee() {
        let card = CoffeeCard(name: "Chelbesa")
        let recipe = Recipe(name: "V60", method: .v60, dose: 15, water: 250)
        let pair = (card, recipe)
        #expect(pair.0.id == card.id)
        #expect(pair.1.id == recipe.id)
        #expect(BrewFlow.coffees([card]).first?.id == card.id)
    }
}
