import os
import SwiftUI

/// After the pour: the note. What you did, how the cup was, a comment.
/// What to change next time is the next screen, reachable again from every
/// past brew; nothing here asks for it.
struct AfterBrewSheet: View {
    @Bindable var session: BrewSession
    var onSave: () -> Void
    var onDelete: (() -> Void)?
    /// Compare can still start a cup from one of the two brews. The note
    /// itself has no Brew again: that button lives on For next time.
    var onBrewFromCompare: ((Brew) -> Void)? = nil
    var onBack: () -> Void

    @Environment(SetupStore.self) private var setup
    @Environment(RecipeStore.self) private var recipes
    @Environment(CardStore.self) private var store
    @Environment(AIFlags.self) private var flags
    @Environment(AIEventLog.self) private var events
    @Environment(LotFlags.self) private var lotFlags
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var showCompare = false
    @State private var showStepEditor = false
    @State private var tapCount = 0
    @State private var saveTrigger = 0
    @State private var savedAsRecipe = false
    @State private var completenessTrigger = 0
    @State private var voiceNoteTrigger = 0
    @State private var brewBeforeVoice: Brew?
    @State private var isTranscribingNote = false
    @State private var voiceTranscript = ""
    @FocusState private var timeFocused: Bool
    @FocusState private var commentFocused: Bool
    @State private var fieldFocused = false
    @State private var isEditingSaved = false
    @State private var droppedTasting: Set<String> = []
    @State private var editingTasting = false
    @State private var acceptedNarration: Set<String> = []
    @State private var addingCoffee = false
    /// Live: the dictation gave no step, so the clock stands for the brew.
    @State private var nothingHeard = false
    @State private var liveDraft: Recipe?
    @AppStorage(PourSplit.countsBloomKey) private var countsBloom = true

    private var card: CoffeeCard { session.card }
    private var isLocked: Bool { session.mode == .edit && !isEditingSaved }

    var body: some View {
        StepFlow(
            step: session.progressIndex,
            total: session.progressTotal,
            question: Copy.itsDone,
            onBack: onBack,
            onClose: nil,
            primaryTitle: "Save",
            onPrimary: save
        ) {
            VStack(alignment: .leading, spacing: 28) {
                if isLocked { unlock }
                Text(session.brew.completeness.tag)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .onTapGesture { completenessTrigger += 1 }
                Group {
                    if !session.hasCard { coffeeRow }
                    summary
                    saveAsRecipe
                    if session.isLive { stepsHeard } else { whatYouDid }
                }
                .disabled(isLocked)
                sensory
                Group {
                    comment
                    tastingUnderstood
                    more
                    dateSection
                }
                .disabled(isLocked)
                if onDelete != nil { deleteButton }
            }
            .padding(.bottom, 24)
        }
        .onPreferenceChange(FieldFocusPreference.self) { fieldFocused = $0 }
        .animation(Motion.snappy, value: fieldFocused)
        .haptic(.tap, trigger: tapCount)
        .haptic(.saved, trigger: saveTrigger)
        .task {
            #if DEBUG
            if DebugHooks.keyboardRepro == "after" {
                try? await Task.sleep(for: .milliseconds(800))
                showStepEditor = true
            }
            #endif
            await transcribeVoiceNoteIfNeeded()
        }
        .sheet(isPresented: $showCompare) {
            if let appEnvironment {
                BrewCompareSheet(
                    card: card,
                    reference: session.brew,
                    others: store.cards,
                    waters: setup.waterProfiles,
                    equipment: setup.equipment,
                    filterStock: setup.filterStock
                ) { seed in
                    onBrewFromCompare?(seed)
                }
                .appEnvironment(appEnvironment)
            }
        }
        .sheet(isPresented: $addingCoffee) {
            LinkCoffeeSheet(coffee: toldCoffee) { linked in
                session.link(to: linked, store: store)
            }
            .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $showStepEditor) {
            StepBuilderSheet(draft: editedRecipe) { recipe in
                applyEdited(recipe)
                showStepEditor = false
            }
            .appEnvironment(appEnvironment)
        }
        .sheet(item: $liveDraft) { draft in
            StepBuilderSheet.creation(draft: draft) { recipe in
                var mine = recipe
                mine.source = .mine
                if !session.hasCard { mine.cardID = nil }
                recipes.add(mine)
                session.brew.recipeID = mine.id
                savedAsRecipe = true
                liveDraft = nil
            }
            .appEnvironment(appEnvironment)
        }
    }

    /// A saved brew opens read-only. One tap opens all of it, counters included.
    private var unlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Copy.savedTapToEdit)
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
            Button {
                tapCount += 1
                isEditingSaved = true
            } label: {
                Label(Copy.editThisBrew, systemImage: "pencil")
                    .font(Typography.value)
                    .foregroundStyle(Palette.ink)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    /// Under the summary: what you just did can be the recipe next time.
    @ViewBuilder
    private var saveAsRecipe: some View {
        if session.isLive {
            if !session.brew.actualSteps.isEmpty, !isTranscribingNote {
                VStack(alignment: .leading, spacing: 4) {
                    Button(savedAsRecipe ? "Saved as a recipe" : Copy.saveAsRecipe) {
                        guard !savedAsRecipe else { return }
                        tapCount += 1
                        liveDraft = RecipeCreation.fromLive(
                            brew: session.brew,
                            family: session.tab(in: setup),
                            card: session.hasCard ? card : nil,
                            countsBloom: countsBloom
                        )
                    }
                    .font(Typography.value)
                    .foregroundStyle(savedAsRecipe ? Palette.inkMuted : Palette.ink)
                    .frame(minHeight: 44)
                    .disabled(savedAsRecipe)
                    Text(Copy.keepTheseSteps)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
        } else if session.brew.dose != nil, session.brew.water != nil || session.brew.beverage != nil {
            VStack(alignment: .leading, spacing: 4) {
                Button(savedAsRecipe ? "Saved as a recipe" : "Save as recipe") {
                    guard !savedAsRecipe else { return }
                    tapCount += 1
                    var saved = recipes.save(brew: session.brew, from: card)
                    if !session.hasCard {
                        saved.cardID = nil
                        recipes.update(saved)
                    }
                    session.brew.recipeID = saved.id
                    savedAsRecipe = true
                }
                .font(Typography.value)
                .foregroundStyle(savedAsRecipe ? Palette.inkMuted : Palette.ink)
                .frame(minHeight: 44)
                .disabled(savedAsRecipe)
                Text(Copy.keepTheseSteps)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
        }
    }

    /// Only on a brew started without a coffee. The brew saves either way.
    private var coffeeRow: some View {
        Button { addingCoffee = true } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(Copy.coffee).catalogueLabel()
                Spacer()
                if let name = session.coffeeTitle {
                    Text(name)
                        .font(Typography.value)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                }
                Text(Copy.addTheCoffee).catalogueLabel(missing: true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var toldCoffee: Binding<TastedCoffee> {
        Binding(
            get: { session.brew.coffee ?? TastedCoffee() },
            set: { session.brew.coffee = $0 }
        )
    }

    private var summary: some View {
        FieldGroup(title: "Summary") {
            VStack(alignment: .leading, spacing: 16) {
                RollingCounter(Copy.coffeeDose, value: $session.brew.dose, range: .dose, unit: "g", style: .brew)
                RollingCounter(
                    session.brew.method == .espresso ? Copy.beverage : Copy.waterWeight,
                    value: session.brew.method == .espresso ? $session.brew.beverage : $session.brew.water,
                    range: session.brew.method == .espresso ? .beverage : .water,
                    unit: "g",
                    style: .brew
                )
                HStack {
                    Text("Ratio").catalogueLabel()
                    Spacer()
                    DerivedValue(text: session.brew.ratio ?? "—")
                }
                KitSummaryRow(session: session, correcting: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Grind").catalogueLabel()
                    GrindRail(
                        setting: $session.brew.grind,
                        grinder: grindGrinder,
                        method: session.brew.method
                    ) { tapCount += 1 }
                }
                timeRow
                RollingCounter("Temp", value: $session.brew.temperature, range: .temperature, unit: "°C", style: .row)
            }
        }
    }

    private var whatYouDid: some View {
        InsightBlock(
            title: Copy.whatYouDid,
            bodyText: whatYouDidReading,
            provenance: session.brew.actualSource.provenance,
            accessory: {
                Button("Edit") { showStepEditor = true }
                    .catalogueLabel()
            }
        ) {
            let rows = session.brew.actualSteps.isEmpty ? session.brew.plannedSteps : session.brew.actualSteps
            let muted = session.brew.actualSource == .none
            VStack(alignment: .leading, spacing: 8) {
                if isTranscribingNote {
                    Text(Copy.transcribingBrewNote).catalogueLabel()
                    ShimmerBar()
                }
                if !voiceTranscript.isEmpty || session.voiceNote.hasFile {
                    TextField("What you said", text: $voiceTranscript, axis: .vertical)
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2...8)
                    if !narrationLines.isEmpty {
                        Text("What we understood")
                            .catalogueLabel()
                        ForEach(narrationLines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(line.summary)
                                    .font(Typography.tag)
                                    .foregroundStyle(Palette.inkMuted)
                                Spacer(minLength: 8)
                                Button(acceptedNarration.contains(line.id) ? "Confirmed" : "Confirm") {
                                    if acceptedNarration.contains(line.id) {
                                        acceptedNarration.remove(line.id)
                                    } else {
                                        acceptedNarration.insert(line.id)
                                    }
                                }
                                .catalogueLabel()
                            }
                        }
                    }
                }
                ForEach(rows) { step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(step.action.label)
                            .catalogueLabel()
                        if let mass = step.mass ?? step.targetMass {
                            Text("\(GrindRange.number(mass)) g")
                                .font(Typography.value)
                                .foregroundStyle(muted ? Palette.inkMuted : Palette.ink)
                        }
                        Spacer()
                        Text(String(format: "%d:%02d", step.at / 60, step.at % 60))
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                        if let delta = step.timingDelta, session.brew.actualSource != .none {
                            Text(delta)
                                .font(Typography.tag)
                                .foregroundStyle(Palette.ink)
                        }
                        if step.skipped {
                            Text("skipped")
                                .font(Typography.tag)
                                .foregroundStyle(Palette.inkMuted)
                        }
                    }
                }
            }
        }
    }

    /// Live: what the dictation gave, each step at the time it was said.
    /// A step can be removed here; Edit opens the full editor.
    private var stepsHeard: some View {
        InsightBlock(
            title: Copy.stepsHeard,
            bodyText: stepsHeardReading,
            provenance: ActualSource.narration.label,
            accessory: {
                Button("Edit") { showStepEditor = true }
                    .catalogueLabel()
            }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if isTranscribingNote {
                    Text(Copy.transcribingBrewNote).catalogueLabel()
                    ShimmerBar()
                }
                if !voiceTranscript.isEmpty {
                    TextField("What you said", text: $voiceTranscript, axis: .vertical)
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2...8)
                }
                ForEach(session.brew.actualSteps) { step in
                    HeardStepRow(step: step) {
                        tapCount += 1
                        withAnimation(Motion.snappy) {
                            session.brew.actualSteps.removeAll { $0.id == step.id }
                            session.brew.refreshPourRates()
                        }
                    }
                }
                if let split = LiveSteps.split(of: session.brew, countsBloom: countsBloom) {
                    Text(countsBloom ? "Split · bloom counted" : "Split · bloom left out")
                        .catalogueLabel()
                        .padding(.top, 6)
                    SplitBar(shares: split.services.map(\.share))
                    Text(zip(split.services, split.percents).map { "\($0.action.label) \($1) %" }.joined(separator: " · "))
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
        }
    }

    private var stepsHeardReading: String {
        if isTranscribingNote { return Copy.transcribingBrewNote }
        if nothingHeard { return Copy.nothingHeard }
        let count = session.brew.actualSteps.count
        return count == 1 ? "One step" : "\(count) steps"
    }

    private var whatYouDidReading: String {
        switch session.brew.actualSource {
        case .none:
            return Copy.defaultSequenceNotConfirmed
        case .narration:
            return "Narrated"
        case .edited:
            return "Edited"
        case .timer:
            let count = session.brew.deviations.filter(\.isMaterial).count
            if count == 0 { return Copy.followedThePlan }
            if count == 1 { return "Followed the plan, with one deviation" }
            return "Followed the plan, with \(count) deviations"
        }
    }

    private var editedRecipe: Recipe {
        var recipe = RecipeRules.recipe(
            from: session.brew,
            card: card,
            source: .express,
            name: session.brew.recipeName
        )
        if recipe.steps.isEmpty {
            recipe.steps = session.brew.plannedSteps.map {
                RecipeStep(
                    at: $0.at,
                    action: $0.action,
                    targetMass: $0.mass ?? $0.targetMass,
                    untilSeconds: $0.targetAt,
                    note: $0.note,
                    agitation: $0.agitation
                )
            }
        }
        if recipe.name.isEmpty {
            recipe.name = Recipe.expressTitle(family: session.tab(in: setup))
        }
        return recipe
    }

    private func applyEdited(_ recipe: Recipe) {
        session.brew.actualSteps = recipe.steps.enumerated().map { index, step in
            BrewStep(
                index: index,
                action: step.action,
                at: step.at,
                mass: step.targetMass,
                targetAt: step.at,
                targetMass: step.targetMass,
                note: step.note,
                agitation: step.agitation
            )
        }
        session.brew.recipeName = recipe.name
        session.brew.actualSource = .edited
        session.brew.refreshPourRates()
    }

    private var sensory: some View {
        SensoryEvaluationSection(
            ratingHalves: $session.brew.ratingHalves,
            taste: $session.brew.taste,
            flavors: $session.brew.flavors,
            previousTaste: previousTaste,
            previousCaption: Copy.previousBrewIsLighter,
            declared: card.declaredFlavors,
            recent: recentFlavors,
            enabled: !isLocked
        ) { tapCount += 1 }
        .completenessPulse(.rating, completeness: session.brew.completeness, trigger: completenessTrigger)
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

    private var comment: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Copy.comment).catalogueLabel()
            TextField(Placeholders.text(.brewNotes), text: $session.brew.notes, axis: .vertical)
                .font(Typography.body)
                .lineLimit(2...6)
                .focused($commentFocused)
                .reportsFieldFocus(commentFocused)
                .guessHighlight(trigger: voiceNoteTrigger, onUndo: undoVoiceNote)
            DictationField(text: $session.brew.notes, vocabulary: {
                CoffeeLexicon.brew(
                    session.brew,
                    recipe: session.recipe,
                    equipment: setup.equipment,
                    filters: setup.filterStock
                )
            })
        }
    }

    private var timeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Time").catalogueLabel()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            TextField(
                "",
                text: timeBinding,
                prompt: Text(Placeholders.text(.brewTime)).foregroundStyle(Palette.hairline)
            )
            .formValue()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
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
            RollingCounter(
                "TDS",
                value: $session.brew.tds,
                range: .brewTDS,
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

    private var confirmedTasting: [TastingIntent] {
        TastingIntent.confirmed(from: session.brew.notes, dropping: droppedTasting)
    }

    private var tastingUnderstood: some View {
        let note = session.brew.notes
        let line = TastingIntent.understoodLine(for: note, dropping: droppedTasting)
        return VStack(alignment: .leading, spacing: 8) {
            if let line {
                Button {
                    editingTasting.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Text(line)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.inkMuted)
                    }
                }
                .buttonStyle(.plain)
            }
            if editingTasting {
                ForEach(TastingIntent.extract(note)) { intent in
                    Button(droppedTasting.contains(intent.id) ? "Restore \(intent.axis.rawValue)" : "Not \(intent.axis.rawValue)") {
                        if droppedTasting.contains(intent.id) {
                            droppedTasting.remove(intent.id)
                        } else {
                            droppedTasting.insert(intent.id)
                        }
                    }
                    .catalogueLabel()
                }
            }
        }
    }

    private var narrationLines: [NarrationDeviation] {
        NarrationDeviation.parse(voiceTranscript) + NarrationDeviation.clockNotes(
            in: voiceTranscript,
            steps: session.brew.actualSteps
        )
    }

    private func save() {
        saveTrigger += 1
        TastingIntent.prefill(&session.brew, from: confirmedTasting)
        let frozen = SuggestedCorrection.fallback(
            from: session.brew,
            card: card,
            equipment: setup.equipment,
            filterStock: setup.filterStock,
            tasting: confirmedTasting
        )
        session.frozenCorrection = frozen
        let spoken = NarrationDeviation.parse(voiceTranscript)
            .filter { acceptedNarration.contains($0.id) }
        if !spoken.isEmpty {
            NarrationDeviation.apply(spoken, to: &session.brew)
        }
        DictationArchive.shared.keep(
            editedSteps: LiveSteps.timed(session.brew.actualSteps),
            brewID: session.brew.id
        )
        onSave()
    }

    /// Live with nothing to read: one step for the whole clock.
    private func settleLive(_ heard: [SpokenBrewParser.TimedStep], nothingHeard: Bool) {
        guard session.isLive, session.mode == .create else { return }
        self.nothingHeard = nothingHeard
        LiveSteps.apply(heard, to: &session.brew)
    }

    private func settleSilentLive() {
        guard session.isLive, session.brew.actualSteps.isEmpty else { return }
        settleLive(
            LiveSteps.fallback(seconds: session.brew.seconds, water: session.brew.water),
            nothingHeard: true
        )
    }

    private func transcribeVoiceNoteIfNeeded() async {
        guard session.voiceNote.hasFile else {
            settleSilentLive()
            return
        }
        isTranscribingNote = true
        defer {
            isTranscribingNote = false
            settleSilentLive()
        }
        do {
            let sharing = lotFlags.isOn(.shareDictations)
            var stash: UUID?
            let lexicon = SpokenLexicon.terms(
                brew: session.brew,
                recipe: session.recipe,
                equipment: setup.equipment,
                filters: setup.filterStock
            )
            let outcome = try await session.voiceNote.transcribe(
                keepAudio: lotFlags.isOn(.keepVoiceNote),
                contextualStrings: Array((SpokenLexicon.stepWords + lexicon).prefix(100))
            ) { url, _ in
                stash = DictationArchive.shared.stash(audio: url, sharing: sharing)
            }
            let spoken = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let timed = SpokenBrewParser.timedSteps(
                phrases: outcome.phrases,
                water: session.brew.water,
                rewrite: { SpokenLexicon.rewrite($0, terms: lexicon) }
            )
            DictationArchive.shared.record(
                id: stash,
                outcome: outcome,
                context: session.isLive ? .live : .afterBrew,
                brewID: session.brew.id,
                recipeID: session.recipe?.id,
                parsed: DictationRecord.Parsed(
                    steps: timed,
                    result: SpokenBrewParser.parse(spoken, waters: setup.waterProfiles, filters: setup.filterStock)
                )
            )
            guard !spoken.isEmpty else { return }
            let terms = lexicon
            let rewritten = SpokenLexicon.rewrite(spoken, terms: terms)
            brewBeforeVoice = session.brew
            let parsed = SpokenBrewParser.parse(
                rewritten,
                waters: setup.waterProfiles,
                filters: setup.filterStock
            )
            SpokenBrewParser.apply(parsed, to: &session.brew, appendLeftover: false)
            session.brew.notes = DictationTranscript.apply(rewritten, to: brewBeforeVoice?.notes ?? "")
            voiceTranscript = rewritten
            if session.isLive {
                if timed.isEmpty {
                    settleLive(
                        LiveSteps.fallback(seconds: session.brew.seconds, water: session.brew.water),
                        nothingHeard: true
                    )
                } else {
                    settleLive(timed, nothingHeard: false)
                }
            } else if session.brew.actualSource == .timer || session.brew.actualSource == .none {
                session.brew.actualSource = .narration
                session.brew.refreshPourRates()
            }
            voiceNoteTrigger += 1
            if let tidied = await FieldExtract.tidy(
                transcript: rewritten,
                terms: terms,
                flags: flags,
                events: events
            ), tidied != rewritten {
                voiceTranscript = tidied
                session.brew.notes = DictationTranscript.apply(tidied, to: brewBeforeVoice?.notes ?? "")
            }
        } catch {
            Log.app.notice("voice note transcription: \(error)")
        }
    }

    private func undoVoiceNote() {
        guard let brewBeforeVoice else { return }
        withAnimation(Motion.snappy) { session.brew = brewBeforeVoice }
        self.brewBeforeVoice = nil
        voiceTranscript = ""
    }
}
