import Foundation

/// What a step of a recipe asks you to do.
nonisolated enum StepAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case bloom
    case pour
    case stir
    case press
    case swirl
    case drawdown
    case steep
    case release
    case wait
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bloom: "Bloom"
        case .pour: "Pour"
        case .stir: "Stir"
        case .press: "Press"
        case .swirl: "Swirl"
        case .drawdown: "Drawdown"
        case .steep: "Steep"
        case .release: "Release"
        case .wait: "Wait"
        case .custom: "Step"
        }
    }

    /// The imperative shown by the guided timer, where the verb is the whole
    /// instruction and there is no room for a sentence.
    var imperative: String {
        switch self {
        case .bloom: "Bloom"
        case .pour: "Pour to"
        case .stir: "Stir"
        case .press: "Press"
        case .swirl: "Swirl"
        case .drawdown: "Let it draw down"
        case .steep: "Steep"
        case .release: "Release"
        case .wait: "Wait"
        case .custom: "Step"
        }
    }
}

/// One instruction, at a time on the clock.
nonisolated struct RecipeStep: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    /// Seconds from the start of the brew.
    var at: Int
    var action: StepAction
    /// Total mass in the vessel once this step is done, not the mass added —
    /// which is what a scale actually reads.
    var targetMass: Double?
    /// When the step is a pour with a duration, the time it should be finished
    /// by: "pour to 300 g, there by 1:15".
    var untilSeconds: Int?
    var note: String

    init(
        id: UUID = UUID(),
        at: Int,
        action: StepAction,
        targetMass: Double? = nil,
        untilSeconds: Int? = nil,
        note: String = ""
    ) {
        self.id = id
        self.at = at
        self.action = action
        self.targetMass = targetMass
        self.untilSeconds = untilSeconds
        self.note = note
    }

    var timeLabel: String {
        String(format: "%d:%02d", at / 60, at % 60)
    }

    /// "Pour to 300 g" / "Bloom 60 g" / "Stir".
    var instruction: String {
        guard let targetMass else { return action.imperative }
        let mass = GrindRange.number(targetMass) + " g"
        switch action {
        case .pour: return "Pour to \(mass)"
        case .bloom: return "Bloom \(mass)"
        case .custom:
            let name = note.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? "Step \(mass)" : "\(name) \(mass)"
        default: return "\(action.imperative) \(mass)"
        }
    }
}

/// Where a recipe came from. Always shown, never inferred at display time.
nonisolated enum RecipeSource: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Printed on the coffee's own card.
    case card
    /// One of the bundled reference recipes.
    case reference
    /// Saved from one of your brews.
    case mine
    /// A reference recipe adjusted by the rules.
    case adapted
    /// A variant proposed by the model, always shown beneath the rules'
    /// answer and never in its place.
    case ai

    var id: String { rawValue }

    var label: String {
        switch self {
        case .card: "Card"
        case .reference: Copy.fromThePros
        case .mine: "Mine"
        case .adapted: "Adapted"
        case .ai: "Variant"
        }
    }
}

/// How much weight a recipe's numbers can carry. Kept on the record and shown,
/// because a figure brewed and checked against its author is not the same
/// claim as a figure that is simply common practice.
nonisolated enum Evidence: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Parameters and steps match the author's own published source.
    case verified
    /// Some figures check out, others still need the source.
    case partial
    /// Widely done, attributable to nobody in particular.
    case practice
    /// Nothing stands behind it yet — a model's variant, or something typed
    /// in without a source. Shown as such rather than left blank.
    case unverified

    var id: String { rawValue }

    var label: String {
        switch self {
        case .verified: "verified"
        case .partial: "partly verified"
        case .practice: "common practice"
        case .unverified: "unverified"
        }
    }
}

/// A recipe: the parameters, the steps, and who to credit.
///
/// Reference recipes ship in the bundle and are read-only; the ones you save
/// from a brew live in `RecipeStore` and sync. Both are the same shape, so the
/// brew sheet does not care which it was handed.
nonisolated struct Recipe: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var method: BrewMethod

    var dose: Double?
    /// Brew water for infusion methods.
    var water: Double?
    /// Liquid out, for espresso.
    var beverage: Double?
    var temperature: Double?
    /// Set when the author gave a range: "93–95 °C".
    var temperatureMax: Double?
    var seconds: Int?

    /// The author's own words for the grind: "medium-fine".
    var grindLabel: String
    /// Indicative particle size for the method (annexe G1). A starting point
    /// for translating into your grinder's units, never a measurement.
    var grindMicronsLow: Double?
    var grindMicronsHigh: Double?

    var steps: [RecipeStep]
    var source: RecipeSource
    var evidence: Evidence
    var attribution: String
    var sourceURL: String?
    var notes: String

    /// The coffee this was saved from, when it came from a brew.
    var cardID: UUID?
    /// The brew it was saved from.
    var brewID: UUID?

    /// Reference row id, stable across builds, for a bundled recipe.
    var referenceID: String?

    /// Sensory profile chips used by the Filters sheet: fruity, floral, sweet,
    /// bright, clean, body. Empty until the recipe names them.
    var profileTags: [String]
    /// The grinder the author named, when they named one.
    var authorGrinder: String?
    /// The guided brew advances on its own when the step's time is up.
    /// On for reference recipes; off for yours unless you turn it on.
    var autoAdvance: Bool

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "",
        method: BrewMethod = .v60,
        dose: Double? = nil,
        water: Double? = nil,
        beverage: Double? = nil,
        temperature: Double? = nil,
        temperatureMax: Double? = nil,
        seconds: Int? = nil,
        grindLabel: String = "",
        grindMicronsLow: Double? = nil,
        grindMicronsHigh: Double? = nil,
        steps: [RecipeStep] = [],
        source: RecipeSource = .mine,
        evidence: Evidence = .practice,
        attribution: String = "",
        sourceURL: String? = nil,
        notes: String = "",
        cardID: UUID? = nil,
        brewID: UUID? = nil,
        referenceID: String? = nil,
        profileTags: [String] = [],
        authorGrinder: String? = nil,
        autoAdvance: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.method = method
        self.dose = dose
        self.water = water
        self.beverage = beverage
        self.temperature = temperature
        self.temperatureMax = temperatureMax
        self.seconds = seconds
        self.grindLabel = grindLabel
        self.grindMicronsLow = grindMicronsLow
        self.grindMicronsHigh = grindMicronsHigh
        self.steps = steps
        self.source = source
        self.evidence = evidence
        self.attribution = attribution
        self.sourceURL = sourceURL
        self.notes = notes
        self.cardID = cardID
        self.brewID = brewID
        self.referenceID = referenceID
        self.profileTags = profileTags
        self.authorGrinder = authorGrinder
        self.autoAdvance = autoAdvance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Computed

    /// "1:16.7". Water for infusion, beverage for espresso.
    var ratio: String? {
        guard let value = ratioValue else { return nil }
        return value < 10
            ? String(format: "1:%.1f", value)
            : String(format: "1:%.1f", value)
    }

    var ratioValue: Double? {
        guard let dose, dose > 0 else { return nil }
        guard let liquid = water ?? beverage, liquid > 0 else { return nil }
        return liquid / dose
    }

    var timeLabel: String? {
        guard let seconds, seconds > 0 else { return nil }
        if seconds >= 3_600 {
            let hours = Double(seconds) / 3_600
            return "\(GrindRange.number(hours)) h"
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// "93–95 °C" when the author gave a range, "93 °C" otherwise.
    var temperatureLabel: String? {
        guard let temperature else { return nil }
        if let temperatureMax, temperatureMax > temperature {
            return "\(GrindRange.number(temperature))–\(GrindRange.number(temperatureMax)) °C"
        }
        return "\(GrindRange.number(temperature)) °C"
    }

    /// One line for a list: "V60 · 15 g · 1:16.7 · 92 °C". Time and water live in the detail.
    var compactLine: String {
        var parts = [method.label]
        if let dose { parts.append("\(GrindRange.number(dose)) g") }
        if let ratio { parts.append(ratio) }
        if let temperatureLabel { parts.append(temperatureLabel) }
        return parts.joined(separator: " · ")
    }

    /// One line, in the same order as a brew's: "V60 · 30 g · 500 g · 1:16.7 · 3:30 · 99 °C".
    var parameterLine: String {
        var parts = [method.label]
        if let dose { parts.append("\(GrindRange.number(dose)) g") }
        if let water { parts.append("\(GrindRange.number(water)) g") }
        if let beverage { parts.append("\(GrindRange.number(beverage)) g out") }
        if let ratio { parts.append(ratio) }
        if let timeLabel { parts.append(timeLabel) }
        if let temperatureLabel { parts.append(temperatureLabel) }
        if !grindLabel.isEmpty { parts.append(grindLabel) }
        return parts.joined(separator: " · ")
    }

    /// A recipe you could actually follow: something to weigh, something to
    /// pour, and a grind or a time.
    var isComplete: Bool {
        dose != nil && (water != nil || beverage != nil)
    }

    /// Seeds a brew from this recipe, so "Use" lands on a filled-in sheet.
    func seededBrew(date: Date = .now, size: RecipeSize? = nil) -> Brew {
        let scaled = size.map { RecipeScaling.scaled(self, to: $0) }
        let source = scaled?.recipe ?? self
        let link = brewLink()
        return Brew(
            date: date,
            method: source.method,
            dose: source.dose,
            water: source.water,
            beverage: source.beverage,
            seconds: source.seconds,
            grind: GrindSetting(raw: source.grindLabel),
            temperature: source.temperature,
            recipeID: link.recipeID,
            recipeRef: link.recipeRef,
            recipeSnapshot: link.snapshot,
            scale: scaled?.isScaled == true ? size : nil
        )
    }

    /// How this recipe is stored on a brew: user recipes keep a FK, bundled
    /// ones a `ref:` key, and both keep a snapshot of the numbers as they were.
    func brewLink() -> (recipeID: UUID?, recipeRef: String?, snapshot: RecipeSnapshot) {
        let snapshot = RecipeSnapshot(from: self)
        if source == .mine {
            return (id, nil, snapshot)
        }
        return (nil, referenceID.map { "ref:\($0)" }, snapshot)
    }

    init(snapshot: RecipeSnapshot) {
        self.init(
            name: snapshot.name,
            method: snapshot.method,
            dose: snapshot.dose,
            water: snapshot.water,
            beverage: snapshot.beverage,
            temperature: snapshot.temperature,
            seconds: snapshot.seconds,
            grindLabel: snapshot.grindLabel,
            steps: snapshot.steps,
            source: snapshot.source,
            attribution: snapshot.attribution,
            referenceID: snapshot.referenceID,
            autoAdvance: snapshot.source == .reference
        )
    }
}

/// The parameters and steps as they were when the brew was made, so a later
/// edit of the recipe does not rewrite history.
nonisolated struct RecipeSnapshot: Codable, Hashable, Sendable {
    var name: String
    var method: BrewMethod
    var dose: Double?
    var water: Double?
    var beverage: Double?
    var temperature: Double?
    var seconds: Int?
    var grindLabel: String
    var steps: [RecipeStep]
    var attribution: String
    var referenceID: String?
    var source: RecipeSource

    init(from recipe: Recipe) {
        name = recipe.name
        method = recipe.method
        dose = recipe.dose
        water = recipe.water
        beverage = recipe.beverage
        temperature = recipe.temperature
        seconds = recipe.seconds
        grindLabel = recipe.grindLabel
        steps = recipe.steps
        attribution = recipe.attribution
        referenceID = recipe.referenceID
        source = recipe.source
    }
}

nonisolated extension Recipe {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        method = try c.decodeIfPresent(BrewMethod.self, forKey: .method) ?? .v60
        dose = try c.decodeIfPresent(Double.self, forKey: .dose)
        water = try c.decodeIfPresent(Double.self, forKey: .water)
        beverage = try c.decodeIfPresent(Double.self, forKey: .beverage)
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature)
        temperatureMax = try c.decodeIfPresent(Double.self, forKey: .temperatureMax)
        seconds = try c.decodeIfPresent(Int.self, forKey: .seconds)
        grindLabel = try c.decodeIfPresent(String.self, forKey: .grindLabel) ?? ""
        grindMicronsLow = try c.decodeIfPresent(Double.self, forKey: .grindMicronsLow)
        grindMicronsHigh = try c.decodeIfPresent(Double.self, forKey: .grindMicronsHigh)
        steps = try c.decodeIfPresent([RecipeStep].self, forKey: .steps) ?? []
        source = try c.decodeIfPresent(RecipeSource.self, forKey: .source) ?? .mine
        evidence = try c.decodeIfPresent(Evidence.self, forKey: .evidence) ?? .practice
        attribution = try c.decodeIfPresent(String.self, forKey: .attribution) ?? ""
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        cardID = try c.decodeIfPresent(UUID.self, forKey: .cardID)
        brewID = try c.decodeIfPresent(UUID.self, forKey: .brewID)
        referenceID = try c.decodeIfPresent(String.self, forKey: .referenceID)
        profileTags = try c.decodeIfPresent([String].self, forKey: .profileTags) ?? []
        authorGrinder = try c.decodeIfPresent(String.self, forKey: .authorGrinder)
        autoAdvance = try c.decodeIfPresent(Bool.self, forKey: .autoAdvance) ?? (source == .reference)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }
}

nonisolated extension RecipeStep {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        at = try c.decodeIfPresent(Int.self, forKey: .at) ?? 0
        action = try c.decodeIfPresent(StepAction.self, forKey: .action) ?? .pour
        targetMass = try c.decodeIfPresent(Double.self, forKey: .targetMass)
        untilSeconds = try c.decodeIfPresent(Int.self, forKey: .untilSeconds)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}
