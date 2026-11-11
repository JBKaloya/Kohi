import SwiftUI
import Testing
@testable import Kohi

@Suite(.serialized)
@MainActor
struct RecipesArchiveSnapshotTests {
    @Test func allWithNoBrewShowsTheSuggestionBlock() {
        let chelbesa = CoffeeCard(name: "Chelbesa", roaster: "Dak", brewMethod: .v60, roastLevel: .light)
        let gedeb = CoffeeCard(name: "Gedeb", roaster: "Dak", brewMethod: .v60, roastLevel: .light)
        SnapshotSupport.image(
            of: host(RecipesScreen(initialTab: .all), cards: [chelbesa, gedeb]),
            height: 720,
            named: "all-suggestions"
        )
    }

    @Test func allListsBrewsFromTwoCoffees() {
        let earlier = Brew(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            method: .v60,
            dose: 15,
            water: 250,
            rating: 4
        )
        let middle = Brew(
            date: Date(timeIntervalSince1970: 1_710_000_000),
            method: .v60,
            dose: 15,
            water: 250,
            rating: 3
        )
        let later = Brew(
            date: Date(timeIntervalSince1970: 1_720_000_000),
            method: .v60,
            dose: 15,
            water: 250,
            temperature: 93,
            rating: 5
        )
        let chelbesa = CoffeeCard(name: "Chelbesa", roaster: "Dak", brewMethod: .v60, brews: [later, middle], roastLevel: .light)
        let gedeb = CoffeeCard(name: "Gedeb", roaster: "Dak", brewMethod: .v60, brews: [earlier], roastLevel: .light)
        SnapshotSupport.image(
            of: host(
                RecipesScreen(
                    onOpenBrew: { _, _ in },
                    onAgainBrew: { _, _ in },
                    onReadBrew: { _, _ in },
                    initialTab: .all
                ),
                cards: [gedeb, chelbesa]
            ),
            height: 640,
            named: "all-brews"
        )
    }

    @Test func mineKeepsTheBlockAboveASavedRecipe() {
        let brewed = CoffeeCard(
            name: "Chelbesa",
            roaster: "Dak",
            brewMethod: .v60,
            brews: [Brew(method: .v60, dose: 15, water: 250, rating: 5)],
            roastLevel: .light
        )
        let waiting = CoffeeCard(name: "Gedeb", roaster: "Dak", brewMethod: .v60, roastLevel: .light)
        let recipe = Recipe(
            name: "Filter · 26 Sep",
            method: .v60,
            dose: 15,
            water: 250,
            temperature: 99,
            seconds: 180,
            source: .mine,
            cardID: brewed.id
        )
        SnapshotSupport.image(
            of: host(
                RecipesScreen(initialTab: .mine),
                cards: [brewed, waiting],
                recipes: [recipe]
            ),
            height: 780,
            named: "mine-block"
        )
    }

    private func host<V: View>(
        _ view: V,
        cards: [CoffeeCard],
        recipes: [Recipe] = []
    ) -> some View {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: "recipes-shot-\(name)")!
        let store = CardStore(
            files: CardFileStore(url: FileManager.default.temporaryDirectory.appending(path: "recipes-cards-\(name).json"))
        )
        for card in cards { store.add(card) }
        let saved = RecipeStore(files: JSONFileStore(filename: "recipes-shot-\(name).json"))
        for recipe in recipes { saved.add(recipe) }
        return view
            .environment(store)
            .environment(saved)
            .environment(BrewJourneySupport.setup())
            .environment(AIFlags(defaults: defaults))
            .environment(LotFlags(defaults: defaults))
            .environment(AIEventLog())
            .environment(LooseBrewStore(
                files: JSONFileStore(filename: "loose-brews-shot-\(name).json"),
                ledgerFile: JSONDocumentStore(filename: "loose-brews-ledger-shot-\(name).json")
            ))
    }
}
