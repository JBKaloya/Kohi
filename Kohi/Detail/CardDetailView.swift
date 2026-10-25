import os
import SwiftUI

/// The card as an archival object: cut out, centred on paper, lit by a soft
/// shadow, with its catalogue entry set underneath.
struct CardDetailView: View {
    let card: CoffeeCard
    /// A recipe picked in the Recipes tab, which opens a brew already filled in.
    var seedRecipe: Recipe?
    /// The size that recipe was shown at, when it was scaled.
    var seedSize: RecipeSize?
    /// A shortcut sent you straight here to log something.
    var startsBrew = false
    /// Opened from Suggested, so the scroll lands on that section.
    var startsAtSuggested = false

    @Environment(CardStore.self) private var store
    @Environment(TastingStore.self) private var tastings
    @Environment(PlaceIndex.self) private var places
    @Environment(RecipeStore.self) private var recipes
    @Environment(SetupStore.self) private var setup
    @Environment(LotFlags.self) private var lotFlags
    @Environment(AIFlags.self) private var flags
    @Environment(CardLookStore.self) private var looks
    @Environment(StampLibrary.self) private var stamps
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var deleteTrigger = 0
    @State private var isEditing = false
    @State private var flow: BrewSession?
    @State private var isScanningAttachment = false
    @State private var isIngestingAttachment = false
    @State private var selectedAttachment: CardAttachment?
    @State private var openedRecipe: Recipe?
    @State private var showOriginal = false
    @State private var brewToCompare: Brew?
    @State private var isAsking = false
    @State private var showProfile = false
    @State private var rangeGrinder: Equipment?
    @State private var pendingDelete: (brew: Brew, index: Int)?
    @State private var undoToken = 0
    @State private var showFaceMenu = false
    @State private var showSymbolEditor = false
    @State private var openedTasting: Tasting?

    /// Reads through the store so edits made elsewhere show up here.
    private var live: CoffeeCard { store.card(id: card.id) ?? card }

    /// Closed and temporarily closed places say so. Open places stay quiet.
    private var placeTag: String? {
        if let id = live.placeID, let place = places.place(id: id) {
            return place.statusTag
        }
        if let name = live.place?.name, let match = places.match(name: name) {
            return match.statusTag
        }
        return nil
    }

    private var cardTitle: String { store.title(for: live) }

    /// The recipe to offer for this coffee, from the rules. Recomputed rather
    /// than stored: the answer changes as the coffee ages and as you log brews,
    /// and a stored suggestion would quietly go stale.
    ///
    /// Hidden once the card's own printed recipe is what the rules would pick
    /// anyway, since `BrewList` already shows that row.
    private var suggestion: RecipeSuggestion? {
        let result = RecipeRules.suggestion(
            for: live,
            mine: recipes.recipes,
            neighbours: store.cards
        )
        guard let result, result.provenance != .card else { return nil }
        return result
    }

    /// The suggested grind in your grinder's units, with the three states
    /// the brief asks for: clicks, no range, or add a grinder.
    private var forYourGrinder: ForYourGrinder {
        GrindConversion.forYourGrinder(
            recipe: suggestion?.recipe ?? Recipe(),
            grinder: suggestion.flatMap { setup.preferredGrinder(for: $0.recipe.method) },
            calibrations: setup.calibrations,
            shift: suggestion?.grindShift ?? 0
        )
    }

    private var forYourGrinderLine: String? {
        guard suggestion != nil else { return nil }
        return forYourGrinder.line
    }

    /// Opens the one brew journey, filled in from a recipe.
    private func use(_ recipe: Recipe, size: RecipeSize? = nil) {
        openFlow(recipe: recipe, size: size)
    }

    private func openFlow(
        recipe: Recipe? = nil,
        size: RecipeSize? = nil,
        existing: Brew? = nil,
        mode: BrewSession.Mode = .create,
        start: BrewSession.Step = .scope,
        lastApplication: BrewPrefill.LastApplication? = nil
    ) {
        flow = BrewSession(
            card: live,
            recipe: recipe,
            size: size,
            existing: existing,
            mode: mode,
            start: start,
            lastApplication: lastApplication,
            setup: setup
        )
    }

    private func deleteBrew(_ brew: Brew) {
        let index = live.brews.firstIndex { $0.id == brew.id } ?? 0
        pendingDelete = (brew, index)
        var updated = live
        updated.brews.removeAll { $0.id == brew.id }
        store.update(updated)
        deleteTrigger += 1
        undoToken += 1
        let token = undoToken
        Task {
            try? await Task.sleep(for: .seconds(5))
            if undoToken == token { pendingDelete = nil }
        }
    }

    private func restoreDeletedBrew() {
        guard let pending = pendingDelete else { return }
        undoToken += 1
        var updated = live
        let index = min(pending.index, updated.brews.count)
        updated.brews.insert(pending.brew, at: index)
        store.update(updated)
        pendingDelete = nil
    }

    private func openRead(_ brew: Brew) {
        let session = BrewSession(
            card: live,
            existing: brew,
            mode: .edit,
            start: .after,
            setup: setup
        )
        session.opensRead = true
        session.frozenCorrection = SuggestedCorrection.fallback(
            from: brew,
            card: live,
            equipment: setup.equipment,
            filterStock: setup.filterStock,
            tasting: TastingIntent.confirmed(from: brew.notes)
        )
        flow = session
    }

    private func openAgain(from brew: Brew) {
        let prepared = BrewPrefill.preparedAgain(from: brew, setup: setup)
        let recipe = brew.recipeSnapshot.map(Recipe.init(snapshot:))
        openFlow(
            recipe: recipe,
            existing: prepared.brew,
            start: .dial,
            lastApplication: prepared.application
        )
    }

    @ViewBuilder
    private var brewAndAsk: some View {
        if live.recipeSuggestion != nil || suggestion != nil {
            BrewRecipes(
                card: live,
                suggestion: suggestion,
                inYourTerms: forYourGrinderLine,
                onUseRecipe: live.recipeSuggestion == nil ? nil : {
                    if let printed = live.recipeSuggestion {
                        openFlow(recipe: RecipeRules.recipe(from: printed, card: live))
                    }
                },
                onOpenSuggestion: { openedRecipe = $0.recipe },
                onUseSuggestion: { use($0.recipe) },
                onSetGrindRange: {
                    if let grinder = setup.preferredGrinder(for: suggestion?.recipe.method) {
                        rangeGrinder = grinder
                    } else {
                        showProfile = true
                    }
                }
            )
        }

        TastingsBlock(
            card: live,
            tasted: tastings.tastings(forCard: live.id),
            onSelectBrew: { openFlow(existing: $0, mode: .edit, start: .after) },
            onAgain: { brew in openAgain(from: brew) },
            onCompare: lotFlags.isOn(.brewCompare) ? { brewToCompare = $0 } : nil,
            onDeleteBrew: { brew in deleteBrew(brew) },
            onRead: { brew in openRead(brew) },
            onOpenTasting: { openedTasting = $0 }
        )

        if pendingDelete != nil {
            Button("Undo") { restoreDeletedBrew() }
                .catalogueLabel()
                .padding(.top, 8)
        }

        kitPrompt

        if flags.isOn(.ask) {
            Button { isAsking = true } label: {
                HStack(spacing: 8) {
                    CoffeeCupIcon(size: 14, color: Palette.primary)
                    Text("Ask about this coffee")
                        .font(Typography.label)
                        .tracking(Typography.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.primary)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var kitPrompt: some View {
        if setup.kitIsEmpty {
            Button { showProfile = true } label: {
                Text("Set up your kit")
                    .catalogueLabel()
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let objectWidth = proxy.size.width * Motion.Object.widthFraction
            let kohiWidth = max(120, proxy.size.width - 56)

            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    tombstone
                        .padding(.horizontal, 28)
                        .padding(.top, 18)

                    VStack(spacing: 18) {
                        CardFaceStage(
                            card: live,
                            scanWidth: objectWidth,
                            kohiWidth: kohiWidth,
                            look: looks.resolved(live),
                            layout: looks.layout(for: live.id),
                            mark: stamps.mark(for: live.id),
                            ink: stamps.file(for: live.id),
                            onFlip: { looks.setOverride($0, for: live.id) }
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 52)

                    VStack(alignment: .leading, spacing: 30) {
                        Text(cardTitle)
                            .font(Typography.title)
                            .foregroundStyle(Palette.ink)

                        if !live.tastingNotes.isEmpty {
                            notes
                        }

                        if !live.declaredFlavors.isEmpty {
                            onTheWheel
                        }

                        CaptionBlock(card: live, placeTag: placeTag)

                        if !live.originalFields.isEmpty {
                            originalSection
                        }

                        brewAndAsk

                        if lotFlags.isOn(.cardProfile) {
                            CardProfile(card: live, tasted: tastings.tastings(forCard: live.id))
                        }

                        if !live.attachments.isEmpty || isIngestingAttachment {
                            attachmentSection
                        }

                        if !live.personalNotes.trimmingCharacters(in: .whitespaces).isEmpty {
                            personal
                        }

                        actions
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 72)
                }
            }
            .scrollIndicators(.hidden)
            .onAppear {
                guard startsAtSuggested else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(Motion.gentle) {
                        proxy.scrollTo("suggested-recipe", anchor: .top)
                    }
                }
            }
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                CatalogueBackButton(title: "COFFEES") { dismiss() }
                Spacer()
                Button { showFaceMenu = true } label: {
                    Text(Copy.cards)
                        .catalogueLabel()
                }
                .buttonStyle(.plain)
                .touchTarget()
            }
            .padding(.horizontal, 16)
            .background(Palette.paper)
        }
        .haptic(.deleted, trigger: deleteTrigger)
        .fullScreenCover(isPresented: $showSymbolEditor) {
            SymbolEditorView(card: live)
                .appEnvironment(appEnvironment)
        }
        .confirmationDialog(Copy.cards, isPresented: $showFaceMenu, titleVisibility: .visible) {
            Button(Copy.showTheScan) { looks.setOverride(.scan, for: live.id) }
            Button(Copy.showTheKohiCard) { looks.setOverride(.kohi, for: live.id) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showProfile) {
            ProfileSheet()
                .appEnvironment(appEnvironment)
        }
        .sheet(item: $rangeGrinder) { grinder in
            EquipmentSheet(equipment: grinder)
                .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $isAsking) {
            AskSheet(topic: cardTitle)
                .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $isEditing) {
            CardEditSheet(card: live, isNew: false) { store.update($0) }
                .appEnvironment(appEnvironment)
        }
        .navigationDestination(item: $openedTasting) { tasting in
            TastingDetailView(tastingID: tasting.id, opensCard: false)
                .appEnvironment(appEnvironment)
        }
        .task {
            if let seedRecipe {
                use(seedRecipe, size: seedSize)
            } else if startsBrew {
                openFlow()
            }
        }
        .sheet(item: $openedRecipe) { recipe in
            RecipeDetailSheet(
                recipe: recipe,
                adjustments: suggestion?.adjustments ?? [],
                provenance: suggestion?.provenance,
                forYourGrinder: forYourGrinder,
                card: live,
                onUse: { use($0, size: $1) }
            )
            .appEnvironment(appEnvironment)
        }
        .fullScreenCover(item: $flow) { session in
            BrewFlowHost(
                session: session,
                onDismiss: { flow = nil },
                onAgain: { seed in openAgain(from: seed) },
                onDelete: session.mode == .edit ? {
                    var updated = live
                    updated.brews.removeAll { $0.id == session.brew.id }
                    store.update(updated)
                    flow = nil
                } : nil
            )
            .appEnvironment(appEnvironment)
        }
        .sheet(item: $brewToCompare) { brew in
            BrewCompareSheet(
                card: live,
                reference: brew,
                others: store.cards,
                waters: setup.waterProfiles,
                equipment: setup.equipment,
                filterStock: setup.filterStock
            ) { seed in
                openAgain(from: seed)
            }
            .appEnvironment(appEnvironment)
        }
        .fullScreenCover(isPresented: $isScanningAttachment) {
            ScanScreen(
                onScan: { scan in
                    isScanningAttachment = false
                    isIngestingAttachment = true
                    Task { await ingestAttachment(scan) }
                },
                onCancel: { isScanningAttachment = false }
            )
            .appEnvironment(appEnvironment)
        }
        .sheet(item: $selectedAttachment) { attachment in
            AttachmentDetailSheet(cardID: live.id, attachment: attachment) {
                var updated = live
                updated.attachments.removeAll { $0.id == attachment.id }
                store.update(updated)
            }
        }
    }

    /// The small line the book pages put above the plate.
    private var tombstone: some View {
        Text(
            [cardTitle, live.originLine, live.altitude]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        )
        .catalogueLabel()
        .textCase(nil)
        .lineLimit(2)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .catalogueLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(live.tastingNotes, id: \.self) { note in
                        Text(note)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .overlay(
                                Capsule().stroke(Palette.hairline, lineWidth: 1)
                            )
                    }
                }
            }
        }
    }

    private var onTheWheel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On the wheel")
                .catalogueLabel()
            FlowLayout {
                ForEach(live.declaredFlavors) { tag in
                    Text(tag.displayName)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(
                            Capsule().stroke(Palette.hairline, lineWidth: 1)
                        )
                }
            }
        }
    }

    private var personal: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Note to self")
                .catalogueLabel()
            Text(live.personalNotes)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The card's own words, shown under the translated fields. "風味: 白花"
    /// stays reachable after the fields switched to English.
    private var originalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(Motion.snappy) { showOriginal.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(showOriginal ? "Hide original" : "Show original\(originalLanguageSuffix)")
                        .catalogueLabel()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Palette.inkMuted)
                        .rotationEffect(showOriginal ? .degrees(180) : .zero)
                }
            }
            .buttonStyle(.plain)

            if showOriginal {
                VStack(spacing: 0) {
                    ForEach(originalRows, id: \.label) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 20) {
                            Text(row.label)
                                .catalogueLabel()
                                .frame(width: 78, alignment: .leading)
                            Text(row.value)
                                .font(Typography.value)
                                .foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private var originalLanguageSuffix: String {
        switch live.sourceLanguage {
        case "ja": " (日本語)"
        case "zh": " (中文)"
        default: ""
        }
    }

    private var originalRows: [(label: String, value: String)] {
        let order: [(key: String, label: String)] = [
            ("name", "Coffee"), ("roaster", "Roaster"), ("country", "Country"),
            ("region", "Region"), ("producer", "Producer"), ("altitude", "Altitude"),
            ("variety", "Variety"), ("process", "Process"),
        ]
        var rows: [(String, String)] = order.compactMap { entry in
            live.originalFields[entry.key].map { (entry.label, $0) }
        }
        let notes = live.originalFields
            .filter { $0.key == "notes" || $0.key.hasPrefix("note:") }
            .sorted { $0.key < $1.key }
            .map(\.value)
        if !notes.isEmpty {
            rows.append(("Notes", notes.joined(separator: ", ")))
        }
        return rows
    }

    private var actions: some View {
        HStack(spacing: 22) {
            Button { isEditing = true } label: {
                Text("Edit")
                    .catalogueLabel()
                    .foregroundStyle(Palette.ink)
            }
            Button { showSymbolEditor = true } label: {
                Text(Copy.symbol)
                    .catalogueLabel()
                    .foregroundStyle(Palette.ink)
            }
            Button {
                deleteTrigger += 1
                dismiss()
                store.delete(live)
            } label: {
                Text("Remove from archive")
                    .catalogueLabel()
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    // MARK: - Attachments

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isIngestingAttachment {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text("Adding page")
                        .catalogueLabel()
                }
            }

            AttachmentStrip(
                cardID: live.id,
                attachments: live.attachments,
                onAdd: { isScanningAttachment = true },
                onSelect: { selectedAttachment = $0 }
            )
        }
    }

    private func ingestAttachment(_ scan: ScanResult) async {
        let cardID = live.id
        do {
            let attachment = try await Task.detached(priority: .userInitiated) {
                try await ImagePipeline.ingestAttachment(scan, cardID: cardID)
            }.value

            var updated = live
            updated.attachments.insert(attachment, at: 0)
            store.update(updated)

            withAnimation(Motion.snappy) {
                isIngestingAttachment = false
            }
        } catch {
            isIngestingAttachment = false
            Log.app.error("attachment ingest failed: \(error)")
        }
    }
}
