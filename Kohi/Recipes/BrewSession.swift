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
    var size: RecipeSize
    var brew: Brew
    var step: Step
    var mode: Mode
    /// Skip the timer and go to After — logging a cup that already happened.
    var logged = false
    var dictationEventID: UUID?

    enum Step: Hashable {
        case scope
        case kit
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
        size: RecipeSize? = nil,
        existing: Brew? = nil,
        mode: Mode = .create,
        start: Step = .scope,
        setup: SetupStore
    ) {
        self.card = card
        self.recipe = recipe
        let brew = BrewPrefill.seed(
            card: card,
            recipe: recipe,
            size: size,
            existing: existing,
            setup: setup
        )
        self.brew = brew
        self.size = size ?? RecipeSize.inferred(from: brew.water)
        self.mode = mode
        self.step = start
        if mode == .edit { logged = true }
    }

    /// Scope / Kit / After share this so Already brewed does not keep a
    /// four-tick bar after the timer has been skipped.
    var progressTotal: Int { mode == .edit || logged ? 3 : 4 }

    var timerRecipe: Recipe {
        if let snapshot = brew.recipeSnapshot {
            return Recipe(snapshot: snapshot)
        }
        if let recipe {
            return RecipeScaling.scaled(recipe, to: size).recipe
        }
        return BrewPrefill.timerRecipe(from: brew, named: card.name.isEmpty ? "Brew" : card.name)
    }

    func apply(recipe: Recipe, setup: SetupStore) {
        self.recipe = recipe
        brew = BrewPrefill.seed(
            card: card,
            recipe: recipe,
            size: size,
            setup: setup
        )
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
            recipe = nil
        }
        BrewPrefill.applyDefaults(to: &brew, method: method, setup: setup)
        BrewPrefill.fill(&brew, card: card, recipe: recipe, setup: setup)
    }

    func goToKit() { step = .kit }

    func brewNow() { step = .pour }

    func alreadyBrewed() {
        logged = true
        step = .after
    }

    func poured(_ brew: Brew) {
        self.brew = brew
        step = .after
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
