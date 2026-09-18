import SwiftUI

/// After the pour: rating, taste, correction, comment, parameters, save.
struct AfterBrewSheet: View {
    @Bindable var session: BrewSession
    var onSave: () -> Void
    var onDelete: (() -> Void)?
    var onAgain: ((Brew) -> Void)?
    var onBack: () -> Void

    @Environment(SetupStore.self) private var setup
    @Environment(RecipeStore.self) private var recipes
    @Environment(CardStore.self) private var store
    @Environment(AIFlags.self) private var flags
    @Environment(AIEventLog.self) private var events
    @Environment(AIFeedbackStore.self) private var feedback
    @Environment(LotFlags.self) private var lotFlags
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var showParameters = false
    @State private var showTaste = true
    @State private var showCompare = false
    @State private var tapCount = 0
    @State private var correction: SuggestedCorrection?
    @State private var pickedMove: Int?
    @State private var saveTrigger = 0
    @State private var savedAsRecipe = false
    @State private var completenessTrigger = 0
    @FocusState private var timeFocused: Bool
    @FocusState private var commentFocused: Bool
    @State private var fieldFocused = false

    private var card: CoffeeCard { session.card }
    private var recipe: Recipe { session.timerRecipe }

    private var progressIndex: Int { session.progressTotal - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 26)
                .padding(.top, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    rating
                        .completenessPulse(.rating, completeness: session.brew.completeness, trigger: completenessTrigger)
                    if lotFlags.isOn(.taste7) { taste }
                    axes
                    comment
                    suggested
                    parameters
                    more
                    dateSection
                    if onDelete != nil { deleteButton }
                }
                .padding(.horizontal, 26)
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .fieldKeyboardClearance()
        }
        .background(Palette.paper.ignoresSafeArea())
        .onPreferenceChange(FieldFocusPreference.self) { fieldFocused = $0 }
        .animation(Motion.snappy, value: fieldFocused)
        .safeAreaInset(edge: .bottom) {
            if !fieldFocused {
                Button(action: save) {
                    Text("Save")
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
                .padding(.top, 12)
                .padding(.bottom, 18)
                .background(Palette.paper)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .haptic(.tap, trigger: tapCount)
        .haptic(.saved, trigger: saveTrigger)
        .task { await loadCorrection() }
        .task(id: "\(session.brew.acidity)-\(session.brew.bitterness)-\(session.brew.body)-\(session.brew.rating ?? 0)-\(session.brew.notes)") {
            await loadCorrection()
        }
        .sheet(isPresented: $showCompare) {
            if let appEnvironment {
                BrewCompareSheet(
                    card: card,
                    reference: session.brew,
                    others: store.cards,
                    waters: setup.waterProfiles,
                    equipment: setup.equipment
                ) { seed in
                    onAgain?(seed)
                }
                .appEnvironment(appEnvironment)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .touchTarget()
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                ForEach(0..<session.progressTotal, id: \.self) { index in
                    Rectangle()
                        .fill(index == progressIndex ? Palette.ink : Palette.hairline)
                        .frame(width: 24, height: 1)
                }
            }
            Spacer()
            Text(session.brew.completeness.tag)
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
                .onTapGesture { completenessTrigger += 1 }
        }
    }

    private var rating: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rating").catalogueLabel()
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { step in
                    Button {
                        tapCount += 1
                        session.brew.rating = session.brew.rating == step ? nil : step
                    } label: {
                        Circle()
                            .fill((session.brew.rating ?? 0) >= step ? Palette.ink : Color.clear)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Palette.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .touchTarget()
                }
            }
        }
    }

    private var taste: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                tapCount += 1
                withAnimation(Motion.snappy) { showTaste.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Taste").catalogueLabel()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Palette.inkMuted)
                        .rotationEffect(.degrees(showTaste ? 90 : 0))
                    Spacer()
                    if !session.brew.taste.isEmpty, !showTaste {
                        Text("\(session.brew.taste.scoredAxes.count) of 7")
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }
                }
            }
            .buttonStyle(.plain)

            if showTaste {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Spacer()
                        TasteRadar(taste: session.brew.taste, previous: previousTaste)
                        Spacer()
                    }
                    if previousTaste != nil {
                        Text("The previous brew of this coffee is the lighter shape.")
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }
                    AxisRails(taste: $session.brew.taste) { tapCount += 1 }
                    if lotFlags.isOn(.flavorWheel) {
                        FlavorPicker(
                            selection: $session.brew.flavors,
                            recent: recentFlavors,
                            suggested: card.declaredFlavors
                        )
                    }
                }
            }
        }
    }

    private var previousTaste: TasteProfile? {
        card.brews
            .first { $0.id != session.brew.id && !$0.taste.isEmpty }?
            .taste
    }

    private var recentFlavors: [FlavorTag] {
        var seen = Set<String>()
        var tags: [FlavorTag] = []
        for brew in card.brews {
            for tag in brew.flavors where seen.insert(tag.id).inserted {
                tags.append(tag)
            }
        }
        return Array(tags.prefix(8))
    }

    private var grindGrinder: Equipment? {
        session.brew.grind.grinderId.flatMap { setup.equipment(id: $0) }
            ?? setup.preferredGrinder(for: session.brew.method)
    }

    private var axes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Correction").catalogueLabel()
            axis("Acidity", value: $session.brew.acidity)
            axis("Bitterness", value: $session.brew.bitterness)
            axis("Body", value: $session.brew.body)
        }
    }

    private func axis(_ name: String, value: Binding<Int>) -> some View {
        HStack(spacing: 14) {
            Text(name)
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
                .frame(width: 74, alignment: .leading)
            ForEach([-1, 0, 1], id: \.self) { step in
                Button {
                    tapCount += 1
                    value.wrappedValue = value.wrappedValue == step ? 0 : step
                } label: {
                    Text(step < 0 ? "−" : step > 0 ? "+" : "·")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(value.wrappedValue == step ? Palette.paper : Palette.ink)
                        .frame(width: 28, height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(value.wrappedValue == step ? Palette.ink : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Palette.hairline, lineWidth: value.wrappedValue == step ? 0 : 1)
                                )
                        }
                }
                .buttonStyle(.plain)
                .touchTarget()
            }
        }
    }

    private var comment: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comment").catalogueLabel()
            TextField(Placeholders.text(.brewNotes), text: $session.brew.notes, axis: .vertical)
                .font(Typography.body)
                .lineLimit(2...6)
                .focused($commentFocused)
                .reportsFieldFocus(commentFocused)
            DictationField(text: $session.brew.notes)
        }
    }

    @ViewBuilder
    private var suggested: some View {
        if let correction {
            VStack(alignment: .leading, spacing: 12) {
                SuggestedCorrectionView(
                    correction: correction,
                    pickedRank: $pickedMove
                ) { move in
                    session.brew.nextTimeSuggestion = move.change
                }
                if flags.isOn(.aiFeedback), let eventID = correction.eventID {
                    AIFeedbackScale(eventID: eventID, feature: .suggestedCorrection, store: feedback)
                }
            }
        }
    }

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(Motion.snappy) { showParameters.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Parameters").catalogueLabel()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Palette.inkMuted)
                        .rotationEffect(.degrees(showParameters ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if showParameters {
                Text(recipe.compactLine)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                NumberRow(
                    Copy.coffeeDose,
                    value: $session.brew.dose,
                    unit: "g",
                    placeholder: Placeholders.text(.brewDose),
                    labelWidth: 74
                )
                NumberRow(
                    session.brew.method == .espresso ? Copy.beverage : Copy.waterWeight,
                    value: session.brew.method == .espresso ? $session.brew.beverage : $session.brew.water,
                    unit: "g",
                    placeholder: Placeholders.text(.brewWater),
                    labelWidth: 74
                )
                timeRow
                VStack(alignment: .leading, spacing: 4) {
                    Text("Grind").catalogueLabel()
                    GrindRail(
                        setting: $session.brew.grind,
                        grinder: grindGrinder,
                        method: session.brew.method,
                        onChange: { tapCount += 1 }
                    )
                }
                NumberRow(
                    "Temp",
                    value: $session.brew.temperature,
                    unit: "°C",
                    placeholder: Placeholders.text(.brewTemperature),
                    labelWidth: 74
                )
            }
        }
    }

    private var timeRow: some View {
        HStack(spacing: 8) {
            Text("Time").catalogueLabel()
                .frame(width: 74, alignment: .leading)
            TextField(
                "",
                text: timeBinding,
                prompt: Text(Placeholders.text(.brewTime)).foregroundStyle(Palette.hairline)
            )
            .formValue()
            .frame(width: 50)
            .keyboardType(.numbersAndPunctuation)
            .focused($timeFocused)
            .reportsFieldFocus(timeFocused)
        }
    }

    private var timeBinding: Binding<String> {
        Binding(
            get: {
                guard let s = session.brew.seconds, s > 0 else { return "" }
                return String(format: "%d:%02d", s / 60, s % 60)
            },
            set: { text in
                let parts = text.split(separator: ":")
                if parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]) {
                    session.brew.seconds = m * 60 + s
                } else {
                    session.brew.seconds = Int(text)
                }
            }
        )
    }

    @ViewBuilder
    private var more: some View {
        VStack(alignment: .leading, spacing: 16) {
            NumberRow(
                "TDS",
                value: $session.brew.tds,
                unit: "%",
                placeholder: Placeholders.text(.brewTDS),
                labelWidth: 74
            )
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Yield").catalogueLabel().frame(width: 74, alignment: .leading)
                if let ey = session.brew.extractionYield {
                    Text(String(format: "%.1f %%", ey))
                        .font(Typography.value)
                        .foregroundStyle(Palette.inkMuted)
                } else {
                    Text("—").font(Typography.value).foregroundStyle(Palette.hairline)
                }
            }
            if session.brew.dose != nil, session.brew.water != nil || session.brew.beverage != nil {
                Button(savedAsRecipe ? "Saved as a recipe" : "Save as recipe") {
                    guard !savedAsRecipe else { return }
                    tapCount += 1
                    let saved = recipes.save(brew: session.brew, from: card)
                    session.brew.recipeID = saved.id
                    savedAsRecipe = true
                }
                .font(Typography.tag)
                .foregroundStyle(savedAsRecipe ? Palette.inkMuted : Palette.ink)
                .disabled(savedAsRecipe)
            }
            if lotFlags.isOn(.brewCompare) {
                Button {
                    tapCount += 1
                    showCompare = true
                } label: {
                    Text("Compare with…").catalogueLabel()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Date").catalogueLabel()
            DatePicker("", selection: $session.brew.date, displayedComponents: .date)
                .labelsHidden()
        }
    }

    private var deleteButton: some View {
        Button {
            onDelete?()
        } label: {
            Text("Delete this brew").catalogueLabel()
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func loadCorrection() async {
        correction = await SuggestedCorrection.ranked(
            for: session.brew,
            card: card,
            comment: session.brew.notes,
            equipment: setup.equipment,
            flags: flags,
            events: events
        )
    }

    private func save() {
        saveTrigger += 1
        onSave()
    }
}
