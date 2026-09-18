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
        setup: SetupStore
    ) -> Brew {
        var brew: Brew
        if let existing {
            brew = existing
        } else if let recipe {
            brew = recipe.seededBrew(size: size)
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
        fillGrind(&brew, card: card, recipe: recipe, setup: setup)
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
        return Recipe(
            name: name,
            method: brew.method ?? .v60,
            dose: brew.dose,
            water: brew.water,
            beverage: brew.beverage,
            temperature: brew.temperature,
            seconds: brew.seconds,
            grindLabel: brew.grind.display(),
            source: .mine
        )
    }

    static func finish(_ brew: Brew, events: AIEventLog, dictationEventID: UUID?) -> Brew {
        var saved = brew
        saved.flowGs = saved.averageFlow
        if saved.captureSource == nil { saved.captureSource = .typed }
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
        }
    }

    private static func fillFilter(_ brew: inout Brew, setup: SetupStore) {
        guard brew.filterId == nil else { return }
        let brewer = brew.equipmentIDs.compactMap { setup.equipment(id: $0) }.first { $0.kind == .brewer }
            ?? setup.defaults(for: brew.method ?? .v60).first { $0.kind == .brewer }
        guard let brewer else { return }
        brew.filterId = brewer.defaultFilterId ?? brewer.filters.first?.id
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
        guard let saved = last.nextTimeSuggestion,
              let suggestion = BrewDiagnosis.candidates(for: last)
                  .first(where: { $0.change == saved })
        else { return nil }
        return BrewDiagnosis.draft(
            from: last,
            applying: suggestion,
            grinder: setup.preferredGrinder(for: last.method)
        )
    }
}
