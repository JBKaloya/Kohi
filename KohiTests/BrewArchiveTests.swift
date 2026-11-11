import Foundation
import Testing
@testable import Kohi

struct BrewArchiveTests {
    @Test func newestBrewComesFirstAndKeepsItsCoffee() {
        let older = Brew(date: Date(timeIntervalSince1970: 10), method: .v60)
        let newer = Brew(date: Date(timeIntervalSince1970: 20), method: .v60)
        let gedeb = CoffeeCard(name: "Gedeb", brews: [older])
        let chelbesa = CoffeeCard(name: "Chelbesa", brews: [newer])

        let rows = BrewArchive.recent(in: [gedeb, chelbesa])

        #expect(rows.map(\.brew.id) == [newer.id, older.id])
        #expect(rows.map(\.card?.name) == ["Chelbesa", "Gedeb"])
    }

    @Test func aRememberedSuggestedTabIsNoLongerATab() {
        #expect(RecipeTab(rawValue: "suggested") == nil)
        #expect(RecipeTab.all.label == "All")
    }

    @Test func theSuggestionBlockFollowsTheArchive() {
        #expect(RecipeSuggestions.blockHome(hasBrew: false, count: 0) == .all)
        #expect(RecipeSuggestions.blockHome(hasBrew: false, count: 2) == .all)
        #expect(RecipeSuggestions.blockHome(hasBrew: true, count: 1) == .mine)
        #expect(RecipeSuggestions.blockHome(hasBrew: true, count: 0) == .hidden)
    }
}
