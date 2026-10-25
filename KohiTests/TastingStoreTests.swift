import Foundation
import Testing
@testable import Kohi

@MainActor
struct TastingStoreTests {
    private let crible = Place(name: "Crible", address: "75 Rue Buffon", latitude: 48.84, longitude: 2.35)

    private func names() -> (String, String) {
        let id = UUID().uuidString
        return ("tastings-store-\(id).json", "tastings-store-ledger-\(id).json")
    }

    private func store(_ names: (String, String)) -> TastingStore {
        TastingStore(files: JSONFileStore(filename: names.0), ledgerFile: JSONDocumentStore(filename: names.1))
    }

    private func tasting(_ name: String = "Gesha", cardID: UUID? = nil) -> Tasting {
        Tasting(
            context: .out(place: crible, placeID: "crible"),
            cardID: cardID,
            coffee: TastedCoffee(name: name, roaster: "Fève"),
            method: .filter,
            brewer: .v60,
            price: CupPrice(amount: Decimal(string: "4.50")!, currency: "eur"),
            rating: 5
        )
    }

    @Test func saveEditAndDeleteSurviveARestart() {
        let files = names()
        let first = store(files)
        let saved = first.add(tasting())
        first.flush()
        #expect(store(files).tasting(id: saved.id)?.coffee.name == "Gesha")

        var edited = saved
        edited.note = "jasmine"
        first.update(edited)
        first.flush()
        #expect(store(files).tasting(id: saved.id)?.note == "jasmine")

        first.delete(edited)
        first.flush()
        let reloaded = store(files)
        #expect(reloaded.tasting(id: saved.id) == nil)
        #expect(reloaded.all.first { $0.id == saved.id }?.isDeleted == true)
        #expect(reloaded.knows(saved.id))
    }

    @Test func thePriceKeepsItsCurrency() {
        let price = tasting().price!
        #expect(price.currency == "EUR")
        #expect(price.amount == Decimal(string: "4.50"))
    }

    @Test func theNewerUpdateWinsAMerge() {
        let store = store(names())
        let saved = store.add(tasting())
        var older = saved
        older.note = "older"
        older.updatedAt = saved.updatedAt.addingTimeInterval(-60)
        store.merge([older])
        #expect(store.tasting(id: saved.id)?.note == nil)

        var newer = saved
        newer.note = "newer"
        newer.updatedAt = saved.updatedAt.addingTimeInterval(60)
        store.merge([newer])
        #expect(store.tasting(id: saved.id)?.note == "newer")
    }

    @Test func deletingACardOnlyUnlinksItsTastings() {
        let cardID = UUID()
        let store = store(names())
        let saved = store.add(tasting(cardID: cardID))
        store.unlinkCard(cardID)
        let kept = store.tasting(id: saved.id)
        #expect(kept != nil)
        #expect(kept?.cardID == nil)
        #expect(kept?.coffee.name == "Gesha")
    }

    @Test func editingACardLeavesTheSnapshotAlone() {
        var card = CoffeeCard(name: "Chelbesa", roaster: "Fève")
        let snapshot = TastedCoffee(card: card)
        card.name = "Renamed"
        #expect(snapshot.name == "Chelbesa")
    }

    @Test func oneCoffeeAtSeveralPlacesAndOnePlaceWithSeveralCoffees() {
        let store = store(names())
        let other = Place(name: "Ten Belles", address: "", latitude: 48.87, longitude: 2.36)
        store.add(tasting("Gesha"))
        store.add(Tasting(context: .out(place: other, placeID: nil), coffee: TastedCoffee(name: "Gesha")))
        store.add(tasting("Sidra"))
        #expect(store.tastings.filter { $0.coffee.name == "Gesha" }.count == 2)
        #expect(store.tastings.filter { $0.place == crible }.count == 2)
    }

    @Test func theShopAndTheRoasterStayDistinct() {
        let saved = tasting()
        #expect(saved.coffee.roaster == "Fève")
        #expect(saved.place?.name == "Crible")
    }

    @Test func aTastingNeedsNoCard() {
        let store = store(names())
        let saved = store.add(tasting())
        #expect(saved.cardID == nil)
        #expect(store.tastings(forCard: UUID()).isEmpty)
    }

    @Test func anEditClearsInsertOnly() {
        let store = store(names())
        let legacy = Tasting(context: .out(place: crible, placeID: nil))
        store.importLegacy([legacy])
        #expect(store.isInsertOnly(legacy.id))
        store.update(store.tastings[0])
        #expect(!store.isInsertOnly(legacy.id))
    }
}
