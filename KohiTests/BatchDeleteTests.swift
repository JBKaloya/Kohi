import Foundation
import Testing
@testable import Kohi

@MainActor
private final class RecordingSink: ArchiveChangeSink {
    var changed: [UUID] = []
    var deleted: [UUID] = []
    func changed(_ kind: EntityKind, id: UUID) { changed.append(id) }
    func deleted(_ kind: EntityKind, id: UUID) { deleted.append(id) }
}

@MainActor
struct BatchDeleteTests {
    private func store(_ count: Int) -> (CardStore, RecordingSink, [CoffeeCard]) {
        let store = BrewJourneySupport.cards()
        let sink = RecordingSink()
        let cards = (0..<count).map { CoffeeCard(name: "Coffee \($0)", roaster: "Dak", brewMethod: .v60) }
        store.insert(cards)
        store.sink = sink
        return (store, sink, cards)
    }

    @Test func undoBringsTheCoffeesBackAndTellsTheServerNothing() async throws {
        let (store, sink, cards) = store(4)
        store.deleteLater(Set(cards.prefix(3).map(\.id)), window: .milliseconds(80))
        #expect(store.cards.count == 1)
        store.undoDeletion()
        #expect(store.cards.count == 4)
        try await Task.sleep(for: .milliseconds(200))
        #expect(store.cards.count == 4)
        #expect(sink.deleted.isEmpty)
    }

    @Test func theServerHearsOnlyOnceTheWindowCloses() async throws {
        let (store, sink, cards) = store(3)
        let going = Set(cards.prefix(2).map(\.id))
        store.deleteLater(going, window: .milliseconds(80))
        #expect(sink.deleted.isEmpty)
        try await eventually { !sink.deleted.isEmpty }
        #expect(Set(sink.deleted) == going)
        #expect(store.cards.map(\.id) == [cards[2].id])
        store.undoDeletion()
        #expect(store.cards.count == 1)
    }

    @Test func leavingTheAppClosesTheWindow() {
        let (store, sink, cards) = store(2)
        store.deleteLater([cards[0].id])
        store.commitHeldDeletion()
        #expect(sink.deleted == [cards[0].id])
        #expect(store.heldForUndo.isEmpty)
    }

    @Test func tastingsWaitTooThenBecomeTombstones() async throws {
        let tastings = TastingStore(
            files: JSONFileStore(filename: "tastings-batch-\(UUID().uuidString).json"),
            ledgerFile: JSONDocumentStore(filename: "tastings-ledger-batch-\(UUID().uuidString).json")
        )
        let sink = RecordingSink()
        tastings.sink = sink
        let one = Tasting(context: .out(place: Place(name: "Café A", address: "", latitude: 0, longitude: 0), placeID: nil))
        let two = Tasting(context: .out(place: Place(name: "Café B", address: "", latitude: 0, longitude: 0), placeID: nil))
        _ = tastings.add(one)
        _ = tastings.add(two)
        sink.changed = []
        tastings.deleteLater([one.id], window: .milliseconds(80))
        #expect(tastings.tastings.map(\.id) == [two.id])
        #expect(sink.changed.isEmpty)
        tastings.undoDeletion()
        #expect(tastings.tastings.count == 2)

        tastings.deleteLater([one.id, two.id], window: .milliseconds(80))
        try await eventually { tastings.heldForUndo.isEmpty }
        #expect(tastings.tastings.isEmpty)
        #expect(tastings.all.allSatisfy { $0.isDeleted })
        #expect(Set(sink.changed) == [one.id, two.id])
    }

    /// Waits for the undo window to close, however loaded the run.
    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func theConfirmationSaysTheBrewsGoToo() {
        #expect(Copy.deleteCoffees(3) == "Delete 3 coffees? Their brews go too.")
        #expect(Copy.deleteCoffees(1) == "Delete 1 coffee? Its brews go too.")
        #expect(Copy.compareUpToThree == "Compare up to 3")
    }
}
