import Foundation
import Testing
@testable import Kohi

/// Create your recipe at 1:15, three services, then all the way through:
/// How much? at 300 g, the timer on Auto, After, Save as recipe. The parts
/// hold at every screen, with a coffee and without one.
@MainActor
struct RecipeSplitJourneyTests {
    private func store() -> RecipeStore {
        RecipeStore(files: JSONFileStore(filename: "recipes-split-\(UUID().uuidString).json"))
    }

    /// What Create your recipe saves: 15 g, 1:15, bloom counted, 20 / 50 / 30.
    private func created(card: CoffeeCard?) throws -> Recipe {
        var draft = RecipeCreation.draft(
            from: Brew(method: .v60, dose: 15),
            family: .handBrew,
            card: card,
            roastLevel: nil
        )
        draft.water = try #require(PourSplit.water(dose: 15, ratio: 15))
        draft.steps = PourSplit.steps(dose: 15, water: 225, count: 3, countsBloom: true, targetTime: 180)
        draft.steps = PourSplit.applying(shares: [0.2, 0.5, 0.3], to: draft.steps, total: 225, countsBloom: true)
        draft.source = .mine
        return draft
    }

    private func percents(_ steps: [RecipeStep], total: Double) -> [Int]? {
        PourSplit.split(steps: steps, total: total, countsBloom: true)?.percents
    }

    private func replay(_ session: BrewSession, recipes: RecipeStore, setup: SetupStore) throws -> Recipe {
        let recipe = try created(card: session.hasCard ? session.card : nil)
        #expect(percents(recipe.steps, total: 225) == [20, 50, 30])
        let saved = recipes.add(recipe)

        session.applyCreated(recipe: saved, setup: setup)
        #expect(session.brew.dose == 15)
        #expect(session.brew.water == 225)

        session.goToDial()
        session.brew.water = 300
        session.resizeRecipeToBrew()
        #expect(session.recipe?.water == 300)
        #expect(percents(session.recipe?.steps ?? [], total: 300) == [20, 50, 30])

        session.brewNow(in: setup)
        #expect(session.step == .pour)
        let timer = session.timerRecipe(in: setup)
        #expect(percents(timer.steps, total: 300) == [20, 50, 30])
        #expect(timer.steps.last { PourSplit.carriesWater($0.action) }?.targetMass == 300)

        var poured = session.brew
        poured.steps = session.brew.plannedSteps.map { planned in
            var step = planned
            step.at = planned.targetAt ?? 0
            step.mass = planned.targetMass
            return step
        }
        session.poured(poured)
        #expect(session.step == .after)

        let kept = recipes.save(brew: session.brew, from: session.card, name: "Kept")
        #expect(kept.source == .mine)
        #expect(percents(kept.steps, total: 300) == [20, 50, 30])
        return kept
    }

    @Test func withACoffeeThePartsHoldToTheSavedRecipe() throws {
        let setup = BrewJourneySupport.setup()
        let session = BrewSession(card: BrewJourneySupport.card(), setup: setup)
        session.openCreation()
        #expect(session.step == .scope)
        let kept = try replay(session, recipes: store(), setup: setup)
        #expect(kept.cardID == session.card.id)
    }

    @Test func withoutACoffeeThePartsHoldToo() throws {
        let setup = BrewJourneySupport.setup()
        let session = BrewSession.withoutCoffee(store: BrewJourneySupport.looseBrews(), setup: setup)
        #expect(!session.hasCard)
        _ = try replay(session, recipes: store(), setup: setup)
    }

    @Test func theCreationFormAsksForRatioAndSplit() throws {
        let text = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Recipes/StepBuilderSheet.swift"))
        #expect(text.contains("RollingCounter(Copy.ratioOneTo, value: ratioBinding"))
        #expect(text.contains("if PourSplitEditing.showsSplit(draft) { splitGroup }"))
        #expect(text.contains("private var countsBloom: Bool { draft.splitCountsBloom ?? true }"))
        #expect(text.contains("RollingCounter(\"Dose\", value: doseBinding"))
        #expect(text.contains("Rescale steps to these totals"))
    }
}
