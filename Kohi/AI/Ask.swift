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

    /// Why no answer came back. The sheet used to collapse every case into
    /// a connection failure — a 429 quota and a missing plist look the same
    /// that way.
    enum Failure: Sendable, Equatable, Error {
        case off
        case notConfigured
        case unauthorized
        case busy
        case server
        case network
        case decode

        var message: String {
            switch self {
            case .off:
                "Ask is off."
            case .notConfigured:
                "Ask is not set up on this build."
            case .unauthorized:
                "This session cannot call Ask."
            case .busy:
                "Ask hit today's limit. Try again later."
            case .server:
                "The answer service failed. Try again in a moment."
            case .network:
                "No answer came back. Check the connection and try again."
            case .decode:
                "The answer came back unreadable."
            }
        }
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

    private struct ErrorBody: Decodable, Sendable {
        var error: String?
        var model: String?
    }

    @MainActor
    static func answer(
        to question: String,
        topic: String? = nil,
        flags: AIFlags,
        events: AIEventLog
    ) async -> Result<Answer, Failure> {
        guard flags.isOn(.ask) else { return .failure(.off) }
        guard let client = SupabaseConfig.current else { return .failure(.notConfigured) }
        guard let question = question.trimmed else { return .failure(.decode) }

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
            return .success(Answer(
                text: response.answer,
                isCovered: response.isCovered,
                sources: response.sources ?? [],
                eventID: eventID,
                tag: response.tag
            ))
        } catch {
            let failure = classify(error)
            events.record(AIEvent(
                feature: .ask,
                model: "unknown",
                latencyMs: FieldExtract.elapsed(since: started),
                accepted: false,
                failure: "\(error)"
            ))
            log(failure, error: error)
            return .failure(failure)
        }
    }

    static func classify(_ error: Error) -> Failure {
        if let functions = error as? FunctionsError {
            switch functions {
            case .httpError(let code, let data):
                return classify(http: code, body: data)
            case .relayError:
                return .network
            }
        }
        if error is DecodingError { return .decode }
        if error is URLError { return .network }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return .network }
        return .server
    }

    static func classify(http status: Int, body: Data) -> Failure {
        let payload = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error ?? ""
        let text = payload + (String(data: body, encoding: .utf8) ?? "")
        if status == 401 || status == 403 { return .unauthorized }
        if status == 429 || text.contains("429") || text.localizedCaseInsensitiveContains("quota") {
            return .busy
        }
        if status == 500, text.contains("not configured") { return .notConfigured }
        if (500...599).contains(status) { return .server }
        return .server
    }

    private static func log(_ failure: Failure, error: Error) {
        let status: String
        let body: String
        if let functions = error as? FunctionsError, case .httpError(let code, let data) = functions {
            status = "\(code)"
            body = String(data: data, encoding: .utf8) ?? ""
        } else {
            status = "—"
            body = "\(error)"
        }
        #if DEBUG
        Log.app.notice("ask failed \(String(describing: failure), privacy: .public) status=\(status, privacy: .public) body=\(body, privacy: .public)")
        #else
        Log.app.notice("ask failed \(String(describing: failure), privacy: .public) status=\(status, privacy: .public)")
        #endif
    }
}
