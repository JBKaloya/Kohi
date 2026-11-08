import Foundation
import Observation

/// The one brew in progress. Every entry (card, recipe, cup FAB, edit, again)
/// mutates this rather than opening a different sheet.
@Observable
@MainActor
final class BrewSession: Identifiable {
    let id = UUID()
    var card: CoffeeCard
    var recipe: Recipe?
    /// The recipe as it was chosen, before any resizing on Today's settings.
    ///
    /// Resizing always measures from here. Scaling from `recipe` instead made
    /// each keystroke compound on the last one, which is how a 150 g rinse
    /// reached 60 kg. Set it through `adopt(recipe:)`.
    private(set) var nominalRecipe: Recipe?
    var size: RecipeSize
    var brew: Brew
    var step: Step
    var mode: Mode
    /// True when this journey opened on Start a brew because the coffee already had a cup.
    var includesLauncher: Bool
    /// Mine or From the pros. The Last lane is not part of this journey.
    var recipeLane: RecipePickerList.Lane
    /// The screen How much? returns to. Nil dismisses the journey.
    var dialReturn: Step?
    /// Skip the timer and go to After — logging a cup that already happened.
    var logged = false
    /// The tab last tapped on Which recipe or With what. Only read when the
    /// brew has no brewer: a batch brew without its machine records `.filter`,
    /// which alone reads as Hand brew.
    var familyHint: BrewerFamily?
    /// Set when Brew again already applied the move chosen last time.
    var lastApplication: BrewPrefill.LastApplication?
    /// Suggestion captured once, when the cup is saved. Read does not recompute it.
    var frozenCorrection: SuggestedCorrection?
    /// Open straight on Read when revisiting a saved cup.
    var opensRead = false
    var dictationEventID: UUID?
    let voiceNote = BrewVoiceNote()
    /// False when the journey started from the cup FAB (coffee was picked first).
    var fromCard: Bool

    enum Step: Hashable {
        case start
        case previous
        case scope
        case kit
        case dial
        case pour
        case after
    }

    enum Mode: Hashable {
        case create
        case edit
    }

    init(
        card: CoffeeCard,
        recipe: Recipe? = nil,
        suggested: Recipe? = nil,
        size: RecipeSize? = nil,
        existing: Brew? = nil,
        mode: Mode = .create,
        start: Step = .scope,
        fromCard: Bool = true,
        lastApplication: BrewPrefill.LastApplication? = nil,
        setup: SetupStore
    ) {
        let opensLauncher = mode == .create
            && recipe == nil
            && existing == nil
            && start == .scope
            && !card.brews.isEmpty
        self.card = card
        self.recipe = recipe
        self.nominalRecipe = recipe
        let brew = BrewPrefill.seed(
            card: card,
            recipe: recipe ?? (opensLauncher ? nil : suggested),
            size: size,
            existing: opensLauncher ? Brew(method: card.brewMethod) : existing,
            setup: setup,
            keepSnapshot: recipe != nil
        )
        self.brew = brew
        self.size = size ?? RecipeSize.inferred(from: brew.water)
        self.mode = mode
        self.includesLauncher = opensLauncher
        self.recipeLane = recipe?.source == .reference || recipe?.source == .ai || card.brews.isEmpty
            ? .pros
            : .mine
        self.dialReturn = nil
        self.step = opensLauncher ? .start : start
        self.fromCard = fromCard
        self.lastApplication = lastApplication
        if mode == .edit { logged = true }
        if self.brew.recipeName == nil {
            self.brew.recipeName = recipe?.name ?? suggested?.name
        }
    }

    /// Launcher, recipe or previous brew, amounts, then the pour when the timer runs.
    /// A first brew has no launcher. Logging without the timer drops the pour tick.
    var progressTotal: Int {
        let coffee = fromCard ? 0 : 1
        let pour = (mode == .edit || logged) ? 0 : 1
        let launcher = includesLauncher ? 1 : 0
        return coffee + launcher + 3 + pour
    }

    var progressIndex: Int {
        let coffee = fromCard ? 0 : 1
        let choice = coffee + (includesLauncher ? 1 : 0)
        switch step {
        case .start: return coffee
        case .previous, .scope, .kit: return choice
        case .dial: return choice + 1
        case .pour: return choice + 2
        case .after: return choice + 1 + ((mode == .edit || logged) ? 0 : 1)
        }
    }

    func timerRecipe(in setup: SetupStore) -> Recipe {
        // 1. Choose a base, scaling to the brew's live numbers.
        //    The snapshot already has steps; use them when present.
        let base: Recipe
        if let snapshot = brew.recipeSnapshot {
            let fromSnapshot = Recipe(snapshot: snapshot)
            // Scale the non-rinse steps when the brew's numbers differ from
            // the snapshot. RecipeScaling refuses an absurd factor, so a
            // half-typed digit in the water field leaves the sequence alone.
            if let live = RecipeScaling.liquid(of: brew),
               let resized = RecipeScaling.rescaled(fromSnapshot, toLiquid: live)
            {
                base = resized
            } else {
                base = fromSnapshot
            }
        } else if let recipe {
            base = RecipeScaling.scaled(recipe, to: size).recipe
        } else {
            base = BrewPrefill.timerRecipe(from: brew, named: brew.recipeName ?? card.name)
        }

        let brewer = BrewKit.activeBrewer(on: brew, in: setup)
        let filled = DefaultSequence.filling(
            base,
            type: brewer?.brewerKind,
            roastLevel: card.roastLevel
        )

        // 2. The rinse step is *never* stored in a recipe or snapshot.
        //    It is injected here, from RinseRule, every time.
        //    Whatever rinse mass may be in the snapshot (e.g. a stale one
        //    from a build before the scaling fix) is stripped first.
        var stripped = filled
        stripped.steps = filled.steps.filter { $0.action != .rinse }

        let stock = brew.filterStockId.flatMap { setup.filterStock(id: $0) }
        var guided = RinseRule.injecting(into: stripped, brewer: brewer, stock: stock)
        if let mode = recipe?.advanceMode ?? nominalRecipe?.advanceMode {
            guided.advanceMode = mode
            guided.autoAdvance = mode == .auto
        }
        return guided
    }

    /// Attaches a recipe and pins it as the resize baseline. Every path that
    /// *chooses* a recipe goes through here; resizing does not.
    func adopt(recipe: Recipe?) {
        self.recipe = recipe
        nominalRecipe = recipe
    }

    func apply(recipe: Recipe, setup: SetupStore) {
        adopt(recipe: recipe)
        brew = BrewPrefill.seed(
            card: card,
            recipe: recipe,
            size: size,
            setup: setup
        )
    }

    /// The liquid total of the recipe as chosen, before any resizing.
    var nominalRecipeLiquid: Double? {
        nominalRecipe.flatMap { RecipeScaling.liquid(of: $0) }
    }

    /// Resizes the attached recipe to whatever the brew now says, measuring
    /// from the nominal recipe so keystrokes never compound.
    ///
    /// Silently does nothing when there is no recipe, no baseline, or when
    /// `RecipeScaling` judges the factor absurd — a half-typed "2" on the way
    /// to "200" must not rewrite the sequence.
    func resizeRecipeToBrew() {
        guard let nominal = nominalRecipe,
              let live = RecipeScaling.liquid(of: brew),
              let resized = RecipeScaling.rescaled(nominal, toLiquid: live)
        else { return }
        recipe = resized
        brew.recipeSnapshot = resized.brewLink().snapshot
        brew.recipeName = resized.name
    }

    func undoLastApplication() {
        guard let saved = lastApplication else { return }
        brew.grind = saved.undo.grind
        brew.dose = saved.undo.dose
        brew.water = saved.undo.water
        brew.beverage = saved.undo.beverage
        brew.temperature = saved.undo.temperature
        brew.seconds = saved.undo.seconds
        lastApplication = nil
    }

    func keepLastApplication() {
        lastApplication = nil
    }

    func setAdvanceMode(_ mode: AdvanceMode) {
        recipe?.advanceMode = mode
        recipe?.autoAdvance = mode == .auto
        if nominalRecipe != nil {
            nominalRecipe?.advanceMode = mode
            nominalRecipe?.autoAdvance = mode == .auto
        }
    }

    func apply(size: RecipeSize) {
        self.size = size
        if let recipe {
            let scaled = RecipeScaling.scaled(recipe, to: size)
            brew.dose = scaled.recipe.dose
            brew.water = scaled.recipe.water
            brew.recipeSnapshot = scaled.recipe.brewLink().snapshot
            brew.scale = scaled.isScaled ? size : nil
        } else if brew.method != .espresso {
            if let dose = brew.dose, let water = brew.water, water > 0, dose > 0 {
                let ratio = water / dose
                brew.water = size.waterGrams
                brew.dose = RecipeScaling.roundHalf(size.waterGrams / ratio)
            } else {
                brew.water = size.waterGrams
            }
            brew.scale = size
        }
    }

    func apply(method: BrewMethod?, setup: SetupStore) {
        brew.method = method
        guard let method else { return }
        if recipe?.method != method {
            adopt(recipe: nil)
        }
        BrewPrefill.applyDefaults(to: &brew, method: method, setup: setup)
        BrewPrefill.fill(&brew, card: card, recipe: recipe, setup: setup)
    }

    /// The tabs on Which recipe and With what. Drops a recipe that belongs
    /// to another tab so the list and the cupboard stay in step.
    func apply(family: BrewerFamily, setup: SetupStore) {
        familyHint = family
        BrewKit.applyFamily(family, to: &brew, setup: setup, card: card, recipe: recipe)
        if let recipe, !BrewKit.accepts(family, recipe.method) {
            adopt(recipe: nil)
        }
    }

    func tab(in setup: SetupStore) -> BrewerFamily {
        BrewKit.tab(for: brew, in: setup, hint: familyHint)
    }

    /// Edit a recipe immediately before the timer.
    ///
    /// - Recipes you own (mine / express) are updated in place.
    /// - Reference, card or AI recipes are copied as a new .express recipe.
    ///
    /// Either way `self.recipe` and `brew.recipeSnapshot` are refreshed so
    /// `timerRecipe` and `seedPlan` pick up the edited numbers.
    func applyEdited(_ edited: Recipe, store: RecipeStore) {
        var saved = edited
        saved.source = .express
        saved.autoAdvance = false
        if let current = recipe, current.source == .mine || current.source == .express,
           store.recipe(id: current.id) != nil
        {
            // Merge the edited fields into the existing record to preserve its id.
            var updated = current
            updated.name = saved.name
            updated.method = saved.method
            updated.dose = saved.dose
            updated.water = saved.water
            updated.beverage = saved.beverage
            updated.temperature = saved.temperature
            updated.seconds = saved.seconds
            updated.grindLabel = saved.grindLabel
            updated.steps = saved.steps
            updated.source = saved.source
            updated.evidence = saved.evidence
            updated.autoAdvance = saved.autoAdvance
            store.update(updated)
            saved = updated
        } else {
            // Build a fresh record with a new UUID so it does not collide with
            // the original reference recipe.
            let copy = Recipe(
                name: saved.name,
                method: saved.method,
                dose: saved.dose,
                water: saved.water,
                beverage: saved.beverage,
                temperature: saved.temperature,
                seconds: saved.seconds,
                grindLabel: saved.grindLabel,
                steps: saved.steps,
                source: .express,
                evidence: .unverified,
                autoAdvance: false
            )
            store.add(copy)
            saved = copy
        }
        // An explicit edit becomes the new baseline: what you just wrote is
        // the recipe, not a resize of the old one.
        adopt(recipe: saved)
        brew.recipeSnapshot = saved.brewLink().snapshot
        brew.recipeName = saved.name
        // Sync the brew's top-level dose/water to the edited recipe so the
        // prefill and the timer both see the same numbers.
        brew.dose = saved.dose
        brew.water = saved.water
        brew.beverage = saved.beverage
        if let temp = saved.temperature { brew.temperature = temp }
    }

    func goToKit() { step = .kit }

    /// How much? remembers the screen that opened it, so Back returns there.
    func goToDial() {
        if step != .dial { dialReturn = step }
        step = .dial
    }

    func openRecipes(_ lane: RecipePickerList.Lane) {
        recipeLane = lane
        step = .scope
    }

    func openPrevious() { step = .previous }

    func repeatBrew(_ source: Brew, setup: SetupStore) {
        let prepared = BrewPrefill.preparedAgain(from: source, setup: setup)
        brew = prepared.brew
        lastApplication = prepared.application
        if let snapshot = source.recipeSnapshot {
            adopt(recipe: Recipe(snapshot: snapshot))
        } else {
            adopt(recipe: nil)
        }
        if brew.recipeName == nil { brew.recipeName = recipe?.name }
        goToDial()
    }

    func repeatLast(in setup: SetupStore) {
        guard let last = card.brews.first else { return }
        repeatBrew(last, setup: setup)
    }

    /// Moves back one screen. False means the journey itself should close.
    func retreat() -> Bool {
        switch step {
        case .dial:
            guard let target = dialReturn else { return false }
            dialReturn = nil
            step = target
            return true
        case .previous:
            step = .start
            return true
        case .scope:
            guard includesLauncher else { return false }
            step = .start
            return true
        case .kit:
            step = includesLauncher ? .start : .scope
            return true
        case .start, .pour, .after:
            return false
        }
    }

    func brewNow(in setup: SetupStore) {
        seedPlan(in: setup)
        step = .pour
    }

    func alreadyBrewed(in setup: SetupStore) {
        seedPlan(in: setup)
        logged = true
        brew.actualSource = .none
        brew.pourRates = []
        step = .after
    }

    func seedPlan(in setup: SetupStore) {
        let recipe = timerRecipe(in: setup)
        brew.plannedSteps = recipe.steps.enumerated().map { index, step in
            BrewStep(
                index: index,
                action: step.action,
                at: 0,
                targetAt: step.untilSeconds ?? step.at,
                targetMass: step.targetMass,
                note: step.note,
                agitation: step.agitation
            )
        }
        if brew.recipeName == nil || brew.recipeName?.isEmpty == true {
            brew.recipeName = recipe.name
        }
        brew.recipeSnapshot = recipe.brewLink().snapshot
    }

    func poured(_ brew: Brew) {
        self.brew = brew
        step = .after
    }

    /// Read is not a form, but the move you pick there is a decision. It goes
    /// onto the saved cup straight away, so reopening it still shows the move.
    func recordSuggestion(_ change: String, store: CardStore, events: AIEventLog) {
        brew.nextTimeSuggestion = change
        BrewPrefill.persist(
            brew,
            onto: card,
            replacing: true,
            store: store,
            events: events,
            dictationEventID: dictationEventID
        )
    }

    /// The wishes in For next time save as they change, onto the saved cup.
    func saveEdits(store: CardStore, events: AIEventLog) {
        BrewPrefill.persist(
            brew,
            onto: card,
            replacing: true,
            store: store,
            events: events,
            dictationEventID: dictationEventID
        )
    }

    func finish(store: CardStore, events: AIEventLog) {
        BrewPrefill.persist(
            brew,
            onto: card,
            replacing: mode == .edit,
            store: store,
            events: events,
            dictationEventID: dictationEventID
        )
    }
}
