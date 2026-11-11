import Foundation
import Testing
@testable import Kohi

/// Hands-free by default: Auto for a new recipe, a brew without one, and
/// every recipe of yours that never had a mode picked.
@MainActor
struct AdvanceModeTests {
    private func store() -> RecipeStore {
        RecipeStore(files: JSONFileStore(filename: "recipes-advance-\(UUID().uuidString).json"))
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "kohi-advance-\(UUID().uuidString)")!
    }

    @Test func aNewRecipeAdvancesOnItsOwn() {
        let recipe = Recipe(name: "Mine", method: .v60, source: .mine)
        #expect(recipe.advanceMode == .auto)
        #expect(recipe.autoAdvance)
        #expect(!recipe.advanceModeChosen)
    }

    @Test func nothingForcesManualAnyMore() throws {
        let root = BrewJourneySupport.kohiRoot()
        for file in ["Recipes/StepBuilderSheet.swift", "Recipes/RecipeEditSheet.swift", "Recipes/BrewSession.swift", "Recipes/RecipeDetailSheet.swift"] {
            let text = try String(contentsOf: root.appending(path: file))
            #expect(!text.contains("autoAdvance = false"), "manual forced in \(file)")
            #expect(!text.contains("autoAdvance: false"), "manual forced in \(file)")
        }
    }

    @Test func aBrewWithoutARecipeIsAuto() {
        let setup = BrewJourneySupport.setup()
        let session = BrewSession(card: BrewJourneySupport.card(), start: .dial, setup: setup)
        #expect(session.advanceMode == .auto)
        #expect(session.timerRecipe(in: setup).advanceMode == .auto)
    }

    @Test func aBrewWithoutARecipeKeepsTheModePicked() {
        let setup = BrewJourneySupport.setup()
        let session = BrewSession(card: BrewJourneySupport.card(), start: .dial, setup: setup)
        session.setAdvanceMode(.manual)
        #expect(session.timerRecipe(in: setup).advanceMode == .manual)
    }

    @Test func aPickOnYourRecipeIsKept() {
        let setup = BrewJourneySupport.setup()
        let recipes = store()
        let mine = recipes.add(Recipe(name: "Mine", method: .v60, dose: 15, water: 250, source: .mine))
        let session = BrewSession(card: BrewJourneySupport.card(), recipe: mine, start: .dial, setup: setup)
        session.setAdvanceMode(.cues, store: recipes)
        let stored = recipes.recipe(id: mine.id)
        #expect(stored?.advanceMode == .cues)
        #expect(stored?.advanceModeChosen == true)
        #expect(session.timerRecipe(in: setup).advanceMode == .cues)
    }

    @Test func aPickOnAReferenceStaysOnThisBrew() {
        let setup = BrewJourneySupport.setup()
        let recipes = store()
        let reference = ReferenceBase.recipe(referenceID: "a1-v60-ultimate")
        let session = BrewSession(card: BrewJourneySupport.card(), recipe: reference, start: .dial, setup: setup)
        session.setAdvanceMode(.manual, store: recipes)
        #expect(recipes.recipes.isEmpty)
        #expect(ReferenceBase.recipe(referenceID: "a1-v60-ultimate")?.advanceMode == .auto)
        #expect(session.advanceMode == .manual)
    }

    @Test func theMoveToAutoRunsOnceAndSparesAChoice() {
        let recipes = store()
        let defaults = defaults()
        let unset = recipes.add(Recipe(name: "Old", method: .v60, source: .mine, autoAdvance: false))
        let chosen = recipes.add(Recipe(name: "Chosen", method: .v60, source: .express, autoAdvance: false, advanceModeChosen: true))
        recipes.moveToAutoAdvanceIfNeeded(defaults: defaults)
        #expect(recipes.recipe(id: unset.id)?.advanceMode == .auto)
        #expect(recipes.recipe(id: chosen.id)?.advanceMode == .manual)

        let later = recipes.add(Recipe(name: "Later", method: .v60, source: .mine, autoAdvance: false))
        recipes.moveToAutoAdvanceIfNeeded(defaults: defaults)
        #expect(recipes.recipe(id: later.id)?.advanceMode == .manual)
    }

    @Test func aChoiceTravelsWithTheRow() {
        let recipe = Recipe(name: "Chosen", method: .v60, source: .mine, autoAdvance: false, advanceModeChosen: true)
        let restored = RecipeRow(recipe: recipe, userID: UUID()).toRecipe()
        #expect(restored.advanceModeChosen)
        #expect(restored.advanceMode == .manual)
        let unset = RecipeRow(recipe: Recipe(name: "Unset", method: .v60), userID: UUID())
        #expect(unset.advance_mode_chosen == nil)
    }

    @Test func anOlderRecipeHasNoChoiceYet() throws {
        let json = Data(#"{"name":"V60","method":"v60","source":"mine","autoAdvance":false}"#.utf8)
        let recipe = try JSONDecoder().decode(Recipe.self, from: json)
        #expect(!recipe.advanceModeChosen)
        #expect(recipe.advanceMode == .manual)
    }

    @Test func howMuchOffersTheThreeModes() throws {
        let dial = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Recipes/BrewDialView.swift"))
        #expect(dial.contains("session.setAdvanceMode(mode, store: recipes)"))
        #expect(BrewDialView.advanceLabel(.manual) == "Tap")
        #expect(AdvanceMode.allCases.count == 3)
    }
}
