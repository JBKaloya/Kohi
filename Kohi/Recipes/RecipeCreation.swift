import Foundation

/// The one way a recipe is created from nothing, from the brew journey or
/// from Recipes. It lands in Mine.
nonisolated enum RecipeCreation {
    static let blankDose: Double = 15
    static let blankRatio: Double = 15

    /// A draft started from today's numbers on the brew journey.
    static func draft(from brew: Brew, family: BrewerFamily, card: CoffeeCard?, roastLevel: RoastLevel?) -> Recipe {
        let recipe = Recipe(
            name: Recipe.expressTitle(family: family, card: card),
            method: brew.method ?? .v60,
            dose: brew.dose,
            water: brew.water,
            beverage: brew.beverage,
            temperature: brew.temperature,
            seconds: brew.seconds,
            grindLabel: brew.grind.display(),
            source: .mine,
            evidence: .unverified,
            cardID: card?.id
        )
        return DefaultSequence.filling(recipe, roastLevel: roastLevel)
    }

    /// A draft with nothing behind it, from Recipes.
    static func blank(method: BrewMethod = .v60) -> Recipe {
        let recipe = Recipe(
            method: method,
            dose: blankDose,
            water: method == .espresso ? nil : blankDose * blankRatio,
            beverage: method == .espresso ? 36 : nil,
            source: .mine,
            evidence: .unverified
        )
        return DefaultSequence.filling(recipe)
    }

    /// Save as recipe after a Live brew: what was heard, as written.
    static func fromLive(brew: Brew, family: BrewerFamily, card: CoffeeCard?, countsBloom: Bool = true) -> Recipe {
        let steps = LiveSteps.recipeSteps(brew.actualSteps)
        let last = steps.last { PourSplit.carriesWater($0.action) && $0.targetMass != nil }?.targetMass
        return Recipe(
            name: Recipe.expressTitle(family: family, card: card),
            method: brew.method ?? .v60,
            dose: brew.dose,
            water: brew.method == .espresso ? nil : (brew.water ?? last),
            beverage: brew.method == .espresso ? (brew.beverage ?? last) : nil,
            temperature: brew.temperature,
            seconds: brew.seconds,
            grindLabel: brew.grind.display(),
            steps: steps,
            source: .mine,
            evidence: .unverified,
            cardID: card?.id,
            brewID: brew.id,
            splitCountsBloom: countsBloom ? nil : false
        )
    }

    /// Mine and express recipes are edited in place by Adjust.
    static func isYours(_ recipe: Recipe) -> Bool {
        recipe.source == .mine || recipe.source == .express
    }

    /// Adjust on someone else's recipe: a copy in Mine with its own id. The
    /// reference id and the attribution are dropped so the pickers never
    /// take the copy for the original; the credit moves into the notes.
    static func adjusting(_ recipe: Recipe) -> Recipe {
        Recipe(
            name: recipe.name,
            method: recipe.method,
            dose: recipe.dose,
            water: recipe.water,
            beverage: recipe.beverage,
            temperature: recipe.temperature,
            temperatureMax: recipe.temperatureMax,
            seconds: recipe.seconds,
            grindLabel: recipe.grindLabel,
            grindMicronsLow: recipe.grindMicronsLow,
            grindMicronsHigh: recipe.grindMicronsHigh,
            steps: recipe.steps.filter { $0.action != .rinse }.map { step in
                var copy = step
                copy.id = UUID()
                return copy
            },
            source: .mine,
            evidence: .unverified,
            sourceURL: recipe.sourceURL,
            notes: [adjustedNote(from: recipe), recipe.notes]
                .filter { !$0.isEmpty }
                .joined(separator: "\n"),
            cardID: recipe.cardID,
            profileTags: recipe.profileTags,
            authorGrinder: recipe.authorGrinder,
            rinseMassOverride: recipe.rinseMassOverride,
            splitCountsBloom: recipe.splitCountsBloom
        )
    }

    static func adjustedNote(from recipe: Recipe) -> String {
        let credit = recipe.attribution.trimmingCharacters(in: .whitespaces)
        return credit.isEmpty
            ? "Adjusted from \(recipe.name)"
            : "Adjusted from \(recipe.name) · \(credit)"
    }

    /// The method changed on a draft: steps nobody touched follow it.
    static func switching(_ draft: Recipe, to method: BrewMethod) -> Recipe {
        var next = draft
        next.method = method
        if method == .espresso, next.beverage == nil {
            next.beverage = (next.dose ?? blankDose) * 2
        }
        if method != .espresso, next.water == nil {
            next.water = (next.dose ?? blankDose) * blankRatio
        }
        guard draft.steps.allSatisfy(\.derived) else { return next }
        next.steps = []
        return DefaultSequence.filling(next)
    }
}
