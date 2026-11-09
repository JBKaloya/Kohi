import Foundation
import Supabase
import os

/// A variant of a recipe the rules already produced, offered underneath it.
///
/// The order matters more than the content: the rules answer first and always,
/// this is a second row. Sending the rules' answer up as the input is what
/// keeps the variant anchored — the model is editing, not composing.
nonisolated enum RecipeAdapt {
    /// A variant, with the one thing it moved and why.
    struct Variant: Sendable, Hashable {
        var recipe: Recipe
        var changed: String
        var why: String
        var eventID: UUID
    }

    private struct Response: Decodable, Sendable {
        var variant: Body
        var model: String
        var inputTokens: Int?
        var outputTokens: Int?
        var latencyMs: Int?

        struct Body: Decodable, Sendable {
            var hasVariant: Bool
            var dose: Double?
            var water: Double?
            var beverage: Double?
            var temperature: Double?
            var seconds: Int?
            var grindLabel: String?
            var changed: String?
            var why: String?
        }
    }

    static func cacheKey(recipe: Recipe, card: CoffeeCard) -> String {
        let history = card.brews.filter { $0.ratingHalves != nil }.prefix(5).map {
            "\($0.id.uuidString):\($0.ratingHalves ?? 0):\($0.grind.display()):\(String($0.dose ?? 0))"
        }.joined(separator: ",")
        return [
            recipe.id.uuidString,
            recipe.referenceID ?? "",
            card.id.uuidString,
            recipe.method.rawValue,
            String(recipe.dose ?? 0),
            String(recipe.water ?? 0),
            String(recipe.temperature ?? 0),
            String(recipe.seconds ?? 0),
            recipe.grindLabel,
            history
        ].joined(separator: "\u{1e}")
    }

    @MainActor
    static func variant(
        of base: Recipe,
        for card: CoffeeCard,
        flags: AIFlags,
        events: AIEventLog
    ) async -> Variant? {
        guard flags.isOn(.recipeAdapt) else { return nil }
        let key = cacheKey(recipe: base, card: card)
        if let cached = AICallCache.variant(for: key) { return cached }
        if AICallCache.hasEmptyVariant(for: key) { return nil }
        guard let client = SupabaseConfig.current else { return nil }

        struct Payload: Encodable {
            let recipe: RecipeBody
            let coffee: CoffeeBody
            let history: [HistoryBody]
        }
        struct RecipeBody: Encodable {
            let name: String
            let method: String
            let dose: Double?
            let water: Double?
            let beverage: Double?
            let temperature: Double?
            let seconds: Int?
            let grindLabel: String
            let attribution: String
        }
        struct CoffeeBody: Encodable {
            let name: String
            let country: String
            let process: String
            let roastLevel: String?
            let isDecaf: Bool
            let daysOffRoast: Int?
            let tastingNotes: [String]
        }
        struct HistoryBody: Encodable {
            let dose: Double?
            let water: Double?
            let temperature: Double?
            let grind: String
            /// Out of 5, in half points: 3.5.
            let rating: Double?
        }

        let payload = Payload(
            recipe: RecipeBody(
                name: base.name,
                method: base.method.rawValue,
                dose: base.dose,
                water: base.water,
                beverage: base.beverage,
                temperature: base.temperature,
                seconds: base.seconds,
                grindLabel: base.grindLabel,
                attribution: base.attribution
            ),
            coffee: CoffeeBody(
                name: card.name,
                country: card.country,
                process: card.process,
                roastLevel: card.roastLevel?.rawValue,
                isDecaf: card.isDecaf,
                daysOffRoast: card.daysOffRoast(),
                tastingNotes: card.tastingNotes
            ),
            // Only rated brews: an unrated one says nothing about whether the
            // variant would be a repeat.
            history: card.brews.filter { $0.ratingHalves != nil }.prefix(5).map {
                HistoryBody(
                    dose: $0.dose,
                    water: $0.water,
                    temperature: $0.temperature,
                    grind: $0.grind.display(),
                    rating: $0.ratingHalves.map(HalfRating.points)
                )
            }
        )

        let started = Date.now
        do {
            let response: Response = try await client.functions.invoke(
                "recipe-adapt",
                options: FunctionInvokeOptions(body: payload)
            )
            let eventID = events.record(AIEvent(
                feature: .recipeAdapt,
                model: response.model,
                inputTokens: response.inputTokens,
                outputTokens: response.outputTokens,
                latencyMs: response.latencyMs ?? FieldExtract.elapsed(since: started)
            ))

            // "Nothing to change" is a real answer and gets logged as one, so
            // a model that always finds something to say shows up in the data.
            guard response.variant.hasVariant,
                  let changed = response.variant.changed?.trimmed
            else {
                AICallCache.storeEmptyVariant(for: key)
                return nil
            }

            let recipe = Recipe(
                name: "\(base.name) — variant",
                method: base.method,
                dose: response.variant.dose ?? base.dose,
                water: response.variant.water ?? base.water,
                beverage: response.variant.beverage ?? base.beverage,
                temperature: response.variant.temperature ?? base.temperature,
                seconds: response.variant.seconds ?? base.seconds,
                grindLabel: response.variant.grindLabel?.trimmed ?? base.grindLabel,
                grindMicronsLow: base.grindMicronsLow,
                grindMicronsHigh: base.grindMicronsHigh,
                steps: base.steps,
                source: .ai,
                evidence: .unverified,
                attribution: "Variant of \(base.attribution.isEmpty ? base.name : base.attribution)",
                sourceURL: base.sourceURL,
                notes: base.notes,
                cardID: card.id,
                referenceID: base.referenceID
            )

            let variant = Variant(
                recipe: recipe,
                changed: changed,
                why: response.variant.why?.trimmed ?? "",
                eventID: eventID
            )
            AICallCache.store(variant, for: key)
            return variant
        } catch {
            events.record(AIEvent(
                feature: .recipeAdapt,
                model: "unknown",
                latencyMs: FieldExtract.elapsed(since: started),
                accepted: false,
                failure: "\(error)"
            ))
            Log.app.notice("recipe adapt failed, the rules stand alone (\(error))")
            return nil
        }
    }
}
