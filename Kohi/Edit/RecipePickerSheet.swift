import SwiftUI

/// The Recipe row's list: what the card printed, what the rules suggest, the
/// reference recipes, your last brew, and your own saved ones.
///
/// Grouped by provenance rather than merged into one ranked list, because
/// picking a recipe is a choice about whose judgement to follow. Lives without
/// a NavigationStack so the brew flow can embed it.
struct RecipePickerList: View {
    let card: CoffeeCard
    let method: BrewMethod?
    /// When set, rows show the recipe at this cup size and keep a "scaled from"
    /// line rather than hiding a 15 g recipe from a 30 g brew.
    var size: RecipeSize? = nil
    var selected: Recipe? = nil
    let onPick: (Recipe) -> Void

    @Environment(CardStore.self) private var store
    @Environment(RecipeStore.self) private var recipes

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if let printed { section("Card", recipes: [printed]) }
            if let suggested {
                section(
                    "Suggested",
                    recipes: [suggested.recipe]
                )
            }
            if let last { section("Last brew", recipes: [last]) }
            if !recipes.recipes.isEmpty {
                section("Mine", recipes: filtered(recipes.recipes))
            }
            section(Copy.fromThePros, recipes: dedupedReferences)
        }
    }

    // MARK: - Sources

    private var printed: Recipe? {
        guard let recipe = card.recipeSuggestion, recipe.dose != nil else { return nil }
        return RecipeRules.recipe(from: recipe, card: card)
    }

    private var suggested: RecipeSuggestion? {
        let result = RecipeRules.suggestion(
            for: card,
            method: method,
            mine: recipes.recipes,
            neighbours: store.cards
        )
        guard let result, result.provenance != .card else { return nil }
        return result
    }

    private var last: Recipe? {
        guard let brew = card.brews.first, brew.dose != nil else { return nil }
        var recipe = RecipeRules.recipe(from: brew, card: card, source: .mine)
        recipe.name = "Last brew · \(CatalogueDate.happened(brew.date))"
        return recipe
    }

    /// Filtered to the chosen method when there is one, because a French press
    /// recipe is not a candidate for the espresso you are about to pull.
    private func filtered(_ pool: [Recipe]) -> [Recipe] {
        guard let method else { return pool }
        return pool.filter { $0.method == method }
    }

    /// A recipe already offered as Suggested is not listed again under From
    /// the pros. Capture 3 showed Ultimate twice.
    private var dedupedReferences: [Recipe] {
        RecipePickerMatch.withoutDuplicate(
            filtered(ReferenceBase.recipes),
            of: suggested?.recipe
        )
    }

    @ViewBuilder
    private func section(_ title: String, recipes list: [Recipe]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).catalogueLabel()
                Rectangle().fill(Palette.hairline).frame(height: 1)

                VStack(spacing: 0) {
                    ForEach(list) { recipe in
                        let shown = displayed(recipe)
                        RecipeRowView(
                            recipe: shown.recipe,
                            provenance: recipe.source.label,
                            attribution: recipe.attribution,
                            scaledFrom: shown.scaledFrom,
                            isSelected: isSelected(recipe),
                            action: { onPick(recipe) }
                        )
                    }
                }
            }
        }
    }

    private func displayed(_ recipe: Recipe) -> (recipe: Recipe, scaledFrom: String) {
        guard let size else { return (recipe, "") }
        let scaled = RecipeScaling.scaled(recipe, to: size)
        return (scaled.recipe, scaled.scaledFromLabel ?? "")
    }

    private func isSelected(_ recipe: Recipe) -> Bool {
        guard let selected else { return false }
        return RecipePickerMatch.isSame(recipe, selected)
    }
}

/// The Recipe row's list as a sheet, for the brew form.
struct RecipePickerSheet: View {
    let card: CoffeeCard
    let method: BrewMethod?
    var size: RecipeSize? = nil
    var selected: Recipe? = nil
    let onPick: (Recipe) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                RecipePickerList(card: card, method: method, size: size, selected: selected) { recipe in
                    onPick(recipe)
                    dismiss()
                }
                .padding(.horizontal, 26)
                .padding(.top, 16)
                .padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(Palette.ink)
    }
}

/// Identity for the picker: a suggested Hoffman recipe is the same row as
/// the From the pros copy, even when the rules adjusted the temperature.
nonisolated enum RecipePickerMatch {
    static func isSame(_ a: Recipe, _ b: Recipe) -> Bool {
        if a.id == b.id { return true }
        if let left = a.referenceID, let right = b.referenceID { return left == right }
        return a.name == b.name && a.method == b.method && a.attribution == b.attribution
    }

    static func withoutDuplicate(_ pool: [Recipe], of suggested: Recipe?) -> [Recipe] {
        guard let suggested else { return pool }
        return pool.filter { !isSame($0, suggested) }
    }
}
