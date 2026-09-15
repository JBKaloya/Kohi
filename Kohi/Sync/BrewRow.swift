import Foundation

/// DTO matching the `public.brews` table schema (snake_case).
struct BrewRow: Codable, Sendable {
    let id: UUID
    let card_id: UUID
    let user_id: UUID

    var date: Date
    var method: String?

    var dose: Double?
    var water: Double?
    var beverage: Double?
    var seconds: Int?
    var grind: String
    var grind_grinder_id: UUID?
    var grind_value: Double?
    var grind_raw: String?
    var temperature: Double?

    var tds: Double?
    var rating: Int?

    var recipe_id: UUID?
    var recipe_ref: String?
    var recipe_snapshot: RecipeSnapshot?
    var scale: String?
    var equipment_ids: [UUID]
    var water_profile_id: UUID?
    var agitation: String?
    var filter_id: UUID?
    var steps: [BrewStep]
    var flow_gs: Double?
    var taste: TasteProfile
    var legacy_taste: [String: Int]?
    var flavors: [String]
    var flavor_tags: [FlavorTag]?
    var next_time_suggestion: String?
    var capture_source: String?

    var acidity: Int
    var bitterness: Int
    var body: Int

    var notes: String

    init(brew: Brew, cardID: UUID, userID: UUID) {
        self.id = brew.id
        self.card_id = cardID
        self.user_id = userID
        self.date = brew.date
        self.method = brew.method?.rawValue
        self.dose = brew.dose
        self.water = brew.water
        self.beverage = brew.beverage
        self.seconds = brew.seconds
        self.grind = brew.grind.display()
        self.grind_grinder_id = brew.grind.grinderId
        self.grind_value = brew.grind.value
        self.grind_raw = brew.grind.raw
        self.temperature = brew.temperature
        self.tds = brew.tds
        self.rating = brew.rating
        self.recipe_id = brew.recipeID
        self.recipe_ref = brew.recipeRef
        self.recipe_snapshot = brew.recipeSnapshot
        self.scale = brew.scale?.rawValue
        self.equipment_ids = brew.equipmentIDs
        self.water_profile_id = brew.waterProfileID
        self.agitation = brew.agitation?.rawValue
        self.filter_id = brew.filterId
        self.steps = brew.steps
        self.flow_gs = brew.flowGs
        self.taste = brew.taste
        self.legacy_taste = brew.legacyTaste
        self.flavors = brew.flavors.map(\.id)
        self.flavor_tags = brew.flavors
        self.next_time_suggestion = brew.nextTimeSuggestion
        self.capture_source = brew.captureSource?.rawValue
        self.acidity = brew.acidity
        self.bitterness = brew.bitterness
        self.body = brew.body
        self.notes = brew.notes
    }

    func toBrew() -> Brew {
        let setting = GrindSetting(
            grinderId: grind_grinder_id,
            value: grind_value,
            raw: grind_raw ?? (grind.isEmpty ? nil : grind)
        )
        let tags: [FlavorTag]
        if let flavor_tags, !flavor_tags.isEmpty {
            tags = flavor_tags
        } else {
            tags = FlavorMatcher.match(flavors).tags
        }
        return Brew(
            id: id,
            date: date,
            method: method.flatMap { BrewMethod(rawValue: $0) },
            dose: dose,
            water: water,
            beverage: beverage,
            seconds: seconds,
            grind: setting.value != nil || setting.raw != nil || setting.grinderId != nil
                ? setting
                : GrindSetting(raw: grind),
            temperature: temperature,
            tds: tds,
            recipeID: recipe_id,
            recipeRef: recipe_ref,
            recipeSnapshot: recipe_snapshot,
            scale: scale.flatMap(RecipeSize.init(rawValue:)),
            equipmentIDs: equipment_ids,
            waterProfileID: water_profile_id,
            agitation: agitation.flatMap(Agitation.init(rawValue:)),
            filterId: filter_id,
            steps: steps,
            flowGs: flow_gs,
            taste: taste,
            legacyTaste: legacy_taste,
            flavors: tags,
            nextTimeSuggestion: next_time_suggestion,
            captureSource: capture_source.flatMap { CaptureSource(rawValue: $0) },
            rating: rating,
            acidity: acidity,
            bitterness: bitterness,
            body: body,
            notes: notes
        )
    }
}
