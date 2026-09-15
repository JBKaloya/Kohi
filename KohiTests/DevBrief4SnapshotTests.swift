import SwiftUI
import Testing
@testable import Kohi

@MainActor
struct DevBrief4SnapshotTests {
    @Test func cardCaptionShowsRoastedOn() {
        let card = CoffeeCard(
            name: "Chelbesa",
            roaster: "Dak",
            country: "Ethiopia",
            region: "Gedeb",
            producer: "Chelchele",
            process: "Washed",
            roastLevel: .light
        )
        SnapshotSupport.image(
            of: CaptionBlock(card: card).padding(26),
            height: 420,
            named: "caption"
        )
    }

    @Test func brewLabelsUseCoffeeDoseAndWaterWeight() {
        SnapshotSupport.image(
            of: VStack(alignment: .leading, spacing: 12) {
                Text(Copy.coffeeDose).catalogueLabel()
                Text(Copy.waterWeight).catalogueLabel()
                Text(Copy.beverage).catalogueLabel()
                Text(Copy.brewAgain).catalogueLabel()
                Text(Copy.compare).catalogueLabel()
                Text(Copy.roastedOn).catalogueLabel()
            }
            .padding(26),
            height: 180,
            named: "brew-labels"
        )
    }

    @Test func filtersSheetIsVertical() {
        SnapshotSupport.image(
            of: RecipeFilterSheet(
                state: .constant(RecipeFilterState()),
                grinders: ["Comandante C40"]
            ),
            height: 720,
            named: "filters"
        )
    }

    @Test func guidedBrewShowsTheCurrentBlock() {
        let recipe = ReferenceBase.recipe(referenceID: "a1-v60-ultimate")
            ?? Recipe(name: "V60", method: .v60, dose: 30, water: 500, seconds: 210, steps: [
                RecipeStep(at: 0, action: .bloom, targetMass: 60),
                RecipeStep(at: 45, action: .pour, targetMass: 300),
            ], autoAdvance: true)
        SnapshotSupport.image(
            of:             GuidedBrewView(
                card: CoffeeCard(name: "Chelbesa"),
                recipe: recipe,
                brew: recipe.seededBrew(),
                onFinish: { _ in },
                onCancel: {},
                startsRunning: false
            ),
            height: 720,
            named: "guided"
        )
    }

    @Test func suggestedCorrectionShowsThreeMoves() {
        SnapshotSupport.image(
            of: SuggestedCorrectionView(
                correction: SuggestedCorrection(
                    reading: "Thin body, extraction reads fine.",
                    target: "more body",
                    moves: [
                        .init(rank: 1, variable: "grind", change: "grind finer", why: "More contact"),
                        .init(rank: 2, variable: "steps", change: "Add a pour", why: "More agitation"),
                        .init(rank: 3, variable: "agitation", change: "Stir after pour 2", why: "Changes the bed"),
                    ],
                    isModel: false
                ),
                pickedRank: .constant(1)
            ) { _ in }
            .padding(26),
            height: 320,
            named: "correction"
        )
    }

    @Test func feedbackScaleHasFourLevels() {
        SnapshotSupport.image(
            of: AIFeedbackScale(feature: .ask, store: AIFeedbackStore())
                .padding(26),
            height: 180,
            named: "feedback"
        )
    }

    @Test func suggestedRecipeRowKeepsUseApartFromProvenance() {
        let recipe = Recipe(
            name: "V60 « Ultimate »",
            method: .v60,
            dose: 30,
            water: 500,
            temperature: 99,
            source: .reference,
            referenceID: "a1-v60-ultimate"
        )
        SnapshotSupport.image(
            of: BrewList(
                card: CoffeeCard(
                    name: "Chelchele",
                    brews: [Brew(method: .v60, dose: 30, water: 500, rating: 5)]
                ),
                suggestion: RecipeSuggestion(
                    recipe: recipe,
                    provenance: .reference("James Hoffmann"),
                    adjustments: [],
                    grindShift: 0
                ),
                inYourTerms: "No click range on file for this grinder yet",
                onSelect: { _ in },
                onAdd: {}
            )
            .padding(26),
            height: 280,
            named: "suggested-row"
        )
    }
}
