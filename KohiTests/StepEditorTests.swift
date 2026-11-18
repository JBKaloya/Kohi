import Foundation
import Testing
@testable import Kohi

@MainActor
struct StepEditorTests {
    private let steps = [
        RecipeStep(at: 0, action: .bloom, targetMass: 45, untilSeconds: 45),
        RecipeStep(at: 45, action: .pour, targetMass: 150, untilSeconds: 75),
        RecipeStep(at: 75, action: .pour, targetMass: 250, untilSeconds: 105),
    ]

    @Test func anInsertedStepStartsWhereThePreviousEnds() {
        let next = StepEditing.inserting(.swirl, after: 0, in: steps)
        #expect(next.count == 4)
        #expect(next[1].action == .swirl)
        #expect(next[1].at == 45)
        #expect(next[1].targetMass == nil)
        #expect(next[2].id == steps[1].id)
    }

    @Test func anInsertedPourStartsFromTheMassReached() {
        let next = StepEditing.inserting(.pour, after: 1, in: steps)
        #expect(next[2].at == 75)
        #expect(next[2].targetMass == 150)
        #expect(next[2].untilSeconds == 90)
    }

    @Test func untilCarriesTheNextStepOnlyWhenTheyTouch() {
        let moved = StepEditing.settingUntil(50, at: 0, in: steps)
        #expect(moved[0].untilSeconds == 50)
        #expect(moved[1].at == 50)
        #expect(moved[2].at == 75)

        var gap = steps
        gap[1].at = 60
        let kept = StepEditing.settingUntil(50, at: 0, in: gap)
        #expect(kept[1].at == 60)
    }

    @Test func clearingUntilLeavesTheNextStepAlone() {
        let cleared = StepEditing.settingUntil(nil, at: 0, in: steps)
        #expect(cleared[0].untilSeconds == nil)
        #expect(cleared[1].at == 45)
    }

    @Test func brewOnceKeepsNothingAndLinksNoRecipe() {
        let setup = BrewJourneySupport.setup()
        let session = BrewSession(card: BrewJourneySupport.card(), setup: setup)
        let once = Recipe(name: "Just today", method: .v60, dose: 15, water: 250, steps: steps, source: .mine)
        session.applyOnce(recipe: once, setup: setup)
        #expect(session.brew.recipeID == nil)
        #expect(session.brew.recipeSnapshot?.name == "Just today")
        #expect(session.recipe?.source == .express)
        #expect(session.brew.water == 250)
    }

    @Test func brewOnceIsOfferedOnlyOnTheWayToTheTimer() throws {
        let scope = try source("Recipes/BrewScopeView.swift")
        #expect(scope.contains("session.applyOnce(recipe: recipe, setup: setup)"))
        let recipes = try source("Recipes/RecipesScreen.swift")
        #expect(!recipes.contains("onBrewOnce"))
        let sheet = try source("Recipes/StepBuilderSheet.swift")
        #expect(sheet.contains("if onBrewOnce != nil"))
    }

    @Test func otherPeoplesRecipesAreEditedAsACopy() throws {
        let detail = try source("Recipes/RecipeDetailSheet.swift")
        #expect(detail.contains("StepBuilderSheet.copying(draft: copy)"))
        let scope = try source("Recipes/BrewScopeView.swift")
        #expect(scope.contains("StepBuilderSheet.copying(draft: draft)"))
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Kohi/\(path)"), encoding: .utf8)
    }
}
