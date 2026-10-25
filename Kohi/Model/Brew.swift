import Foundation

/// One extraction of a saved coffee card. Tracks the recipe, a simple rating,
/// and three correction axes that tell you what to change next time.
nonisolated struct Brew: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var date: Date
    var method: BrewMethod?

    // Recipe
    var dose: Double?
    var water: Double?
    var beverage: Double?
    var seconds: Int?
    var grind: GrindSetting
    var temperature: Double?

    // Measurement
    var tds: Double?

    // What it was made with. Ids rather than copies: the equipment can be
    // renamed, and a brew should follow rather than keep a stale name.
    var recipeID: UUID?
    /// Bundled reference recipe, e.g. `ref:a1-v60-ultimate`. Never a FK.
    var recipeRef: String?
    /// Parameters and steps as they were when this brew was made.
    var recipeSnapshot: RecipeSnapshot?
    /// The size the recipe was shown at when this brew was created, if it was scaled.
    var scale: RecipeSize?
    var equipmentIDs: [UUID]
    var waterProfileID: UUID?
    var agitation: Agitation?
    var filterStockId: UUID?

    /// What actually happened, when the guided timer was used.
    var steps: [BrewStep]
    /// Plan shown at the timer, recipe or derived default.
    var plannedSteps: [BrewStep]
    var actualSource: ActualSource
    /// Average flow in g/s, computed at save time from the water and the time.
    var flowGs: Double?
    /// Snapshot of the recipe name when this brew was saved.
    var recipeName: String?
    /// Per-pour rates from actuals. Empty when `actualSource` is `.none`.
    var pourRates: [PourRate]

    /// Seven axes, 0 to 10. What the coffee was like, as opposed to what to change.
    var taste: TasteProfile
    /// The 1…5 scores this brew had before lot 2, kept until a major version.
    var legacyTaste: [String: Int]?
    var flavors: [FlavorTag]

    /// The one change to try next time, from the diagnostic rules.
    var nextTimeSuggestion: String?
    var captureSource: CaptureSource?

    /// 1...5, displayed as filled/empty dots.
    var rating: Int?

    /// Each axis is −1 (under), 0 (balanced), or +1 (over).
    var acidity: Int
    var bitterness: Int
    var body: Int
    /// Aromatic complexity, stored as the wish for next time: +1 more, −1
    /// less. Nil on every brew made before it existed, and when left as is.
    var complexity: Int?

    var notes: String

    init(
        id: UUID = UUID(),
        date: Date = .now,
        method: BrewMethod? = nil,
        dose: Double? = nil,
        water: Double? = nil,
        beverage: Double? = nil,
        seconds: Int? = nil,
        grind: GrindSetting = GrindSetting(),
        temperature: Double? = nil,
        tds: Double? = nil,
        recipeID: UUID? = nil,
        recipeRef: String? = nil,
        recipeSnapshot: RecipeSnapshot? = nil,
        scale: RecipeSize? = nil,
        equipmentIDs: [UUID] = [],
        waterProfileID: UUID? = nil,
        agitation: Agitation? = nil,
        filterStockId: UUID? = nil,
        steps: [BrewStep] = [],
        plannedSteps: [BrewStep] = [],
        actualSource: ActualSource = .none,
        flowGs: Double? = nil,
        recipeName: String? = nil,
        pourRates: [PourRate] = [],
        taste: TasteProfile = TasteProfile(),
        legacyTaste: [String: Int]? = nil,
        flavors: [FlavorTag] = [],
        nextTimeSuggestion: String? = nil,
        captureSource: CaptureSource? = nil,
        rating: Int? = nil,
        acidity: Int = 0,
        bitterness: Int = 0,
        body: Int = 0,
        complexity: Int? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.date = date
        self.method = method
        self.dose = dose
        self.water = water
        self.beverage = beverage
        self.seconds = seconds
        self.grind = grind
        self.temperature = temperature
        self.tds = tds
        self.recipeID = recipeID
        self.recipeRef = recipeRef
        self.recipeSnapshot = recipeSnapshot
        self.scale = scale
        self.equipmentIDs = equipmentIDs
        self.waterProfileID = waterProfileID
        self.agitation = agitation
        self.filterStockId = filterStockId
        self.steps = steps
        self.plannedSteps = plannedSteps
        self.actualSource = actualSource
        self.flowGs = flowGs
        self.recipeName = recipeName
        self.pourRates = pourRates
        self.taste = taste
        self.legacyTaste = legacyTaste
        self.flavors = flavors
        self.nextTimeSuggestion = nextTimeSuggestion
        self.captureSource = captureSource
        self.rating = rating
        self.acidity = acidity
        self.bitterness = bitterness
        self.body = body
        self.complexity = complexity
        self.notes = notes
    }

    // MARK: - Completeness

    /// Enough of a recipe to compare this brew to another.
    var isComparable: Bool {
        completeness == .complete
    }

    var completeness: Completeness {
        var missing: [Completeness.Field] = []
        if method == nil { missing.append(.method) }
        if dose == nil { missing.append(.dose) }
        if water == nil && beverage == nil { missing.append(.output) }
        if seconds == nil { missing.append(.time) }
        if grind.isEmpty { missing.append(.grind) }
        if rating == nil { missing.append(.rating) }
        return missing.isEmpty ? .complete : .missing(missing)
    }

    // MARK: - Computed

    /// Brew ratio as "1:16" when it is a whole number, "1:14.3" otherwise.
    /// Today's water divided by the recipe's nominal water. Not `scale`, which is a cup size.
    var waterScale: Double? {
        guard let live = water ?? beverage,
              let nominal = recipeSnapshot?.water ?? recipeSnapshot?.beverage,
              nominal > 0, live > 0
        else { return nil }
        let factor = live / nominal
        guard abs(factor - 1) >= 0.01 else { return 1 }
        return factor
    }

    var ratio: String? {
        guard let dose, dose > 0 else { return nil }
        let liquid = water ?? beverage
        guard let liquid, liquid > 0 else { return nil }
        let r = liquid / dose
        let rounded = (r * 10).rounded() / 10
        if abs(r - rounded.rounded()) < 0.05 {
            return String(format: "1:%.0f", r.rounded())
        }
        return String(format: "1:%.1f", r)
    }

    /// Average flow in g/s: the water divided by the time. Espresso reads its
    /// flow at the spout, so it uses the beverage instead.
    var averageFlow: Double? {
        guard let seconds, seconds > 0 else { return nil }
        let liquid = method == .espresso ? (beverage ?? water) : (water ?? beverage)
        guard let liquid, liquid > 0 else { return nil }
        return liquid / Double(seconds)
    }

    /// Flow between two steps of the guided timer, which is where an uneven
    /// pour actually shows up.
    var stepFlows: [(step: BrewStep, flow: Double)] {
        var result: [(BrewStep, Double)] = []
        var previousMass = 0.0
        var previousAt = 0
        for step in steps.sorted(by: { $0.at < $1.at }) where step.action != .rinse {
            defer {
                if let mass = step.mass { previousMass = mass }
                previousAt = step.at
            }
            guard let mass = step.mass, step.at > previousAt else { continue }
            let poured = mass - previousMass
            guard poured > 0 else { continue }
            result.append((step, poured / Double(step.at - previousAt)))
        }
        return result
    }

    func flow(for step: BrewStep) -> Double? {
        stepFlows.first { $0.step.id == step.id }?.flow
    }

    /// Extraction yield percentage, when TDS and beverage weight are known.
    var extractionYield: Double? {
        guard let tds, let beverage, let dose, dose > 0 else { return nil }
        return tds * beverage / dose
    }

    /// Formatted brew time, e.g. "2:45".
    var timeLabel: String? {
        guard let seconds, seconds > 0 else { return nil }
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    /// One line for a recipe read off a card: "Filter · 14g · 210ml · 2:20 · 90°C · Medium fine".
    var recipeLine: String {
        func quantity(_ value: Double) -> String {
            value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
        }
        var parts: [String] = []
        if let method { parts.append(method.label) }
        if let dose { parts.append(quantity(dose) + "g") }
        if let water { parts.append(quantity(water) + "ml") }
        if let timeLabel { parts.append(timeLabel) }
        if let temperature { parts.append(quantity(temperature) + "°C") }
        let grindText = grind.display()
        if !grindText.isEmpty { parts.append(grindText) }
        return parts.joined(separator: " · ")
    }

    /// A copy that logs the same recipe on a new day, with rating and taste empty.
    func again(date: Date = .now) -> Brew {
        Brew(
            date: date,
            method: method,
            dose: dose,
            water: water,
            beverage: beverage,
            seconds: seconds,
            grind: grind,
            temperature: temperature,
            recipeID: recipeID,
            recipeRef: recipeRef,
            recipeSnapshot: recipeSnapshot,
            scale: scale,
            equipmentIDs: equipmentIDs,
            waterProfileID: waterProfileID,
            agitation: agitation,
            filterStockId: filterStockId,
            steps: steps.map {
                BrewStep(
                    index: $0.index,
                    action: $0.action,
                    at: 0,
                    mass: nil,
                    targetAt: $0.targetAt,
                    targetMass: $0.targetMass,
                    note: $0.note,
                    agitation: $0.agitation
                )
            },
            plannedSteps: plannedSteps,
            actualSource: .none,
            recipeName: recipeName,
            captureSource: .prefilled
        )
    }

    /// A brew that pointed at a bundled recipe used that recipe's UUID as
    /// `recipeID`. Those ids are not in `public.recipes`, so the FK fails.
    mutating func dropOrphanRecipeLink() {
        guard let recipeID else { return }
        if let match = ReferenceBase.recipes.first(where: { $0.id == recipeID }) {
            if recipeRef == nil {
                recipeRef = match.referenceID.map { "ref:\($0)" }
            }
            self.recipeID = nil
            return
        }
        if recipeRef?.hasPrefix("ref:") == true {
            self.recipeID = nil
        }
    }
}

nonisolated extension Brew {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .now
        method = try c.decodeIfPresent(BrewMethod.self, forKey: .method)
        dose = try c.decodeIfPresent(Double.self, forKey: .dose)
        water = try c.decodeIfPresent(Double.self, forKey: .water)
        beverage = try c.decodeIfPresent(Double.self, forKey: .beverage)
        seconds = try c.decodeIfPresent(Int.self, forKey: .seconds)
        if let setting = try c.decodeIfPresent(GrindSetting.self, forKey: .grind) {
            grind = setting
        } else if let text = try c.decodeIfPresent(String.self, forKey: .grind) {
            grind = GrindSetting(raw: text)
        } else {
            grind = GrindSetting()
        }
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature)
        tds = try c.decodeIfPresent(Double.self, forKey: .tds)
        recipeID = try c.decodeIfPresent(UUID.self, forKey: .recipeID)
        recipeRef = try c.decodeIfPresent(String.self, forKey: .recipeRef)
        recipeSnapshot = try c.decodeIfPresent(RecipeSnapshot.self, forKey: .recipeSnapshot)
        scale = try c.decodeIfPresent(RecipeSize.self, forKey: .scale)
        equipmentIDs = try c.decodeIfPresent([UUID].self, forKey: .equipmentIDs) ?? []
        waterProfileID = try c.decodeIfPresent(UUID.self, forKey: .waterProfileID)
        agitation = try c.decodeIfPresent(Agitation.self, forKey: .agitation)
        let filterKeys = try decoder.container(keyedBy: FilterIDKeys.self)
        filterStockId = try filterKeys.decodeIfPresent(UUID.self, forKey: .filterStockId)
            ?? filterKeys.decodeIfPresent(UUID.self, forKey: .filterId)
        steps = try c.decodeIfPresent([BrewStep].self, forKey: .steps) ?? []
        plannedSteps = try c.decodeIfPresent([BrewStep].self, forKey: .plannedSteps) ?? []
        actualSource = try c.decodeIfPresent(ActualSource.self, forKey: .actualSource) ?? .none
        flowGs = try c.decodeIfPresent(Double.self, forKey: .flowGs)
        recipeName = try c.decodeIfPresent(String.self, forKey: .recipeName)
        pourRates = try c.decodeIfPresent([PourRate].self, forKey: .pourRates) ?? []
        legacyTaste = try c.decodeIfPresent([String: Int].self, forKey: .legacyTaste)
        if let profile = try c.decodeIfPresent(TasteProfile.self, forKey: .taste) {
            taste = profile
            if legacyTaste == nil { legacyTaste = profile.legacy }
        } else {
            taste = TasteProfile()
        }
        if let tags = try c.decodeIfPresent([FlavorTag].self, forKey: .flavors) {
            flavors = tags
        } else if let texts = try c.decodeIfPresent([String].self, forKey: .flavors) {
            flavors = FlavorMatcher.match(texts).tags
        } else {
            flavors = []
        }
        nextTimeSuggestion = try c.decodeIfPresent(String.self, forKey: .nextTimeSuggestion)
        captureSource = try c.decodeIfPresent(CaptureSource.self, forKey: .captureSource)
        rating = try c.decodeIfPresent(Int.self, forKey: .rating)
        acidity = try c.decodeIfPresent(Int.self, forKey: .acidity) ?? 0
        bitterness = try c.decodeIfPresent(Int.self, forKey: .bitterness) ?? 0
        body = try c.decodeIfPresent(Int.self, forKey: .body) ?? 0
        complexity = try c.decodeIfPresent(Int.self, forKey: .complexity)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

private enum FilterIDKeys: String, CodingKey {
    case filterStockId, filterId
}
