import CoreGraphics
import Foundation

/// Everything that runs on a photo after the local text read: barcodes, the
/// label link, and the vision model when that read is weak. One module, two
/// ways in: a bag filed in the collection, and a cup's card photographed for
/// a tasting. Both go through every pass, and the result only fills what is
/// empty.
nonisolated enum ScanPipeline {
    /// The collection path. Starts from the read `ingest` already did, and is
    /// detached so the edit sheet does not freeze while it runs.
    static func fields(
        of pending: PendingScan,
        visionAllowed: Bool,
        events: AIEventLog
    ) async -> ParsedFields {
        await Task.detached(priority: .userInitiated) {
            async let foundCodes = LabelCodeReader.readAll(cardID: pending.card.id)

            var parsed = pending.parsed
            parsed.linesRead = pending.lines.count

            let found = await foundCodes
            OCRSidecar.write(
                cardID: pending.card.id,
                lines: pending.lines,
                barcodes: found.map(\.bounds)
            )
            parsed = await following(found, from: parsed)

            if parsed.wantsVisionAssist, visionAllowed, CardVision.isAvailable,
               let reading = await CardVision.read(cardID: pending.card.id) {
                await secondOpinion(reading, into: &parsed, events: events)
            }

            return parsed
        }.value
    }

    /// The tasting path's first pass, on the codes read off the photo in
    /// memory. Never asks a model; the page fetch gives up after 8 s.
    static func linked(codes: [LabelCodeReader.Found], local: ParsedFields) async -> ParsedFields {
        await Task.detached(priority: .userInitiated) {
            await following(codes, from: local)
        }.value
    }

    /// Keeps the code, prefers a link, and fills what the product page says.
    private static func following(_ codes: [LabelCodeReader.Found], from local: ParsedFields) async -> ParsedFields {
        var parsed = local
        let payloads = codes.map(\.payload)
        let code = payloads.first { $0.hasPrefix("https://") || $0.hasPrefix("http://") } ?? payloads.first
        if let code, code.hasPrefix("http") {
            if parsed.productURL == nil {
                parsed.productURL = code
            }
            if let linked = await LabelLink.fetch(code) {
                parsed.mergeLinked(linked)
            }
        } else {
            parsed.labelCode = code
        }
        return parsed
    }

    /// The tasting path's second pass: the vision model, on the photo in
    /// memory, only when what the text and the code gave is weak or empty.
    static func secondOpinion(
        image: CGImage,
        local: ParsedFields,
        visionAllowed: Bool,
        events: AIEventLog
    ) async -> ParsedFields? {
        guard local.linesRead > 0, local.wantsVisionAssist || local.isEmpty,
              visionAllowed, CardVision.isAvailable else { return nil }
        return await Task.detached(priority: .userInitiated) {
            guard let reading = await CardVision.read(image: image) else { return nil }
            var parsed = local
            await secondOpinion(reading, into: &parsed, events: events)
            return parsed.modelFill == nil ? nil : parsed
        }.value
    }

    /// Records the call, fills the holes, and remembers which values were the
    /// model's, so the save can answer for them.
    private static func secondOpinion(
        _ reading: CardVision.Reading,
        into parsed: inout ParsedFields,
        events: AIEventLog
    ) async {
        let eventID = await events.record(reading.event)
        guard let vision = reading.fields else { return }
        let before = FieldValues.of(parsed)
        parsed.fillMissing(from: vision)
        parsed.modelFill = ModelFill(
            eventID: eventID,
            values: ModelFill.landed(model: FieldValues.of(vision), before: before, after: FieldValues.of(parsed))
        )
    }
}

/// The values a model put into empty fields of a draft, by field.
///
/// This is what `accepted` means for a reading model: at least one of these
/// values is still there, unchanged, when the card or the tasting is saved.
/// A value edited, cleared, or a draft thrown away counts as not kept, and so
/// does a call that filled nothing, since it cost a round trip for no field.
nonisolated struct ModelFill: Equatable, Sendable {
    let eventID: UUID
    let values: [String: String]

    func kept(in current: [String: String]) -> Bool {
        values.contains { key, value in current[key] == value }
    }

    /// The model's values that went into a slot that was empty before.
    static func landed(
        model: [String: String],
        before: [String: String],
        after: [String: String]
    ) -> [String: String] {
        model.filter { key, value in before[key] == nil && after[key] == value }
    }

    /// The same fill, narrowed to what actually reached a draft.
    func narrowed(before: [String: String], after: [String: String]) -> ModelFill {
        ModelFill(eventID: eventID, values: Self.landed(model: values, before: before, after: after))
    }
}

/// Fields flattened to comparable text, under one set of keys for a parse, a
/// card and a tasted coffee. Empty means absent.
nonisolated enum FieldValues {
    static func of(_ parsed: ParsedFields) -> [String: String] {
        var values: [String: String] = [:]
        values["name"] = text(parsed.name)
        values["roaster"] = text(parsed.roaster)
        values["country"] = text(parsed.country)
        values["region"] = text(parsed.region)
        values["producer"] = text(parsed.producer)
        values["altitude"] = text(parsed.altitude)
        values["variety"] = text(parsed.variety)
        values["process"] = text(parsed.process)
        values["notes"] = notes(parsed.tastingNotes)
        values["roastLevel"] = parsed.roastLevel?.rawValue
        values["agtron"] = parsed.agtron.map(String.init)
        values["roastedOn"] = day(parsed.roastedOn)
        values["harvest"] = text(parsed.harvest)
        values["cupping"] = number(parsed.cuppingScore)
        values["price"] = number(parsed.price)
        values["currency"] = text(parsed.currency)
        values["bagWeight"] = number(parsed.bagWeightG)
        values["lot"] = text(parsed.lot)
        return values
    }

    static func of(_ card: CoffeeCard) -> [String: String] {
        var values: [String: String] = [:]
        values["name"] = text(card.name)
        values["roaster"] = text(card.roaster)
        values["country"] = text(card.country)
        values["region"] = text(card.region)
        values["producer"] = text(card.producer)
        values["altitude"] = text(card.altitude)
        values["variety"] = text(card.variety)
        values["process"] = text(card.process)
        values["notes"] = notes(card.tastingNotes)
        values["roastLevel"] = card.roastLevel?.rawValue
        values["agtron"] = card.agtron.map(String.init)
        values["roastedOn"] = day(card.roastedOn)
        values["harvest"] = text(card.harvest)
        values["cupping"] = number(card.cuppingScore)
        values["price"] = number(card.price)
        values["currency"] = text(card.currency)
        values["bagWeight"] = number(card.bagWeightG)
        values["lot"] = text(card.lot)
        return values
    }

    /// A tasting keeps fewer fields; the producer lands in `farm`.
    static func of(_ coffee: TastedCoffee) -> [String: String] {
        var values: [String: String] = [:]
        values["name"] = text(coffee.name)
        values["roaster"] = text(coffee.roaster)
        values["country"] = text(coffee.country)
        values["region"] = text(coffee.region)
        values["producer"] = text(coffee.farm)
        values["variety"] = text(coffee.variety)
        values["process"] = text(coffee.process)
        values["notes"] = notes(coffee.tastingNotes)
        return values
    }

    private static func text(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func notes(_ notes: [String]) -> String? {
        notes.isEmpty ? nil : notes.joined(separator: "|")
    }

    private static func number(_ value: Double?) -> String? {
        value.map { String($0) }
    }

    private static func day(_ date: Date?) -> String? {
        date.map { $0.formatted(.iso8601.year().month().day()) }
    }
}
