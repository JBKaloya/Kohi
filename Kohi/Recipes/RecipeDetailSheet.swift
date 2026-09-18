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
    @State private var flow: BrewSession?
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
                .padding(.bottom, canBrew ? 80 : 24)
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                ZStack {
                    Text(recipe.name)
                        .font(Typography.value)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 96)
                    HStack {
                        CatalogueBackButton(title: Copy.recipes) { dismiss() }
                        Spacer()
                    }
                }
                .padding(.horizontal, 12)
                .background(Palette.paper)
            }
            .safeAreaInset(edge: .bottom) {
                if canBrew {
                    Button {
                        startBrew()
                    } label: {
                        Text("Brew")
                            .font(Typography.label)
                            .tracking(Typography.labelTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.paper)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Palette.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 18)
                }
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
        .fullScreenCover(item: $flow) { session in
            BrewFlowHost(
                session: session,
                onDismiss: { flow = nil },
                onAgain: { seed in
                    flow = BrewSession(
                        card: session.card,
                        existing: seed.again(),
                        start: .kit,
                        setup: setup
                    )
                }
            )
            .appEnvironment(appEnvironment)
        }
    }

    private var canBrew: Bool { picked != nil }

    private func startBrew(with recipe: Recipe? = nil) {
        guard let picked else { return }
        let using = recipe ?? shown
        flow = BrewSession(
            card: picked,
            recipe: using,
            size: scaled?.isScaled == true ? scaled?.size : nil,
            setup: setup
        )
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
                    TagChip(
                        text: store.title(for: coffee),
                        isSelected: picked?.id == coffee.id
                    ) {
                        picked = coffee
                    }
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
                HStack(spacing: 18) {
                    Button("Use the variant") {
                        events.setAccepted(true, for: variant.eventID)
                        if let onUse {
                            onUse(variant.recipe, nil)
                            dismiss()
                        } else {
                            startBrew(with: variant.recipe)
                        }
                    }
                    Button("Dismiss") {
                        events.setAccepted(false, for: variant.eventID)
                        withAnimation(Motion.quick) { self.variant = nil }
                    }
                    .foregroundStyle(Palette.inkMuted)
                }
                .font(Typography.tag)
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
                        let on = picked?.id == coffee.id
                        Button {
                            picked = coffee
                            dismiss()
                        } label: {
                            HStack {
                                Text(store.title(for: coffee))
                                    .font(Typography.value)
                                    .foregroundStyle(CatalogueChoice.ink(on))
                                Spacer()
                            }
                            .padding(.vertical, 14)
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        Rectangle().fill(CatalogueChoice.rule(on)).frame(height: 1)
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
