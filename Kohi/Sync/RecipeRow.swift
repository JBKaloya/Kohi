import Foundation

/// DTO matching the `public.recipes` table schema (snake_case).
///
/// Only your own recipes travel: the bundled reference recipes ship with the
/// app and have no business taking up rows. `steps` is jsonb — a list, read as
/// a whole, edited as a whole.
struct RecipeRow: Codable, Sendable {
    let id: UUID
    let user_id: UUID

    var name: String
    var method: String
    var dose: Double?
    var water: Double?
    var beverage: Double?
    var temperature: Double?
    var temperature_max: Double?
    var seconds: Int?
    var grind_label: String
    var grind_microns_low: Double?
    var grind_microns_high: Double?
    var steps: [RecipeStep]
    var source: String
    var evidence: String
    var attribution: String
    var source_url: String?
    var notes: String
    var card_id: UUID?
    var brew_id: UUID?
    var reference_id: String?
    var profile_tags: [String]?
    var author_grinder: String?
    var auto_advance: Bool?
    var advance_mode: String?
    var advance_mode_chosen: Bool?
    var rinse_mass_override: Double?
    var created_at: Date
    var updated_at: Date

    init(recipe: Recipe, userID: UUID) {
        self.id = recipe.id
        self.user_id = userID
        self.name = recipe.name
        self.method = recipe.method.rawValue
        self.dose = recipe.dose
        self.water = recipe.water
        self.beverage = recipe.beverage
        self.temperature = recipe.temperature
        self.temperature_max = recipe.temperatureMax
        self.seconds = recipe.seconds
        self.grind_label = recipe.grindLabel
        self.grind_microns_low = recipe.grindMicronsLow
        self.grind_microns_high = recipe.grindMicronsHigh
        self.steps = recipe.steps
        self.source = recipe.source.rawValue
        self.evidence = recipe.evidence.rawValue
        self.attribution = recipe.attribution
        self.source_url = recipe.sourceURL
        self.notes = recipe.notes
        self.card_id = recipe.cardID
        self.brew_id = recipe.brewID
        self.reference_id = recipe.referenceID
        self.profile_tags = recipe.profileTags
        self.author_grinder = recipe.authorGrinder
        self.auto_advance = recipe.advanceMode == .auto
        self.advance_mode = recipe.advanceMode.rawValue
        self.advance_mode_chosen = recipe.advanceModeChosen ? true : nil
        self.rinse_mass_override = recipe.rinseMassOverride
        self.created_at = recipe.createdAt
        self.updated_at = recipe.updatedAt
    }

    func toRecipe() -> Recipe {
        Recipe(
            id: id,
            name: name,
            method: BrewMethod(rawValue: method) ?? .filter,
            dose: dose,
            water: water,
            beverage: beverage,
            temperature: temperature,
            temperatureMax: temperature_max,
            seconds: seconds,
            grindLabel: grind_label,
            grindMicronsLow: grind_microns_low,
            grindMicronsHigh: grind_microns_high,
            steps: steps,
            source: RecipeSource(rawValue: source) ?? .mine,
            evidence: Evidence(rawValue: evidence) ?? .practice,
            attribution: attribution,
            sourceURL: source_url,
            notes: notes,
            cardID: card_id,
            brewID: brew_id,
            referenceID: reference_id,
            profileTags: profile_tags ?? [],
            authorGrinder: author_grinder,
            autoAdvance: auto_advance ?? true,
            advanceMode: advance_mode.flatMap(AdvanceMode.init(rawValue:)),
            advanceModeChosen: advance_mode_chosen ?? false,
            rinseMassOverride: rinse_mass_override,
            createdAt: created_at,
            updatedAt: updated_at
        )
    }
}
