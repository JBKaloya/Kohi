import Foundation
import Supabase
import os

/// Testers compare every way of hearing a Live note on their own brews: the
/// iPhone's reading and each cloud pipeline, shown blind and shuffled. What
/// they pick, and what they would change, decides which pipeline ships.
nonisolated enum NarrationCompare {
    typealias TimedStep = SpokenBrewParser.TimedStep

    /// The iPhone's own reading, shown among the others.
    static let device = "device"

    /// Debug or TestFlight, the server switch and yours, and dictations
    /// shared: the audio goes to every provider being compared.
    @MainActor
    static func isEnabled(flags: AIFlags, sharing: Bool) -> Bool {
        TesterBuild.isTester && NarrationAudio.isAllowed(flags: flags, sharing: sharing)
            && flags.isOn(.narrationCompare)
    }

    /// One version of the note, as it is shown and as it is kept.
    struct Candidate: Codable, Equatable, Identifiable, Sendable {
        var pipeline: String
        var ok: Bool
        var model: String
        var transcript: String
        var steps: [TimedStep]
        var latencyMs: Int
        var costUsd: Double?
        var failure: String?

        var id: String { pipeline }

        enum CodingKeys: String, CodingKey {
            case pipeline, ok, model, transcript, steps, failure
            case latencyMs = "latency_ms"
            case costUsd = "cost_usd"
        }
    }

    /// What the tester said. Nil `chosen` with neither flag set never leaves
    /// the sheet.
    struct Answer: Equatable, Sendable {
        var chosen: String?
        var noneRight = false
        var skipped = false
        var comment = ""

        static let skip = Answer(skipped: true)
    }

    /// What narration-compare returns for one pipeline.
    struct Remote: Decodable, Sendable {
        var pipeline: String
        var ok: Bool
        var fields: NarrationAudio.Heard?
        var model: String
        var latencyMs: Int
        var costUsd: Double?
        var failure: String?
    }

    private struct Envelope: Decodable, Sendable {
        var candidates: [Remote]
    }

    /// The row in `public.narration_trials`.
    struct Trial: Encodable, Sendable {
        var id = UUID()
        var userID: UUID
        var dictationID: UUID?
        var brewID: UUID?
        var duration: Double
        var candidates: [Candidate]
        var shownOrder: [String]
        var chosen: String?
        var noneRight: Bool
        var skipped: Bool
        var comment: String
        var appBuild: String

        enum CodingKeys: String, CodingKey {
            case id, candidates, chosen, skipped, comment
            case userID = "user_id"
            case dictationID = "dictation_id"
            case brewID = "brew_id"
            case duration = "duration_s"
            case shownOrder = "shown_order"
            case noneRight = "none_right"
            case appBuild = "app_build"
        }

        init(
            userID: UUID,
            dictationID: UUID?,
            brewID: UUID?,
            duration: Double,
            shown: [Candidate],
            answer: Answer,
            appBuild: String = DictationArchive.appBuild
        ) {
            self.userID = userID
            self.dictationID = dictationID
            self.brewID = brewID
            self.duration = duration
            candidates = shown
            shownOrder = shown.map(\.pipeline)
            chosen = answer.skipped || answer.noneRight ? nil : answer.chosen
            noneRight = answer.noneRight
            skipped = answer.skipped
            comment = answer.comment.trimmingCharacters(in: .whitespacesAndNewlines)
            self.appBuild = appBuild
        }
    }

    /// Every version, each checked the way the model's steps are before they
    /// are shown, the iPhone's first. The order shown is `shuffled`'s.
    static func candidates(
        _ remote: [Remote],
        duration: TimeInterval,
        water: Double?,
        device steps: [TimedStep],
        deviceTranscript: String
    ) -> [Candidate] {
        let iPhone = Candidate(
            pipeline: device,
            ok: true,
            model: "on-device",
            transcript: deviceTranscript,
            steps: steps,
            latencyMs: 0
        )
        return [iPhone] + remote.map { answer in
            let heard = answer.fields
            let grounded = heard.flatMap {
                NarrationGrounding.steps(
                    $0.steps ?? [],
                    duration: duration,
                    water: water ?? $0.water,
                    device: steps
                )
            } ?? []
            return Candidate(
                pipeline: answer.pipeline,
                ok: answer.ok,
                model: answer.model,
                transcript: heard?.transcript ?? "",
                steps: grounded,
                latencyMs: answer.latencyMs,
                costUsd: answer.costUsd,
                failure: answer.failure
            )
        }
    }

    static func shuffled<Generator: RandomNumberGenerator>(
        _ candidates: [Candidate],
        using generator: inout Generator
    ) -> [Candidate] {
        candidates.shuffled(using: &generator)
    }

    /// The events for the account sheet and `ai_events`: one per cloud
    /// version, kept when it was the one picked.
    static func events(for shown: [Candidate], answer: Answer) -> [AIEvent] {
        shown.filter { $0.pipeline != device }.map { candidate in
            AIEvent(
                feature: .narrationCompare,
                model: "\(candidate.pipeline): \(candidate.model)",
                latencyMs: candidate.latencyMs,
                accepted: answer.skipped ? nil : answer.chosen == candidate.pipeline && !answer.noneRight,
                failure: candidate.failure
            )
        }
    }

    /// Every pipeline on the same note. Nil on any failure: the comparison
    /// is simply not offered.
    @MainActor
    static func fetch(audio: Data, context: NarrationAudio.Context) async -> [Remote]? {
        guard !audio.isEmpty, audio.count <= NarrationAudio.maxBytes,
              let client = SupabaseConfig.current
        else { return nil }

        struct Payload: Encodable {
            let audio: String
            let mime = "audio/mp4"
            let context: NarrationAudio.Context
        }

        do {
            let envelope: Envelope = try await client.functions.invoke(
                "narration-compare",
                options: FunctionInvokeOptions(
                    body: Payload(audio: audio.base64EncodedString(), context: context)
                )
            )
            return envelope.candidates
        } catch {
            Log.app.notice("narration compare failed, nothing to compare (\(error))")
            return nil
        }
    }

    /// Sends the answer. Telemetry: a failure is logged and dropped.
    @MainActor
    static func send(
        _ answer: Answer,
        shown: [Candidate],
        dictationID: UUID?,
        brewID: UUID?,
        duration: Double,
        events: AIEventLog
    ) {
        for event in Self.events(for: shown, answer: answer) { events.record(event) }
        guard let client = SupabaseConfig.current else { return }
        Task {
            do {
                let userID = try await client.auth.session.user.id
                let trial = Trial(
                    userID: userID,
                    dictationID: dictationID,
                    brewID: brewID,
                    duration: duration,
                    shown: shown,
                    answer: answer
                )
                try await client.from("narration_trials").insert(trial).execute()
            } catch {
                Log.app.notice("narration trial not sent (\(error))")
            }
        }
    }
}
