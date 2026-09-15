import Foundation
import Observation
import Supabase
import os

/// Local feedback log, pushed when signed in, exportable as CSV.
@Observable
@MainActor
final class AIFeedbackStore {
    private(set) var items: [AIFeedback] = []

    @ObservationIgnored private let files: JSONFileStore<AIFeedback>
    private var client: SupabaseClient?
    private var userID: UUID?

    init(files: JSONFileStore<AIFeedback> = JSONFileStore(filename: "ai-feedback.json")) {
        self.files = files
        items = files.load().sorted { $0.createdAt > $1.createdAt }
    }

    func attach(client: SupabaseClient?, userID: UUID?) {
        self.client = client
        self.userID = userID
        if client != nil, userID != nil { flushSoon() }
    }

    @discardableResult
    func add(_ feedback: AIFeedback) -> AIFeedback {
        if let index = items.firstIndex(where: { $0.aiEventId != nil && $0.aiEventId == feedback.aiEventId }) {
            items[index] = feedback
        } else {
            items.insert(feedback, at: 0)
        }
        persist()
        flushSoon()
        return feedback
    }

    var csv: String {
        ([AIFeedback.csvHeader] + items.map(\.csvLine)).joined(separator: "\n")
    }

    func persist() {
        try? files.save(items)
    }

    private func flushSoon() {
        guard let client, let userID, !items.isEmpty else { return }
        let batch = items
        Task {
            do {
                try await client
                    .from("ai_feedback")
                    .upsert(batch.map { AIFeedbackRow(feedback: $0, userID: userID) })
                    .execute()
            } catch {
                Log.app.notice("ai feedback not sent (\(error))")
            }
        }
    }
}
