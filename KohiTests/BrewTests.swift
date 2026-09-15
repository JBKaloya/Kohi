import Foundation
import Testing

@testable import Kohi

/// The enriched brew: taste axes, recorded steps, flow, and the tolerant
/// decoding that lets a brew written by an older build still open.
struct BrewTests {
    // MARK: - Taste

    @Test func anUnscoredTasteIsEmpty() {
        #expect(TasteProfile().isEmpty)
        #expect(TasteProfile().scoredAxes.isEmpty)
    }

    @Test func theSubscriptReachesEveryAxis() {
        var taste = TasteProfile()
        for axis in TasteAxis.allCases {
            taste[axis] = 4
        }

        #expect(taste.scoredAxes.count == TasteAxis.allCases.count)
        #expect(taste[.aroma] == 4)
        #expect(taste[.aftertaste] == 4)
    }

    @Test func anAxisCanBeUnscoredAgain() {
        var taste = TasteProfile(aroma: 5)
        taste[.aroma] = nil

        #expect(taste.isEmpty)
    }

    // MARK: - Flow

    @Test func flowIsWaterOverTime() {
        let brew = Brew(method: .v60, dose: 15, water: 250, seconds: 150)

        #expect(brew.averageFlow == 250.0 / 150.0)
    }

    @Test func flowNeedsBothNumbers() {
        #expect(Brew(method: .v60, dose: 15, water: 250).averageFlow == nil)
        #expect(Brew(method: .v60, dose: 15, seconds: 150).averageFlow == nil)
        #expect(Brew(method: .v60, dose: 15, water: 250, seconds: 0).averageFlow == nil)
    }

    @Test func espressoFlowUsesWhatCameOutNotWhatWentIn() {
        let brew = Brew(method: .espresso, dose: 18, beverage: 36, seconds: 30)

        #expect(brew.averageFlow == 36.0 / 30.0)
    }

    // MARK: - Recorded steps

    @Test func aRecordedStepKnowsHowLateItWas() {
        let step = BrewStep(index: 1, action: .pour, at: 52, targetAt: 45)

        #expect(step.timingDelta == "+7 s")
        #expect(step.timeLabel == "0:52")
    }

    @Test func aStepWithoutATargetHasNoDelta() {
        #expect(BrewStep(index: 0, action: .bloom, at: 3).timingDelta == nil)
    }

    @Test func stepFlowsAreMeasuredBetweenPours() {
        let brew = Brew(
            method: .v60,
            dose: 15,
            water: 250,
            steps: [
                BrewStep(index: 0, action: .bloom, at: 0, mass: 50),
                BrewStep(index: 1, action: .pour, at: 45, mass: 150),
                BrewStep(index: 2, action: .pour, at: 85, mass: 250),
            ]
        )

        let flows = brew.stepFlows
        #expect(flows.count == 2)
        // 100 g over 45 s, then 100 g over 40 s.
        #expect(abs(flows[0].flow - 100.0 / 45.0) < 0.001)
        #expect(abs(flows[1].flow - 100.0 / 40.0) < 0.001)
    }

    // MARK: - Tolerant decoding

    /// A brew saved before chantier 5 has none of these keys. It must still
    /// open, with the new fields at their empty defaults — the whole archive
    /// depends on that rule.
    @Test func aBrewFromAnOlderBuildStillDecodes() throws {
        let json = """
        {
          "id": "11111111-0000-0000-0000-000000000001",
          "date": "2025-01-04T09:00:00Z",
          "method": "v60",
          "dose": 15,
          "water": 250,
          "grind": "22 clicks",
          "acidity": 0,
          "bitterness": 0,
          "body": 0,
          "notes": "",
          "caffeineOverrideMg": 120
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let brew = try decoder.decode(Brew.self, from: Data(json.utf8))

        #expect(brew.dose == 15)
        #expect(brew.grind.value == 22)
        #expect(brew.taste.isEmpty)
        #expect(brew.steps.isEmpty)
        #expect(brew.flavors.isEmpty)
        #expect(brew.equipmentIDs.isEmpty)
        #expect(brew.captureSource == nil)
        #expect(brew.nextTimeSuggestion == nil)
    }

    @Test func anEnrichedBrewSurvivesItsOwnEncoding() throws {
        let original = SyncParityTests.fullBrew()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(Brew.self, from: encoder.encode(original))

        #expect(restored == original)
    }
}
