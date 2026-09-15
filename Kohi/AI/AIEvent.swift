import Foundation
import Observation
import Supabase
import os

/// One call to a model: what it was for, what it cost, how long it took, and
/// whether you kept what it said.
///
/// The last field is the only one that matters in the end. Latency and tokens
/// say what a feature costs; `accepted` says whether it was worth it, and it
/// is what decides which of these features survives past the experiment.
nonisolated struct AIEvent: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var feature: AIFeature
    var model: String
    var inputTokens: Int?
    var outputTokens: Int?
    /// Round trip in milliseconds, measured from the app.
    var latencyMs: Int
    /// Nil until the answer is either kept or dismissed. A feature nobody
    /// answers for is a feature nobody used.
    var accepted: Bool?
    var failure: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        feature: AIFeature,
        model: String,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        latencyMs: Int,
        accepted: Bool? = nil,
        failure: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.feature = feature
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.latencyMs = latencyMs
        self.accepted = accepted
        self.failure = failure
        self.createdAt = createdAt
    }
}

/// DTO for `public.ai_events`.
struct AIEventRow: Codable, Sendable {
    let id: UUID
    let user_id: UUID

    var feature: String
    var model: String
    var input_tokens: Int?
    var output_tokens: Int?
    var latency_ms: Int
    var accepted: Bool?
    var failure: String?
    var created_at: Date

    init(event: AIEvent, userID: UUID) {
        id = event.id
        user_id = userID
        feature = event.feature.rawValue
        model = event.model
        input_tokens = event.inputTokens
        output_tokens = event.outputTokens
        latency_ms = event.latencyMs
        accepted = event.accepted
        failure = event.failure
        created_at = event.createdAt
    }
}

/// Buffers events and sends them when there is somewhere to send them.
///
/// Deliberately not part of the outbox: telemetry that fails to upload should
/// be dropped, not retried forever, and it must never sit in the same queue as
/// a brew you wrote.
@Observable
@MainActor
final class AIEventLog {
    private(set) var pending: [AIEvent] = []
    /// Kept for the account sheet: how the layer is behaving, in one line.
    private(set) var recent: [AIEvent] = []

    private var client: SupabaseClient?
    private var userID: UUID?
    private static let maximumPending = 200

    func attach(client: SupabaseClient?, userID: UUID?) {
        self.client = client
        self.userID = userID
        if client != nil, userID != nil { flushSoon() }
    }

    @discardableResult
    func record(_ event: AIEvent) -> UUID {
        pending.append(event)
        recent.insert(event, at: 0)
        if recent.count > 20 { recent.removeLast() }
        if pending.count > Self.maximumPending { pending.removeFirst() }
        flushSoon()
        return event.id
    }

    /// The verdict, given later: the same event, answered.
    func setAccepted(_ accepted: Bool, for id: UUID) {
        if let index = pending.firstIndex(where: { $0.id == id }) {
            pending[index].accepted = accepted
        } else if let event = recent.first(where: { $0.id == id }) {
            // Already sent: an update row with the same id upserts over it.
            var answered = event
            answered.accepted = accepted
            pending.append(answered)
        }
        if let index = recent.firstIndex(where: { $0.id == id }) {
            recent[index].accepted = accepted
        }
        flushSoon()
    }

    /// A rough acceptance rate over what is still in memory, for the account
    /// sheet. Not a metric to optimise, a smell to notice.
    var acceptanceLine: String? {
        let answered = recent.compactMap(\.accepted)
        guard answered.count >= 3 else { return nil }
        let kept = answered.filter { $0 }.count
        return "\(kept) of \(answered.count) kept"
    }

    private func flushSoon() {
        guard let client, let userID, !pending.isEmpty else { return }
        let batch = pending
        pending = []
        Task {
            do {
                try await client
                    .from("ai_events")
                    .upsert(batch.map { AIEventRow(event: $0, userID: userID) })
                    .execute()
            } catch {
                Log.app.notice("ai events not sent, dropping the batch (\(error))")
            }
        }
    }
}
