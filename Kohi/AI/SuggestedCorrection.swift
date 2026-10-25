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
        /// The chain from the wish to this move: extraction factors, then
        /// coffee factors. Empty from older payloads.
        var because: [String]?
        /// "high", "medium" or "low".
        var confidence: String?

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
    static func fallback(
        from brew: Brew,
        card: CoffeeCard? = nil,
        equipment: [Equipment] = [],
        filterStock: [FilterStock] = [],
        tasting: [TastingIntent] = []
    ) -> SuggestedCorrection? {
        let allowed = BrewDiagnosis.admissibleSet(
            for: brew,
            equipment: equipment,
            filterStock: filterStock,
            tasting: tasting,
            card: card
        )
        guard let first = allowed.min(by: { $0.variable.priority < $1.variable.priority })
                ?? allowed.first else { return nil }
        return SuggestedCorrection(
            reading: first.reason.capitalizedFirst,
            target: first.change,
            moves: [
                Move(
                    rank: 1,
                    variable: first.variable.rawValue,
                    change: first.change,
                    why: first.reason,
                    because: because(for: brew, card: card),
                    confidence: confidence(of: first.evidence)
                )
            ],
            eventID: nil,
            isModel: false
        )
    }

    /// What the rule stood on, in the order the screen reads: the wish,
    /// then the extraction, then the coffee.
    static func because(for brew: Brew, card: CoffeeCard?) -> [String] {
        var chain = BrewWish.Axis.allCases.compactMap { axis -> String? in
            let wish = BrewWish.wish(axis, of: brew)
            return wish == 0 ? nil : BrewWish.caption(axis, wish: wish)
        }
        let reading = ExtractionReading.read(brew, card: card)
        chain += reading.extractionFactors.prefix(1).map { "\($0.label.lowercased()) \($0.value)" }
        chain += reading.coffeeFactors.prefix(1).map { "\($0.label.lowercased()) \($0.value)" }
        return chain
    }

    static func confidence(of evidence: Evidence) -> String {
        switch evidence {
        case .verified: "high"
        case .partial, .practice: "medium"
        case .unverified: "low"
        }
    }

    /// Stable for one brew + comment + admissible set. Reopening After with
    /// the same diagnosis must not spend another generate.
    static func cacheKey(
        brew: Brew,
        comment: String,
        equipment: [Equipment],
        filterStock: [FilterStock] = []
    ) -> String {
        cacheKey(
            brew: brew,
            comment: comment,
            allowed: BrewDiagnosis.admissibleSet(for: brew, equipment: equipment, filterStock: filterStock)
        )
    }

    static func cacheKey(brew: Brew, comment: String, allowed: [NextTime]) -> String {
        let moves = allowed
            .map { "\($0.variable.rawValue)\u{1f}\($0.change)" }
            .sorted()
            .joined(separator: "\n")
        return [brew.id.uuidString, comment, moves].joined(separator: "\u{1e}")
    }

    @MainActor
    static func ranked(
        for brew: Brew,
        card: CoffeeCard?,
        comment: String,
        equipment: [Equipment],
        filterStock: [FilterStock] = [],
        flags: AIFlags,
        events: AIEventLog,
        refresh: Bool = false
    ) async -> SuggestedCorrection? {
        let allowed = BrewDiagnosis.admissibleSet(
            for: brew,
            equipment: equipment,
            filterStock: filterStock,
            tasting: TastingIntent.confirmed(from: comment),
            card: card
        )
        guard !allowed.isEmpty else { return nil }
        let key = cacheKey(brew: brew, comment: comment, allowed: allowed)

        if flags.isOn(.suggestedCorrection) {
            if !refresh, let cached = AICallCache.suggested(for: key) {
                return cached
            }
            if let client = SupabaseConfig.current,
               let ranked = await askModel(
                    brew: brew,
                    card: card,
                    comment: comment,
                    allowed: allowed,
                    client: client,
                    events: events
               ) {
                AICallCache.store(ranked, for: key)
                return ranked
            }
        }
        return fallback(
            from: brew,
            card: card,
            equipment: equipment,
            filterStock: filterStock,
            tasting: TastingIntent.confirmed(from: comment)
        )
    }

    private struct Request: Encodable {
        var readingHint: String?
        var comment: String
        var recipeName: String?
        var actualSource: String?
        var pourRates: [String]
        var deviations: Int
        /// "less bitterness", "more complexity".
        var wishes: [String]
        var reading: ExtractionReading
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
            recipeName: brew.recipeName ?? brew.title,
            actualSource: brew.actualSource.rawValue,
            pourRates: brew.pourRates.map(\.tag),
            deviations: brew.deviations.filter(\.isMaterial).count,
            wishes: BrewWish.Axis.allCases.compactMap { axis in
                let wish = BrewWish.wish(axis, of: brew)
                return wish == 0 ? nil : BrewWish.caption(axis, wish: wish)
            },
            reading: ExtractionReading.read(brew, card: card),
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
