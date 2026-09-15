import Foundation

/// Four-level usefulness score for a model output.
nonisolated enum AIFeedbackScore: Int, Codable, CaseIterable, Identifiable, Sendable {
    case notAtAll = 1
    case aLittle = 2
    case useful = 3
    case aLot = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .notAtAll: "Not at all"
        case .aLittle: "A little"
        case .useful: "Useful"
        case .aLot: "A lot"
        }
    }
}

/// One answer about one model output.
nonisolated struct AIFeedback: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var aiEventId: UUID?
    var feature: AIFeature
    var score: AIFeedbackScore
    var comment: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        aiEventId: UUID? = nil,
        feature: AIFeature,
        score: AIFeedbackScore,
        comment: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.aiEventId = aiEventId
        self.feature = feature
        self.score = score
        self.comment = comment
        self.createdAt = createdAt
    }

    /// CSV row: id, feature, score, comment, created_at.
    var csvLine: String {
        let comment = (comment ?? "")
            .replacingOccurrences(of: "\"", with: "\"\"")
        return [
            id.uuidString,
            feature.rawValue,
            String(score.rawValue),
            "\"\(comment)\"",
            createdAt.ISO8601Format()
        ].joined(separator: ",")
    }

    static let csvHeader = "id,feature,score,comment,created_at"
}

struct AIFeedbackRow: Codable, Sendable {
    let id: UUID
    let user_id: UUID
    var ai_event_id: UUID?
    var feature: String
    var score: Int
    var comment: String?
    var created_at: Date

    init(feedback: AIFeedback, userID: UUID) {
        id = feedback.id
        user_id = userID
        ai_event_id = feedback.aiEventId
        feature = feedback.feature.rawValue
        score = feedback.score.rawValue
        comment = feedback.comment
        created_at = feedback.createdAt
    }
}
