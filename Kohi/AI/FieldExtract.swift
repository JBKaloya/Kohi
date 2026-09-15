import Foundation
import Supabase
import os

/// The second reader. Called only when the local grammar came back thin, and
/// only when the feature is on.
///
/// Everything it returns is a suggestion for an empty field. It cannot
/// overwrite, it cannot delete, and the caller records whether what came back
/// was kept — which is the only number that will decide whether this stays.
nonisolated enum FieldExtract {
    struct Outcome<Value: Sendable>: Sendable {
        var value: Value
        /// The event id, so the caller can answer for it later.
        var eventID: UUID
    }

    /// What the model made of a dictated phrase.
    struct Spoken: Decodable, Sendable {
        var dose: Double?
        var water: Double?
        var beverage: Double?
        var seconds: Int?
        var temperature: Double?
        var grind: String?
        var method: String?
        var rating: Int?
        var flavors: [String]?
        var notes: String?

        /// Into the same shape the on-device parser produces, so the caller
        /// applies one thing either way.
        func asResult() -> SpokenBrewParser.Result {
            var result = SpokenBrewParser.Result()
            result.dose = dose
            result.water = water
            result.beverage = beverage
            result.seconds = seconds
            if let temperature, (60...100).contains(temperature) {
                result.temperature = temperature
            }
            result.grind = grind?.trimmed
            result.method = method.flatMap { BrewMethod(rawValue: $0) }
            if let rating, (1...5).contains(rating) { result.rating = rating }
            result.flavors = flavors ?? []
            result.leftover = notes?.trimmed ?? ""
            result.confidence = result.isEmpty ? 0 : 1
            return result
        }
    }

    private struct Envelope<Fields: Decodable & Sendable>: Decodable, Sendable {
        var fields: Fields
        var model: String
        var inputTokens: Int?
        var outputTokens: Int?
        var latencyMs: Int?
    }

    /// Reads a dictated sentence. Returns nil on any failure, which leaves
    /// whatever the on-device parse found in place.
    @MainActor
    static func brew(
        transcript: String,
        context: String = "",
        flags: AIFlags,
        events: AIEventLog
    ) async -> Outcome<SpokenBrewParser.Result>? {
        guard flags.isOn(.fieldExtract), let client = SupabaseConfig.current else { return nil }

        struct Payload: Encodable {
            let kind = "brew"
            let transcript: String
            let context: String
        }

        let started = Date.now
        do {
            let envelope: Envelope<Spoken> = try await client.functions.invoke(
                "field-extract",
                options: FunctionInvokeOptions(
                    body: Payload(transcript: transcript, context: context)
                )
            )
            let id = events.record(AIEvent(
                feature: .fieldExtract,
                model: envelope.model,
                inputTokens: envelope.inputTokens,
                outputTokens: envelope.outputTokens,
                latencyMs: envelope.latencyMs ?? elapsed(since: started)
            ))
            return Outcome(value: envelope.fields.asResult(), eventID: id)
        } catch {
            events.record(AIEvent(
                feature: .fieldExtract,
                model: "unknown",
                latencyMs: elapsed(since: started),
                accepted: false,
                failure: "\(error)"
            ))
            Log.app.notice("field extract failed, keeping the local parse (\(error))")
            return nil
        }
    }

    /// What the model made of a photographed receipt, bag or water label.
    struct Label: Decodable, Sendable {
        var kind: String?
        var price: Double?
        var currency: String?
        var shop: String?
        var bagWeightGrams: Double?
        var name: String?
        var roaster: String?
        var country: String?
        var region: String?
        var process: String?
        var variety: String?
        var roastLevel: String?
        var roastedOn: String?
        var lot: String?
        var tastingNotes: [String]?
        var waterName: String?
        var calcium: Double?
        var magnesium: Double?
        var sodium: Double?
        var bicarbonate: Double?
        var tds: Double?

        /// The card fields, for a bag or a receipt.
        func asFields() -> ParsedFields {
            var fields = ParsedFields()
            fields.name = name?.trimmed
            fields.roaster = (roaster ?? shop)?.trimmed
            fields.country = country?.trimmed
            fields.region = region?.trimmed
            fields.process = process?.trimmed
            fields.variety = variety?.trimmed
            fields.lot = lot?.trimmed
            fields.tastingNotes = tastingNotes ?? []
            fields.roastLevel = roastLevel.flatMap { RoastLevel(rawValue: $0) }
            fields.roastedOn = roastedOn.flatMap { BagFieldParser.date(in: $0) }
            if let price, price > 0 {
                fields.price = price
                fields.currency = currency?.uppercased()
            }
            if let grams = bagWeightGrams, (50...5000).contains(grams) {
                fields.bagWeightG = grams
            }
            return fields
        }

        /// The water profile, when that is what was photographed.
        func asWaterProfile() -> WaterProfile? {
            guard kind == "water" || waterName != nil else { return nil }
            var profile = WaterProfile(
                name: waterName?.trimmed ?? "Bottled water",
                source: .bottled
            )
            profile.calcium = calcium
            profile.magnesium = magnesium
            profile.sodium = sodium
            profile.bicarbonate = bicarbonate
            profile.tds = tds
            return profile
        }
    }

    @MainActor
    static func label(
        jpeg: Data,
        context: String = "",
        flags: AIFlags,
        events: AIEventLog
    ) async -> Outcome<Label>? {
        guard flags.isOn(.fieldExtract), let client = SupabaseConfig.current else { return nil }

        struct Payload: Encodable {
            let kind = "label"
            let image: String
            let mime = "image/jpeg"
            let context: String
        }

        let started = Date.now
        do {
            let envelope: Envelope<Label> = try await client.functions.invoke(
                "field-extract",
                options: FunctionInvokeOptions(
                    body: Payload(image: jpeg.base64EncodedString(), context: context)
                )
            )
            let id = events.record(AIEvent(
                feature: .fieldExtract,
                model: envelope.model,
                inputTokens: envelope.inputTokens,
                outputTokens: envelope.outputTokens,
                latencyMs: envelope.latencyMs ?? elapsed(since: started)
            ))
            return Outcome(value: envelope.fields, eventID: id)
        } catch {
            events.record(AIEvent(
                feature: .fieldExtract,
                model: "unknown",
                latencyMs: elapsed(since: started),
                accepted: false,
                failure: "\(error)"
            ))
            Log.app.notice("label extract failed (\(error))")
            return nil
        }
    }

    static func elapsed(since start: Date) -> Int {
        Int(Date.now.timeIntervalSince(start) * 1000)
    }
}

nonisolated extension String {
    /// Trimmed, or nil when there was nothing but whitespace. Models return
    /// empty strings where they mean null often enough to be worth folding.
    var trimmed: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
