import SwiftUI
import Testing
@testable import Kohi

@Suite(.serialized)
@MainActor
struct PrdBrewV2SnapshotTests {
    @Test func afterBrewShowsFlavors() {
        let setup = BrewJourneySupport.setup()
        var brew = Brew(method: .v60, dose: 15, water: 250, seconds: 180, rating: 4)
        brew.flavors = [FlavorTag(id: "floral-floral-jasmine")]
        brew.recipeName = "Filter · 19 Sep"
        brew.actualSource = .timer
        let card = CoffeeCard(
            name: "Chelbesa",
            tastingNotes: ["jasmine"],
            brewMethod: .v60
        )
        let session = BrewSession(
            card: card,
            existing: brew,
            mode: .edit,
            start: .after,
            setup: setup
        )
        SnapshotSupport.image(
            of: BrewJourneySupport.wrap(
                AfterBrewSheet(session: session, onSave: {}, onBack: {}),
                setup: setup
            ),
            height: 980,
            named: "after-flavors"
        )
    }
}
