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
    case rinse
    case preInfusion
    case shot
    case fill
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
        case .rinse: "Rinse"
        case .preInfusion: "Pre-infusion"
        case .shot: "Shot"
        case .fill: "Fill"
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
        case .rinse: "Rinse"
        case .preInfusion: "Pre-infuse"
        case .shot: "Shot to"
        case .fill: "Fill"
        case .custom: "Step"
        }
    }

    /// Whether this action carries a target mass on the scale.
    var acceptsMass: Bool {
        switch self {
        case .bloom, .pour, .rinse, .shot, .fill, .steep: true
        case .stir, .press, .swirl, .drawdown, .release,
             .wait, .preInfusion, .custom: false
        }
    }

    /// Whether an "until" time reads as anything. A stir is instant; a steep
    /// has a duration.
    var hasUntil: Bool {
        switch self {
        case .bloom, .pour, .preInfusion, .shot, .steep, .wait,
             .rinse, .fill: true
        case .stir, .press, .swirl, .drawdown, .release, .custom: false
        }
    }

    /// Actions that read the same whatever the method: you can always stir,
    /// swirl, wait, or write a step of your own.
    static let universal: [StepAction] = [.stir, .swirl, .wait, .custom]
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
    var agitation: Agitation?
    var derived: Bool
    /// Kit accessories to use during this step (e.g. Melodrip, Switch).
    /// Decoded with `decodeIfPresent` so existing data is not affected.
    var accessoryIDs: [UUID]
    /// Optional sensory mark. Nil means the step is timed.
    var cue: StepCue?

    init(
        id: UUID = UUID(),
        at: Int,
        action: StepAction,
        targetMass: Double? = nil,
        untilSeconds: Int? = nil,
        note: String = "",
        agitation: Agitation? = nil,
        derived: Bool = false,
        accessoryIDs: [UUID] = [],
        cue: StepCue? = nil
    ) {
        self.id = id
        self.at = at
        self.action = action
        self.targetMass = targetMass
        self.untilSeconds = untilSeconds
        self.note = note
        self.agitation = agitation
        self.derived = derived
        self.accessoryIDs = accessoryIDs
        self.cue = cue
    }

    var timeLabel: String {
        String(format: "%d:%02d", at / 60, at % 60)
    }

    /// "Pour to 300 g" / "Bloom 60 g" / "Stir".
    var instruction: String {
        guard let targetMass else {
            if action == .rinse {
                let extra = note.trimmingCharacters(in: .whitespaces)
                return extra.isEmpty ? "Rinse" : "Rinse · \(extra)"
            }
            return action.imperative
        }
        let mass = GrindRange.number(targetMass) + " g"
        switch action {
        case .pour: return "Pour to \(mass)"
        case .bloom: return "Bloom \(mass)"
        case .rinse:
            let extra = note.trimmingCharacters(in: .whitespaces)
            return extra.isEmpty ? "Rinse \(mass)" : "Rinse \(mass) · \(extra)"
        case .custom:
            let name = note.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? "Step \(mass)" : "\(name) \(mass)"
        default: return "\(action.imperative) \(mass)"
        }
    }
}
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
    /// Built in thirty seconds on the brew journey.
    case express

    var id: String { rawValue }

    var label: String {
        switch self {
        case .card: "Card"
        case .reference: Copy.fromThePros
        case .mine: "Mine"
        case .adapted: "Adapted"
        case .ai: "Variant"
        case .express: "Express"
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
    /// On by default, for every recipe; Tap or Cues is a choice you make.
    var autoAdvance: Bool
    /// Auto follows the clock, Manual waits for a tap, Cues shows a sensory mark.
    var advanceMode: AdvanceMode
    /// Set once you pick a mode on How much?. The move to Auto by default
    /// leaves a chosen mode alone.
    var advanceModeChosen: Bool
    /// Chemex (and similar) can override the indicative rinse mass.
    var rinseMassOverride: Double?

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
        autoAdvance: Bool = true,
        advanceMode: AdvanceMode? = nil,
        advanceModeChosen: Bool = false,
        rinseMassOverride: Double? = nil,
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
        self.advanceMode = advanceMode ?? (autoAdvance ? .auto : .manual)
        self.advanceModeChosen = advanceModeChosen
        self.rinseMassOverride = rinseMassOverride
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
        let link = source.brewLink()
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
            scale: scaled?.isScaled == true ? size : nil,
            plannedSteps: source.steps.enumerated().map { index, step in
                BrewStep(
                    index: index,
                    action: step.action,
                    at: 0,
                    targetAt: step.untilSeconds ?? step.at,
                    targetMass: step.targetMass,
                    note: step.note,
                    agitation: step.agitation
                )
            },
            recipeName: source.name
        )
    }

    static func expressTitle(family: BrewerFamily, date: Date = .now, card: CoffeeCard? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        let dateStr = formatter.string(from: date)
        let coffeePrefix = card.map { c in c.name.isEmpty ? nil : c.name }?.map { "\($0) · " } ?? ""
        return "\(coffeePrefix)\(family.label) · \(dateStr)"
    }

    /// How this recipe is stored on a brew: user recipes keep a FK, bundled
    /// ones a `ref:` key, and both keep a snapshot of the numbers as they were.
    func brewLink() -> (recipeID: UUID?, recipeRef: String?, snapshot: RecipeSnapshot) {
        // Rinse steps are ephemeral: RinseRule injects them at timer time from
        // the day's brewer and paper. Storing a rinse in the snapshot led to
        // stale, sometimes enormous masses being used by the timer.
        var withoutRinse = self
        withoutRinse.steps = steps.filter { $0.action != .rinse }
        let snapshot = RecipeSnapshot(from: withoutRinse)
        if source == .mine || source == .express {
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
            referenceID: snapshot.referenceID
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
        advanceMode = try c.decodeIfPresent(AdvanceMode.self, forKey: .advanceMode)
            ?? (autoAdvance ? .auto : .manual)
        advanceModeChosen = try c.decodeIfPresent(Bool.self, forKey: .advanceModeChosen) ?? false
        rinseMassOverride = try c.decodeIfPresent(Double.self, forKey: .rinseMassOverride)
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
        agitation = try c.decodeIfPresent(Agitation.self, forKey: .agitation)
        derived = try c.decodeIfPresent(Bool.self, forKey: .derived) ?? false
        accessoryIDs = try c.decodeIfPresent([UUID].self, forKey: .accessoryIDs) ?? []
        cue = try c.decodeIfPresent(StepCue.self, forKey: .cue)
    }
}

/// How the guided timer leaves a step.
nonisolated enum AdvanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case manual
    case cues

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .manual: "Manual"
        case .cues: "Cues"
        }
    }

    var detail: String {
        switch self {
        case .auto: "By time"
        case .manual: "Tap"
        case .cues: "Visual"
        }
    }
}

/// What tells you the step is done, when it is not the clock.
nonisolated enum StepCue: Codable, Hashable, Sendable {
    case time
    case mass
    case visual(String)
    case smell(String)

    var label: String {
        switch self {
        case .time: "Time"
        case .mass: "Mass"
        case .visual(let text): text.isEmpty ? "Visual" : text
        case .smell(let text): text.isEmpty ? "Smell" : text
        }
    }
}
