import SwiftUI
import Testing
@testable import Kohi

@MainActor
struct BrewControlsSnapshotTests {
    @Test func rollingCounterAtRest() {
        SnapshotSupport.image(
            of: RollingCounter("Coffee", value: .constant(15), range: .dose, unit: "g", style: .brew)
                .padding(24),
            height: 160,
            named: "counter"
        )
    }

    @Test func checklistAtRest() {
        SnapshotSupport.image(
            of: TickList(title: "Before you pour", items: ["Rinse the filter", "Preheat the server", "Tare the scale"])
                .padding(24),
            height: 220,
            named: "checklist"
        )
    }

    @Test func liquidToggleOff() {
        SnapshotSupport.image(
            of: Toggle("Bloom", isOn: .constant(false))
                .toggleStyle(.liquid)
                .padding(24),
            height: 80,
            named: "toggle"
        )
    }

    @Test func sloshAtSix() {
        SnapshotSupport.image(
            of: SloshRail(label: "Acidity", value: .constant(6))
                .padding(24),
            height: 80,
            named: "slosh"
        )
    }

    @Test func swipeAtRest() {
        SnapshotSupport.image(
            of: SwipeToStart(lift: .constant(0), onCommit: {}),
            height: 120,
            named: "swipe"
        )
    }

    @Test func brewDial() {
        let setup = BrewJourneySupport.setup()
        let session = BrewSession(
            card: BrewJourneySupport.card(agitation: nil),
            recipe: ReferenceBase.recipe(referenceID: "a1-v60-ultimate"),
            size: .twoCups,
            start: .dial,
            setup: setup
        )
        SnapshotSupport.image(
            of: BrewJourneySupport.wrap(
                BrewDialView(
                    session: session,
                    onBack: {},
                    onClose: {},
                    onBrewNow: {},
                    onAlreadyBrewed: {}
                ),
                setup: setup
            ),
            height: 852,
            named: "dial"
        )
    }

    @Test func guidedBrew() {
        let recipe = ReferenceBase.recipe(referenceID: "a1-v60-ultimate")
            ?? Recipe(name: "V60", method: .v60, dose: 30, water: 500, seconds: 210, steps: [
                RecipeStep(at: 0, action: .bloom, targetMass: 60),
                RecipeStep(at: 45, action: .pour, targetMass: 300),
            ], autoAdvance: true)
        SnapshotSupport.image(
            of: GuidedBrewView(
                card: CoffeeCard(name: "Chelbesa"),
                recipe: recipe,
                brew: recipe.seededBrew(),
                voiceNote: BrewVoiceNote(),
                onFinish: { _ in },
                onCancel: {},
                startsRunning: false
            ),
            height: 852,
            named: "guided"
        )
    }
}
