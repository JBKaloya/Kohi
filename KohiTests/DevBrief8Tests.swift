import CoreLocation
import Foundation
import Testing
@testable import Kohi

@MainActor
struct DevBrief8Tests {
    private func place(
        _ id: String,
        name: String,
        latitude: Double,
        longitude: Double,
        status: PlaceStatus = .open,
        roasters: [String] = []
    ) -> SeedPlace {
        SeedPlace(
            id: id,
            name: name,
            brand: name,
            address: "\(name), Paris",
            postalCode: "75005",
            arrondissement: 5,
            city: "Paris",
            roasterIDs: roasters,
            status: status,
            closedOn: status == .closed ? "2026-05" : nil,
            fetchedAt: "2026-10-01",
            latitude: latitude,
            longitude: longitude
        )
    }

    private func index(_ places: [SeedPlace]) -> PlaceIndex {
        PlaceIndex(
            places: places,
            notes: JSONDocumentStore(filename: "place-notes-brief8-\(UUID().uuidString).json")
        )
    }

    // MARK: - Duplicate

    @Test func aStrongMatchIgnoresAccentsAndPunctuation() {
        let existing = CoffeeCard(name: "Chelbesa", roaster: "Fève")
        let hit = CardMatch.find(roaster: "Feve", name: "Chelbesa!", in: [existing])
        #expect(hit?.confidence == .strong)
        #expect(hit?.card.id == existing.id)
    }

    @Test func aCloseNameFromTheSameRoasterIsOnlyProbable() {
        let existing = CoffeeCard(name: "Chelbesa", roaster: "Fève")
        let hit = CardMatch.find(roaster: "Fève", name: "Chelbesa Natural", in: [existing])
        #expect(hit?.confidence == .probable)
        #expect(hit?.card.id == existing.id)
    }

    @Test func aDifferentRoasterIsNotAMatch() {
        let existing = CoffeeCard(name: "Chelbesa", roaster: "Fève")
        #expect(CardMatch.find(roaster: "Lomi", name: "Chelbesa", in: [existing]) == nil)
    }

    @Test func aBlankNameMatchesNothing() {
        let existing = CoffeeCard(name: "Chelbesa", roaster: "Fève")
        let untitled = CoffeeCard(name: "", roaster: "Fève")
        #expect(CardMatch.find(roaster: "Fève", name: "   ", in: [existing]) == nil)
        #expect(CardMatch.find(roaster: "Fève", name: "Chelbesa", in: [untitled]) == nil)
    }

    @Test func aShortFragmentDoesNotMatch() {
        let existing = CoffeeCard(name: "Kenya AA", roaster: "Fève")
        #expect(CardMatch.find(roaster: "Fève", name: "AA", in: [existing]) == nil)
    }

    @Test func originBreaksATieBetweenTwoStrongMatches() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let ethiopia = CoffeeCard(
            name: "Chelbesa", roaster: "Fève", country: "Ethiopia", createdAt: older
        )
        let kenya = CoffeeCard(
            name: "Chelbesa", roaster: "Fève", country: "Kenya", createdAt: newer
        )
        var origin = ParsedFields()
        origin.country = "Ethiopia"
        let hit = CardMatch.find(
            roaster: "Feve",
            name: "Chelbesa",
            origin: origin,
            in: [kenya, ethiopia]
        )
        #expect(hit?.card.id == ethiopia.id)
    }

    // MARK: - Places

    @Test func suggestionsStayInside150MetresAndRaiseTheRoaster() {
        let origin = CLLocationCoordinate2D(latitude: 48.844, longitude: 2.356)
        let places = [
            place("a", name: "Near", latitude: 48.84410, longitude: 2.356),
            place("b", name: "Serves", latitude: 48.84470, longitude: 2.356, roasters: ["feve"]),
            place("c", name: "Farther", latitude: 48.84520, longitude: 2.356),
            place("d", name: "Too far", latitude: 48.84600, longitude: 2.356),
            place("e", name: "Closed", latitude: 48.84405, longitude: 2.356, status: .closed),
            place("f", name: "Temp", latitude: 48.84430, longitude: 2.356, status: .temp),
        ]
        let card = CoffeeCard(name: "Chelbesa", roaster: "Fève")
        let suggested = TastingPlaces.suggest(
            card: card,
            index: index(places),
            from: origin
        )
        #expect(suggested.map(\.id) == ["b", "a", "f"])
        #expect(suggested.contains { $0.status == .temp })
        #expect(!suggested.contains { $0.status == .closed })
    }

    @Test func noFixMeansNoSuggestion() {
        let places = [place("a", name: "Near", latitude: 48.8441, longitude: 2.356)]
        let suggested = TastingPlaces.suggest(
            card: CoffeeCard(name: "Chelbesa", roaster: "Fève"),
            index: index(places),
            from: nil
        )
        #expect(suggested.isEmpty)
    }

    @Test func aTypedPlaceIsRememberedOnce() {
        let crible = Place(name: "Crible", address: "75 Rue Buffon", latitude: 0, longitude: 0)
        let typed = Place(name: "The corner", address: "", latitude: 0, longitude: 0)
        let tastings = [
            Tasting(context: .out(place: typed, placeID: nil), rating: 4),
            Tasting(context: .out(place: typed, placeID: nil), rating: 5),
            Tasting(context: .out(place: crible, placeID: "crible")),
        ]
        let remembered = TastingPlaces.remembered(in: tastings)
        #expect(remembered.count == 2)
        #expect(remembered.contains { $0.placeID == nil && $0.place.name == "The corner" })
        #expect(TastingPlaces.remembered(in: tastings, matching: "corner").count == 1)
    }

    // MARK: - Score

    @Test func theAverageCountsRatedTastingsAndIgnoresBrews() {
        var card = CoffeeCard(name: "Chelbesa", roaster: "Fève")
        card.brews = [
            Brew(rating: 5),
            Brew(rating: 5),
            Brew(rating: 1),
        ]
        let place = Place(name: "Crible", address: "", latitude: 0, longitude: 0)
        card.tastings = [
            Tasting(context: .out(place: place, placeID: "crible"), rating: 4),
            Tasting(context: .out(place: place, placeID: "crible"), rating: 2),
            Tasting(context: .out(place: place, placeID: "crible")),
            Tasting(context: .home(brewID: nil)),
        ]
        #expect(card.tastingScore?.count == 2)
        #expect(card.tastingScore?.average == 3)
        #expect(card.tastingScoreLine == "3.0 · 2 tastings")
        #expect(card.ratedTastings.count == 2)
    }

    @Test func aCardWithNoRatedTastingHasNoScore() {
        var card = CoffeeCard(name: "Chelbesa")
        card.brews = [Brew(rating: 5)]
        #expect(card.tastingScore == nil)
        #expect(card.tastingScoreLine == nil)
    }

    // MARK: - Archive

    @Test func aTastingRoundTripsAndAnOldCardDecodesWithoutOne() throws {
        let tasting = Tasting(
            id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000009")!,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            context: .home(brewID: nil),
            rating: 4,
            note: "no recipe"
        )
        let encoded = try JSONEncoder().encode(tasting)
        let decoded = try JSONDecoder().decode(Tasting.self, from: encoded)
        #expect(decoded == tasting)

        var card = CoffeeCard(name: "Chelbesa", roaster: "Fève", tastings: [tasting])
        let cardData = try JSONEncoder().encode(card)
        var object = try #require(JSONSerialization.jsonObject(with: cardData) as? [String: Any])
        object.removeValue(forKey: "tastings")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let restored = try JSONDecoder().decode(CoffeeCard.self, from: legacy)
        #expect(restored.tastings.isEmpty)
        #expect(restored.name == "Chelbesa")

        card.tastings = [tasting]
        let roundTrip = try JSONDecoder().decode(CoffeeCard.self, from: JSONEncoder().encode(card))
        #expect(roundTrip.tastings == [tasting])
    }

    @Test func theTasteBlocksRoundTripAndDefaultWhenAbsent() throws {
        let scored = Tasting(
            context: .out(
                place: Place(name: "Crible", address: "", latitude: 0, longitude: 0),
                placeID: "crible"
            ),
            rating: 4,
            taste: TasteProfile(acidity: 8, sweetness: 5, body: 3),
            flavors: [FlavorTag(custom: "Jasmine"), FlavorTag(custom: "Peach")],
            acidity: 1,
            bitterness: -1,
            body: 1,
            note: "bright"
        )
        let data = try JSONEncoder().encode(scored)
        #expect(try JSONDecoder().decode(Tasting.self, from: data) == scored)

        // A tasting filed before the blocks existed: score and note only.
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["taste", "flavors", "acidity", "bitterness", "body"] {
            object.removeValue(forKey: key)
        }
        let older = try JSONSerialization.data(withJSONObject: object)
        let restored = try JSONDecoder().decode(Tasting.self, from: older)
        #expect(restored.taste.isEmpty)
        #expect(restored.flavors.isEmpty)
        #expect(restored.acidity == 0)
        #expect(restored.bitterness == 0)
        #expect(restored.body == 0)
        #expect(restored.rating == 4)
        #expect(restored.note == "bright")
    }

    @Test func aTastingWithOnlyAPlaceIsBlank() {
        let place = Place(name: "Crible", address: "", latitude: 0, longitude: 0)
        #expect(Tasting(context: .out(place: place, placeID: "crible")).isBlank)
        #expect(!Tasting(context: .home(brewID: nil), rating: 3).isBlank)
        #expect(!Tasting(context: .home(brewID: nil), taste: TasteProfile(acidity: 6)).isBlank)
        #expect(!Tasting(context: .home(brewID: nil), bitterness: -1).isBlank)
    }
}
