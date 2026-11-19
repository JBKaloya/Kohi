import Foundation
import Testing
@testable import Kohi

/// Testers compare the readings of a note blind; what they pick must map
/// back to the pipeline that produced it.
@MainActor
struct NarrationCompareTests {
    typealias Candidate = NarrationCompare.Candidate
    typealias Remote = NarrationCompare.Remote
    typealias Step = NarrationAudio.Heard.Step

    /// Deterministic, so a shuffle can be checked.
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private func remote(_ pipeline: String, steps: [Step], transcript: String = "heard") -> Remote {
        Remote(
            pipeline: pipeline,
            ok: true,
            fields: NarrationAudio.Heard(transcript: transcript, steps: steps),
            model: "model",
            latencyMs: 1200,
            costUsd: 0.002
        )
    }

    private func candidates() -> [Candidate] {
        NarrationCompare.candidates(
            [
                remote("scribe+luna", steps: [Step(at: 3, action: "bloom", mass: 40), Step(at: 20, action: "pour", mass: 200)]),
                Remote(pipeline: "gemini-audio", ok: false, model: "timeout", latencyMs: 30_000, failure: "no answer in 30 s"),
                remote("openai+luna", steps: [Step(at: 400, action: "pour", mass: 200)]),
            ],
            duration: 60,
            water: 200,
            device: [SpokenBrewParser.TimedStep(at: 30, action: .pour, mass: 200)],
            deviceTranscript: "Et enfin je termine"
        )
    }

    @Test func theIPhoneComesFirstAndEveryVersionIsGrounded() {
        let all = candidates()
        #expect(all.map(\.pipeline) == ["device", "scribe+luna", "gemini-audio", "openai+luna"])
        #expect(all[0].transcript == "Et enfin je termine")
        #expect(all[0].steps.map(\.mass) == [200])
        #expect(all[1].steps.map(\.at) == [3, 20])
        #expect(all[2].ok == false)
        #expect(all[2].failure == "no answer in 30 s")
        // A step past the end of the note does not hold.
        #expect(all[3].steps.isEmpty)
    }

    @Test func theShuffleKeepsEveryVersionAndIsTheGeneratorsOrder() {
        var first = SeededGenerator(state: 7)
        var again = SeededGenerator(state: 7)
        let shown = NarrationCompare.shuffled(candidates(), using: &first)
        #expect(Set(shown.map(\.pipeline)) == Set(candidates().map(\.pipeline)))
        #expect(shown.map(\.pipeline) == NarrationCompare.shuffled(candidates(), using: &again).map(\.pipeline))
    }

    @Test func thePickMapsBackToItsPipelineWhateverTheOrderShown() throws {
        var generator = SeededGenerator(state: 3)
        let shown = NarrationCompare.shuffled(candidates(), using: &generator)
        let answer = NarrationCompare.Answer(chosen: "scribe+luna", comment: "  la bloom était à 3 s  ")
        let steps = try #require(NarrationCompare.pickedSteps(answer, shown: shown))
        #expect(steps.map(\.mass) == [40, 200])

        let trial = NarrationCompare.Trial(
            userID: UUID(), dictationID: nil, brewID: nil, duration: 60, shown: shown, answer: answer, appBuild: "1.0 (1)"
        )
        #expect(trial.shownOrder == shown.map(\.pipeline))
        #expect(trial.chosen == "scribe+luna")
        #expect(trial.comment == "la bloom était à 3 s")
    }

    @Test func skippingOrNoneRightLeavesTheSteps() {
        let shown = candidates()
        #expect(NarrationCompare.pickedSteps(.skip, shown: shown) == nil)
        #expect(NarrationCompare.pickedSteps(.init(chosen: "scribe+luna", noneRight: true), shown: shown) == nil)
        #expect(NarrationCompare.pickedSteps(.init(chosen: "gemini-audio"), shown: shown) == nil)
        #expect(NarrationCompare.pickedSteps(.init(chosen: "openai+luna"), shown: shown) == nil)
    }

    @Test func theRowUsesTheTableColumns() throws {
        let answer = NarrationCompare.Answer(chosen: "device", noneRight: true)
        let trial = NarrationCompare.Trial(
            userID: UUID(), dictationID: UUID(), brewID: UUID(), duration: 12, shown: candidates(), answer: answer
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(trial)) as? [String: Any]
        )
        for column in ["id", "user_id", "dictation_id", "brew_id", "duration_s", "candidates", "shown_order",
                       "none_right", "skipped", "comment", "app_build"] {
            #expect(object[column] != nil, "\(column)")
        }
        // None right: no pipeline was chosen.
        #expect(object["chosen"] == nil || object["chosen"] is NSNull)
        let first = try #require((object["candidates"] as? [[String: Any]])?.first)
        #expect(first["latency_ms"] != nil)
    }

    @Test func eachCloudVersionIsAnEventKeptOnlyWhenPicked() {
        let events = NarrationCompare.events(for: candidates(), answer: .init(chosen: "scribe+luna"))
        #expect(events.count == 3)
        #expect(events.map(\.feature) == [.narrationCompare, .narrationCompare, .narrationCompare])
        #expect(events.map(\.accepted) == [true, false, false])
        #expect(NarrationCompare.events(for: candidates(), answer: .skip).allSatisfy { $0.accepted == nil })
    }

    @Test func theGateNeedsSharingAndBothSwitches() {
        let defaults = UserDefaults(suiteName: "NarrationCompareTests.\(UUID())")!
        let flags = AIFlags(defaults: defaults)
        #expect(NarrationCompare.isEnabled(flags: flags, sharing: true))
        #expect(!NarrationCompare.isEnabled(flags: flags, sharing: false))
        flags.setOn(.narrationCompare, false)
        #expect(!NarrationCompare.isEnabled(flags: flags, sharing: true))
        flags.setOn(.narrationCompare, true)
        flags.setOn(.narration, false)
        #expect(!NarrationCompare.isEnabled(flags: flags, sharing: true))
    }
}
