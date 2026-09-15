import Foundation
import Supabase
import os

/// Three ranked moves, chosen from the admissible set. The model may not
/// invent a variable the rules did not offer.
nonisolated struct SuggestedCorrection: Hashable, Sendable {
    var reading: String
    var target: String
    var moves: [Move]
    var eventID: UUID?
    var isModel: Bool

    struct Move: Hashable, Sendable, Identifiable, Codable {
        var rank: Int
        var variable: String
        var change: String
        var why: String
        var effect: [String: String]?

        var id: Int { rank }

        var line: String {
            "\(rank) · \(change.capitalizedFirst)"
        }
    }

    struct Payload: Codable, Sendable {
        var reading: String
        var target: String
        var moves: [Move]
    }

    /// JSON that names three moves, all of them in `allowed`.
    static func validated(_ data: Data, allowed: [NextTime]) -> Payload? {
        let decoded: Payload
        do {
            decoded = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            return nil
        }
        return validated(decoded, allowed: allowed)
    }

    static func validated(_ payload: Payload, allowed: [NextTime]) -> Payload? {
        guard payload.moves.count == 3 else { return nil }
        let allowedChanges = Set(allowed.map { $0.change.lowercased() })
        let allowedVariables = Set(allowed.map { $0.variable.rawValue })
        let ranks = payload.moves.map(\.rank).sorted()
        guard ranks == [1, 2, 3] else { return nil }
        for move in payload.moves {
            let knownChange = allowedChanges.contains(move.change.lowercased())
            let knownVariable = allowedVariables.contains(move.variable)
            guard knownChange || knownVariable else { return nil }
        }
        return payload
    }

    /// Offline: the highest-priority rule, as a single-move correction.
    static func fallback(from brew: Brew, equipment: [Equipment] = []) -> SuggestedCorrection? {
        let allowed = BrewDiagnosis.admissibleSet(for: brew, equipment: equipment)
        guard let first = allowed.min(by: { $0.variable.priority < $1.variable.priority })
                ?? allowed.first else { return nil }
        return SuggestedCorrection(
            reading: first.reason.capitalizedFirst,
            target: first.change,
            moves: [
                Move(rank: 1, variable: first.variable.rawValue, change: first.change, why: first.reason)
            ],
            eventID: nil,
            isModel: false
        )
    }

    @MainActor
    static func ranked(
        for brew: Brew,
        card: CoffeeCard?,
        comment: String,
        equipment: [Equipment],
        flags: AIFlags,
        events: AIEventLog
    ) async -> SuggestedCorrection? {
        let allowed = BrewDiagnosis.admissibleSet(for: brew, equipment: equipment)
        guard !allowed.isEmpty else { return nil }

        if flags.isOn(.suggestedCorrection), let client = SupabaseConfig.current {
            if let ranked = await askModel(
                brew: brew,
                card: card,
                comment: comment,
                allowed: allowed,
                client: client,
                events: events
            ) {
                return ranked
            }
        }
        return fallback(from: brew, equipment: equipment)
    }

    private struct Request: Encodable {
        var readingHint: String?
        var comment: String
        var allowed: [Allowed]
        struct Allowed: Encodable {
            var variable: String
            var change: String
            var why: String
        }
    }

    private struct Envelope: Decodable, Sendable {
        var reading: String
        var target: String
        var moves: [Move]
        var model: String?
        var inputTokens: Int?
        var outputTokens: Int?
        var latencyMs: Int?
    }

    @MainActor
    private static func askModel(
        brew: Brew,
        card: CoffeeCard?,
        comment: String,
        allowed: [NextTime],
        client: SupabaseClient,
        events: AIEventLog
    ) async -> SuggestedCorrection? {
        let started = Date.now
        let request = Request(
            readingHint: BrewDiagnosis.nextTime(for: brew)?.reason,
            comment: comment,
            allowed: allowed.map {
                Request.Allowed(variable: $0.variable.rawValue, change: $0.change, why: $0.reason)
            }
        )
        do {
            let envelope: Envelope = try await client.functions.invoke(
                "suggested-correction",
                options: FunctionInvokeOptions(body: request)
            )
            let payload = Payload(reading: envelope.reading, target: envelope.target, moves: envelope.moves)
            guard let valid = validated(payload, allowed: allowed) else {
                events.record(AIEvent(
                    feature: .suggestedCorrection,
                    model: envelope.model ?? "unknown",
                    latencyMs: envelope.latencyMs ?? FieldExtract.elapsed(since: started),
                    accepted: false,
                    failure: "invalid JSON"
                ))
                return nil
            }
            let eventID = events.record(AIEvent(
                feature: .suggestedCorrection,
                model: envelope.model ?? "suggested-correction",
                inputTokens: envelope.inputTokens,
                outputTokens: envelope.outputTokens,
                latencyMs: envelope.latencyMs ?? FieldExtract.elapsed(since: started)
            ))
            return SuggestedCorrection(
                reading: valid.reading,
                target: valid.target,
                moves: valid.moves,
                eventID: eventID,
                isModel: true
            )
        } catch {
            events.record(AIEvent(
                feature: .suggestedCorrection,
                model: "unknown",
                latencyMs: FieldExtract.elapsed(since: started),
                accepted: false,
                failure: "\(error)"
            ))
            return nil
        }
    }
}
