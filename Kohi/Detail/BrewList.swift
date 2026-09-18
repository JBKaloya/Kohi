import SwiftUI

/// Compact extraction history in the card detail, matching CaptionBlock's
/// catalogue grammar: monospaced uppercase labels, hairline rules, warm paper.
///
/// Suggested (and the recipe on the bag) sit above the log so a brew you
/// made is never mistaken for a recommendation.
struct BrewList: View {
    let card: CoffeeCard
    /// What the rules propose for this coffee, when it is not simply the
    /// recipe printed on the bag.
    var suggestion: RecipeSuggestion?
    /// The suggested grind in your own grinder's units, when it can be read
    /// there at all.
    var inYourTerms: String?
    let onSelect: (Brew) -> Void
    let onAdd: () -> Void
    /// Starts a new brew seeded from the recipe printed on the card.
    var onUseRecipe: (() -> Void)?
    /// Opens the suggested recipe in full, with its reasons.
    var onOpenSuggestion: ((RecipeSuggestion) -> Void)?
    var onUseSuggestion: ((RecipeSuggestion) -> Void)?
    var onAgain: ((Brew) -> Void)?
    var onCompare: ((Brew) -> Void)?

    private var hasPrinted: Bool { card.recipeSuggestion != nil && onUseRecipe != nil }
    private var hasSuggestion: Bool { suggestion != nil }
    private var hasRecipes: Bool { hasPrinted || hasSuggestion }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if hasRecipes {
                recipesBlock
            }
            brewsBlock
        }
    }

    private var recipesBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasPrinted, let recipe = card.recipeSuggestion, let onUseRecipe {
                Button(action: onUseRecipe) {
                    recipeRow(recipe)
                }
                .buttonStyle(.plain)

                if hasSuggestion {
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)
                }
            }

            if let suggestion {
                suggestedRow(suggestion)
                    .id("suggested-recipe")
            }
        }
    }

    private var brewsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !card.brews.isEmpty {
                header
                    .padding(.bottom, 10)

                VStack(spacing: 0) {
                    ForEach(Array(card.brews.enumerated()), id: \.element.id) { index, brew in
                        if index > 0 {
                            Rectangle()
                                .fill(Palette.hairline)
                                .frame(height: 1)
                        }
                        Button { onSelect(brew) } label: {
                            brewRow(brew)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if onAgain != nil {
                                Button(Copy.brewAgain) { onAgain?(brew) }
                            }
                            if onCompare != nil {
                                Button(Copy.compare) { onCompare?(brew) }
                            }
                        }
                    }
                }
            }

            addButton
                .padding(.top, card.brews.isEmpty ? 0 : 14)
        }
    }

    /// The recipe the roaster printed: tap to brew it.
    private func recipeRow(_ recipe: Brew) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Card")
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
                .frame(width: 52, alignment: .leading)

            Text(recipe.recipeLine)
                .font(Typography.tag)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text("Use")
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
        }
        .padding(.vertical, 10)
    }

    /// The suggested recipe. Provenance and Use sit on their own line so
    /// "From the pros" never collides with the compact figures or wraps into Use.
    private func suggestedRow(_ suggestion: RecipeSuggestion) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { onOpenSuggestion?(suggestion) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suggested")
                        .catalogueLabel()
                    Text(suggestion.recipe.compactLine)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 8) {
                        Text(suggestion.provenance.listLabel)
                            .catalogueLabel()
                            .lineLimit(1)
                        if let secondLine {
                            Text(secondLine)
                                .font(Typography.tag)
                                .foregroundStyle(Palette.inkMuted)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button { onUseSuggestion?(suggestion) } label: {
                Text("Use")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.ink)
                    .touchTarget()
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }

    /// What the rules moved, and the grind in your units. Both are the
    /// reason to trust the row, so they share its second line.
    private var secondLine: String? {
        var parts = suggestion?.adjustments.map(\.label) ?? []
        if let inYourTerms { parts.append(inYourTerms) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Brews")
                .catalogueLabel()
            Spacer()
            Text("\(card.brews.count)")
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
        }
    }

    private func brewRow(_ brew: Brew) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(CatalogueDate.happened(brew.date))
                    .font(Typography.tag)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let rating = brew.rating {
                    ratingDots(rating)
                }
            }

            if !brewSubtitle(brew).isEmpty {
                Text(brewSubtitle(brew))
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .lineLimit(1)
            }

            if let next = brew.nextTimeSuggestion {
                Text("\(Copy.suggestedCorrection) · \(next)")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 10)
    }

    private func brewSubtitle(_ brew: Brew) -> String {
        var parts: [String] = []
        if let name = brew.recipeSnapshot?.name, !name.isEmpty {
            parts.append(name)
        } else if let method = brew.method {
            parts.append(method.label)
        }
        if let dose = brew.dose { parts.append("\(GrindRange.number(dose)) g") }
        if let ratio = brew.ratio { parts.append(ratio) }
        if let temperature = brew.temperature {
            parts.append("\(GrindRange.number(temperature)) °C")
        }
        return parts.joined(separator: " · ")
    }

    private func ratingDots(_ rating: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { step in
                Circle()
                    .fill(step <= rating ? Palette.ink : Palette.hairline)
                    .frame(width: 5, height: 5)
            }
        }
    }

    private var addButton: some View {
        Button(action: onAdd) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text("Log a brew")
                    .font(Typography.tag)
            }
            .foregroundStyle(Palette.ink)
        }
        .buttonStyle(.plain)
    }
}
