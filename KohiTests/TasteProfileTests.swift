import Foundation
import Testing
@testable import Kohi

struct TasteProfileTests {
    @Test func zeroIsAScore() {
        let taste = TasteProfile(bitterness: 0)
        #expect(!taste.isEmpty)
        #expect(taste[.bitterness] == 0)
        #expect(taste.scoredAxes == [.bitterness])
    }

    @Test func clearingAnAxisRemovesIt() {
        var taste = TasteProfile(acidity: 7)
        taste[.acidity] = nil
        #expect(taste.isEmpty)
    }

    @Test func valuesOutsideTheScaleAreIgnored() {
        let taste = TasteProfile(values: [.acidity: 11, .body: -1, .sweetness: 5])
        #expect(taste[.acidity] == nil)
        #expect(taste[.sweetness] == 5)
    }

    @Test func legacyScoresDoubleOntoTheNewScale() {
        let taste = TasteProfile.migrated(from: [
            "aroma": 4, "acidity": 3, "sweetness": 5, "body": 2, "bitterness": 1, "aftertaste": 4,
        ])
        #expect(taste[.aroma] == 8)
        #expect(taste[.acidity] == 6)
        #expect(taste[.sweetness] == 10)
        #expect(taste[.clarity] == nil)
        #expect(taste.legacy?["acidity"] == 3)
    }

    @Test func aLegacyObjectDecodesByDoubling() throws {
        let data = Data(#"{"aroma":4,"acidity":3,"sweetness":5,"body":2,"bitterness":2,"aftertaste":4}"#.utf8)
        let taste = try JSONDecoder().decode(TasteProfile.self, from: data)
        #expect(taste[.aroma] == 8)
        #expect(taste[.acidity] == 6)
        #expect(taste[.clarity] == nil)
        #expect(taste.legacy?["aroma"] == 4)
    }

    @Test func theValuesWrapperDoesNotDouble() throws {
        let original = TasteProfile(acidity: 7, clarity: 0)
        let data = try JSONEncoder().encode(original)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let values = object?["values"] as? [String: Any]
        #expect(values?["acidity"] as? Int == 7)
        #expect(object?["acidity"] == nil)

        let restored = try JSONDecoder().decode(TasteProfile.self, from: data)
        #expect(restored[.acidity] == 7)
        #expect(restored[.clarity] == 0)
        #expect(restored.legacy == nil)
    }

    @Test func radarOrderStartsAtAcidity() {
        #expect(TasteAxis.allCases.map(\.rawValue) == [
            "acidity", "bitterness", "sweetness", "aroma", "aftertaste", "body", "clarity",
        ])
    }
}
