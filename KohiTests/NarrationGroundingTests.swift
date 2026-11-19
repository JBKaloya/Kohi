import Foundation
import Testing
@testable import Kohi

/// What the model heard is only shown once it holds against the note.
struct NarrationGroundingTests {
    typealias Step = NarrationAudio.Heard.Step

    @Test func theModelsStepsComeThroughInOrder() throws {
        let steps = try #require(NarrationGrounding.steps([
            Step(at: 50, action: "pour", mass: 80),
            Step(at: 3, action: "bloom", mass: 40, note: "swirl"),
            Step(at: 150, action: "drawdown"),
        ], duration: 160, water: 200))
        #expect(steps.map(\.at) == [3, 50, 150])
        #expect(steps.map(\.action) == [.bloom, .pour, .wait])
        #expect(steps.map(\.mass) == [40, 80, nil])
        #expect(steps[0].note == "swirl")
        #expect(steps[2].note == StepAction.drawdown.label)
    }

    @Test func aStepPastTheNoteIsDropped() throws {
        let steps = try #require(NarrationGrounding.steps([
            Step(at: 10, action: "pour", mass: 100),
            Step(at: 400, action: "pour", mass: 200),
        ], duration: 120, water: nil))
        #expect(steps.map(\.mass) == [100])
    }

    @Test func anUnknownActionIsDropped() throws {
        let steps = try #require(NarrationGrounding.steps([
            Step(at: 10, action: "dance", mass: 100),
            Step(at: 20, action: "pour", mass: 100),
        ], duration: 60, water: nil))
        #expect(steps.map(\.action) == [.pour])
    }

    @Test func massesNeverGoBackAndStayNearTheWater() throws {
        let steps = try #require(NarrationGrounding.steps([
            Step(at: 5, action: "bloom", mass: 40),
            Step(at: 30, action: "pour", mass: 150),
            Step(at: 50, action: "pour", mass: 100),
            Step(at: 70, action: "pour", mass: 2500),
            Step(at: 90, action: "pour", mass: 250),
        ], duration: 120, water: 250))
        #expect(steps.map(\.mass) == [40, 150, 250])
    }

    @Test func aPourWithoutAMassIsNotAStep() throws {
        let steps = try #require(NarrationGrounding.steps([
            Step(at: 5, action: "pour"),
            Step(at: 20, action: "swirl", mass: 30),
        ], duration: 60, water: nil))
        #expect(steps.map(\.action) == [.swirl])
        #expect(steps[0].mass == nil)
    }

    @Test func nothingThatHoldsKeepsTheDevicesSteps() {
        #expect(NarrationGrounding.steps([], duration: 60, water: nil) == nil)
        #expect(NarrationGrounding.steps([Step(at: 500, action: "pour", mass: 40)], duration: 60, water: nil) == nil)
    }

    @Test func theFunctionsAnswerDecodes() throws {
        let json = """
        {"transcript":"Bloom 40","utterances":[{"at":3.2,"text":"Bloom 40"}],
         "steps":[{"at":3,"action":"bloom","mass":40,"until":null,"note":""}],
         "dose":null,"water":null,"seconds":null}
        """
        let heard = try JSONDecoder().decode(NarrationAudio.Heard.self, from: Data(json.utf8))
        #expect(heard.steps == [Step(at: 3, action: "bloom", mass: 40, until: nil, note: "")])
        #expect(heard.utterances?.first?.at == 3.2)
    }

    @Test func anOlderRecordStillDecodes() throws {
        let old = try JSONEncoder().encode(DictationRecord.Parsed(steps: []))
        var object = try #require(JSONSerialization.jsonObject(with: old) as? [String: Any])
        object.removeValue(forKey: "modelSteps")
        object.removeValue(forKey: "model")
        let parsed = try JSONDecoder().decode(
            DictationRecord.Parsed.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(parsed.modelSteps == nil)
    }

    @Test func theModelOnlyListensWhenTheAudioIsShared() {
        #expect(AIFeature.narration.function == "brew-narration")
        #expect(AIFeature.narration.isExperimental)
    }

    @Test func theSheetReplacesOnlyUntouchedSteps() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Kohi/Recipes/AfterBrewSheet.swift")
        let sheet = try String(contentsOf: url, encoding: .utf8)
        #expect(sheet.contains("session.brew.actualSteps == device"))
        #expect(sheet.contains("Copy.heardByModel"))
        #expect(sheet.contains("Button(\"Undo\", action: undoModelSteps)"))
    }
}
