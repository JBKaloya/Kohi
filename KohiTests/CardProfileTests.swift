import Foundation
import Testing
@testable import Kohi

struct CardProfileTests {
    @Test func twoComparableBrewsMakeAProfile() {
        let card = CoffeeCard(
            name: "Chelbesa",
            tastingNotes: ["jasmine"],
            brews: [
                Brew(
                    method: .v60,
                    dose: 15,
                    water: 250,
                    seconds: 165,
                    grind: "22 clicks",
                    taste: TasteProfile(acidity: 8, body: 4),
                    flavors: [FlavorTag(id: "floral-floral-jasmine")],
                    rating: 4
                ),
                Brew(
                    date: Date(timeIntervalSince1970: 1),
                    method: .v60,
                    dose: 15,
                    water: 250,
                    seconds: 170,
                    grind: "20 clicks",
                    taste: TasteProfile(acidity: 4, body: 8),
                    flavors: [FlavorTag(id: "floral-floral-jasmine")],
                    rating: 5
                ),
            ]
        )

        let profile = try! #require(CardProfileData.make(from: card))
        #expect(profile.median[.acidity] == 6)
        #expect(profile.median[.body] == 6)
        #expect(profile.found.contains { $0.tag.id == "floral-floral-jasmine" && $0.declared })
        #expect(profile.summary.contains("2 brews"))
        #expect(profile.best?[.body] == 8)
    }

    @Test func oneBrewIsNotAProfile() {
        let card = CoffeeCard(brews: [
            Brew(method: .v60, dose: 15, water: 250, seconds: 165, grind: "22 clicks", rating: 4),
        ])
        #expect(CardProfileData.make(from: card) == nil)
    }

    @Test func coffeeShopsSortByRatingAndATastingOnlyCardStillHasAProfile() throws {
        let terra = Place(name: "Terra", address: "", latitude: 1, longitude: 1)
        let kb = Place(name: "KB", address: "", latitude: 2, longitude: 2)
        let tasted = [
            Tasting(
                context: .out(place: terra, placeID: "terra"),
                rating: 3,
                taste: TasteProfile(acidity: 4)
            ),
            Tasting(
                date: Date(timeIntervalSince1970: 2),
                context: .out(place: terra, placeID: "terra"),
                rating: 5,
                taste: TasteProfile(acidity: 8)
            ),
            Tasting(
                context: .out(place: kb, placeID: "kb"),
                rating: 5,
                taste: TasteProfile(body: 6)
            ),
        ]

        let profile = try #require(CardProfileData.make(from: CoffeeCard(), tasted: tasted))
        #expect(profile.byPlace.map(\.name) == ["KB", "Terra"])
        #expect(profile.byPlace[0].average == 5)
        #expect(profile.byPlace[1].count == 2)
        #expect(profile.byPlace[1].average == 4)
        #expect(profile.byPlace[1].median[.acidity] == 6)
        #expect(profile.summary.contains("3 tastings"))
    }

    /// `PlaceKey`: the same folded name merges only with both pins close by.
    @Test func theSameCafeNameNearbyIsOnePlaceButNeverByNameAlone() throws {
        let first = Place(name: "KB Cafe", address: "1", latitude: 48.8800, longitude: 2.3400)
        let again = Place(name: "kb café", address: "2", latitude: 48.8802, longitude: 2.3401)
        let unpinned = Place(name: "KB Cafe", address: "3", latitude: 0, longitude: 0)
        let home = Tasting(context: .home(brewID: nil), rating: 2, taste: TasteProfile(sweetness: 5))
        let card = CoffeeCard(tastings: [home])
        let tasted = [
            Tasting(date: Date(timeIntervalSince1970: 3), context: .out(place: first, placeID: nil), rating: 4),
            Tasting(date: Date(timeIntervalSince1970: 2), context: .out(place: again, placeID: nil), rating: 2),
            Tasting(date: Date(timeIntervalSince1970: 1), context: .out(place: unpinned, placeID: nil), rating: 1),
        ]

        let profile = try #require(CardProfileData.make(from: card, tasted: tasted))
        let kb = try #require(profile.byPlace.first { $0.count == 2 })
        #expect(kb.average == 3)
        #expect(profile.byPlace.count == 3)
        #expect(profile.byPlace.contains { $0.id == "home" && $0.name == Copy.atHome })
    }
}
