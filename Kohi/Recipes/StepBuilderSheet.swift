import SwiftUI

/// Name a sequence, edit its blocks — doses, times, masses — and pick a
/// template. Dose and water are fully independent: tapping a number never
/// rewrites the other one. Rescaling the steps to new totals is an explicit
/// action, not an automatic side-effect.
struct StepBuilderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SetupStore.self) private var setup

    @State private var draft: Recipe
    var onSave: (Recipe) -> Void

    @State private var tapCount = 0

    init(draft: Recipe, onSave: @escaping (Recipe) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    headerGroup
                    totalsGroup
                    stepsGroup
                }
                .padding(.horizontal, 26)
                .padding(.top, 16)
                .padding(.bottom, 44)
                .fieldKeyboardClearance()
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Steps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.medium)
                }
            }
        }
        .tint(Palette.ink)
        .haptic(.tap, trigger: tapCount)
    }

    // MARK: - Header

    private var headerGroup: some View {
        FieldGroup(title: "Recipe") {
            TextRow(
                label: "Name",
                text: $draft.name,
                placeholder: "Name this recipe",
                presence: .useful
            )
            DictationField(text: $draft.name)
        }
    }

    // MARK: - Totals

    private var totalsGroup: some View {
        FieldGroup(title: "Totals") {
            NumberRow("Dose", value: $draft.dose, unit: "g", labelWidth: 74)
            if draft.method == .espresso {
                NumberRow("Out", value: $draft.beverage, unit: "g", labelWidth: 74)
            } else {
                NumberRow("Water", value: $draft.water, unit: "g", labelWidth: 74)
            }
            if let ratio = draft.ratioValue {
                HStack {
                    Text("Ratio").catalogueLabel().frame(width: 74, alignment: .leading)
                    Text("1:\(GrindRange.number(ratio))")
                        .font(Typography.value)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            if stepsNeedRescale {
                Button("Rescale steps to these totals") {
                    tapCount += 1
                    rescaleSteps()
                }
                .catalogueLabel()
            }
        }
    }

    // MARK: - Steps list

    private var stepsGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Steps").catalogueLabel()
                .padding(.bottom, 14)

            if draft.steps.isEmpty {
                Text("No steps yet — add a pour or a step below.")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.bottom, 14)
            } else {
                // Steps with a timeline running between them.
                ForEach(Array(draft.steps.enumerated()), id: \.element.id) { index, step in
                    stepRow(step: step, index: index)
                }
            }

            addStepButtons

            // Footer: running total and target warning.
            stepFooter
                .padding(.top, 12)
        }
    }

    // MARK: - Step row

    private func stepRow(step: RecipeStep, index: Int) -> some View {
        let isFirst = index == 0
        let isLast = index == draft.steps.count - 1

        return HStack(alignment: .top, spacing: 12) {
            // ── Timeline column ──────────────────────────────────────────
            VStack(spacing: 0) {
                // Top connector line (hidden on first step).
                Rectangle()
                    .fill(isFirst ? Color.clear : Palette.hairline)
                    .frame(width: 1, height: 18)

                // Step index badge.
                ZStack {
                    Circle()
                        .fill(Palette.ink)
                        .frame(width: 22, height: 22)
                    Text("\(index + 1)")
                        .font(Typography.label)
                        .foregroundStyle(Palette.paper)
                }

                // Bottom connector line (hidden on last step).
                Rectangle()
                    .fill(isLast ? Color.clear : Palette.hairline)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }

            // ── Step card ────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {
                // Card header: action name + move controls + delete X
                HStack(alignment: .center, spacing: 8) {
                    Text(step.action.label)
                        .font(Typography.value)
                        .foregroundStyle(Palette.ink)

                    Spacer(minLength: 4)

                    // Move up / down
                    if !isFirst {
                        Button {
                            tapCount += 1
                            draft.steps.move(fromOffsets: IndexSet([index]),
                                             toOffset: index - 1)
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.inkMuted)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if !isLast {
                        Button {
                            tapCount += 1
                            draft.steps.move(fromOffsets: IndexSet([index]),
                                             toOffset: index + 2)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.inkMuted)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    // Delete
                    Button {
                        tapCount += 1
                        withAnimation(Motion.quick) {
                            draft.steps.removeAll { $0.id == step.id }
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.inkMuted)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
                .padding(.bottom, 10)

                Rectangle().fill(Palette.hairline).frame(height: 1)
                    .padding(.bottom, 12)

                // ── Editable fields ──────────────────────────────────────
                stepFields(step: step, index: index)
                    .padding(.bottom, 16)
            }
        }
        // Extra space between step rows so the timeline flows comfortably.
        .padding(.bottom, isLast ? 0 : 4)
    }

    @ViewBuilder
    private func stepFields(step: RecipeStep, index: Int) -> some View {
        let stepBinding = Binding<RecipeStep>(
            get: { draft.steps[safe: index] ?? step },
            set: { draft.steps[safe: index] = $0 }
        )

        // Action picker
        FormField(label: "Action") {
            ChipPicker(
                items: availableActions,
                label: \.label,
                selection: Binding(
                    get: { Optional(stepBinding.wrappedValue.action) },
                    set: { if let a = $0 { stepBinding.wrappedValue.action = a } }
                ),
                allowsDeselect: false,
                onPick: { tapCount += 1 }
            )
        }

        // Mass
        if step.action.acceptsMass {
            NumberRow("Mass", value: Binding(
                get: { stepBinding.wrappedValue.targetMass },
                set: { stepBinding.wrappedValue.targetMass = $0 }
            ), unit: "g", labelWidth: 74)
            .padding(.top, 8)
        }

        // Timing
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("At").catalogueLabel()
                TextField("0:00", text: stepTimeBinding(Binding(
                    get: { stepBinding.wrappedValue.at },
                    set: { stepBinding.wrappedValue.at = $0 }
                )))
                .formValue()
                .keyboardType(.numbersAndPunctuation)
                .frame(width: 56)
            }

            if step.action.hasUntil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Until").catalogueLabel()
                    TextField("0:00", text: stepTimeBinding(Binding(
                        get: { stepBinding.wrappedValue.untilSeconds },
                        set: { stepBinding.wrappedValue.untilSeconds = $0 }
                    )))
                    .formValue()
                    .keyboardType(.numbersAndPunctuation)
                    .frame(width: 56)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 8)

        // Agitation
        if step.action == .pour || step.action == .bloom {
            FormField(label: "Agitation") {
                ChipPicker(
                    items: Array(Agitation.allCases),
                    label: \.label,
                    selection: Binding(
                        get: { stepBinding.wrappedValue.agitation },
                        set: { stepBinding.wrappedValue.agitation = $0 }
                    ),
                    allowsDeselect: true,
                    onPick: { tapCount += 1 }
                )
            }
            .padding(.top, 8)
        }

        // Note
        TextRow(
            label: "Note",
            text: Binding(
                get: { stepBinding.wrappedValue.note },
                set: { stepBinding.wrappedValue.note = $0 }
            ),
            placeholder: "optional",
            capitalization: .sentences
        )
        .padding(.top, 8)

        TextRow(
            label: "Cue",
            text: Binding(
                get: { stepBinding.wrappedValue.cue?.label ?? "" },
                set: { text in
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    stepBinding.wrappedValue.cue = trimmed.isEmpty ? nil : .visual(trimmed)
                }
            ),
            placeholder: "bed drops to 2 mm",
            capitalization: .sentences
        )
        .padding(.top, 8)

        // Accessories for this step (Melodrip, Switch…)
        accessoryChips(stepBinding: stepBinding)
            .padding(.top, 8)
    }

    /// Multi-select chips for accessories attached to this step.
    @ViewBuilder
    private func accessoryChips(stepBinding: Binding<RecipeStep>) -> some View {
        let accessories = setup.accessories
        if !accessories.isEmpty {
            FormField(label: "Accessories") {
                FlowLayout {
                    ForEach(accessories) { item in
                        let selected = stepBinding.wrappedValue.accessoryIDs.contains(item.id)
                        TagChip(text: item.displayName, isSelected: selected) {
                            tapCount += 1
                            if selected {
                                stepBinding.wrappedValue.accessoryIDs.removeAll { $0 == item.id }
                            } else {
                                stepBinding.wrappedValue.accessoryIDs.append(item.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Add buttons

    private var addStepButtons: some View {
        HStack(spacing: 16) {
            // The pouring verb differs by method: you pour a V60, you pull a
            // shot. Both come from the method's own action list.
            Button {
                tapCount += 1
                appendStep(action: primaryAction)
            } label: {
                Label(primaryAction.label, systemImage: "plus")
                    .font(Typography.label)
                    .tracking(Typography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.inkMuted)
            }
            .buttonStyle(.plain)

            Button {
                tapCount += 1
                appendStep(action: .wait)
            } label: {
                Label("Step", systemImage: "plus")
                    .font(Typography.label)
                    .tracking(Typography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.inkMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, draft.steps.isEmpty ? 0 : 12)
    }

    /// The method's main mass-carrying action — Pour on a V60, Shot on an
    /// espresso, Fill on a moka.
    private var primaryAction: StepAction {
        DefaultSequence.actions(for: draft.method).first(where: \.acceptsMass) ?? .pour
    }

    private func appendStep(action: StepAction) {
        let prevAt = draft.steps.last?.untilSeconds ?? draft.steps.last?.at ?? 0
        let at = prevAt + 15
        let mass: Double? = action.acceptsMass
            ? (RecipeScaling.liquid(of: draft) ?? (lastPourMass ?? 0) + 50)
            : nil
        draft.steps.append(RecipeStep(
            at: at,
            action: action,
            targetMass: mass,
            untilSeconds: at + 20
        ))
    }

    // MARK: - Footer

    private var stepFooter: some View {
        let maxMass = lastPourMass ?? 0
        let target = RecipeScaling.liquid(of: draft) ?? 0
        let time = draft.timeLabel ?? "—"

        return VStack(alignment: .leading, spacing: 6) {
            Text("Last pour \(GrindRange.number(maxMass)) g · \(time)")
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)

            // Warn when the sequence never reaches the declared total.
            if target > 0, maxMass < target - 1 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Steps reach \(GrindRange.number(maxMass)) g — target is \(GrindRange.number(target)) g")
                }
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
            }
        }
    }

    // MARK: - Rescale

    /// The last pour, which is what the sequence should add up to. The rinse
    /// is excluded: its mass belongs to the paper, not to the recipe.
    private var lastPourMass: Double? {
        draft.steps
            .filter { $0.action != .rinse }
            .compactMap(\.targetMass)
            .max()
    }

    private var stepsNeedRescale: Bool {
        guard let target = RecipeScaling.liquid(of: draft), let last = lastPourMass
        else { return false }
        return abs(last - target) > 1
    }

    private func rescaleSteps() {
        guard let target = RecipeScaling.liquid(of: draft), let current = lastPourMass,
              current > 0
        else { return }
        let factor = target / current
        guard RecipeScaling.factorBounds.contains(factor) else { return }
        draft.steps = RecipeScaling.scalingSteps(draft.steps, by: factor)
    }

    // MARK: - Save

    private func save() {
        draft.steps.sort { $0.at < $1.at }
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            draft.name = Recipe.expressTitle(family: draft.method.family)
        }
        draft.source = .express
        draft.evidence = .unverified
        draft.autoAdvance = false
        onSave(draft)
        dismiss()
    }

    // MARK: - Helpers

    /// Actions offered for the draft's method, plus whatever a step already
    /// uses — editing an imported recipe must not silently drop its action.
    private var availableActions: [StepAction] {
        var actions = DefaultSequence.actions(for: draft.method)
        for step in draft.steps where !actions.contains(step.action) {
            actions.append(step.action)
        }
        return actions
    }

    private func stepTimeBinding(_ value: Binding<Int>) -> Binding<String> {
        Binding(
            get: { formatSeconds(value.wrappedValue) },
            set: { value.wrappedValue = parseTimeString($0) ?? value.wrappedValue }
        )
    }

    private func stepTimeBinding(_ value: Binding<Int?>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue.map(formatSeconds) ?? "" },
            set: { value.wrappedValue = parseTimeString($0) }
        )
    }

    private func formatSeconds(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }

    private func parseTimeString(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        if parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]) {
            return m * 60 + s
        }
        return Int(text)
    }
}

// MARK: - Safe subscript for array binding

private extension Array {
    subscript(safe index: Int) -> Element? {
        get { indices.contains(index) ? self[index] : nil }
        set {
            guard indices.contains(index), let value = newValue else { return }
            self[index] = value
        }
    }
}
