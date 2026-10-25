import Foundation

/// One seed for every brew entry. The recipe path used to write a thinner
/// brew than the card path; this is the reason those rows could not feed
/// Compare or the diagnostic.
@MainActor
enum BrewPrefill {
    /// Fills kit, grind, water, filter, agitation and capture source without
    /// overwriting what is already on the brew.
    static func seed(
        card: CoffeeCard,
        recipe: Recipe? = nil,
        size: RecipeSize? = nil,
        existing: Brew? = nil,
        setup: SetupStore,
        keepSnapshot: Bool = true
    ) -> Brew {
        var brew: Brew
        if let existing {
            brew = existing
        } else if let recipe {
            brew = recipe.seededBrew(size: size)
            if !keepSnapshot { brew.recipeSnapshot = nil }
        } else if let last = card.brews.first {
            brew = nextTimeDraft(from: last, setup: setup) ?? last.again()
        } else {
            brew = Brew(method: card.brewMethod)
        }
        // An existing brew already has a kit; replacing it would rewrite
        // history. Empty kit (Brew again of an old thin row) still fills.
        fill(
            &brew,
            card: card,
            recipe: recipe,
            setup: setup,
            replaceKit: existing == nil || brew.equipmentIDs.isEmpty
        )
        return brew
    }

    /// Kit and empty-field fill. Called after a method change as well as
    /// after the first seed.
    static func fill(
        _ brew: inout Brew,
        card: CoffeeCard,
        recipe: Recipe?,
        setup: SetupStore,
        replaceKit: Bool = true
    ) {
        if replaceKit, let method = brew.method {
            applyDefaults(to: &brew, method: method, setup: setup)
        }
        ensureMatchingBrewer(on: &brew, setup: setup)
        fillGrind(&brew, card: card, recipe: recipe, setup: setup)
        fillTemperature(&brew, card: card)
        fillAgitation(&brew, card: card)
        fillFilter(&brew, setup: setup)
        fillSteps(&brew, card: card, recipe: recipe)
        if brew.waterProfileID == nil {
            brew.waterProfileID = setup.defaultWaterProfile?.id
        }
        if brew.captureSource == nil, brew.dose != nil, brew.water != nil || brew.beverage != nil {
            brew.captureSource = .prefilled
        }
    }

    /// Paper you swap between cups. The selected brewer's family wins; the
    /// method is the fallback when no brewer is on the brew yet.
    static func showsFilter(method: BrewMethod?, brewer: Equipment?) -> Bool {
        if let family = brewer?.brewerFamily {
            return family.usesInterchangeableFilter
        }
        return method?.usesInterchangeableFilter ?? false
    }

    /// When Setup has a brewer for this method but it was never marked as a
    /// default, Dial would otherwise have nothing to hang a filter list on.
    /// Espresso never borrows a filter dripper.
    static func ensureMatchingBrewer(on brew: inout Brew, setup: SetupStore) {
        let tab = BrewKit.tab(for: brew.method)
        if let current = BrewKit.activeBrewer(on: brew, in: setup) {
            if BrewKit.matches(tab, current) { return }
            BrewKit.clearCupboard(from: &brew, setup: setup)
            brew.filterStockId = nil
        }
        guard let method = brew.method else { return }
        let match = setup.equipment.first {
            BrewKit.isCupboard($0.kind) && BrewKit.matches(tab, $0) && $0.brewerKind?.method == method
        } ?? setup.equipment.first {
            BrewKit.isCupboard($0.kind) && BrewKit.matches(tab, $0)
        }
        guard let match else { return }
        brew.equipmentIDs.append(match.id)
        if brew.filterStockId == nil, match.takesPaper,
           let paper = FilterFit.default(for: match, in: setup) {
            brew.filterStockId = paper.id
        }
    }

    static func applyDefaults(to brew: inout Brew, method: BrewMethod, setup: SetupStore) {
        let defaults = setup.defaults(for: method)
        guard !defaults.isEmpty else { return }
        let kept = brew.equipmentIDs.filter { id in
            guard let item = setup.equipment(id: id) else { return false }
            return !defaults.contains { $0.kind == item.kind }
        }
        brew.equipmentIDs = kept + defaults.map(\.id)
    }

    /// A recipe the timer can follow when the brew was freeform.
    static func timerRecipe(from brew: Brew, named name: String = "Brew") -> Recipe {
        if let snapshot = brew.recipeSnapshot {
            return Recipe(snapshot: snapshot)
        }
        var recipe = Recipe(
            name: name.isEmpty ? Recipe.expressTitle(family: (brew.method ?? .v60).family) : name,
            method: brew.method ?? .v60,
            dose: brew.dose,
            water: brew.water,
            beverage: brew.beverage,
            temperature: brew.temperature,
            seconds: brew.seconds,
            grindLabel: brew.grind.display(),
            source: .express,
            evidence: .unverified
        )
        return DefaultSequence.filling(recipe, roastLevel: nil)
    }

    static func finish(_ brew: Brew, events: AIEventLog, dictationEventID: UUID?) -> Brew {
        var saved = brew
        saved.flowGs = saved.averageFlow
        if saved.captureSource == nil { saved.captureSource = .typed }
        if saved.recipeName == nil {
            saved.recipeName = saved.recipeSnapshot?.name
        }
        if saved.agitation == nil {
            saved.agitation = saved.resolvedAgitation
        }
        saved.refreshPourRates()
        if let dictationEventID {
            events.setAccepted(true, for: dictationEventID)
        }
        return saved
    }

    static func persist(
        _ brew: Brew,
        onto card: CoffeeCard,
        replacing: Bool,
        store: CardStore,
        events: AIEventLog,
        dictationEventID: UUID?
    ) {
        let saved = finish(brew, events: events, dictationEventID: dictationEventID)
        var updated = store.card(id: card.id) ?? card
        if replacing, let index = updated.brews.firstIndex(where: { $0.id == saved.id }) {
            updated.brews[index] = saved
        } else {
            updated.brews.insert(saved, at: 0)
        }
        store.update(updated)
    }

    // MARK: - Empty fields

    private static func fillGrind(
        _ brew: inout Brew,
        card: CoffeeCard,
        recipe: Recipe?,
        setup: SetupStore
    ) {
        if brew.grind.grinderId == nil, let grinder = setup.preferredGrinder(for: brew.method) {
            brew.grind.grinderId = grinder.id
        }
        guard brew.grind.value == nil else { return }

        if let last = card.brews.first(where: {
            $0.id != brew.id && $0.method == brew.method && $0.grind.value != nil
        }) {
            brew.grind = last.grind
            return
        }

        if let recipe,
           let grinder = setup.preferredGrinder(for: recipe.method),
           let translation = GrindConversion.translate(
               recipe: recipe,
               to: grinder,
               calibrations: setup.calibrations
           )
        {
            brew.grind = GrindSetting(
                grinderId: grinder.id,
                value: translation.setting,
                raw: translation.label
            )
            return
        }

        if let grinder = setup.preferredGrinder(for: brew.method),
           let range = grinder.range(for: brew.method ?? .v60)
        {
            let mid = (range.low + range.high) / 2
            brew.grind = GrindSetting(
                grinderId: grinder.id,
                value: grinder.adjustment?.isDetented == true ? mid.rounded() : mid
            )
        }
    }

    private static func fillAgitation(_ brew: inout Brew, card: CoffeeCard) {
        guard brew.agitation == nil else { return }
        if let last = card.brews.first(where: {
            $0.id != brew.id && $0.method == brew.method && $0.agitation != nil
        }) {
            brew.agitation = last.agitation
        } else {
            brew.agitation = .none
        }
    }

    private static func fillTemperature(_ brew: inout Brew, card: CoffeeCard) {
        guard brew.temperature == nil, let method = brew.method else { return }
        brew.temperature = RecipeRules.suggestedTemperature(for: card.roastLevel, method: method)
        if brew.captureSource == nil { brew.captureSource = .prefilled }
    }

    private static func fillFilter(_ brew: inout Brew, setup: SetupStore) {
        guard brew.filterStockId == nil else { return }
        let tab = BrewKit.tab(for: brew.method)
        let brewer = BrewKit.activeBrewer(on: brew, in: setup)
            ?? setup.defaults(for: brew.method ?? .v60).first {
                BrewKit.isCupboard($0.kind) && BrewKit.matches(tab, $0)
            }
        guard let brewer, BrewKit.matches(tab, brewer), brewer.takesPaper else { return }
        brew.filterStockId = FilterFit.default(for: brewer, in: setup)?.id
    }

    private static func fillSteps(_ brew: inout Brew, card: CoffeeCard, recipe: Recipe?) {
        guard brew.steps.isEmpty else { return }
        if let recipe, !recipe.steps.isEmpty { return }
        if let last = card.brews.first(where: { $0.id != brew.id && !$0.steps.isEmpty }) {
            brew.steps = last.steps.map {
                BrewStep(
                    index: $0.index,
                    action: $0.action,
                    at: 0,
                    mass: nil,
                    targetAt: $0.targetAt ?? $0.at,
                    targetMass: $0.targetMass ?? $0.mass,
                    note: $0.note
                )
            }
        }
    }

    private static func nextTimeDraft(from last: Brew, setup: SetupStore) -> Brew? {
        guard let pair = matchedSuggestion(on: last) else { return nil }
        return BrewDiagnosis.draft(
            from: last,
            applying: pair,
            grinder: setup.preferredGrinder(for: last.method)
        )
    }

    /// Brew again, with the move chosen last time already on the numbers.
    ///
    /// `Brew.again()` copies the cup as brewed. The chosen correction lives on
    /// the previous cup, so it has to be applied here — passing `again()` in
    /// as `existing` used to skip `nextTimeDraft` entirely.
    static func preparedAgain(
        from last: Brew,
        setup: SetupStore
    ) -> (brew: Brew, application: LastApplication?) {
        let copy = last.again()
        guard let suggestion = matchedSuggestion(on: last) else { return (copy, nil) }
        let drafted = BrewDiagnosis.draft(
            from: last,
            applying: suggestion,
            grinder: setup.preferredGrinder(for: last.method)
        )
        let undo = UndoFields(
            grind: copy.grind,
            dose: copy.dose,
            water: copy.water,
            beverage: copy.beverage,
            temperature: copy.temperature,
            seconds: copy.seconds
        )
        var brew = copy
        brew.grind = drafted.grind
        brew.dose = drafted.dose
        brew.water = drafted.water
        brew.beverage = drafted.beverage
        brew.temperature = drafted.temperature
        brew.seconds = drafted.seconds
        return (brew, LastApplication(change: suggestion.change, undo: undo))
    }

    private static func matchedSuggestion(on last: Brew) -> NextTime? {
        guard let saved = last.nextTimeSuggestion else { return nil }
        return BrewDiagnosis.candidates(for: last).first { $0.change == saved }
    }
}

extension BrewPrefill {
    /// What Brew again already moved, and the numbers to put back on Undo.
    struct LastApplication: Equatable, Sendable {
        var change: String
        var undo: UndoFields
    }

    struct UndoFields: Equatable, Sendable {
        var grind: GrindSetting
        var dose: Double?
        var water: Double?
        var beverage: Double?
        var temperature: Double?
        var seconds: Int?
    }
}
