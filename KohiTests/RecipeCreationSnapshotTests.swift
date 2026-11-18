import SwiftUI
import Testing
@testable import Kohi

/// Create your recipe: totals with the ratio, then the split, before the steps.
@MainActor
struct RecipeCreationSnapshotTests {
    @Test func createYourRecipeShowsRatioAndSplit() {
        let setup = BrewJourneySupport.setup()
        var draft = RecipeCreation.blank()
        draft.name = "Huabal · V60"
        draft.steps = PourSplit.applying(shares: [0.2, 0.5, 0.3], to: draft.steps, total: 225, countsBloom: true)
        SnapshotSupport.image(
            of: BrewJourneySupport.wrap(
                StepBuilderSheet.creation(draft: draft, asksMethod: true) { _ in },
                setup: setup
            ),
            height: 1300,
            named: "creation"
        )
    }

    @Test func onTheWayToTheTimerCreationOffersBrewOnce() {
        let setup = BrewJourneySupport.setup()
        var draft = RecipeCreation.blank()
        draft.name = "Huabal · V60"
        SnapshotSupport.image(
            of: BrewJourneySupport.wrap(
                StepBuilderSheet.creation(draft: draft, onBrewOnce: { _ in }, onSave: { _ in }),
                setup: setup
            ),
            height: 1300,
            named: "creation-brew-once"
        )
    }

    @Test func someoneElsesRecipeIsEditedAsACopy() {
        let setup = BrewJourneySupport.setup()
        var draft = RecipeCreation.blank()
        draft.name = "Hoffmann · V60"
        draft.source = .reference
        SnapshotSupport.image(
            of: BrewJourneySupport.wrap(StepBuilderSheet.copying(draft: draft) { _ in }, setup: setup),
            height: 1300,
            named: "edit-a-copy"
        )
    }
}
