import SwiftUI
import Testing
@testable import Kohi

/// Recipe with Live first, the Live clock, and the steps heard after it.
@Suite(.serialized)
@MainActor
struct RecipeLiveSnapshotTests {
    @Test func recipeLeadsWithLiveAndNewRecipeHeadsMine() {
        let setup = BrewJourneySupport.setup()
        let session = BrewSession(card: BrewJourneySupport.card(agitation: nil), setup: setup)
        session.recipeLane = .mine
        SnapshotSupport.image(
            of: BrewJourneySupport.wrap(
                BrewScopeView(session: session, onBack: {}, onClose: {}, onNext: {}),
                setup: setup
            ),
            height: 720,
            named: "recipe"
        )
    }

    @Test func liveShowsAFreeClock() {
        let recipe = Recipe(name: Copy.live, method: .v60, dose: 15, source: .express, evidence: .unverified)
        SnapshotSupport.image(
            of: GuidedBrewView(
                card: CoffeeCard(name: "Chelbesa"),
                recipe: recipe,
                brew: Brew(method: .v60, dose: 15),
                voiceNote: BrewVoiceNote(),
                isLive: true,
                onFinish: { _ in },
                onCancel: {},
                startsRunning: false
            ),
            height: 720,
            named: "live"
        )
    }

    @Test func afterLiveShowsTheStepsHeardAndTheSplit() {
        let setup = BrewJourneySupport.setup()
        let session = BrewSession(card: BrewJourneySupport.card(agitation: nil), setup: setup)
        session.startLive()
        session.brew.seconds = 200
        LiveSteps.apply([
            .init(at: 4, action: .bloom, mass: 40, note: "swirle"),
            .init(at: 46, action: .pour, mass: 150),
            .init(at: 91, action: .pour, mass: 250, note: "plus lent"),
            .init(at: 188, action: .wait, note: "Drawdown"),
        ], to: &session.brew)
        session.step = .after
        SnapshotSupport.image(
            of: BrewJourneySupport.wrap(
                AfterBrewSheet(session: session, onSave: {}, onBack: {}),
                setup: setup
            ),
            height: 1300,
            named: "steps-heard"
        )
    }
}
