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
}
