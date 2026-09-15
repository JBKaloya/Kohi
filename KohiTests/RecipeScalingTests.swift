import Foundation
import Testing
@testable import Kohi

struct RecipeScalingTests {
    private func ultimate() -> Recipe {
        Recipe(
            name: "V60 « Ultimate »",
            method: .v60,
            dose: 30,
            water: 500,
            temperature: 92,
            seconds: 210,
            steps: [
                RecipeStep(at: 0, action: .bloom, targetMass: 60),
                RecipeStep(at: 45, action: .pour, targetMass: 300, untilSeconds: 75),
                RecipeStep(at: 75, action: .pour, targetMass: 500, untilSeconds: 105),
            ]
        )
    }

    @Test func aFiveHundredGramRecipeHalvesToOneCup() {
        let scaled = RecipeScaling.scaled(ultimate(), to: .cup)
        #expect(scaled.isScaled)
        #expect(scaled.recipe.dose == 15)
        #expect(scaled.recipe.water == 250)
        #expect(scaled.recipe.ratio == "1:16.7")
        #expect(scaled.recipe.steps.map(\.targetMass) == [30, 150, 250])
        #expect(scaled.recipe.steps.map(\.at) == [0, 45, 75])
        #expect(scaled.recipe.steps.map(\.untilSeconds) == [nil, 75, 105])
        #expect(scaled.recipe.temperature == 92)
        #expect(scaled.scaledFromLabel == "scaled from 30 g")
    }

    @Test func aDoseUnderTwelveGramsIsLeftAlone() {
        let small = Recipe(method: .v60, dose: 10, water: 160)
        let scaled = RecipeScaling.scaled(small, to: .cup)
        #expect(!scaled.isScaled)
        #expect(scaled.recipe.dose == 10)
        #expect(scaled.recipe.water == 160)
    }

    @Test func espressoIsNeverScaled() {
        let shot = Recipe(method: .espresso, dose: 18, water: nil, beverage: 36)
        let scaled = RecipeScaling.scaled(shot, to: .cup)
        #expect(!scaled.isScaled)
        #expect(scaled.recipe.dose == 18)
    }

    @Test func aRecipeAlreadyAtTheSizeIsNotTagged() {
        let cup = Recipe(method: .v60, dose: 15, water: 250)
        let scaled = RecipeScaling.scaled(cup, to: .cup)
        #expect(!scaled.isScaled)
    }

    @Test func aSeededBrewRecordsTheScale() {
        let brew = ultimate().seededBrew(size: .cup)
        #expect(brew.dose == 15)
        #expect(brew.water == 250)
        #expect(brew.scale == .cup)
        #expect(brew.recipeID != nil)
        #expect(brew.recipeSnapshot != nil)
    }

    @Test func aReferenceRecipeDoesNotWriteAForeignKey() {
        let recipe = Recipe(
            name: "V60 « Ultimate »",
            method: .v60,
            dose: 30,
            water: 500,
            source: .reference,
            referenceID: "a1-v60-ultimate"
        )
        let brew = recipe.seededBrew()
        #expect(brew.recipeID == nil)
        #expect(brew.recipeRef == "ref:a1-v60-ultimate")
        #expect(brew.recipeSnapshot?.name == "V60 « Ultimate »")
    }

    @Test func aMineRecipeKeepsTheForeignKey() {
        let recipe = Recipe(
            name: "House V60",
            method: .v60,
            dose: 15,
            water: 250,
            source: .mine
        )
        let brew = recipe.seededBrew()
        #expect(brew.recipeID == recipe.id)
        #expect(brew.recipeRef == nil)
    }

    @Test func aBundledRecipeUUIDIsNotSentAsAForeignKey() {
        let recipe = ReferenceBase.recipe(referenceID: "a1-v60-ultimate") ?? Recipe(
            name: "V60 « Ultimate »",
            method: .v60,
            source: .reference,
            referenceID: "a1-v60-ultimate"
        )
        var brew = Brew(method: .v60, dose: 30, water: 500, recipeID: recipe.id)
        brew.dropOrphanRecipeLink()
        #expect(brew.recipeID == nil)
        #expect(brew.recipeRef == "ref:a1-v60-ultimate")
    }

    @Test func aNilDoseIsLeftAlone() {
        let recipe = Recipe(method: .v60, dose: nil, water: 250)
        let scaled = RecipeScaling.scaled(recipe, to: .cup)
        #expect(!scaled.isScaled)
        #expect(scaled.recipe.dose == nil)
    }
}
