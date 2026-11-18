import SwiftUI

/// Name a sequence, edit its blocks — doses, times, masses — and pick a
/// template. The ratio is the pivot: the dose carries the water at the same
/// ratio, the water carries the ratio, and the parts of the split hold
/// while their grams follow.
struct StepBuilderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SetupStore.self) private var setup
    @Environment(RecipeStore.self) private var recipes

    @State private var draft: Recipe
    var onSave: (Recipe) -> Void
    /// What the recipe becomes on Save: express when edited on the way to
    /// the timer, mine when created.
    private let saveAs: RecipeSource
    /// Create your recipe: the sheet also asks for the parameters a blank
    /// recipe has nowhere else to get.
    private let creating: Bool
    /// Adjust on a recipe of mine: the whole recipe is editable, as when it
    /// was created, and it keeps its source.
    private let adjusting: Bool
    /// From Recipes there is no brew to take the method from.
    private let asksMethod: Bool
    /// On the way to the timer: use the recipe for this brew without
    /// keeping it in Mine.
    private let onBrewOnce: ((Recipe) -> Void)?
    private let titleOverride: String?

    /// How the parts of the split are written. The same grams either way.
    private enum SplitUnit: String, CaseIterable, Identifiable, Equatable {
        case percent = "%"
        case grams = "g"
        var id: String { rawValue }
    }
    @State private var splitUnit: SplitUnit = .percent

    @State private var tapCount = 0
    /// The parts last written, held across total changes so rounding to the
    /// half gram never drifts them.
    @State private var shares: [Double]?
    @FocusState private var focus: Field?
    @State private var keyboardUp = false

    private enum Field: Hashable {
        case at(UUID), until(UUID)
    }

    init(
        draft: Recipe,
        saveAs: RecipeSource = .express,
        creating: Bool = false,
        adjusting: Bool = false,
        asksMethod: Bool = false,
        onBrewOnce: ((Recipe) -> Void)? = nil,
        titleOverride: String? = nil,
        onSave: @escaping (Recipe) -> Void
    ) {
        var draft = draft
        draft.steps.removeAll { $0.action == .rinse }
        _draft = State(initialValue: draft)
        self.saveAs = saveAs
        self.creating = creating
        self.adjusting = adjusting
        self.asksMethod = asksMethod
        self.onBrewOnce = onBrewOnce
        self.titleOverride = titleOverride
        self.onSave = onSave
    }

    /// Create your recipe, ready to fill in, saved to Mine.
    static func creation(
        draft: Recipe,
        asksMethod: Bool = false,
        onBrewOnce: ((Recipe) -> Void)? = nil,
        onSave: @escaping (Recipe) -> Void
    ) -> StepBuilderSheet {
        StepBuilderSheet(draft: draft, saveAs: .mine, creating: true, asksMethod: asksMethod, onBrewOnce: onBrewOnce, onSave: onSave)
    }

    /// Edit a copy of someone else's recipe: created in Mine, titled as such.
    static func copying(draft: Recipe, onSave: @escaping (Recipe) -> Void) -> StepBuilderSheet {
        StepBuilderSheet(draft: draft, saveAs: .mine, creating: true, titleOverride: Copy.editACopy, onSave: onSave)
    }

    /// Edit on a recipe of mine, from the brew or from Recipes.
    static func adjusting(draft: Recipe, onSave: @escaping (Recipe) -> Void) -> StepBuilderSheet {
        StepBuilderSheet(draft: draft, saveAs: draft.source, adjusting: true, onSave: onSave)
    }

    private var editsEverything: Bool { creating || adjusting }

    private var countsBloom: Bool { draft.splitCountsBloom ?? true }

    private var title: String {
        if let titleOverride { return titleOverride }
        if creating { return Copy.createYourRecipe }
        return adjusting ? Copy.edit : "Steps"
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        headerGroup
                        totalsGroup
                        if PourSplitEditing.showsSplit(draft) { splitGroup }
                        if editsEverything { parametersGroup }
                        stepsGroup
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 16)
                    .padding(.bottom, 44)
                    .background {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { dismissKeyboard() }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focus) { _, field in
                    guard let field else { return }
                    withAnimation(Motion.snappy) {
                        proxy.scrollTo(field, anchor: Self.focusAnchor)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !keyboardUp {
                    stepFooter
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 12)
                        .background(Palette.paper)
                        .overlay(alignment: .top) {
                            Rectangle().fill(Palette.hairline).frame(height: 1)
                        }
                        .transition(.opacity)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardUp = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardUp = false
            }
            .animation(Motion.snappy, value: keyboardUp)
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if onBrewOnce != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button(Copy.brewOnce) { brewOnce() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.medium)
                }
            }
        }
        .tint(Palette.ink)
        .haptic(.tap, trigger: tapCount)
        #if DEBUG
        .task {
            guard DebugHooks.keyboardRepro != nil, let last = draft.steps.last else { return }
            try? await Task.sleep(for: .milliseconds(900))
            focus = .at(last.id)
        }
        #endif
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
            DictationField(text: $draft.name, vocabulary: { CoffeeLexicon.recipes(recipes.recipes) })
            if asksMethod {
                RollingPicker(
                    label: "Method",
                    options: BrewMethod.allCases.map { RollOption(id: $0, name: $0.label) },
                    selection: Binding(
                        get: { draft.method },
                        set: {
                            tapCount += 1
                            draft = RecipeCreation.switching(draft, to: $0)
                        }
                    )
                )
            }
        }
    }

    /// Writing the ratio sets the water from the dose; the parts follow.
    private var ratioBinding: Binding<Double?> {
        Binding(
            get: { PourSplit.ratio(dose: draft.dose, water: RecipeScaling.liquid(of: draft)) },
            set: { ratio in
                draft = PourSplitEditing.settingRatio(ratio, on: draft, countsBloom: countsBloom, shares: shares)
            }
        )
    }

    /// The dose carries the water at the same ratio.
    private var doseBinding: Binding<Double?> {
        Binding(
            get: { draft.dose },
            set: { draft = PourSplitEditing.settingDose($0, on: draft, countsBloom: countsBloom, shares: shares) }
        )
    }

    /// The water, or the shot out on an espresso. The ratio moves.
    private var liquidBinding: Binding<Double?> {
        Binding(
            get: { draft.method == .espresso ? draft.beverage : draft.water },
            set: { draft = PourSplitEditing.settingWater($0, on: draft, countsBloom: countsBloom, shares: shares) }
        )
    }

    // MARK: - Split

    private var split: PourSplit.Split? {
        PourSplit.split(of: draft, countsBloom: countsBloom)
    }

    private var splitGroup: some View {
        FieldGroup(title: Copy.split) {
            RollingCounter(
                Copy.services,
                value: serviceCountBinding,
                range: NumberRange(
                    min: Double(PourSplit.serviceRange.lowerBound),
                    max: Double(PourSplit.serviceRange.upperBound),
                    step: 1,
                    decimals: 0,
                    default: 3
                ),
                labelWidth: 74
            )
            HStack(spacing: 10) {
                Text(Copy.countTheBloom).catalogueLabel()
                Spacer(minLength: 0)
                LiquidToggle(isOn: countsBloomBinding, label: Copy.countTheBloom, height: 24)
            }
            .frame(minHeight: 44)
            if split == nil {
                Text(Copy.addASecondPour)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
            if let split {
                if let bloom = split.bloom {
                    Text("Bloom \(GrindRange.number(bloom.grams)) g, outside the split")
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
                let percents = split.percents
                ChipPicker(
                    items: SplitUnit.allCases,
                    label: \.rawValue,
                    selection: Binding(get: { splitUnit }, set: { if let unit = $0 { splitUnit = unit } }),
                    allowsDeselect: false,
                    onPick: { tapCount += 1 }
                )
                ForEach(Array(split.services.enumerated()), id: \.element.stepID) { index, service in
                    let label = "\(index + 1) · \(service.action.label)"
                    if index == split.services.count - 1 {
                        HStack {
                            Text(label).catalogueLabel().frame(width: 74, alignment: .leading)
                            Text("\(percents[index]) % · \(GrindRange.number(service.grams)) g · \(Copy.theRest.lowercased())")
                                .font(Typography.value)
                                .foregroundStyle(Palette.inkMuted)
                        }
                    } else if splitUnit == .grams {
                        RollingCounter(
                            label,
                            value: gramsBinding(at: index),
                            range: .water,
                            unit: "g",
                            labelWidth: 74,
                            hint: "\(percents[index]) %"
                        )
                    } else {
                        RollingCounter(
                            label,
                            value: shareBinding(at: index),
                            range: .share,
                            unit: "%",
                            labelWidth: 74,
                            hint: "\(GrindRange.number(service.grams)) g"
                        )
                    }
                }
            }
        }
    }

    private var serviceCountBinding: Binding<Double?> {
        Binding(
            get: { split.map { Double($0.services.count) } },
            set: { value in
                guard let value, let total = RecipeScaling.liquid(of: draft) else { return }
                let count = Int(value.rounded())
                guard count != split?.services.count else { return }
                tapCount += 1
                draft.steps = PourSplit.restructuring(
                    draft.steps,
                    dose: draft.dose,
                    water: total,
                    count: count,
                    countsBloom: countsBloom,
                    targetTime: draft.seconds
                )
                shares = nil
            }
        )
    }

    private var countsBloomBinding: Binding<Bool> {
        Binding(
            get: { countsBloom },
            set: { draft.splitCountsBloom = $0 ? nil : false }
        )
    }

    private func shareBinding(at index: Int) -> Binding<Double?> {
        Binding(
            get: { split.map { Double($0.percents[index]) } },
            set: { value in
                guard let value, let split, let total = RecipeScaling.liquid(of: draft) else { return }
                let next = PourSplit.setting(share: value / 100, at: index, in: split.services.map(\.share))
                draft.steps = PourSplit.applying(shares: next, to: draft.steps, total: total, countsBloom: countsBloom)
                shares = next
            }
        )
    }

    /// The grams a service adds, written as its part of the water.
    private func gramsBinding(at index: Int) -> Binding<Double?> {
        Binding(
            get: { split?.services[safe: index]?.grams },
            set: { value in
                guard let value, let split, split.base > 0 else { return }
                shareBinding(at: index).wrappedValue = value / split.base * 100
            }
        )
    }

    // MARK: - Parameters

    private var parametersGroup: some View {
        FieldGroup(title: "Parameters") {
            RollingCounter("Temp", value: $draft.temperature, range: .temperature, unit: "°C", labelWidth: 74)
            RollingCounter("Time", value: secondsBinding, range: .brewTime, unit: "s", labelWidth: 74)
            TextRow(label: "Grind", text: $draft.grindLabel, placeholder: "medium-fine", capitalization: .never)
        }
    }

    private var secondsBinding: Binding<Double?> {
        Binding(
            get: { draft.seconds.map(Double.init) },
            set: { draft.seconds = $0.map { Int($0.rounded()) } }
        )
    }

    // MARK: - Totals

    private var totalsGroup: some View {
        FieldGroup(title: "Totals") {
            RollingCounter("Dose", value: doseBinding, range: .dose, unit: "g", labelWidth: 74)
            if draft.method == .espresso {
                RollingCounter("Out", value: liquidBinding, range: .beverage, unit: "g", labelWidth: 74)
            } else {
                RollingCounter("Water", value: liquidBinding, range: .water, unit: "g", labelWidth: 74)
            }
            if editsEverything {
                RollingCounter(Copy.ratioOneTo, value: ratioBinding, range: .ratio, labelWidth: 74)
            } else if let ratio = draft.ratioValue {
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
                    if index < draft.steps.count - 1 {
                        insertButton(after: index)
                    }
                }
            }

            addStepButtons
        }
    }

    /// The focused time lands in the upper third, with the rest of its step
    /// visible under it rather than pressed against the keyboard bar.
    static let focusAnchor = UnitPoint(x: 0.5, y: 0.3)

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
            RollingCounter("Mass", value: Binding(
                get: { stepBinding.wrappedValue.targetMass },
                set: { stepBinding.wrappedValue.targetMass = $0 }
            ), range: .water, unit: "g", labelWidth: 74)
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
                .focused($focus, equals: .at(step.id))
                .frame(width: 56)
                .id(Field.at(step.id))
            }

            if step.action.hasUntil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Until").catalogueLabel()
                    TextField("0:00", text: stepTimeBinding(Binding(
                        get: { stepBinding.wrappedValue.untilSeconds },
                        set: { draft.steps = StepEditing.settingUntil($0, at: index, in: draft.steps) }
                    )))
                    .formValue()
                    .keyboardType(.numbersAndPunctuation)
                    .focused($focus, equals: .until(step.id))
                    .frame(width: 56)
                    .id(Field.until(step.id))
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
                ChipRail {
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

    /// A step between two others, on the timeline between their badges.
    private func insertButton(after index: Int) -> some View {
        Menu {
            ForEach(availableActions, id: \.self) { action in
                Button(action.label) {
                    tapCount += 1
                    withAnimation(Motion.quick) {
                        draft.steps = StepEditing.inserting(action, after: index, in: draft.steps)
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.inkMuted)
                .frame(width: 22, height: 22)
                .background(Palette.paper, in: Circle())
                .overlay(Circle().stroke(Palette.hairline, lineWidth: 1))
                .frame(width: 44, height: 30)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Insert a step after step \(index + 1)")
        .padding(.leading, -11)
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

    /// The last pour, which is what the sequence should add up to.
    private var lastPourMass: Double? {
        draft.steps.compactMap(\.targetMass).max()
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

    /// This brew only: the recipe goes to the timer, not to Mine.
    private func brewOnce() {
        guard let onBrewOnce else { return }
        var once = finished(draft)
        once.source = .express
        onBrewOnce(once)
        dismiss()
    }

    private func finished(_ recipe: Recipe) -> Recipe {
        var recipe = recipe
        recipe.steps = PourSplit.inTimeOrder(recipe.steps)
        if recipe.name.trimmingCharacters(in: .whitespaces).isEmpty {
            recipe.name = Recipe.expressTitle(family: recipe.method.family)
        }
        recipe.evidence = .unverified
        return recipe
    }

    private func save() {
        draft.steps.sort { $0.at < $1.at }
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            draft.name = Recipe.expressTitle(family: draft.method.family)
        }
        draft.source = saveAs
        draft.evidence = .unverified
        onSave(draft)
        dismiss()
    }

    // MARK: - Helpers

    /// Actions offered for the draft's method, plus whatever a step already
    /// uses — editing an imported recipe must not silently drop its action.
    private var availableActions: [StepAction] {
        var actions = DefaultSequence.actions(for: draft.method).filter { $0 != .rinse }
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
