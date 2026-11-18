import Foundation
import Testing
@testable import Kohi

/// The guided timer only advances by time. Tap and Cues are gone; a recipe
/// that had either reads as Auto, and nothing written on a step is lost.
@MainActor
struct AdvanceModeTests {
    private func source(_ file: String) throws -> String {
        try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: file))
    }

    @Test func aRecipeFromATapOrCuesBuildDecodesAndDropsTheMode() throws {
        for mode in ["manual", "cues"] {
            let json = Data(#"{"name":"V60","method":"v60","source":"mine","autoAdvance":false,"advanceMode":"\#(mode)","advanceModeChosen":true}"#.utf8)
            let recipe = try JSONDecoder().decode(Recipe.self, from: json)
            #expect(recipe.name == "V60")
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(recipe)) as! [String: Any]
            #expect(encoded["advanceMode"] == nil)
            #expect(encoded["advanceModeChosen"] == nil)
            #expect(encoded["autoAdvance"] == nil)
        }
    }

    @Test func aCueWrittenOnAStepSurvivesARoundTrip() throws {
        let recipe = Recipe(name: "V60", method: .v60, steps: [
            RecipeStep(at: 45, action: .pour, targetMass: 150, cue: .visual("bed drops to 2 mm")),
        ])
        let restored = try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(recipe))
        #expect(restored.steps.first?.cue == .visual("bed drops to 2 mm"))
        let row = RecipeRow(recipe: recipe, userID: UUID()).toRecipe()
        #expect(row.steps.first?.cue == .visual("bed drops to 2 mm"))
    }

    @Test func theRowAlwaysTellsOlderBuildsAuto() {
        let row = RecipeRow(recipe: Recipe(name: "Mine", method: .v60, source: .mine), userID: UUID())
        #expect(row.advance_mode == "auto")
        #expect(row.auto_advance == true)
        #expect(row.advance_mode_chosen == nil)
    }

    @Test func aRowFromAnOlderBuildStillDecodes() throws {
        let data = try JSONEncoder().encode(RecipeRow(recipe: Recipe(name: "Old", method: .v60), userID: UUID()))
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["advance_mode"] = "cues"
        object["auto_advance"] = false
        object["advance_mode_chosen"] = true
        let restored = try JSONDecoder().decode(
            RecipeRow.self,
            from: JSONSerialization.data(withJSONObject: object)
        ).toRecipe()
        #expect(restored.name == "Old")
    }

    @Test func howMuchNoLongerOffersAMode() throws {
        let dial = try source("Recipes/BrewDialView.swift")
        #expect(!dial.contains("advanceRow"))
        #expect(!dial.contains("setAdvanceMode"))
        #expect(!dial.contains("AdvanceMode"))
    }

    @Test func theTimerAdvancesByTimeAndStillTakesATap() throws {
        let timer = try source("Recipes/GuidedBrewView.swift")
        #expect(!timer.contains(".cues"))
        #expect(!timer.contains("advanceMode"))
        #expect(timer.contains("armAutoAdvanceIfNeeded()"))
        #expect(timer.contains(".onTapGesture { advance() }"))
        #expect(!timer.contains("skipRinse"))
    }

    @Test func theEditorNoLongerAsksForACue() throws {
        let editor = try source("Recipes/StepBuilderSheet.swift")
        #expect(!editor.contains("label: \"Cue\""))
    }

    @Test func nothingElseCarriesAMode() throws {
        for file in ["Recipes/BrewSession.swift", "Recipes/RecipeDetailSheet.swift", "Store/RecipeStore.swift", "Store/ReferenceBase.swift", "App/RootView.swift"] {
            let text = try source(file)
            #expect(!text.contains("advanceMode"), "mode left in \(file)")
            #expect(!text.contains("autoAdvance"), "mode left in \(file)")
        }
    }

    @Test func aBrewWithoutARecipeStillHasATimedSequence() {
        let setup = BrewJourneySupport.setup()
        let session = BrewSession(card: BrewJourneySupport.card(), start: .dial, setup: setup)
        let steps = session.timerRecipe(in: setup).steps
        #expect(!steps.isEmpty)
        #expect(steps.filter { $0.action != .rinse }.allSatisfy { $0.at >= 0 })
    }
}
