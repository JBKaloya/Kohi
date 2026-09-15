import Foundation
import Testing
@testable import Kohi

struct ArchiveMigratorTests {
    @Test func inspectCountsGrindValuesAndRawText() {
        let cards = [
            CoffeeCard(
                name: "Chelbesa",
                tastingNotes: ["jasmine", "petrol station"],
                brews: [
                    Brew(method: .v60, dose: 15, water: 250, seconds: 165, grind: "22 clicks", rating: 4),
                    Brew(method: .v60, dose: 15, water: 250, seconds: 165, grind: "medium-fine", rating: 3),
                ]
            ),
        ]

        let report = ArchiveMigrator.inspect(cards: cards, grinders: [])

        #expect(report.brews == 2)
        #expect(report.grindValues == 1)
        #expect(report.grindRawOnly == 1)
        #expect(report.unmatchedNotes.contains("petrol station"))
        #expect(!report.unmatchedNotes.contains("jasmine"))
    }

    @Test func aLegacyTasteObjectIsCountedAsConvertedAxes() throws {
        let json = Data("""
        {
          "id": "11111111-0000-0000-0000-000000000001",
          "date": "2025-01-04T09:00:00Z",
          "method": "v60",
          "dose": 15,
          "water": 250,
          "grind": "22 clicks",
          "taste": {"aroma":4,"acidity":3,"sweetness":5,"body":2,"bitterness":2,"aftertaste":4},
          "acidity": 0,
          "bitterness": 0,
          "body": 0,
          "notes": ""
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let brew = try decoder.decode(Brew.self, from: json)

        #expect(brew.taste[.acidity] == 6)
        #expect(brew.legacyTaste?["acidity"] == 3)

        let report = ArchiveMigrator.inspect(
            cards: [CoffeeCard(name: "Chelbesa", brews: [brew])],
            grinders: []
        )
        #expect(report.axesConverted == 6)
    }
}
