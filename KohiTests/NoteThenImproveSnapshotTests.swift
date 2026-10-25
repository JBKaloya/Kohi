import SwiftUI
import Testing
@testable import Kohi

@Suite(.serialized)
@MainActor
struct NoteThenImproveSnapshotTests {
    @Test func forNextTimeShowsWishesExtractionAndAMove() {
        let setup = BrewJourneySupport.setup()
        var brew = ExtractionReadingTests.brew(
            steps: [
                BrewStep(index: 0, action: .bloom, at: 10, mass: 60),
                BrewStep(index: 1, action: .pour, at: 40, mass: 250),
            ],
            bitterness: 1
        )
        brew.complexity = 1
        brew.notes = "A bit harsh at the end."
        let card = ExtractionReadingTests.card()
        let session = BrewSession(card: card, existing: brew, mode: .edit, start: .after, setup: setup)
        session.opensRead = true
        SnapshotSupport.image(
            of: BrewJourneySupport.wrap(
                BrewReadView(session: session, previous: nil, onAgain: {}, onDone: {}),
                setup: setup
            ),
            height: 1_500,
            named: "for-next-time"
        )
    }
}
