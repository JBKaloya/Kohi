import SwiftUI

/// A recipe as a page: parameters, steps, then brew this coffee.
struct RecipeDetailSheet: View {
    let recipe: Recipe
    var scaled: ScaledRecipe? = nil
    var adjustments: [RecipeAdjustment] = []
    var provenance: RecipeProvenance?
    var inYourTerms: String?
    var forYourGrinder: ForYourGrinder?
    var card: CoffeeCard?
    var onUse: ((Recipe, RecipeSize?) -> Void)?
    var onDelete: (() -> Void)?

    @Environment(CardStore.self) private var store
    @Environment(SetupStore.self) private var setup
    @Environment(AIFlags.self) private var flags
    @Environment(AIEventLog.self) private var events
    @Environment(AIFeedbackStore.self) private var feedback
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var isConfirmingDelete = false
    @State private var variant: RecipeAdapt.Variant?
    @State private var isAskingForVariant = false
    @State private var picked: CoffeeCard?
    @State private var isPickingCoffee = false
    @State private var session: GuidedSession?
    @State private var after: GuidedSession?
    @State private var showProfile = false

    private var shown: Recipe { scaled?.recipe ?? recipe }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    parameters
                    if let scaled, scaled.isScaled { inYourCup(scaled) }
                    if !adjustments.isEmpty { adjustmentsSection }
                    if !shown.steps.isEmpty { stepsSection }
                    if !recipe.notes.isEmpty { notesSection }
                    attributionSection
                    variantSection
                    brewThis

                    if let onDelete {
                        Button("Delete this recipe") { isConfirmingDelete = true }
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                            .confirmationDialog(
                                "Delete \(recipe.name)?",
                                isPresented: $isConfirmingDelete,
                                titleVisibility: .visible
                            ) {
                                Button("Delete", role: .destructive) {
                                    onDelete()
                                    dismiss()
                                }
                            }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 16)
                .padding(.bottom, 80)
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(recipe.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CatalogueBackButton(title: "RECIPES") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: startBrew) {
                    Text("Brew")
                        .font(Typography.label)
                        .tracking(Typography.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.paper)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(canBrew ? Palette.ink : Palette.hairline, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canBrew)
                .padding(.horizontal, 26)
                .padding(.bottom, 18)
            }
        }
        .tint(Palette.ink)
        .task {
            if picked == nil { picked = card }
            await loadVariant()
        }
        .sheet(isPresented: $isPickingCoffee) {
            RecipeCoffeePicker(picked: $picked)
                .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $showProfile) {
            ProfileSheet()
                .appEnvironment(appEnvironment)
        }
        .fullScreenCover(item: $session) { session in
            GuidedBrewView(
                card: session.card,
                recipe: shown,
                brew: session.brew,
                onFinish: { brew in
                    self.session = nil
                    after = GuidedSession(card: session.card, recipe: shown, brew: brew)
                },
                onCancel: { self.session = nil }
            )
            .appEnvironment(appEnvironment)
        }
        .sheet(item: $after) { session in
            AfterBrewSheet(card: session.card, recipe: shown, draft: session.brew) { brew in
                var updated = session.card
                updated.brews.insert(brew, at: 0)
                store.update(updated)
                dismiss()
            }
            .appEnvironment(appEnvironment)
        }
    }

    private var canBrew: Bool { picked != nil }

    private func startBrew() {
        guard let picked else { return }
        var brew = shown.seededBrew(size: scaled?.isScaled == true ? scaled?.size : nil)
        brew.equipmentIDs = setup.defaults(for: shown.method).map(\.id)
        session = GuidedSession(card: picked, recipe: shown, brew: brew)
    }

    // MARK: - Brew this

    private var recentCoffees: [CoffeeCard] {
        Array(store.cards.sorted { $0.createdAt > $1.createdAt }.prefix(5))
    }

    private var brewThis: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Brew this").catalogueLabel()
            FlowLayout {
                ForEach(recentCoffees) { coffee in
                    Button {
                        picked = coffee
                    } label: {
                        HStack(spacing: 6) {
                            if picked?.id == coffee.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            Text(store.title(for: coffee))
                                .font(Typography.tag)
                        }
                        .foregroundStyle(picked?.id == coffee.id ? Palette.paper : Palette.ink)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background {
                            Capsule()
                                .fill(picked?.id == coffee.id ? Palette.ink : Color.clear)
                                .overlay(Capsule().stroke(Palette.hairline, lineWidth: picked?.id == coffee.id ? 0 : 1))
                        }
                    }
                    .buttonStyle(.plain)
                    .touchTarget()
                }
            }
            Button("Another coffee…") { isPickingCoffee = true }
                .catalogueLabel()
        }
    }

    // MARK: - Variant

    @ViewBuilder
    private var variantSection: some View {
        if isAskingForVariant {
            ShimmerBar().frame(height: 1)
        } else if let variant {
            VStack(alignment: .leading, spacing: 12) {
                InsightBlock(
                    title: "Variant",
                    bodyText: variant.recipe.parameterLine,
                    provenance: "SUGGESTED BY A MODEL",
                    isModel: true
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(variant.changed.capitalizedFirst)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.ink)
                        if !variant.why.isEmpty {
                            Text(variant.why)
                                .font(Typography.tag)
                                .foregroundStyle(Palette.inkMuted)
                        }
                    }
                }
                if flags.isOn(.aiFeedback) {
                    AIFeedbackScale(eventID: variant.eventID, feature: .recipeAdapt, store: feedback)
                }
                if let onUse {
                    HStack(spacing: 18) {
                        Button("Use the variant") {
                            events.setAccepted(true, for: variant.eventID)
                            onUse(variant.recipe, nil)
                            dismiss()
                        }
                        Button("Dismiss") {
                            events.setAccepted(false, for: variant.eventID)
                            withAnimation(Motion.quick) { self.variant = nil }
                        }
                        .foregroundStyle(Palette.inkMuted)
                    }
                    .font(Typography.tag)
                }
            }
            .transition(.opacity)
        }
    }

    private func loadVariant() async {
        guard let card, flags.isOn(.recipeAdapt), variant == nil else { return }
        isAskingForVariant = true
        let found = await RecipeAdapt.variant(of: recipe, for: card, flags: flags, events: events)
        withAnimation(Motion.snappy) {
            variant = found
            isAskingForVariant = false
        }
    }

    // MARK: - Sections

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let provenance {
                Text(provenance.label)
                    .catalogueLabel()
            }
            Text("Parameters").catalogueLabel()

            CatalogueRows(items: parameterRows) { row in
                CatalogueRow(row.label, value: row.value)
            }

            if let forYourGrinder {
                Button {
                    if forYourGrinder.opensKit { showProfile = true }
                } label: {
                    CatalogueRow(Copy.forYourGrinder, value: forYourGrinder.line)
                }
                .buttonStyle(.plain)
            } else if let inYourTerms {
                CatalogueRow(Copy.forYourGrinder, value: inYourTerms)
            }
        }
    }

    private struct ParameterRow: Identifiable {
        var id: String { label }
        let label: String
        let value: String
    }

    private var parameterRows: [ParameterRow] {
        var rows = [ParameterRow(label: "Method", value: shown.method.label)]
        if let dose = shown.dose {
            rows.append(ParameterRow(label: Copy.coffeeDose, value: "\(GrindRange.number(dose)) g"))
        }
        if let water = shown.water {
            rows.append(ParameterRow(label: Copy.waterWeight, value: "\(GrindRange.number(water)) g"))
        }
        if let beverage = shown.beverage {
            rows.append(ParameterRow(label: Copy.beverage, value: "\(GrindRange.number(beverage)) g"))
        }
        if let ratio = shown.ratio {
            rows.append(ParameterRow(label: "Ratio", value: ratio))
        }
        if let temperature = shown.temperatureLabel {
            rows.append(ParameterRow(label: "Water temp", value: temperature))
        }
        if let time = shown.timeLabel {
            rows.append(ParameterRow(label: Copy.totalBrewTime, value: time))
        }
        if !grindValue.isEmpty {
            rows.append(ParameterRow(label: "Grind", value: grindValue))
        }
        return rows
    }

    private var grindValue: String {
        var parts: [String] = []
        if !shown.grindLabel.isEmpty { parts.append(shown.grindLabel) }
        if parts.isEmpty, let low = shown.grindMicronsLow, let high = shown.grindMicronsHigh {
            parts.append("≈ \(GrindRange.number(low))–\(GrindRange.number(high)) µm")
        }
        return parts.joined(separator: " · ")
    }

    private var adjustmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Adjusted for this coffee")
                .catalogueLabel()
            VStack(spacing: 9) {
                ForEach(adjustments) { adjustment in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(adjustment.label)
                            .font(Typography.value)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(adjustment.reason)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Steps")
                .catalogueLabel()

            VStack(spacing: 0) {
                ForEach(Array(shown.steps.enumerated()), id: \.element.id) { index, step in
                    if index > 0 {
                        Rectangle().fill(Palette.hairline).frame(height: 1)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(step.timeLabel)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                            .frame(width: 44, alignment: .leading)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.instruction)
                                .font(Typography.value)
                                .foregroundStyle(Palette.ink)
                            if !step.note.isEmpty {
                                Text(step.note)
                                    .font(Typography.tag)
                                    .foregroundStyle(Palette.inkMuted)
                            }
                        }

                        Spacer(minLength: 4)

                        if let until = step.untilSeconds, until > step.at {
                            Text("by \(String(format: "%d:%02d", until / 60, until % 60))")
                                .font(Typography.tag)
                                .foregroundStyle(Palette.inkMuted)
                        }
                    }
                    .padding(.vertical, 10)
                }
            }

            if let time = shown.timeLabel {
                Text("\(Copy.totalBrewTime) · \(time)")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.top, 4)
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .catalogueLabel()
            Text(recipe.notes)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var attributionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Source")
                .catalogueLabel()

            if !recipe.attribution.isEmpty {
                Text(recipe.attribution)
                    .font(Typography.value)
                    .foregroundStyle(Palette.ink)
            }

            if let url = recipe.sourceURL, let link = URL(string: url) {
                Link(destination: link) {
                    Text(url)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                        .underline()
                        .lineLimit(1)
                }
            }
        }
    }

    private func inYourCup(_ scaled: ScaledRecipe) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In your cup").catalogueLabel()
            Text(scaled.recipe.compactLine)
                .font(Typography.value)
                .foregroundStyle(Palette.ink)
            if let label = scaled.scaledFromLabel {
                Text(label)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
        }
    }
}

/// Coffee picker for "Another coffee…"
struct RecipeCoffeePicker: View {
    @Binding var picked: CoffeeCard?
    @Environment(CardStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.cards.sorted { $0.createdAt > $1.createdAt }) { coffee in
                        Button {
                            picked = coffee
                            dismiss()
                        } label: {
                            HStack {
                                Text(store.title(for: coffee))
                                    .font(Typography.value)
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                if picked?.id == coffee.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Palette.ink)
                                }
                            }
                            .padding(.vertical, 14)
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(Palette.hairline).frame(height: 1)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 16)
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Coffee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .tint(Palette.ink)
    }
}
