import Foundation

/// One change the rules made to a recipe, and why.
///
/// Adjustments are values rather than prose baked into the recipe, so the sheet
/// can list them under the parameters and you can see what was decided for you.
nonisolated struct RecipeAdjustment: Identifiable, Hashable, Sendable {
    var id: String { label }
    /// "94 °C", "one step coarser", "bloom +15 s".
    var label: String
    /// "light roast", "decaf", "3 days off roast".
    var reason: String
}

/// Where a suggested recipe came from, in a form the UI can put in a `tag`.
nonisolated enum RecipeProvenance: Hashable, Sendable {
    /// Printed on the bag, used as it stands.
    case card
    /// A bundled reference recipe, with its attribution.
    case reference(String)
    /// A reference recipe moved by the rules.
    case adjustedReference(String)
    /// Derived from a brew of yours that you rated well.
    case yourBrew(coffee: String)
    /// One of your saved recipes.
    case mine(String)

    var label: String {
        switch self {
        case .card: "Card recipe"
        case .reference(let who): who.isEmpty ? Copy.fromThePros : who
        case .adjustedReference(let who): who.isEmpty ? "\(Copy.fromThePros), adjusted" : "\(who), adjusted"
        case .yourBrew(let coffee): "Your best \(coffee)"
        case .mine(let name): name
        }
    }

    /// The short word for the `tag` column.
    var kind: String {
        switch self {
        case .card: "card"
        case .reference: "reference"
        case .adjustedReference: "adjusted"
        case .yourBrew: "yours"
        case .mine: "mine"
        }
    }

    /// Provenance in a list, one line, as a catalogue label.
    var listLabel: String {
        switch self {
        case .card: "Card"
        case .reference: Copy.fromThePros
        case .adjustedReference: "Adapted"
        case .yourBrew, .mine: "Yours"
        }
    }
}

nonisolated struct RecipeSuggestion: Hashable, Sendable {
    var recipe: Recipe
    var provenance: RecipeProvenance
    var adjustments: [RecipeAdjustment]
    /// How many notches coarser the grind should go, negative for finer.
    /// Applied to your grinder's numbers by `GrindConversion`, not here.
    var grindShift: Int

    var hasAdjustments: Bool { !adjustments.isEmpty }
}

/// The deterministic half of the recipe assistant.
///
/// Every rule here comes from annexe G, runs offline, and is testable without
/// a network or a model. The AI variant in chantier 6 sits *under* this, never
/// in its place: if the model is off, unavailable or wrong, you still get a
/// recipe with a reason attached to every number.
nonisolated enum RecipeRules {
    /// Starting temperature by roast level (annexe G3). Practice, not physics:
    /// the temperature is a way to reach the extraction you want, and the
    /// published sensory effect at fixed TDS is small.
    static func temperature(for roast: RoastLevel?, method: BrewMethod) -> ClosedRange<Double> {
        let isEspresso = method == .espresso
        switch roast {
        case .light: return isEspresso ? 94...96 : 94...100
        case .mediumLight: return isEspresso ? 93...95 : 92...96
        case .medium, .none: return isEspresso ? 92...94 : 90...94
        case .mediumDark: return isEspresso ? 90...93 : 88...92
        case .dark: return isEspresso ? 88...92 : 85...90
        }
    }

    /// The single number to pre-fill: the middle of the band, rounded to a
    /// degree, because no kettle is set to 96.5.
    static func suggestedTemperature(for roast: RoastLevel?, method: BrewMethod) -> Double {
        let band = temperature(for: roast, method: method)
        return ((band.lowerBound + band.upperBound) / 2).rounded()
    }

    /// Days after roasting before a coffee is usually ready (annexe G5).
    /// Practice, and the window is wide on purpose.
    static func restWindow(for method: BrewMethod, roast: RoastLevel?) -> ClosedRange<Int> {
        if method == .espresso { return 10...30 }
        switch roast {
        case .dark, .mediumDark: return 5...14
        default: return 7...21
        }
    }

    /// Usual ratios by method (annexe G2), as the liquid per gram of coffee.
    static func ratio(for method: BrewMethod) -> ClosedRange<Double> {
        switch method {
        case .espresso: 1.5...3
        case .v60, .filter: 15...17
        case .aeropress: 12...18
        case .frenchPress: 15...17
        case .moka: 7...10
        case .coldBrew: 5...8
        }
    }

    /// Indicative particle size per method (annexe G1). A published site's
    /// approximate D50 values, not measurements of ours — only ever a starting
    /// point for "in your terms".
    static func microns(for method: BrewMethod) -> ClosedRange<Double>? {
        switch method {
        case .espresso: 180...380
        case .aeropress: 320...960
        case .v60: 400...700
        case .filter: 410...930
        case .frenchPress: 690...1_300
        case .coldBrew: 820...1_270
        case .moka: nil
        }
    }

    // MARK: - Suggestion

    /// The recipe to offer for a coffee, and why.
    ///
    /// Order of preference: what the roaster printed, then a recipe of your own
    /// that worked on a comparable coffee, then a reference recipe moved by the
    /// rules. Your own good brew outranks a generic reference because it is
    /// evidence from your kit, in your water, to your taste.
    static func suggestion(
        for card: CoffeeCard,
        method: BrewMethod? = nil,
        references: [Recipe] = ReferenceBase.recipes,
        mine: [Recipe] = [],
        neighbours: [CoffeeCard] = [],
        now: Date = .now
    ) -> RecipeSuggestion? {
        let method = method ?? preferredMethod(for: card, references: references)

        if let printed = card.recipeSuggestion, printed.dose != nil,
           printed.water != nil || printed.beverage != nil {
            return RecipeSuggestion(
                recipe: recipe(from: printed, card: card),
                provenance: .card,
                adjustments: [],
                grindShift: 0
            )
        }

        if let borrowed = fromYourBestBrew(method: method, neighbours: neighbours, card: card) {
            return borrowed
        }

        let pool = ranked(mine.filter { $0.method == method }, method: method)
            + ranked(references.filter { $0.method == method }, method: method)
        guard let base = pool.first else { return nil }
        return adjust(base, for: card, now: now)
    }

    /// Mine stays in front of references. Within each side: ratio inside the
    /// method's band, then evidence, then the order they were handed in so the
    /// choice is stable. A missing ratio is neutral, not a penalty — moka
    /// does not print one.
    static func ranked(_ recipes: [Recipe], method: BrewMethod) -> [Recipe] {
        let band = ratio(for: method)
        return recipes.enumerated().sorted { a, b in
            let aRatio = ratioRank(a.element, band: band)
            let bRatio = ratioRank(b.element, band: band)
            if aRatio != bRatio { return aRatio < bRatio }
            let aEvidence = evidenceRank(a.element.evidence)
            let bEvidence = evidenceRank(b.element.evidence)
            if aEvidence != bEvidence { return aEvidence < bEvidence }
            return a.offset < b.offset
        }.map(\.element)
    }

    private static func ratioRank(_ recipe: Recipe, band: ClosedRange<Double>) -> Int {
        guard let value = recipe.ratioValue else { return 1 }
        return band.contains(value) ? 0 : 2
    }

    private static func evidenceRank(_ evidence: Evidence) -> Int {
        switch evidence {
        case .verified: 0
        case .partial: 1
        case .practice: 2
        case .unverified: 3
        }
    }

    /// The method to suggest when nothing has been chosen: the one the coffee's
    /// own card names, else the one its last brew used, else V60 if there is a
    /// reference for it.
    static func preferredMethod(
        for card: CoffeeCard,
        references: [Recipe] = ReferenceBase.recipes
    ) -> BrewMethod {
        if let printed = card.recipeSuggestion?.method { return printed }
        if let last = card.brews.first(where: { $0.method != nil })?.method { return last }
        return references.contains(where: { $0.method == .v60 }) ? .v60 : .filter
    }

    // MARK: - Rules

    /// Moves a reference recipe onto this particular bag (annexe G3).
    ///
    /// Four rules, each leaving a reason behind: roast level sets the water
    /// temperature and nudges the ratio, decaf goes a step coarser and a touch
    /// cooler, and a coffee still degassing gets a longer bloom.
    static func adjust(_ base: Recipe, for card: CoffeeCard, now: Date = .now) -> RecipeSuggestion {
        var recipe = base
        var adjustments: [RecipeAdjustment] = []
        var grindShift = 0

        // Temperature, from the roast level — only when the card actually
        // says something, and never on methods whose water is not a choice.
        let temperatureIsAChoice = base.method != .moka && base.method != .coldBrew
        if temperatureIsAChoice, let roast = card.roastLevel {
            let suggested = suggestedTemperature(for: roast, method: base.method)
            if recipe.temperature != suggested {
                recipe.temperature = suggested
                recipe.temperatureMax = nil
                adjustments.append(RecipeAdjustment(
                    label: "\(GrindRange.number(suggested)) °C",
                    reason: "\(roast.label.lowercased()) roast"
                ))
            }
        }

        // Ratio, nudged at the ends of the roast scale only. A light roast
        // gives up its sugars more slowly, so it takes slightly more water;
        // a dark roast is already soluble and turns hollow if stretched.
        if let shift = ratioShift(for: card.roastLevel), let dose = recipe.dose {
            if let water = recipe.water, let ratio = recipe.ratioValue {
                let moved = ((dose * (ratio + shift)) / 5).rounded() * 5
                if moved != water {
                    recipe.water = moved
                    adjustments.append(RecipeAdjustment(
                        label: "1:\(GrindRange.number(ratio + shift))",
                        reason: shift > 0 ? "light roast, a little longer" : "dark roast, a little shorter"
                    ))
                }
            }
        }

        // Decaf: the beans are more brittle, so the same setting produces more
        // fines. One notch coarser, two degrees cooler.
        if card.isDecaf {
            grindShift += 1
            if let temperature = recipe.temperature {
                recipe.temperature = temperature - 2
            }
            adjustments.append(RecipeAdjustment(
                label: "one step coarser · −2 °C",
                reason: "decaf"
            ))
        }

        // Still degassing: CO₂ pushes the water off the bed, so the bloom needs
        // longer before the pours mean anything.
        if let days = card.daysOffRoast(asOf: now), days < 5, !recipe.steps.isEmpty {
            recipe.steps = lengthenBloom(recipe.steps, by: 15)
            recipe.seconds = recipe.seconds.map { $0 + 15 }
            adjustments.append(RecipeAdjustment(
                label: "bloom +15 s",
                reason: days == 0 ? "roasted today, still degassing" : "\(days) days off roast, still degassing"
            ))
        }

        recipe.grindLabel = grindShift == 0
            ? base.grindLabel
            : "\(base.grindLabel), \(grindShift > 0 ? "coarser" : "finer")"

        let provenance: RecipeProvenance = adjustments.isEmpty
            ? .reference(base.attribution)
            : .adjustedReference(base.attribution)

        return RecipeSuggestion(
            recipe: recipe,
            provenance: provenance,
            adjustments: adjustments,
            grindShift: grindShift
        )
    }

    /// How much longer or shorter the ratio should run, in units of the ratio
    /// itself: +1 means 1:16 becomes 1:17.
    static func ratioShift(for roast: RoastLevel?) -> Double? {
        switch roast {
        case .light: 1
        case .dark: -1
        case .mediumLight, .medium, .mediumDark, .none: nil
        }
    }

    /// Pushes every step after the bloom back, so a longer bloom does not eat
    /// into the first pour.
    static func lengthenBloom(_ steps: [RecipeStep], by seconds: Int) -> [RecipeStep] {
        guard let bloomIndex = steps.firstIndex(where: { $0.action == .bloom }) else { return steps }
        return steps.enumerated().map { index, step in
            guard index > bloomIndex else { return step }
            var moved = step
            moved.at += seconds
            moved.untilSeconds = moved.untilSeconds.map { $0 + seconds }
            return moved
        }
    }

    // MARK: - Adapted from your own brews

    /// A coffee is comparable when it shares the two things that change how it
    /// behaves in the brewer: how it was processed and how far it was roasted.
    /// Origin and variety are not in that list on purpose.
    static func isComparable(_ card: CoffeeCard, to other: CoffeeCard) -> Bool {
        guard card.id != other.id else { return false }
        let sameRoast = card.roastLevel == other.roastLevel
        let sameProcess = !card.process.isEmpty
            && card.process.compare(other.process, options: .caseInsensitive) == .orderedSame
        return sameRoast && sameProcess
    }

    /// Your best brew of a comparable coffee, when there is one worth copying.
    /// Requires a rating of 4 or better: a 3 is not a recipe, it is a Tuesday.
    private static func fromYourBestBrew(
        method: BrewMethod,
        neighbours: [CoffeeCard],
        card: CoffeeCard
    ) -> RecipeSuggestion? {
        var best: (card: CoffeeCard, brew: Brew)?
        for neighbour in neighbours where isComparable(card, to: neighbour) {
            for brew in neighbour.brews
            where brew.method == method && (brew.rating ?? 0) >= 4 && brew.dose != nil {
                if let current = best, (current.brew.rating ?? 0) >= (brew.rating ?? 0) { continue }
                best = (neighbour, brew)
            }
        }
        guard let best else { return nil }

        return RecipeSuggestion(
            recipe: recipe(from: best.brew, card: best.card, source: .adapted),
            provenance: .yourBrew(coffee: best.card.name.isEmpty ? "brew" : best.card.name),
            adjustments: [],
            grindShift: 0
        )
    }

    // MARK: - Conversions

    /// A brew read as a recipe — for the card's printed recipe, and for
    /// "Save as recipe".
    static func recipe(
        from brew: Brew,
        card: CoffeeCard,
        source: RecipeSource = .card,
        name: String? = nil
    ) -> Recipe {
        Recipe(
            name: name ?? (source == .card ? "\(card.name) — as printed" : card.name),
            method: brew.method ?? preferredMethod(for: card),
            dose: brew.dose,
            water: brew.water,
            beverage: brew.beverage,
            temperature: brew.temperature,
            seconds: brew.seconds,
            grindLabel: brew.grind.display(),
            source: source,
            evidence: .practice,
            attribution: source == .card ? card.roaster : "",
            notes: brew.notes,
            cardID: card.id,
            brewID: brew.id
        )
    }
}
