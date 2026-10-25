import Foundation
import Testing
@testable import Kohi

@MainActor
struct TastingMigrationTests {
    private let crible = Place(name: "Crible", address: "75 Rue Buffon", latitude: 48.84, longitude: 2.35)

    private func store(_ name: String = UUID().uuidString) -> TastingStore {
        TastingStore(
            files: JSONFileStore(filename: "tastings-test-\(name).json"),
            ledgerFile: JSONDocumentStore(filename: "tastings-ledger-test-\(name).json")
        )
    }

    private func card(with tastings: [Tasting]) -> CoffeeCard {
        CoffeeCard(
            name: "Chelbesa",
            roaster: "Fève",
            country: "Ethiopia",
            region: "Guji",
            variety: "Heirloom",
            process: "Washed",
            tastingNotes: ["Jasmine", "Peach"],
            tastings: tastings
        )
    }

    @Test func aNestedTastingBecomesStandaloneWithItsIdAndCard() {
        let legacy = Tasting(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            context: .out(place: crible, placeID: "crible"),
            rating: 4,
            acidity: 1,
            note: "bright"
        )
        let card = card(with: [legacy])
        let store = store()
        #expect(TastingMigrator.importLegacy(cards: [card], into: store) == 1)

        let imported = try! #require(store.tasting(id: legacy.id))
        #expect(imported.cardID == card.id)
        #expect(imported.coffee.name == "Chelbesa")
        #expect(imported.coffee.roaster == "Fève")
        #expect(imported.coffee.process == "Washed")
        #expect(imported.coffee.tastingNotes == ["Jasmine", "Peach"])
        #expect(imported.place == crible)
        #expect(imported.placeID == "crible")
        #expect(imported.rating == 4)
        #expect(imported.acidity == 1)
        #expect(imported.updatedAt == legacy.date)
        #expect(store.isInsertOnly(legacy.id))
    }

    @Test func importingTwiceIsANoOp() {
        let card = card(with: [Tasting(context: .out(place: crible, placeID: nil))])
        let store = store()
        #expect(TastingMigrator.importLegacy(cards: [card], into: store) == 1)
        #expect(TastingMigrator.importLegacy(cards: [card], into: store) == 0)
        #expect(store.tastings.count == 1)
    }

    @Test func aDeletedImportIsNeverResurrected() {
        let card = card(with: [Tasting(context: .out(place: crible, placeID: nil))])
        let store = store()
        TastingMigrator.importLegacy(cards: [card], into: store)
        store.delete(store.tastings[0])
        #expect(TastingMigrator.importLegacy(cards: [card], into: store) == 0)
        #expect(store.tastings.isEmpty)
        #expect(card.tastings.count == 1)
    }

    @Test func aTombstoneFromAnotherDeviceBlocksTheImport() {
        let legacy = Tasting(context: .out(place: crible, placeID: nil))
        let card = card(with: [legacy])
        let store = store()
        var tombstone = TastingMigrator.standalone(legacy, from: card)
        tombstone.deletedAt = .now
        tombstone.updatedAt = .now
        store.merge([tombstone])
        #expect(TastingMigrator.importLegacy(cards: [card], into: store) == 0)
        #expect(store.tastings.isEmpty)
    }

    @Test func homeEntriesStayOnTheCard() {
        let card = card(with: [Tasting(context: .home(brewID: nil), rating: 3)])
        let store = store()
        #expect(TastingMigrator.importLegacy(cards: [card], into: store) == 0)
        #expect(card.tastings.count == 1)
    }

    @Test func aTastingAddedOnTheCardLaterIsImportedAfterAPull() {
        var card = card(with: [Tasting(context: .out(place: crible, placeID: nil))])
        let store = store()
        TastingMigrator.importLegacy(cards: [card], into: store)
        card.tastings.append(Tasting(context: .out(place: crible, placeID: nil), rating: 5))
        #expect(TastingMigrator.importLegacy(cards: [card], into: store) == 1)
        #expect(store.tastings.count == 2)
    }

    @Test func aMalformedLegacyTastingCostsOnlyItself() throws {
        let good = Tasting(context: .out(place: crible, placeID: nil), rating: 4)
        let card = card(with: [good])
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any]
        )
        var tastings = try #require(object["tastings"] as? [Any])
        tastings.append(["id": "not-a-uuid", "context": 42])
        object["tastings"] = tastings
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(CoffeeCard.self, from: data)
        #expect(decoded.name == "Chelbesa")
        #expect(decoded.tastings.map(\.id) == [good.id])
    }

    @Test func twoDevicesImportingTheSameTastingConverge() {
        let card = card(with: [Tasting(context: .out(place: crible, placeID: nil))])
        let phone = store()
        let pad = store()
        TastingMigrator.importLegacy(cards: [card], into: phone)
        TastingMigrator.importLegacy(cards: [card], into: pad)
        phone.merge(pad.all)
        #expect(phone.tastings.count == 1)
        #expect(phone.tastings[0].id == pad.tastings[0].id)
    }

    @Test func anOldTastingWithoutTheNewFieldsDecodes() throws {
        let legacy = Tasting(context: .out(place: crible, placeID: "crible"), rating: 4, note: "bright")
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any]
        )
        for key in ["cardID", "coffee", "method", "brewer", "isBatch", "methodNote", "price",
                    "photos", "createdAt", "updatedAt", "deletedAt"] {
            object.removeValue(forKey: key)
        }
        let restored = try JSONDecoder().decode(Tasting.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.id == legacy.id)
        #expect(restored.coffee == TastedCoffee())
        #expect(restored.cardID == nil)
        #expect(restored.photos.isEmpty)
        #expect(restored.createdAt == restored.date)
        #expect(!restored.isDeleted)
    }
}
