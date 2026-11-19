import Foundation
import Supabase
import os

/// The second listener for a Live brew. The device has already read the
/// note; this sends the same audio to the model, which hears what Speech
/// dropped between pauses and the patterns the grammar cannot expand.
///
/// It only runs with the feature on and dictations shared, since the audio
/// leaves the phone. Any failure returns nil and the device's steps stay.
nonisolated enum NarrationAudio {
    /// Inline audio past this is refused by the model; a brew note is far below.
    static let maxBytes = 12_000_000

    struct Context: Encodable, Sendable {
        var method: String?
        var dose: Double?
        var water: Double?
        var duration: Double?
        var recipe: [String] = []
        var vocabulary: [String] = []
    }

    struct Heard: Decodable, Sendable {
        struct Utterance: Decodable, Sendable {
            var at: Double
            var text: String
        }

        struct Step: Decodable, Equatable, Sendable {
            var at: Int
            var action: String
            var mass: Double?
            var until: Int?
            var note: String?
        }

        var transcript: String?
        var utterances: [Utterance]?
        var steps: [Step]?
        var dose: Double?
        var water: Double?
        var seconds: Int?
    }

    struct Outcome: Sendable {
        var heard: Heard
        var model: String
        var eventID: UUID
    }

    private struct Envelope: Decodable, Sendable {
        var fields: Heard
        var model: String
        var inputTokens: Int?
        var outputTokens: Int?
        var latencyMs: Int?
    }

    @MainActor
    static func isAllowed(flags: AIFlags, sharing: Bool) -> Bool {
        sharing && flags.isOn(.narration)
    }

    @MainActor
    static func read(
        audio: Data,
        context: Context,
        flags: AIFlags,
        sharing: Bool,
        events: AIEventLog
    ) async -> Outcome? {
        guard isAllowed(flags: flags, sharing: sharing),
              !audio.isEmpty, audio.count <= maxBytes,
              let client = SupabaseConfig.current
        else { return nil }

        struct Payload: Encodable {
            let audio: String
            let mime = "audio/mp4"
            let context: Context
        }

        let started = Date.now
        do {
            let envelope: Envelope = try await client.functions.invoke(
                "brew-narration",
                options: FunctionInvokeOptions(
                    body: Payload(audio: audio.base64EncodedString(), context: context)
                )
            )
            let id = events.record(AIEvent(
                feature: .narration,
                model: envelope.model,
                inputTokens: envelope.inputTokens,
                outputTokens: envelope.outputTokens,
                latencyMs: envelope.latencyMs ?? FieldExtract.elapsed(since: started)
            ))
            return Outcome(heard: envelope.fields, model: envelope.model, eventID: id)
        } catch {
            events.record(AIEvent(
                feature: .narration,
                model: "unknown",
                latencyMs: FieldExtract.elapsed(since: started),
                accepted: false,
                failure: "\(error)"
            ))
            Log.app.notice("brew narration failed, keeping the device's steps (\(error))")
            return nil
        }
    }
}

/// What the model heard, checked against what cannot be argued with: the
/// length of the note, the actions a step can be, and the water.
nonisolated enum NarrationGrounding {
    typealias TimedStep = SpokenBrewParser.TimedStep

    /// A mass past this share of the water is a misheard number.
    static let waterCeiling = 1.3
    /// Seconds a step may sit past the end of the note: the last word is
    /// said as the recording stops.
    static let durationSlack = 2

    private static let allowed: Set<StepAction> = [
        .bloom, .pour, .swirl, .stir, .wait, .press, .steep, .rinse,
    ]

    /// The steps to show, or nil when nothing the model said holds, which
    /// keeps the device's steps.
    static func steps(
        _ heard: [NarrationAudio.Heard.Step],
        duration: TimeInterval,
        water: Double?
    ) -> [TimedStep]? {
        let end = Int(duration.rounded(.up)) + durationSlack
        let ceiling = water.map { $0 * waterCeiling }
        var reached = 0.0
        var steps: [TimedStep] = []
        for step in heard.sorted(by: { $0.at < $1.at }) {
            guard step.at >= 0, duration <= 0 || step.at <= end else { continue }
            let note = step.note?.trimmed ?? ""
            let action: StepAction
            var label = note
            if step.action == "drawdown" {
                action = .wait
                label = note.isEmpty ? StepAction.drawdown.label : note
            } else if let known = StepAction(rawValue: step.action), allowed.contains(known) {
                action = known
            } else {
                continue
            }
            var mass: Double?
            if PourSplit.carriesWater(action) {
                guard let said = step.mass, said > 0 else {
                    if action == .pour || action == .bloom { continue }
                    steps.append(TimedStep(at: step.at, action: action, note: label))
                    continue
                }
                if said < reached { continue }
                if let ceiling, said > ceiling { continue }
                reached = said
                mass = said
            }
            let until = step.until.flatMap { $0 > step.at ? $0 : nil }
            steps.append(TimedStep(at: step.at, action: action, mass: mass, until: until, note: label))
        }
        return steps.isEmpty ? nil : steps
    }
}
