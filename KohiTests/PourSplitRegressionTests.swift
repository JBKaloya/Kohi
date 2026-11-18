import Foundation
import Testing
@testable import Kohi

/// Timour, 18 November: the split comes and goes, misbehaves, and does not
/// follow the dose. Each test is one of those, on Create your recipe's blank
/// V60: 15 g at 1:15, bloom 30, then to 135, then to 225.
@MainActor
struct PourSplitRegressionTests {
    private func blank() -> Recipe {
        Recipe(name: "Blank", method: .v60, dose: 15, water: 225, steps: [
            RecipeStep(at: 0, action: .bloom, targetMass: 30, untilSeconds: 45, agitation: .swirl),
            RecipeStep(at: 45, action: .pour, targetMass: 135, untilSeconds: 75, note: "Centre"),
            RecipeStep(at: 75, action: .wait, untilSeconds: 100, note: "Let it drop"),
            RecipeStep(at: 100, action: .pour, targetMass: 225, untilSeconds: 130),
            RecipeStep(at: 180, action: .wait, note: "Drawdown"),
        ])
    }

    private func masses(_ steps: [RecipeStep]) -> [Double] {
        steps.filter { PourSplit.carriesWater($0.action) }.compactMap(\.targetMass)
    }

    /// Water lowered to 120 g: no part may read below zero, and the parts
    /// stay those of the recipe.
    @Test func lowerWaterKeepsThePartsAndNeverReadsNegative() throws {
        var draft = blank()
        let before = try #require(PourSplit.split(of: draft, countsBloom: true)).percents
        draft = PourSplitEditing.settingWater(120, on: draft, countsBloom: true)
        let after = try #require(PourSplit.split(of: draft, countsBloom: true))
        #expect(after.percents.allSatisfy { $0 >= 0 })
        #expect(after.percents == before)
        #expect(masses(draft.steps).last == 120)
        #expect(PourSplit.percents(of: [0.25, 0.875, 0.75]).allSatisfy { $0 >= 0 })
    }

    /// 15 g to 10 g: the water follows at 1:15, the parts hold, the grams move.
    @Test func theDoseCarriesTheWaterAndTheParts() throws {
        let draft = blank()
        let before = try #require(PourSplit.split(of: draft, countsBloom: true)).percents
        let next = PourSplitEditing.settingDose(10, on: draft, countsBloom: true)
        #expect(next.dose == 10)
        #expect(next.water == 150)
        let after = try #require(PourSplit.split(of: next, countsBloom: true))
        #expect(after.percents == before)
        #expect(masses(next.steps).last == 150)
    }

    /// Three services to four: the steps that carry no water, and what was
    /// written on the bloom, stay as they were.
    @Test func moreServicesKeepEverythingElse() throws {
        let draft = blank()
        let steps = PourSplit.restructuring(draft.steps, dose: 15, water: 225, count: 4, countsBloom: true, targetTime: 180)
        #expect(PourSplit.split(steps: steps, total: 225, countsBloom: true)?.services.count == 4)
        #expect(steps.contains { $0.note == "Let it drop" })
        #expect(steps.contains { $0.note == "Drawdown" })
        #expect(steps.first { $0.action == .bloom }?.agitation == .swirl)
        #expect(steps.first { $0.action == .bloom }?.targetMass == 30)
        #expect(masses(steps).last == 225)
    }

    /// A step moved with the chevrons: the split reads in the order the
    /// steps run, not the order of the list.
    @Test func aMovedStepIsReadInTimeOrder() throws {
        var steps = blank().steps
        steps.swapAt(0, 1)
        let split = try #require(PourSplit.split(steps: steps, total: 225, countsBloom: true))
        #expect(split.services.map(\.grams) == [30, 105, 90])
    }

    /// One pour, or an immersion: the split section stays, with a way to
    /// add the second pour.
    @Test func aSinglePourStillOffersTheSplit() {
        let single = Recipe(method: .v60, dose: 15, water: 250, steps: [
            RecipeStep(at: 0, action: .pour, targetMass: 250),
        ])
        #expect(PourSplitEditing.showsSplit(single))
        #expect(!PourSplitEditing.showsSplit(Recipe(method: .espresso, dose: 18, beverage: 36)))
        let two = PourSplit.restructuring(single.steps, dose: 15, water: 250, count: 2, countsBloom: true, targetTime: nil)
        #expect(PourSplit.split(steps: two, total: 250, countsBloom: true)?.services.count == 2)
    }
}

/// How much? follows the same rule as the editor.
@MainActor
struct HowMuchDoseTests {
    @Test func theDoseCarriesTheWaterOnHowMuch() throws {
        let setup = BrewJourneySupport.setup()
        let recipes = RecipeStore(files: JSONFileStore(filename: "recipes-dose-\(UUID().uuidString).json"))
        let session = BrewSession(card: BrewJourneySupport.card(), setup: setup)
        let recipe = recipes.add(Recipe(name: "Split", method: .v60, dose: 15, water: 225, steps: [
            RecipeStep(at: 0, action: .bloom, targetMass: 45, untilSeconds: 45),
            RecipeStep(at: 45, action: .pour, targetMass: 135, untilSeconds: 75),
            RecipeStep(at: 100, action: .pour, targetMass: 225, untilSeconds: 130),
        ], source: .mine))
        session.applyCreated(recipe: recipe, setup: setup)
        #expect(PourSplitEditing.liquid(following: 10, from: session.brew.dose, liquid: session.brew.water) == 150)
        session.brew.dose = 10
        session.brew.water = 150
        session.resizeRecipeToBrew()
        let steps = try #require(session.recipe?.steps)
        #expect(PourSplit.split(steps: steps, total: 150, countsBloom: true)?.percents == [20, 40, 40])
        #expect(PourSplitEditing.liquid(following: nil, from: 15, liquid: 225) == nil)
        #expect(PourSplitEditing.liquid(following: 10, from: nil, liquid: 225) == nil)
    }
}
