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
    var onSetGrindRange: (() -> Void)?
    var onAgain: ((Brew) -> Void)?
    var onCompare: ((Brew) -> Void)?
    var onDelete: ((Brew) -> Void)?
    var onRead: ((Brew) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            BrewRecipes(
                card: card,
                suggestion: suggestion,
                inYourTerms: inYourTerms,
                onUseRecipe: onUseRecipe,
                onOpenSuggestion: onOpenSuggestion,
                onUseSuggestion: onUseSuggestion,
                onSetGrindRange: onSetGrindRange
            )
            BrewLog(
                brews: card.brews,
                showsHeader: true,
                showsAdd: true,
                onSelect: onSelect,
                onAdd: onAdd,
                onAgain: onAgain,
                onCompare: onCompare,
                onDelete: onDelete,
                onRead: onRead
            )
        }
    }
}

/// The recipe printed on the bag, and the one the rules suggest. Empty when
/// neither exists, so it adds no gap of its own.
struct BrewRecipes: View {
    let card: CoffeeCard
    var suggestion: RecipeSuggestion?
    var inYourTerms: String?
    var onUseRecipe: (() -> Void)?
    var onOpenSuggestion: ((RecipeSuggestion) -> Void)?
    var onUseSuggestion: ((RecipeSuggestion) -> Void)?
    var onSetGrindRange: (() -> Void)?

    private var hasPrinted: Bool { card.recipeSuggestion != nil && onUseRecipe != nil }
    private var hasSuggestion: Bool { suggestion != nil }

    var body: some View {
        if hasPrinted || hasSuggestion {
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
                    Text(suggestedHeadline(suggestion))
                        .font(Typography.tag)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    if inYourTerms == Copy.noClickRange, onSetGrindRange != nil {
                        Button(Copy.forYourGrinderSetRange) {
                            onSetGrindRange?()
                        }
                        .catalogueLabel()
                    } else if let secondLine {
                        Text(secondLine)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                            .lineLimit(1)
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

    private func suggestedHeadline(_ suggestion: RecipeSuggestion) -> String {
        var parts: [String] = []
        let name = suggestion.recipe.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { parts.append(name) }
        if let dose = suggestion.recipe.dose { parts.append("\(GrindRange.number(dose)) g") }
        if let ratio = suggestion.recipe.ratio { parts.append(ratio) }
        if let temperatureLabel = suggestion.recipe.temperatureLabel {
            parts.append(temperatureLabel)
        }
        return parts.isEmpty ? suggestion.recipe.compactLine : parts.joined(separator: " · ")
    }

    /// What the rules moved, and the grind in your units. Both are the
    /// reason to trust the row, so they share its second line.
    private var secondLine: String? {
        var parts = suggestion?.adjustments.map(\.label) ?? []
        if let inYourTerms, inYourTerms != Copy.noClickRange { parts.append(inYourTerms) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Logged brews. The Tastings section hides the "Brews" header and the add
/// button; `BrewList` keeps both, so the existing log reads the same.
struct BrewLog: View {
    let brews: [Brew]
    var showsHeader = false
    var showsAdd = false
    /// Set on the cross-coffee list. The card's own log leaves it empty.
    var coffeeName: (Brew) -> String? = { _ in nil }
    let onSelect: (Brew) -> Void
    var onAdd: () -> Void = {}
    var onAgain: ((Brew) -> Void)?
    var onCompare: ((Brew) -> Void)?
    var onDelete: ((Brew) -> Void)?
    var onRead: ((Brew) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader, !brews.isEmpty {
                header
                    .padding(.bottom, 10)
            }

            if !brews.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(brews.enumerated()), id: \.element.id) { index, brew in
                        let name = coffeeName(brew)
                        let previous = index > 0 ? coffeeName(brews[index - 1]) : nil
                        let startsCoffee = name != nil && name != previous
                        if index > 0, name == nil || name == previous {
                            Rectangle()
                                .fill(Palette.hairline)
                                .frame(height: 1)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            SwipeDeleteRow(onDelete: { onDelete?(brew) }) {
                                Button { onSelect(brew) } label: {
                                    brewRow(brew, name: startsCoffee ? name : nil)
                                }
                                .buttonStyle(.plain)
                            }
                            HStack(spacing: 16) {
                                if onAgain != nil {
                                    Button(Copy.brewAgain) { onAgain?(brew) }
                                        .catalogueLabel()
                                }
                                if onRead != nil {
                                    Button("\(Copy.improveTitle) ›") { onRead?(brew) }
                                        .catalogueLabel()
                                }
                            }
                            .padding(.bottom, 8)
                        }
                        .padding(.top, startsCoffee && index > 0 ? 18 : 0)
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

            if showsAdd {
                addButton
                    .padding(.top, brews.isEmpty ? 0 : 14)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Brews")
                .catalogueLabel()
            Spacer()
            Text("\(brews.count)")
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
        }
    }

    private func brewRow(_ brew: Brew, name: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let name {
                Text(name)
                    .font(Typography.value)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(CatalogueDate.happened(brew.date))
                    .font(Typography.tag)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let halves = brew.ratingHalves {
                    RatingDots(halves: halves)
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
        parts.append(brew.title)
        if let dose = brew.dose { parts.append("\(GrindRange.number(dose)) g") }
        if let ratio = brew.ratio { parts.append(ratio) }
        if let temperature = brew.temperature {
            parts.append("\(GrindRange.number(temperature)) °C")
        }
        return parts.joined(separator: " · ")
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

/// Five dots, filled up to the score, the last one by half when it is a half
/// point. Shared by a brew row and a tasting row.
struct RatingDots: View {
    let halves: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { dot in
                let fill = HalfRating.dot(dot, of: halves)
                ZStack {
                    Circle().fill(fill == .full ? Palette.ink : Palette.hairline)
                    if fill == .half {
                        Circle()
                            .fill(Palette.ink)
                            .mask(alignment: .leading) { Rectangle().frame(width: 2.5) }
                    }
                }
                .frame(width: 5, height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.rating)
        .accessibilityValue(HalfRating.spoken(halves))
    }
}

/// Horizontal swipe reveals Delete. A vertical drag stays with the page scroll.
struct SwipeDeleteRow<Content: View>: View {
    var onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < -8 {
                Button(role: .destructive, action: onDelete) {
                    Text("Delete").catalogueLabel()
                }
                .frame(width: 88)
            }
            content()
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            guard abs(dx) > abs(dy) else { return }
                            offset = min(0, max(-96, dx))
                        }
                        .onEnded { value in
                            withAnimation(Motion.snappy) {
                                offset = value.translation.width < -48 ? -96 : 0
                            }
                        }
                )
        }
        .clipped()
    }
}
