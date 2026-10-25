import Foundation
import Testing
@testable import Kohi

/// The Paris extract has to land in the index without forking a roastery the
/// archive already knows, and without carrying the editorial score.
struct SeedParisTests {
    private func emptyStore() -> RoasterStore {
        let name = UUID().uuidString
        return RoasterStore(
            files: JSONFileStore(filename: "roasters-test-\(name).json"),
            seedStamp: JSONDocumentStore(filename: "roaster-seed-stamp-test-\(name).json")
        )
    }

    private func places() -> PlaceIndex {
        PlaceIndex(
            places: ReferenceBase.parisPlaces,
            notes: JSONDocumentStore(filename: "place-notes-test-\(UUID().uuidString).json")
        )
    }

    private func seed(
        _ slug: String,
        name: String,
        country: String = "France",
        city: String = "Paris",
        website: String? = nil,
        instagram: String? = nil,
        aliases: [String] = []
    ) -> RoasterSeed {
        RoasterSeed(
            slug: slug,
            name: name,
            country: country,
            city: city,
            website: website,
            instagram: instagram,
            parisShopsServed: 3,
            ownShopIDs: [],
            aliases: aliases,
            sources: ["specialtyCoffeeParis"],
            status: "à vérifier (specialtycoffee.paris)",
            note: "",
            fetchedAt: "2026-10-01"
        )
    }

    @Test func knownSpellingsDoNotDuplicate() {
        let store = emptyStore()
        let names = [
            "Belleville Brûlerie",
            "Terres de Café",
            "KB Coffee Roasters",
            "L'Arbre à Café",
            "Noir Torréfacteur",
        ]
        let ids = names.map { store.add(Roaster(name: $0, country: "France")).id }
        store.applySeed(ReferenceBase.roasterSeeds)

        #expect(store.roasters.count == ReferenceBase.roasterSeeds.count)
        for (name, id) in zip(names, ids) {
            let hits = store.roasters.filter { Roaster.fold($0.name) == Roaster.fold(name) }
            #expect(hits.count == 1)
            #expect(hits.first?.id == id)
            #expect(hits.first?.seedID != nil)
        }
        #expect(store.roasters.first { $0.id == ids[2] }?.seedID == "kb")
        #expect(store.roasters.first { $0.id == ids[4] }?.seedID == "noir")
    }

    @Test func applyingTwiceKeepsTheSameID() {
        let store = emptyStore()
        let row = seed("feve", name: "Fève", website: "https://feveparis.com")
        store.applySeed([row])
        let first = store.roaster(seedID: "feve")
        store.applySeed([row])

        #expect(store.roasters.count == 1)
        #expect(first?.id == RoasterSeed.stableUUID(slug: "feve"))
        #expect(store.roaster(seedID: "feve")?.id == first?.id)
    }

    @Test func aTypedWebsiteIsNotOverwritten() {
        let store = emptyStore()
        let original = store.add(Roaster(
            name: "Lomi",
            country: "",
            city: "Lyon",
            website: "https://mine.example"
        ))
        store.applySeed([seed(
            "lomi",
            name: "Lomi",
            website: "https://lomi.cafe",
            instagram: "@lomi"
        )])

        let merged = store.roaster(seedID: "lomi")
        #expect(store.roasters.count == 1)
        #expect(merged?.id == original.id)
        #expect(merged?.website == "https://mine.example")
        #expect(merged?.city == "Lyon")
        #expect(merged?.instagram == "@lomi")
        #expect(merged?.country == "France")
    }

    @Test func pullKeepsTheLocalSeedLink() {
        let store = emptyStore()
        store.applySeed([seed("feve", name: "Fève", website: "https://feveparis.com")])
        let local = store.roaster(seedID: "feve")!
        var remote = local
        remote.seedID = nil
        remote.editedByUser = false
        remote.website = "https://remote.example"
        remote.updatedAt = local.updatedAt.addingTimeInterval(60)
        store.merge([remote])

        let merged = store.roaster(id: local.id)
        #expect(merged?.seedID == "feve")
        #expect(merged?.website == "https://remote.example")

        var edited = merged!
        edited.city = "Lyon"
        store.update(edited)
        let after = store.roaster(id: local.id)!
        #expect(after.editedByUser)
        #expect(store.provenance(of: after) == Copy.fromYou)
    }

    /// Fresh install: the seed lands before the first pull, and someone else
    /// already filed the same roastery. The shared row wins and cards follow.
    @Test func aSharedRowReplacesTheLocalSeedCopy() {
        let store = emptyStore()
        store.applySeed([seed("feve", name: "Fève", website: "https://feveparis.com")])
        let local = store.roaster(seedID: "feve")!
        var moved: [(UUID, UUID)] = []
        store.onReassign = { moved.append(($0, $1)) }

        let remote = Roaster(name: "Feve", country: "France", createdBy: UUID())
        store.merge([remote])

        #expect(store.roasters.count == 1)
        #expect(store.roasters.first?.id == remote.id)
        #expect(store.roaster(seedID: "feve")?.id == remote.id)
        #expect(moved.count == 1)
        #expect(moved.first?.0 == local.id)
        #expect(moved.first?.1 == remote.id)
    }

    @Test func addingWithoutACountryReusesTheSeedRow() {
        let store = emptyStore()
        store.applySeed([seed("feve", name: "Fève")])
        let added = store.add(Roaster(name: "fève", country: ""))
        #expect(store.roasters.count == 1)
        #expect(added.seedID == "feve")
    }

    @Test func industrialRoastersAreAbsentAndEveryPlaceResolves() {
        let names = Set(ReferenceBase.roasterSeeds.map { Roaster.fold($0.name) })
        #expect(!names.contains(Roaster.fold("Illy")))
        #expect(!names.contains(Roaster.fold("Hausbrandt")))
        #expect(names.contains(Roaster.fold("The Coffee")))
        #expect(names.contains(Roaster.fold("Café Joyeux")))

        let slugs = Set(ReferenceBase.roasterSeeds.map(\.slug))
        for place in ReferenceBase.parisPlaces {
            for id in place.roasterIDs {
                #expect(slugs.contains(id))
            }
        }
    }

    @Test func theBundleDoesNotCarryTheEditorialScore() throws {
        for name in ["places-paris", "roasters-seed"] {
            let url = try #require(Bundle.main.url(forResource: name, withExtension: "json"))
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(!text.contains("siteScore"))
        }
    }

    @Test func closedPlacesStayOutOfThePicker() {
        let index = places()
        #expect(index.pickable.allSatisfy { $0.status != .closed })
        let brouillon = index.match(name: "Brouillon")
        #expect(brouillon?.status == .closed)
        #expect(brouillon?.statusTag == "Closed · May 2026")
        #expect(!index.pickable.contains { $0.name == "Brouillon" })
        #expect(index.pickable.contains { $0.status == .temp })
    }

    @Test func aLearnedLinkReplacesTheExtract() {
        let index = places()
        let crible = index.servedRoasterIDs(for: "crible")
        #expect(crible.count > 1)
        index.remember(placeID: "crible", roasterID: "feve")
        #expect(index.servedRoasterIDs(for: "crible") == ["feve"])
    }

    @Test func oneServedRoasterIsFilledIn() throws {
        let index = places()
        let single = ReferenceBase.parisPlaces.first { $0.status == .open && $0.roasterIDs.count == 1 }
        let id = try #require(single?.id)
        #expect(
            PlaceRoasterFill.link(
                servedIDs: index.servedRoasterIDs(for: id),
                roasterIsEmpty: true
            ) == single?.roasterIDs.first
        )
        #expect(PlaceRoasterFill.link(servedIDs: ["a", "b"], roasterIsEmpty: true) == nil)
        #expect(PlaceRoasterFill.link(servedIDs: ["a"], roasterIsEmpty: false) == nil)
    }

    @Test func openPlacesCarryEmbeddedCoordinates() {
        let missing = ReferenceBase.parisPlaces.filter {
            $0.status == .open && ($0.latitude == nil || $0.longitude == nil)
        }.map(\.id)
        #expect(Set(missing) == [
            "manie-avenue-victor-hugo",
            "news-and-coffee",
            "plaine-cafe",
            "goodnews-victor-hugo",
            "coutume-galeries-lafayette",
        ])

        let placed = ReferenceBase.parisPlaces.filter { $0.latitude != nil && $0.longitude != nil }
        #expect(placed.count == 689)
        for place in placed {
            #expect((48.7...49.0).contains(place.latitude!))
            #expect((2.2...2.5).contains(place.longitude!))
        }
    }

    /// Airplane mode: the coordinate is in the bundle, not in a geocode cache.
    @Test func aSeedCoordinateDoesNotNeedTheNotesCache() {
        let index = places()
        let crible = index.place(id: "crible")
        #expect(crible?.latitude != nil)
        #expect(index.coordinate(for: "crible")?.latitude == crible?.latitude)
        #expect(index.coordinate(for: "crible")?.longitude == crible?.longitude)
    }

    @Test func aTypedPlaceIsKeptAndAnOldNotesFileStillLoads() throws {
        let filename = "place-notes-custom-\(UUID().uuidString).json"
        let store = JSONDocumentStore<PlaceNotes>(filename: filename)
        defer { try? FileManager.default.removeItem(at: store.url) }

        let index = PlaceIndex(places: [], notes: store)
        let place = Place(name: "Timour Coffee", address: "1 rue Test", latitude: 0, longitude: 0)
        index.addCustom(place)
        index.addCustom(Place(name: "timour coffee", address: "", latitude: 0, longitude: 0))
        #expect(index.custom(matching: "").count == 1)

        let again = PlaceIndex(places: [], notes: store)
        let found = again.custom(matching: "timour")
        #expect(found.map(\.name) == ["Timour Coffee"])
        #expect(found[0].address == "1 rue Test")

        let legacy = Data(#"{"coordinates":{"x":{"latitude":1,"longitude":2}},"learnedRoasters":{}}"#.utf8)
        let notes = try JSONDecoder().decode(PlaceNotes.self, from: legacy)
        #expect(notes.customPlaces.isEmpty)
        #expect(notes.coordinates["x"]?.latitude == 1)
    }
}
