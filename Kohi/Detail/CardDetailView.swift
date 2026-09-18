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
    @Environment(RecipeStore.self) private var recipes
    @Environment(SetupStore.self) private var setup
    @Environment(LotFlags.self) private var lotFlags
    @Environment(AIFlags.self) private var flags
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var deleteTrigger = 0
    @State private var isEditing = false
    @State private var flow: BrewSession?
    @State private var isScanningAttachment = false
    @State private var isIngestingAttachment = false
    @State private var selectedAttachment: CardAttachment?
    @State private var openedRecipe: Recipe?
    @State private var showOriginal = false
    @State private var showMapPicker = false
    @State private var showingScan = false
    @State private var posterError: String?
    @State private var brewToCompare: Brew?
    @State private var isAsking = false
    @State private var showProfile = false

    /// Reads through the store so edits made elsewhere show up here.
    private var live: CoffeeCard { store.card(id: card.id) ?? card }

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
        start: BrewSession.Step = .scope
    ) {
        flow = BrewSession(
            card: live,
            recipe: recipe,
            size: size,
            existing: existing,
            mode: mode,
            start: start,
            setup: setup
        )
    }

    @ViewBuilder
    private var brewAndAsk: some View {
        BrewList(
            card: live,
            suggestion: suggestion,
            inYourTerms: forYourGrinderLine,
            onSelect: { openFlow(existing: $0, mode: .edit, start: .after) },
            onAdd: { openFlow() },
            onUseRecipe: live.recipeSuggestion == nil ? nil : {
                if let printed = live.recipeSuggestion {
                    openFlow(recipe: RecipeRules.recipe(from: printed, card: live))
                }
            },
            onOpenSuggestion: { openedRecipe = $0.recipe },
            onUseSuggestion: { use($0.recipe) },
            onAgain: { brew in
                let recipe = brew.recipeSnapshot.map(Recipe.init(snapshot:))
                openFlow(recipe: recipe, existing: brew.again(), start: .kit)
            },
            onCompare: lotFlags.isOn(.brewCompare) ? { brewToCompare = $0 } : nil
        )

        kitPrompt

        if flags.isOn(.ask) {
            Button { isAsking = true } label: {
                Text("Ask about this coffee")
                    .catalogueLabel()
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

            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    tombstone
                        .padding(.horizontal, 28)
                        .padding(.top, 18)

                    VStack(spacing: 18) {
                        CardObject(
                            card: live,
                            width: objectWidth,
                            variant: showingScan ? .scan : .poster
                        )
                        .accessibilityLabel(showingScan || live.poster != .ready ? "Scan" : "Flyer")

                        if live.poster == .ready {
                            visualPicker
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 52)
                    .animation(Motion.snappy, value: showingScan)

                    VStack(alignment: .leading, spacing: 30) {
                        Text(cardTitle)
                            .font(Typography.title)
                            .foregroundStyle(Palette.ink)

                        if !live.tastingNotes.isEmpty {
                            notes
                        }

                        if lotFlags.isOn(.flavorWheel), !live.declaredFlavors.isEmpty {
                            onTheWheel
                        }

                        CaptionBlock(card: live) {
                            showMapPicker = true
                        }

                        if !live.originalFields.isEmpty {
                            originalSection
                        }

                        brewAndAsk

                        if lotFlags.isOn(.cardProfile) {
                            CardProfile(card: live)
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
            }
            .padding(.horizontal, 16)
            .background(Palette.paper)
        }
        .haptic(.deleted, trigger: deleteTrigger)
        .confirmationDialog("Open in", isPresented: $showMapPicker) {
            if let place = live.place {
                Button("Apple Maps") {
                    let q = place.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    let url = URL(string: "maps://?q=\(q)&ll=\(place.latitude),\(place.longitude)")!
                    openURL(url)
                }
                Button("Google Maps") {
                    let q = place.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    let gm = URL(string: "comgooglemaps://?q=\(q)&center=\(place.latitude),\(place.longitude)")!
                    let web = URL(string: "https://www.google.com/maps/search/?api=1&query=\(place.latitude),\(place.longitude)&query_place_id=\(q)")!
                    if UIApplication.shared.canOpenURL(gm) {
                        openURL(gm)
                    } else {
                        openURL(web)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileSheet()
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
                onAgain: { seed in
                    openFlow(existing: seed.again(), start: .kit)
                },
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
                equipment: setup.equipment
            ) { seed in
                openFlow(existing: seed.again(), start: .kit)
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
        .alert("Poster generation failed", isPresented: .init(
            get: { posterError != nil },
            set: { if !$0 { posterError = nil } }
        )) {
            Button("OK") { posterError = nil }
        } message: {
            Text(posterError ?? "")
        }
    }

    /// Flyer or the original scan. The home grid keeps the flyer; the plate
    /// here can flip so the archive image stays reachable.
    private var visualPicker: some View {
        HStack(spacing: 8) {
            TagChip(text: "Flyer", isSelected: !showingScan) {
                withAnimation(Motion.snappy) { showingScan = false }
            }
            TagChip(text: "Scan", isSelected: showingScan) {
                withAnimation(Motion.snappy) { showingScan = true }
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
            if CardPoster.isAvailable {
                Button { regeneratePoster() } label: {
                    Text(live.poster == .pending ? "Generating…" : "Regenerate poster")
                        .catalogueLabel()
                        .foregroundStyle(Palette.ink)
                }
                .disabled(live.poster == .pending)
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

    private func regeneratePoster() {
        let cardID = live.id
        var updated = live
        updated.poster = .pending
        store.update(updated)
        posterError = nil
        print("[card-poster] regeneratePoster: set pending for \(cardID)")
        Task {
            let success = await Task.detached(priority: .utility) {
                await CardPoster.generate(cardID: cardID)
            }.value
            print("[card-poster] regeneratePoster: generate returned \(success)")
            guard var latest = store.card(id: cardID) else {
                print("[card-poster] regeneratePoster: card not found in store!")
                return
            }
            latest.poster = success ? .ready : .failed
            store.update(latest)
            print("[card-poster] regeneratePoster: store updated → \(latest.poster)")
            if success {
                ThumbnailCache.shared.invalidate(cardID)
                ThumbnailCache.shared.warm(latest, buckets: ThumbnailCache.buckets)
            } else {
                posterError = "Generation failed. See console for '[card-poster]' logs."
            }
        }
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
