import SwiftUI

/// Format, dose, dictation, then the recipes that fit.
struct BrewScopeView: View {
    @Bindable var session: BrewSession
    var onClose: () -> Void
    var onNext: () -> Void

    @Environment(SetupStore.self) private var setup
    @Environment(AIFlags.self) private var flags
    @Environment(AIEventLog.self) private var events
    @Environment(AIFeedbackStore.self) private var feedback

    @State private var dictation = Dictation()
    @State private var filledTrigger = 0
    @State private var beforeDictation: Brew?
    @State private var tapCount = 0
    @FocusState private var doingFocused: Bool

    var body: some View {
        StepFlow(
            step: 0,
            total: session.progressTotal,
            question: "What are you brewing?",
            onClose: onClose,
            nextTitle: "Kit",
            nextEnabled: true,
            onNext: onNext
        ) {
            VStack(alignment: .leading, spacing: 28) {
                if Dictation.isSupported { sayIt }
                if flags.isOn(.aiFeedback), let id = session.dictationEventID {
                    AIFeedbackScale(eventID: id, feature: .fieldExtract, store: feedback)
                }
                sizeChips
                numbers
                if session.recipe == nil {
                    doing
                }
                RecipePickerList(
                    card: session.card,
                    method: session.brew.method,
                    size: session.size,
                    selected: session.recipe
                ) { recipe in
                    tapCount += 1
                    session.apply(recipe: recipe, setup: setup)
                }
            }
            .padding(.bottom, 24)
        }
        .haptic(.tap, trigger: tapCount)
        .onDisappear { dictation.cancel() }
    }

    private var sayIt: some View {
        SayItLabel(
            isListening: dictation.isListening,
            transcript: dictation.transcript,
            prompt: dictation.state == .unavailable ? Copy.dictationUnavailable : Copy.dictate,
            hint: dictationHint
        ) {
            Task { await toggleDictation() }
        }
        .guessHighlight(trigger: filledTrigger, onUndo: undoDictation)
    }

    private var dictationHint: String? {
        switch dictation.state {
        case .denied: "Dictation needs the microphone. Settings has the switch."
        case .unavailable: Copy.dictationUnavailable
        case .idle, .listening:
            "\"18 in, 250 of water, two forty-five, four stars\""
        }
    }

    private var sizeChips: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Format").catalogueLabel()
            FlowLayout {
                ForEach(RecipeSize.allCases) { size in
                    TagChip(
                        text: size.label,
                        isSelected: session.size == size
                    ) {
                        tapCount += 1
                        session.apply(size: size)
                    }
                }
            }
        }
    }

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Parameters").catalogueLabel()
            HStack(spacing: 0) {
                NumberRow(
                    Copy.coffeeDose,
                    value: $session.brew.dose,
                    unit: "g",
                    placeholder: Placeholders.text(.brewDose),
                    presence: .useful,
                    compactWidth: 70
                )
                DerivedValue(text: session.brew.ratio ?? "—")
                    .frame(maxWidth: .infinity)
                NumberRow(
                    session.brew.method == .espresso ? Copy.beverage : Copy.waterWeight,
                    value: outputBinding,
                    unit: "g",
                    placeholder: session.brew.method == .espresso
                        ? Placeholders.text(.brewBeverage)
                        : Placeholders.text(.brewWater),
                    presence: .useful,
                    compactWidth: 70
                )
            }
        }
    }

    private var outputBinding: Binding<Double?> {
        if session.brew.method == .espresso {
            return $session.brew.beverage
        }
        return $session.brew.water
    }

    private var doing: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Copy.whatYoureDoing).catalogueLabel()
            TextField(
                "Bloom, two pours, a swirl — whatever you are actually doing",
                text: $session.brew.notes,
                axis: .vertical
            )
            .font(Typography.body)
            .foregroundStyle(Palette.ink)
            .lineLimit(3...8)
            .focused($doingFocused)
            .reportsFieldFocus(doingFocused)
            DictationField(text: $session.brew.notes)
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
        beforeDictation = session.brew
        var result = SpokenBrewParser.parse(transcript)
        if result.confidence < 0.5, flags.isOn(.fieldExtract) {
            let context = "method: \(session.brew.method?.rawValue ?? "unknown")"
            if let outcome = await FieldExtract.brew(
                transcript: transcript,
                context: context,
                flags: flags,
                events: events
            ), !outcome.value.isEmpty {
                result = outcome.value
                session.dictationEventID = outcome.eventID
            }
        }
        guard !result.isEmpty || !result.leftover.isEmpty else { return }
        withAnimation(Motion.snappy) {
            SpokenBrewParser.apply(result, to: &session.brew)
            if let water = session.brew.water {
                session.size = RecipeSize.inferred(from: water)
            }
            filledTrigger += 1
        }
    }

    private func undoDictation() {
        guard let beforeDictation else { return }
        withAnimation(Motion.snappy) { session.brew = beforeDictation }
        self.beforeDictation = nil
        if let id = session.dictationEventID {
            events.setAccepted(false, for: id)
            session.dictationEventID = nil
        }
    }
}
