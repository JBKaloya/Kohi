import Combine
import SwiftUI

/// Single-screen extraction editor, in three movements: what you are about to
/// do, what happens while you do it, and what it tasted like.
///
/// Still fast for the second brew — the sheet arrives pre-filled from the
/// recipe, the setup defaults and the previous extraction, so repeating one is
/// a tap on Save. Everything added here is either folded away or only appears
/// when there is something to put in it.
struct BrewSheet: View {
    let card: CoffeeCard
    /// The recipe this brew is following, when it is following one. Drives the
    /// guided timer and the comparison.
    var recipe: Recipe?

    @State private var draft: Brew
    private let onSave: (Brew) -> Void
    private let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(SetupStore.self) private var setup
    @Environment(RecipeStore.self) private var recipes
    @Environment(CardStore.self) private var store
    @Environment(AIFlags.self) private var flags
    @Environment(LotFlags.self) private var lotFlags
    @Environment(AIEventLog.self) private var events
    @Environment(AIFeedbackStore.self) private var feedback
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var dictation = Dictation()
    @State private var filledTrigger = 0
    @State private var beforeDictation: Brew?
    @State private var dictationEventID: UUID?

    @State private var showMore = false
    @State private var showTaste = false
    @State private var showCompare = false
    @State private var timerRunning = false
    @State private var timerStart: Date?
    @State private var timerElapsed: Int = 0
    @State private var saveTrigger = 0
    @State private var tapCount = 0
    @State private var stepTrigger = 0
    @State private var hasPrefilled = false
    @State private var isPickingRecipe = false
    @State private var savedAsRecipe = false
    @State private var grindGuessTrigger = 0
    @State private var agitationGuessTrigger = 0
    @State private var completenessTrigger = 0
    @FocusState private var grindFocused: Bool
    @FocusState private var timeFocused: Bool
    @State private var grindBeforeGuess: GrindSetting?
    @State private var agitationBeforeGuess: Agitation?
    @State private var showPours = false
    @State private var brewAgainFromCompare: Brew?
    @State private var showProfile = false
    @State private var correction: SuggestedCorrection?
    @State private var pickedMove: Int?

    init(
        card: CoffeeCard,
        brew: Brew,
        recipe: Recipe? = nil,
        onSave: @escaping (Brew) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.card = card
        self.recipe = recipe
        _draft = State(initialValue: brew)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if onDelete != nil {
                        HStack(spacing: 18) {
                            Button(Copy.brewAgain) {
                                tapCount += 1
                                draft = draft.again()
                            }
                            .catalogueLabel()
                            .touchTarget()
                            if lotFlags.isOn(.brewCompare) {
                                Button(Copy.compare) {
                                    tapCount += 1
                                    showCompare = true
                                }
                                .catalogueLabel()
                                .touchTarget()
                            }
                            Spacer()
                        }
                    }
                    if Dictation.isSupported { sayItSection }
                    if flags.isOn(.aiFeedback), let dictationEventID {
                        AIFeedbackScale(eventID: dictationEventID, feature: .fieldExtract, store: feedback)
                    }
                    methodSection
                    contextSection
                    recipeSection
                    grindRow
                    temperatureRow

                    if showPours || !steps.isEmpty || !draft.steps.isEmpty { poursSection }

                    ratingSection
                    if lotFlags.isOn(.taste7) { tasteSection }
                    axesSection
                    nextTimeSection

                    if lotFlags.isOn(.brewCompare) { compareSection }

                    moreSection
                    dateSection

                    if onDelete != nil { deleteButton }
                }
                .padding(.horizontal, 26)
                .padding(.top, 14)
                .padding(.bottom, 60)
                .fieldKeyboardClearance()
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Brew")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.medium)
                }
            }
        }
        .tint(Palette.ink)
        .haptic(.tap, trigger: tapCount)
        .haptic(.tick, trigger: timerElapsed)
        .haptic(.stepAdvance, trigger: stepTrigger)
        .haptic(.saved, trigger: saveTrigger)
        .task { prefill() }
        .task(id: "\(draft.acidity)-\(draft.bitterness)-\(draft.body)-\(draft.rating ?? 0)-\(draft.notes)") {
            await loadCorrection()
        }
        // Dismissing the sheet mid-sentence must not leave the microphone on.
        .onDisappear { dictation.cancel() }
        .sheet(isPresented: $isPickingRecipe) {
            RecipePickerSheet(card: card, method: draft.method) { picked in
                apply(picked)
            }
            .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $showCompare) {
            BrewCompareSheet(
                card: card,
                reference: draft,
                others: store.cards,
                waters: setup.waterProfiles,
                equipment: setup.equipment
            ) { seed in
                draft = seed.again()
            }
            .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $showProfile) {
            ProfileSheet()
                .appEnvironment(appEnvironment)
        }
    }

    // MARK: - Saying it

    /// The keyboard-free path in. What it understands lands in the fields
    /// below with a shade behind it; what it does not goes to Notes verbatim.
    private var sayItSection: some View {
        SayItLabel(
            isListening: dictation.isListening,
            transcript: dictation.transcript,
            prompt: dictation.state == .unavailable ? "Dictation unavailable" : "Dictate",
            hint: dictationHint
        ) {
            Task { await toggleDictation() }
        }
        .guessHighlight(trigger: filledTrigger, onUndo: undoDictation)
    }

    private var dictationHint: String? {
        switch dictation.state {
        case .denied: "Dictation needs the microphone. Settings has the switch."
        case .unavailable: "Dictation unavailable"
        case .idle, .listening:
            beforeDictation == nil
                ? "\"18 in, 250 of water, two forty-five, four stars\""
                : "Tap the shaded fields to put them back."
        }
    }

    private func toggleDictation() async {
        tapCount += 1
        guard dictation.isListening else {
            await dictation.start()
            return
        }

        let transcript = await dictation.stop()
        guard !transcript.isEmpty else { return }

        // The state to return to if the fill was wrong. Taken before anything
        // is written, so undo is exact rather than approximate.
        beforeDictation = draft

        // The small grammar first, always. The model is only asked when the
        // grammar left most of the sentence on the floor, which keeps the
        // common case offline and instant.
        var result = SpokenBrewParser.parse(transcript)
        if result.confidence < 0.5, flags.isOn(.fieldExtract) {
            let context = "method: \(draft.method?.rawValue ?? "unknown")"
            if let outcome = await FieldExtract.brew(
                transcript: transcript,
                context: context,
                flags: flags,
                events: events
            ), !outcome.value.isEmpty {
                result = outcome.value
                dictationEventID = outcome.eventID
            }
        }

        guard !result.isEmpty || !result.leftover.isEmpty else { return }
        withAnimation(Motion.snappy) {
            SpokenBrewParser.apply(result, to: &draft)
            filledTrigger += 1
        }
    }

    /// Tapping the shade puts everything back, and says so in the log.
    private func undoDictation() {
        guard let beforeDictation else { return }
        withAnimation(Motion.snappy) { draft = beforeDictation }
        self.beforeDictation = nil
        if let dictationEventID {
            events.setAccepted(false, for: dictationEventID)
            self.dictationEventID = nil
        }
    }

    // MARK: - Before

    private var methodSection: some View {
        group("Method") {
            FlowLayout {
                ForEach(BrewMethod.allCases) { method in
                    TagChip(
                        text: method.label,
                        isSelected: draft.method == method
                    ) {
                        tapCount += 1
                        let picked = draft.method == method ? nil : method
                        draft.method = picked
                        // A new method has its own defaults and its own kit.
                        if let picked { applyDefaults(for: picked) }
                    }
                }
            }
        }
        .completenessPulse(.method, completeness: draft.completeness, trigger: completenessTrigger)
    }

    /// Recipe, With, Water — the three rows that answer "what am I about to
    /// do" before any number is typed.
    private var contextSection: some View {
        VStack(spacing: 0) {
            contextRow(
                label: "Recipe",
                value: recipeLabel,
                detail: recipeDetail
            ) { isPickingRecipe = true }

            Rectangle().fill(Palette.hairline).frame(height: 1)

            contextRow(label: "With", value: equipmentLabel, detail: "") {
                tapCount += 1
                withAnimation(Motion.snappy) { showMore = true }
            }

            Rectangle().fill(Palette.hairline).frame(height: 1)

            contextRow(label: "Water", value: waterLabel, detail: waterDetail) {
                tapCount += 1
                cycleWater()
            }
        }
    }

    private func contextRow(
        label: String,
        value: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(label)
                    .catalogueLabel()
                    .frame(width: 74, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(value.isEmpty ? "—" : value)
                        .font(Typography.value)
                        .foregroundStyle(value.isEmpty ? Palette.hairline : Palette.ink)
                        .multilineTextAlignment(.leading)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }
                }
                Spacer(minLength: 4)
                if label == "Recipe", activeRecipe != nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }

    private var recipeLabel: String {
        activeRecipe?.name ?? "Pick a recipe"
    }

    private var recipeDetail: String {
        guard let activeRecipe else { return "or just start typing below" }
        var parts = [activeRecipe.source.label.lowercased()]
        if !activeRecipe.attribution.isEmpty { parts.append(activeRecipe.attribution) }
        return parts.joined(separator: " · ")
    }

    private var equipmentLabel: String {
        let items = draft.equipmentIDs.compactMap { setup.equipment(id: $0) }
        guard !items.isEmpty else { return setup.isEmpty ? "Add your kit in Profile" : "" }
        return items.map(\.displayName).joined(separator: " · ")
    }

    private var waterLabel: String {
        guard let profile = draft.waterProfileID.flatMap({ setup.waterProfile(id: $0) })
        else { return setup.waterProfiles.isEmpty ? "Add water in Setup" : "" }
        return profile.displayName
    }

    private var waterDetail: String {
        draft.waterProfileID.flatMap { setup.waterProfile(id: $0) }?.summary ?? ""
    }

    /// Tapping the water row moves to the next profile. With one or none on
    /// file there is nothing to move to, and the row just says so.
    private func cycleWater() {
        let profiles = setup.waterProfiles
        guard profiles.count > 1 else { return }
        let index = profiles.firstIndex { $0.id == draft.waterProfileID } ?? -1
        draft.waterProfileID = profiles[(index + 1) % profiles.count].id
    }

    // MARK: - Recipe line

    private var recipeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Parameters").catalogueLabel()

            HStack(spacing: 0) {
                NumberRow(
                    Copy.coffeeDose,
                    value: $draft.dose,
                    unit: "g",
                    placeholder: Placeholders.text(.brewDose),
                    presence: .useful,
                    compactWidth: 70
                )
                .completenessPulse(.dose, completeness: draft.completeness, trigger: completenessTrigger)

                DerivedValue(text: draft.ratio ?? "—")
                    .frame(maxWidth: .infinity)

                NumberRow(
                    draft.method == .espresso ? Copy.beverage : Copy.waterWeight,
                    value: outputBinding,
                    unit: "g",
                    placeholder: outputPlaceholder,
                    presence: .useful,
                    compactWidth: 70
                )
                .completenessPulse(.output, completeness: draft.completeness, trigger: completenessTrigger)
            }

            HStack(spacing: 12) {
                timerField
                    .completenessPulse(.time, completeness: draft.completeness, trigger: completenessTrigger)
                Spacer()
                if let flow = draft.averageFlow {
                    DerivedValue(text: "\(String(format: "%.1f", flow)) g/s", empty: "")
                }
            }
        }
    }

    /// Espresso uses beverage (liquid in cup); infusion uses water.
    private var outputBinding: Binding<Double?> {
        if draft.method == .espresso {
            return $draft.beverage
        }
        return $draft.water
    }

    private var timerField: some View {
        HStack(spacing: 8) {
            Text("Time").catalogueLabel()
                .frame(width: 40, alignment: .leading)

            if timerRunning, steps.isEmpty {
                Text(formatSeconds(timerElapsed))
                    .font(Typography.value)
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()

                Button {
                    tapCount += 1
                    stopTimer()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.ink)
                }
                .buttonStyle(.plain)
            } else {
                secondsField

                // With steps, the clock belongs to the guided timer below.
                if steps.isEmpty {
                    Button {
                        tapCount += 1
                        startTimer()
                    } label: {
                        Image(systemName: "timer")
                            .font(.system(size: 16))
                            .foregroundStyle(Palette.inkMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onReceive(
            Timer.publish(every: 1, on: .main, in: .common).autoconnect()
        ) { _ in
            guard timerRunning, let start = timerStart else { return }
            timerElapsed = Int(Date.now.timeIntervalSince(start))
        }
    }

    private var secondsField: some View {
        let binding = Binding<String>(
            get: {
                guard let s = draft.seconds, s > 0 else { return "" }
                return formatSeconds(s)
            },
            set: { text in
                draft.seconds = parseSeconds(text)
            }
        )
        return TextField(
            "",
            text: binding,
            prompt: Text(Placeholders.text(.brewTime)).foregroundStyle(Palette.hairline)
        )
            .formValue()
            .frame(width: 50)
            .keyboardType(.numbersAndPunctuation)
            .focused($timeFocused)
            .reportsFieldFocus(timeFocused)
    }

    // MARK: - Grind and temperature

    private var grindRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            FormField(
                label: "Grind",
                labelWidth: 74,
                presence: .useful,
                isEmpty: draft.grind.isEmpty,
                isFocused: grindFocused
            ) {
                HStack(spacing: 8) {
                    if !setup.grinders.isEmpty {
                        TagChip(
                            text: grindChipLabel,
                            isSelected: draft.grind.grinderId != nil
                        ) {
                            tapCount += 1
                            cycleGrinder()
                        }
                    }

                    TextField(
                        "",
                        text: grindValueBinding,
                        prompt: Text(grindPlaceholder).foregroundStyle(Palette.hairline)
                    )
                    .formValue()
                    .keyboardType(.decimalPad)
                    .focused($grindFocused)

                    if !grindUnit.isEmpty {
                        Text(grindUnit)
                            .font(Typography.tag)
                            .foregroundStyle(FieldChrome.unit(isEmpty: draft.grind.isEmpty).color)
                    }
                }
            }

            if let microns = draft.grind.micronsLabel(
                grinder: selectedGrinder,
                calibrations: setup.calibrations,
                method: draft.method
            ) {
                DerivedValue(text: microns, empty: "")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 90)
            }
        }
        .completenessPulse(.grind, completeness: draft.completeness, trigger: completenessTrigger)
        .guessHighlight(trigger: grindGuessTrigger) {
            if let grindBeforeGuess {
                draft.grind = grindBeforeGuess
                self.grindBeforeGuess = nil
            }
        }
    }

    private var grindChipLabel: String {
        selectedGrinder?.displayName ?? "Grinder"
    }

    private var grindUnit: String {
        selectedGrinder?.unitLabel ?? ""
    }

    private var selectedGrinder: Equipment? {
        draft.grind.grinderId.flatMap { setup.equipment(id: $0) }
            ?? setup.preferredGrinder(for: draft.method)
    }

    private var grindValueBinding: Binding<String> {
        Binding(
            get: {
                if let value = draft.grind.value { return GrindRange.number(value) }
                return draft.grind.raw ?? ""
            },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    draft.grind.value = nil
                    draft.grind.raw = nil
                    return
                }
                if let number = NumberText.parse(trimmed), setup.grinders.isEmpty == false {
                    draft.grind.value = number
                    if draft.grind.grinderId == nil {
                        draft.grind.grinderId = selectedGrinder?.id
                    }
                } else {
                    draft.grind = GrindSetting(
                        grinderId: draft.grind.grinderId,
                        raw: trimmed
                    )
                }
            }
        )
    }

    private func cycleGrinder() {
        let grinders = setup.grinders
        guard !grinders.isEmpty else { return }
        let index = grinders.firstIndex { $0.id == draft.grind.grinderId } ?? -1
        draft.grind.grinderId = grinders[(index + 1) % grinders.count].id
    }

    private var grindPlaceholder: String {
        Placeholders.text(.brewGrind)
    }

    /// Temperature is a main row now: it is one of the three things a roast
    /// level actually decides, and it was buried under "More".
    private var temperatureRow: some View {
        NumberRow(
            "Temp",
            value: $draft.temperature,
            unit: "°C",
            placeholder: Placeholders.text(.brewTemperature),
            labelWidth: 74,
            hint: temperatureHint,
            error: draft.temperature.flatMap(FieldCopy.boiling)
        )
    }

    private var temperatureHint: String? {
        guard draft.temperature == nil, let method = draft.method else { return nil }
        let band = RecipeRules.temperature(for: card.roastLevel, method: method)
        let roast = card.roastLevel?.label.lowercased() ?? "unknown roast"
        return "\(GrindRange.number(band.lowerBound))–\(GrindRange.number(band.upperBound)) °C for a \(roast) roast"
    }

    // MARK: - During

    private var poursSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pours").catalogueLabel()

            if !draft.steps.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(draft.steps.enumerated()), id: \.element.id) { _, step in
                        pourRow(step)
                    }
                }
            }

            if !steps.isEmpty {
                StepTimer(
                    steps: steps,
                    elapsed: timerElapsed,
                    isRunning: timerRunning,
                    recorded: $draft.steps,
                    onStart: { tapCount += 1; startTimer() },
                    onAdvance: advance,
                    onStop: { tapCount += 1; stopTimer() }
                )
            } else {
                Button {
                    tapCount += 1
                    addPour()
                } label: {
                    Text("Add a step")
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func pourRow(_ step: BrewStep) -> some View {
        let flow = draft.flow(for: step)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(step.timeLabel)
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
                .frame(width: 36, alignment: .leading)

            Text(step.actionLabel)
                .font(Typography.tag)
                .foregroundStyle(Palette.ink)

            Spacer(minLength: 4)

            if let mass = step.mass {
                Text("\(GrindRange.number(mass)) g")
                    .font(Typography.tag)
            } else if let target = step.targetMass {
                Button {
                    tapCount += 1
                    confirmMass(of: step, mass: target)
                } label: {
                    Text("\(GrindRange.number(target)) g")
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
                .buttonStyle(.plain)
            }

            if let flow {
                Text(String(format: "%.1f g/s", flow))
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
        }
        .padding(.vertical, 8)
    }

    private func confirmMass(of step: BrewStep, mass: Double) {
        guard let index = draft.steps.firstIndex(where: { $0.id == step.id }) else { return }
        draft.steps[index].mass = mass
    }

    private func addPour() {
        let index = draft.steps.count
        draft.steps.append(BrewStep(
            index: index,
            action: .pour,
            at: draft.seconds ?? timerElapsed,
            note: ""
        ))
        showPours = true
    }

    /// The steps to follow: the recipe's own, if it has any.
    private var steps: [RecipeStep] {
        activeRecipe?.steps ?? []
    }

    private func startTimer() {
        // Resuming keeps the elapsed time: the brew did not restart.
        timerStart = Date.now.addingTimeInterval(-Double(timerElapsed))
        timerRunning = true
    }

    private func stopTimer() {
        timerRunning = false
        draft.seconds = timerElapsed
    }

    /// Logs the current step at the real time on the clock, keeping the
    /// recipe's target beside it so the two can be compared later.
    private func advance() {
        let index = draft.steps.count
        guard index < steps.count else { return }
        let planned = steps[index]
        stepTrigger += 1
        withAnimation(Motion.quick) {
            draft.steps.append(BrewStep(
                index: index,
                action: planned.action,
                at: timerElapsed,
                mass: nil,
                targetAt: planned.at,
                targetMass: planned.targetMass,
                note: planned.note
            ))
        }
        if draft.steps.count == steps.count {
            draft.seconds = timerElapsed
        }
    }

    // MARK: - After

    private var ratingSection: some View {
        group("Rating") {
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { step in
                    Button {
                        tapCount += 1
                        withAnimation(Motion.quick) {
                            draft.rating = draft.rating == step ? nil : step
                        }
                    } label: {
                        Circle()
                            .fill(
                                (draft.rating ?? 0) >= step
                                    ? Palette.ink
                                    : Color.clear
                            )
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().stroke(Palette.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .touchTarget()
                }
            }
        }
        .completenessPulse(.rating, completeness: draft.completeness, trigger: completenessTrigger)
    }

    /// Six axes and flavour terms, folded: the rating is the fast path and
    /// stays one tap away, this is for when you want to say more.
    private var tasteSection: some View {
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
                    if !draft.taste.isEmpty, !showTaste {
                        Text("\(draft.taste.scoredAxes.count) of 7")
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
                        TasteRadar(taste: draft.taste, previous: previousTaste)
                        Spacer()
                    }

                    if previousTaste != nil {
                        Text("The previous brew of this coffee is the lighter shape.")
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }

                    AxisRails(taste: $draft.taste) { tapCount += 1 }

                    if lotFlags.isOn(.flavorWheel) {
                        FlavorPicker(
                            selection: $draft.flavors,
                            recent: recentFlavors,
                            suggested: card.declaredFlavors
                        )
                    } else {
                        flavorsSection
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// The brew before this one, for the radar underlay. Excludes the brew
    /// being edited, which would otherwise draw itself twice.
    private var previousTaste: TasteProfile? {
        card.brews
            .first { $0.id != draft.id && !$0.taste.isEmpty }?
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

    private var flavorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Flavours").catalogueLabel()

            if !draft.flavors.isEmpty {
                FlowLayout {
                    ForEach(draft.flavors) { tag in
                        TagChip(text: tag.displayName, isSelected: true, showsRemove: true) {
                            withAnimation(Motion.quick) {
                                draft.flavors.removeAll { $0.id == tag.id }
                            }
                        }
                    }
                }
            }

            FlowLayout {
                ForEach(flavorSuggestions) { tag in
                    TagChip(text: tag.displayName) {
                        tapCount += 1
                        withAnimation(Motion.quick) { draft.flavors.append(tag) }
                    }
                }
            }
        }
    }

    private var flavorSuggestions: [FlavorTag] {
        let selected = Set(draft.flavors.map(\.id))
        let fromCard = card.declaredFlavors.filter { !selected.contains($0.id) }
        let fromWheel = FlavorWheel.shared.quick
            .map { FlavorTag(id: $0.id) }
            .filter { !selected.contains($0.id) }
        return Array((fromCard + fromWheel).prefix(16))
    }

    /// The three −/·/+ axes, which answer a different question from the six
    /// above: not what it was like, but what to change.
    private var axesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Correction").catalogueLabel()
            axisRow("Too little / right / too much", value: $draft.acidity, name: "Acidity")
            axisRow("", value: $draft.bitterness, name: "Bitterness")
            axisRow("", value: $draft.body, name: "Body")
        }
    }

    private func axisRow(_ hint: String, value: Binding<Int>, name: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !hint.isEmpty {
                Text(hint)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
            HStack(spacing: 14) {
                Text(name)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .frame(width: 74, alignment: .leading)

                ForEach([-1, 0, 1], id: \.self) { step in
                    Button {
                        tapCount += 1
                        withAnimation(Motion.quick) {
                            value.wrappedValue = value.wrappedValue == step ? 0 : step
                        }
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
                }
            }
        }
    }

    /// Ranked moves from the admissible set. Offline this is one rule.
    @ViewBuilder
    private var nextTimeSection: some View {
        if let correction {
            SuggestedCorrectionView(
                correction: correction,
                pickedRank: $pickedMove
            ) { move in
                tapCount += 1
                draft.nextTimeSuggestion = move.change
            }
            if flags.isOn(.aiFeedback), let eventID = correction.eventID {
                AIFeedbackScale(eventID: eventID, feature: .suggestedCorrection, store: feedback)
            }
        }
    }

    private func loadCorrection() async {
        correction = await SuggestedCorrection.ranked(
            for: draft,
            card: card,
            comment: draft.notes,
            equipment: setup.equipment,
            flags: flags,
            events: events
        )
    }

    /// Opens the side-by-side comparison. B is already chosen in the sheet.
    private var compareSection: some View {
        Button {
            tapCount += 1
            showCompare = true
        } label: {
            HStack(spacing: 6) {
                Text("Compare with…").catalogueLabel()
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expandable MORE

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Button {
                    tapCount += 1
                    withAnimation(Motion.snappy) { showMore.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("More").catalogueLabel()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Palette.inkMuted)
                            .rotationEffect(.degrees(showMore ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Text(draft.completeness.tag)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .onTapGesture {
                        tapCount += 1
                        completenessTrigger += 1
                    }
            }

            if showMore {
                VStack(alignment: .leading, spacing: 16) {
                    equipmentPicker
                    waterPicker
                    tdsRow
                    yieldRow
                    agitationRow
                    filterRow
                    notesRow
                    saveAsRecipeRow
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var equipmentPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kit").catalogueLabel()
            if setup.isEmpty {
                Text("Nothing in the kit yet.")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            } else {
                ChipToggles(
                    items: setup.equipment,
                    label: \.displayName,
                    isOn: { draft.equipmentIDs.contains($0.id) },
                    toggle: { item, on in
                        tapCount += 1
                        if on {
                            draft.equipmentIDs.append(item.id)
                        } else {
                            draft.equipmentIDs.removeAll { $0 == item.id }
                        }
                    }
                )
            }
            Button("Edit kit") { showProfile = true }
                .catalogueLabel()
        }
    }

    private var waterPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Water").catalogueLabel()
            if setup.waterProfiles.isEmpty {
                Text("No water profiles yet.")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            } else {
                ChipPicker(
                    items: setup.waterProfiles,
                    label: \.displayName,
                    selection: Binding(
                        get: { draft.waterProfileID.flatMap { setup.waterProfile(id: $0) } },
                        set: { draft.waterProfileID = $0?.id }
                    ),
                    onPick: { tapCount += 1 }
                )
            }
        }
    }

    private var tdsRow: some View {
        NumberRow(
            "TDS",
            value: $draft.tds,
            unit: "%",
            placeholder: Placeholders.text(.brewTDS),
            labelWidth: 74
        )
    }

    private var yieldRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("Yield")
                .catalogueLabel()
                .frame(width: 74, alignment: .leading)
            if let ey = draft.extractionYield {
                Text(String(format: "%.1f %%", ey))
                    .font(Typography.value)
                    .foregroundStyle(Palette.inkMuted)
            } else {
                Text("—")
                    .font(Typography.value)
                    .foregroundStyle(Palette.hairline)
            }
            Spacer()
        }
    }

    private var agitationRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Agitation").catalogueLabel()
            ChipPicker(
                items: Array(Agitation.allCases),
                label: \.label,
                selection: $draft.agitation,
                onPick: { tapCount += 1 }
            )
        }
        .guessHighlight(trigger: agitationGuessTrigger) {
            draft.agitation = agitationBeforeGuess
            agitationBeforeGuess = nil
        }
    }

    private var filterRow: some View {
        let filters = activeBrewer?.filters.filter { !$0.isEmpty } ?? []
        return VStack(alignment: .leading, spacing: 10) {
            Text("Filter").catalogueLabel()
            if filters.isEmpty {
                Text(activeBrewer == nil ? "Pick a brewer in Kit" : "Add filters in Profile")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            } else {
                ChipPicker(
                    items: filters,
                    label: \.displayName,
                    selection: Binding(
                        get: { filters.first { $0.id == draft.filterId } },
                        set: { draft.filterId = $0?.id }
                    ),
                    onPick: { tapCount += 1 }
                )
            }
        }
    }

    private var activeBrewer: Equipment? {
        draft.equipmentIDs.compactMap { setup.equipment(id: $0) }.first { $0.kind == .brewer }
            ?? setup.defaults(for: draft.method ?? .v60).first { $0.kind == .brewer }
    }

    private var notesRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Notes").catalogueLabel()
            TextField(Placeholders.text(.brewNotes), text: $draft.notes, axis: .vertical)
                .font(Typography.body)
                .lineLimit(2...6)
            DictationField(text: $draft.notes)
        }
    }

    /// Keeping a brew as a recipe is what fills the "Mine" section, and this is
    /// the moment you know it was worth keeping.
    @ViewBuilder
    private var saveAsRecipeRow: some View {
        if draft.dose != nil, draft.water != nil || draft.beverage != nil {
            Button(savedAsRecipe ? "Saved as a recipe" : "Save as recipe") {
                guard !savedAsRecipe else { return }
                tapCount += 1
                let saved = recipes.save(brew: draft, from: card)
                draft.recipeID = saved.id
                savedAsRecipe = true
            }
            .font(Typography.tag)
            .foregroundStyle(savedAsRecipe ? Palette.inkMuted : Palette.ink)
            .disabled(savedAsRecipe)
        }
    }

    // MARK: - Date

    private var dateSection: some View {
        group("Date") {
            DatePicker("", selection: $draft.date, displayedComponents: .date)
                .labelsHidden()
        }
    }

    private var deleteButton: some View {
        Button {
            onDelete?()
            dismiss()
        } label: {
            Text("Delete this brew")
                .catalogueLabel()
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Recipe and defaults

    /// The recipe in play: the one passed in, or the one this brew was saved
    /// against.
    private var activeRecipe: Recipe? {
        if let recipe { return recipe }
        guard let id = draft.recipeID else { return nil }
        return recipes.recipe(id: id) ?? ReferenceBase.recipes.first { $0.id == id }
    }

    /// Fills what is empty, once, from the recipe and the setup defaults.
    /// Nothing already entered is touched — the same rule the OCR pipeline
    /// follows.
    private func prefill() {
        guard !hasPrefilled else { return }
        hasPrefilled = true

        if let recipe {
            apply(recipe, overwrite: false)
        }
        if let method = draft.method {
            applyDefaults(for: method)
        }
        prefillGrind()
        prefillAgitation()
        prefillFilter()
        prefillSteps()
        if draft.waterProfileID == nil {
            draft.waterProfileID = setup.defaultWaterProfile?.id
        }
        if draft.captureSource == nil, draft.dose != nil, (draft.water != nil || draft.beverage != nil) {
            draft.captureSource = .prefilled
        }
        if !steps.isEmpty || !draft.steps.isEmpty { showPours = true }
    }

    private func prefillGrind() {
        if draft.grind.grinderId == nil, let grinder = setup.preferredGrinder(for: draft.method) {
            draft.grind.grinderId = grinder.id
        }
        guard draft.grind.value == nil else { return }

        if let last = card.brews.first(where: {
            $0.id != draft.id && $0.method == draft.method && $0.grind.value != nil
        }) {
            draft.grind = last.grind
            return
        }

        if let recipe = activeRecipe,
           let grinder = setup.preferredGrinder(for: recipe.method),
           let translation = GrindConversion.translate(
               recipe: recipe,
               to: grinder,
               calibrations: setup.calibrations
           )
        {
            grindBeforeGuess = draft.grind
            draft.grind = GrindSetting(
                grinderId: grinder.id,
                value: translation.setting,
                raw: translation.label
            )
            grindGuessTrigger += 1
            return
        }

        if let grinder = setup.preferredGrinder(for: draft.method),
           let range = grinder.range(for: draft.method ?? .v60)
        {
            grindBeforeGuess = draft.grind
            let mid = (range.low + range.high) / 2
            draft.grind = GrindSetting(
                grinderId: grinder.id,
                value: grinder.adjustment?.isDetented == true ? mid.rounded() : mid
            )
            grindGuessTrigger += 1
        }
    }

    private func prefillAgitation() {
        guard draft.agitation == nil else { return }
        if let last = card.brews.first(where: {
            $0.id != draft.id && $0.method == draft.method && $0.agitation != nil
        }) {
            agitationBeforeGuess = nil
            draft.agitation = last.agitation
            agitationGuessTrigger += 1
        }
    }

    private func prefillFilter() {
        guard draft.filterId == nil, let brewer = activeBrewer else { return }
        draft.filterId = brewer.defaultFilterId ?? brewer.filters.first?.id
    }

    private func prefillSteps() {
        guard draft.steps.isEmpty else { return }
        if let recipe = activeRecipe, !recipe.steps.isEmpty { return }
        if let last = card.brews.first(where: { $0.id != draft.id && !$0.steps.isEmpty }) {
            draft.steps = last.steps.map {
                BrewStep(
                    index: $0.index,
                    action: $0.action,
                    at: 0,
                    mass: nil,
                    targetAt: $0.targetAt ?? $0.at,
                    targetMass: $0.targetMass ?? $0.mass,
                    note: $0.note
                )
            }
        }
    }

    private func applyDefaults(for method: BrewMethod) {
        let defaults = setup.defaults(for: method)
        guard !defaults.isEmpty else { return }
        // Replaces the kit rather than adding to it: the previous method's
        // brewer has nothing to do with this one.
        let kept = draft.equipmentIDs.filter { id in
            guard let item = setup.equipment(id: id) else { return false }
            return !defaults.contains { $0.kind == item.kind }
        }
        draft.equipmentIDs = kept + defaults.map(\.id)
    }

    private func apply(_ recipe: Recipe, overwrite: Bool = true) {
        withAnimation(Motion.snappy) {
            let link = recipe.brewLink()
            draft.recipeID = link.recipeID
            draft.recipeRef = link.recipeRef
            draft.recipeSnapshot = link.snapshot
            if overwrite || draft.method == nil { draft.method = recipe.method }
            if overwrite || draft.dose == nil { draft.dose = recipe.dose }
            if overwrite || draft.water == nil { draft.water = recipe.water }
            if overwrite || draft.beverage == nil { draft.beverage = recipe.beverage }
            if overwrite || draft.temperature == nil { draft.temperature = recipe.temperature }
            if overwrite || draft.seconds == nil { draft.seconds = recipe.seconds }
            if overwrite || draft.grind.isEmpty {
                var setting = GrindSetting(raw: recipe.grindLabel)
                setting.grinderId = draft.grind.grinderId
                draft.grind = setting
            }
            // Steps recorded during a brew are not the recipe's to replace.
            if draft.steps.isEmpty, draft.captureSource == nil {
                draft.captureSource = .prefilled
            }
        }
    }

    private func save() {
        saveTrigger += 1
        if timerRunning { stopTimer() }
        if dictation.isListening { dictation.cancel() }
        draft.flowGs = draft.averageFlow
        if draft.captureSource == nil { draft.captureSource = .typed }
        // Saving a brew the model helped fill in is the acceptance: it was
        // right enough to keep.
        if let dictationEventID { events.setAccepted(true, for: dictationEventID) }
        onSave(draft)
        dismiss()
    }

    // MARK: - Helpers

    private var outputPlaceholder: String {
        draft.method == .espresso ? Placeholders.text(.brewBeverage) : Placeholders.text(.brewWater)
    }

    private func group(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).catalogueLabel()
            content()
        }
    }

    private func formatSeconds(_ total: Int) -> String {
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func parseSeconds(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        if parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]) {
            return m * 60 + s
        }
        return Int(text)
    }
}
