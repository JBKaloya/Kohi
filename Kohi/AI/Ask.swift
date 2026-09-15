import Foundation
import Supabase
import os

/// Questions answered from the curated base, with the sources named.
///
/// The interesting case is the one where it declines: `isCovered == false`
/// means the base does not go there, and the app shows that rather than a
/// paragraph. A knowledge feature that never says "I don't know" is not a
/// knowledge feature.
nonisolated enum Ask {
    struct Answer: Sendable, Hashable, Identifiable {
        var id: UUID { eventID }
        var text: String
        var isCovered: Bool
        var sources: [Source]
        var eventID: UUID

        struct Source: Decodable, Sendable, Hashable, Identifiable {
            let id: String
            let title: String
            let source: String
        }

        /// "general" when the model left the base; "off-topic" when it refused.
        var tag: String?
    }

    private struct Response: Decodable, Sendable {
        var answer: String
        var isCovered: Bool
        var sources: [Answer.Source]?
        var tag: String?
        var model: String
        var inputTokens: Int?
        var outputTokens: Int?
        var latencyMs: Int?
    }

    @MainActor
    static func answer(
        to question: String,
        topic: String? = nil,
        flags: AIFlags,
        events: AIEventLog
    ) async -> Answer? {
        guard flags.isOn(.ask), let client = SupabaseConfig.current else { return nil }
        guard let question = question.trimmed else { return nil }

        struct Payload: Encodable {
            let question: String
            let topic: String?
        }

        let started = Date.now
        do {
            let response: Response = try await client.functions.invoke(
                "ask",
                options: FunctionInvokeOptions(body: Payload(question: question, topic: topic))
            )
            let eventID = events.record(AIEvent(
                feature: .ask,
                model: response.model,
                inputTokens: response.inputTokens,
                outputTokens: response.outputTokens,
                latencyMs: response.latencyMs ?? FieldExtract.elapsed(since: started)
            ))
            return Answer(
                text: response.answer,
                isCovered: response.isCovered,
                sources: response.sources ?? [],
                eventID: eventID,
                tag: response.tag
            )
        } catch {
            events.record(AIEvent(
                feature: .ask,
                model: "unknown",
                latencyMs: FieldExtract.elapsed(since: started),
                accepted: false,
                failure: "\(error)"
            ))
            Log.app.notice("ask failed (\(error))")
            return nil
        }
    }
}
