import CoreGraphics
import Foundation
import Supabase
import os

/// The second opinion. When the local parse comes back weak — handwriting,
/// Chinese or Japanese, a layout the heuristics do not know — the card image
/// goes to the `card-vision` edge function, which runs a vision model and
/// returns the same shape of fields, already translated to English with the
/// original text alongside. Results only ever fill empty fields.
nonisolated enum CardVision {
    /// The feature exists only when Supabase is configured; without it the
    /// app quietly stays fully local.
    static var isAvailable: Bool { SupabaseConfig.current != nil }

    /// Longest edge of the JPEG sent up. Big enough to read small print,
    /// small enough to stay cheap and quick on cellular.
    private static let uploadMaxPixel = 1280

    /// What one call returned, and what it cost. The event is the caller's to
    /// record, since the log lives on the main actor and this does not.
    struct Reading: Sendable {
        /// Nil when the call failed or the model saw no coffee label.
        var fields: ParsedFields?
        var event: AIEvent
    }

    /// The card's flattened photo, from disk. The collection path.
    static func read(cardID: UUID) async -> Reading? {
        let url = ImageStore.shared.url(for: cardID, kind: .flat)
        guard let image = ImageCodec.downsample(url, maxPixel: uploadMaxPixel),
              let jpeg = ImageCodec.encodeJPEG(image, quality: 0.8) else {
            return nil
        }
        return await read(jpeg: jpeg)
    }

    /// A photo still in memory. The tasting path, which files no card.
    static func read(image: CGImage) async -> Reading? {
        guard let full = ImageCodec.encodeJPEG(image, quality: 0.9),
              let small = ImageCodec.decodeOriented(full, maxPixel: uploadMaxPixel),
              let jpeg = ImageCodec.encodeJPEG(small, quality: 0.8) else {
            return nil
        }
        return await read(jpeg: jpeg)
    }

    private static func read(jpeg: Data) async -> Reading? {
        guard let client = SupabaseConfig.current else { return nil }

        struct Payload: Encodable {
            let image: String
            let mime: String
        }

        let started = Date.now
        do {
            let extraction: Extraction = try await client.functions.invoke(
                "card-vision",
                options: FunctionInvokeOptions(
                    body: Payload(image: jpeg.base64EncodedString(), mime: "image/jpeg")
                )
            )
            var event = AIEvent(
                feature: .cardVision,
                model: extraction.model ?? "unknown",
                inputTokens: extraction.inputTokens,
                outputTokens: extraction.outputTokens,
                latencyMs: extraction.latencyMs ?? elapsed(since: started)
            )
            guard extraction.isCoffeeLabel == true else {
                Log.app.notice("card vision: model says this is not a coffee label")
                event.accepted = false
                return Reading(fields: nil, event: event)
            }
            return Reading(fields: fields(from: extraction), event: event)
        } catch {
            Log.app.notice("card vision failed, keeping the local read (\(error))")
            return Reading(fields: nil, event: AIEvent(
                feature: .cardVision,
                model: "unknown",
                latencyMs: elapsed(since: started),
                accepted: false,
                failure: "\(error)"
            ))
        }
    }

    private static func elapsed(since start: Date) -> Int {
        Int(Date.now.timeIntervalSince(start) * 1000)
    }

    // MARK: - Response mapping

    struct Extraction: Decodable, Sendable {
        var isCoffeeLabel: Bool?
        var detectedLanguage: String?
        var name: String?
        var roaster: String?
        var country: String?
        var region: String?
        var producer: String?
        var altitude: String?
        var variety: String?
        var process: String?
        var tastingNotes: [String]?
        var roastLevel: String?
        /// "YYYY-MM-DD" as instructed by the prompt.
        var roastedOn: String?
        var harvest: String?
        var lot: String?
        var cuppingScore: Double?
        var price: Double?
        var currency: String?
        var bagWeightGrams: Double?
        var isDecaf: Bool?
        var recipe: Recipe?
        var original: Original?
        /// Usage, sent alongside the fields by the edge function. Absent from
        /// older deployments, which only ever sent the fields.
        var model: String?
        var inputTokens: Int?
        var outputTokens: Int?
        var latencyMs: Int?

        struct Recipe: Decodable, Sendable {
            var doseGrams: Double?
            var waterGrams: Double?
            var seconds: Int?
            var temperatureCelsius: Double?
            var grind: String?
            var method: String?
        }

        struct Original: Decodable, Sendable {
            var name: String?
            var roaster: String?
            var country: String?
            var region: String?
            var producer: String?
            var altitude: String?
            var variety: String?
            var process: String?
            var tastingNotes: [String]?
        }
    }

    private static func fields(from extraction: Extraction) -> ParsedFields {
        var fields = ParsedFields()
        fields.name = clean(extraction.name)
        fields.roaster = clean(extraction.roaster)
        fields.country = clean(extraction.country)
        fields.region = clean(extraction.region)
        fields.producer = clean(extraction.producer)
        fields.altitude = clean(extraction.altitude)
        fields.variety = clean(extraction.variety)
        fields.process = clean(extraction.process)
        fields.tastingNotes = (extraction.tastingNotes ?? []).compactMap(clean)

        if let language = extraction.detectedLanguage?.prefix(2).lowercased(), language != "en" {
            fields.sourceLanguage = language
        }

        // The model is told the vocabulary, but an unknown value still means
        // nothing rather than a wrong notch.
        fields.roastLevel = clean(extraction.roastLevel).flatMap { RoastLevel(rawValue: $0) }
        fields.roastedOn = clean(extraction.roastedOn).flatMap { BagFieldParser.date(in: $0) }
        fields.harvest = clean(extraction.harvest)
        fields.lot = clean(extraction.lot)
        if let score = extraction.cuppingScore, (55...100).contains(score) {
            fields.cuppingScore = score
        }
        if let price = extraction.price, price > 0 {
            fields.price = price
            fields.currency = clean(extraction.currency)?.uppercased()
        }
        if let grams = extraction.bagWeightGrams, (50...5000).contains(grams) {
            fields.bagWeightG = grams
        }
        if extraction.isDecaf == true { fields.isDecaf = true }

        if let recipe = extraction.recipe {
            let quantities: [Double?] = [
                recipe.doseGrams, recipe.waterGrams,
                recipe.seconds.map(Double.init), recipe.temperatureCelsius,
            ]
            if quantities.compactMap(\.self).count >= 2 {
                fields.recipe = Brew(
                    method: recipe.method.flatMap { BrewMethod(rawValue: $0) },
                    dose: recipe.doseGrams,
                    water: recipe.waterGrams,
                    seconds: recipe.seconds,
                    grind: GrindSetting(raw: clean(recipe.grind) ?? ""),
                    temperature: recipe.temperatureCelsius
                )
            }
        }

        if let original = extraction.original {
            var originals: [String: String] = [:]
            originals["name"] = clean(original.name)
            originals["roaster"] = clean(original.roaster)
            originals["country"] = clean(original.country)
            originals["region"] = clean(original.region)
            originals["producer"] = clean(original.producer)
            originals["altitude"] = clean(original.altitude)
            originals["variety"] = clean(original.variety)
            originals["process"] = clean(original.process)
            if let notes = original.tastingNotes, !notes.isEmpty {
                originals["notes"] = notes.joined(separator: ", ")
            }
            fields.originalFields = originals.compactMapValues(\.self)
        }

        return fields
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
