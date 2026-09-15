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
    @State private var brewToEdit: Brew?
    @State private var isAddingBrew = false
    @State private var isScanningAttachment = false
    @State private var isIngestingAttachment = false
    @State private var selectedAttachment: CardAttachment?
    /// Whether the next brew sheet opens pre-filled from the card's recipe.
    @State private var seedFromRecipe = false
    /// The recipe the next brew sheet starts from, when it is not the card's own.
    @State private var seedFromSuggestion: Recipe?
    @State private var seedFromSize: RecipeSize?
    @State private var openedRecipe: Recipe?
    @State private var showOriginal = false
    @State private var showMapPicker = false
    @State private var showingScan = false
    @State private var posterError: String?
    @State private var brewToCompare: Brew?
    @State private var brewAgainSeed: Brew?
    @State private var isAsking = false
    @State private var showProfile = false
    @State private var guided: GuidedSession?
    @State private var after: GuidedSession?

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

    /// Opens a brew filled in from a recipe.
    private func use(_ recipe: Recipe, size: RecipeSize? = nil) {
        var brew = recipe.seededBrew(size: size)
        brew.equipmentIDs = setup.defaults(for: recipe.method).map(\.id)
        guided = GuidedSession(card: live, recipe: recipe, brew: brew)
    }

    @ViewBuilder
    private var brewAndAsk: some View {
        if live.brews.isEmpty {
            suggestedSection
            kitPrompt
            Button {
                isAddingBrew = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Log a brew")
                        .font(Typography.tag)
                }
                .foregroundStyle(Palette.ink)
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        } else {
            BrewList(
                card: live,
                suggestion: suggestion,
                inYourTerms: forYourGrinderLine,
                onSelect: { brewToEdit = $0 },
                onAdd: { isAddingBrew = true },
                onUseRecipe: live.recipeSuggestion == nil ? nil : {
                    seedFromRecipe = true
                    isAddingBrew = true
                },
                onOpenSuggestion: { openedRecipe = $0.recipe },
                onUseSuggestion: { use($0.recipe) },
                onAgain: {
                    let brew = $0.again()
                    let recipe = $0.recipeSnapshot.map(Recipe.init(snapshot:))
                        ?? Recipe(method: $0.method ?? .v60, dose: $0.dose, water: $0.water, beverage: $0.beverage, temperature: $0.temperature, seconds: $0.seconds, grindLabel: $0.grind.display())
                    guided = GuidedSession(card: live, recipe: recipe, brew: brew)
                },
                onCompare: lotFlags.isOn(.brewCompare) ? { brewToCompare = $0 } : nil
            )
        }

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
    private var suggestedSection: some View {
        if let suggestion {
            VStack(alignment: .leading, spacing: 10) {
                Text("Suggested recipe")
                    .catalogueLabel()
                HStack(alignment: .top, spacing: 12) {
                    Button { openedRecipe = suggestion.recipe } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(suggestion.recipe.compactLine)
                                .font(Typography.tag)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            if let forYourGrinderLine {
                                Text(forYourGrinderLine)
                                    .font(Typography.tag)
                                    .foregroundStyle(Palette.inkMuted)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Button("Use") { use(suggestion.recipe) }
                        .font(Typography.tag)
                        .foregroundStyle(Palette.ink)
                        .touchTarget()
                        .buttonStyle(.plain)
                }
                Rectangle().fill(Palette.hairline).frame(height: 1)
            }
            .id("suggested-recipe")
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
                        .onTapGesture {
                            guard live.poster == .ready else { return }
                            withAnimation(Motion.snappy) { showingScan.toggle() }
                        }

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
            // Arriving from the Recipes tab: the recipe was already chosen, so
            // the brew sheet opens on top of the card rather than making you
            // find the button.
            if let seedRecipe {
                use(seedRecipe, size: seedSize)
            } else if startsBrew {
                isAddingBrew = true
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
        .fullScreenCover(item: $guided) { session in
            GuidedBrewView(
                card: session.card,
                recipe: session.recipe,
                brew: session.brew,
                onFinish: { brew in
                    guided = nil
                    after = GuidedSession(card: session.card, recipe: session.recipe, brew: brew)
                },
                onCancel: { guided = nil }
            )
            .appEnvironment(appEnvironment)
        }
        .sheet(item: $after) { session in
            AfterBrewSheet(card: session.card, recipe: session.recipe, draft: session.brew) { brew in
                var updated = live
                updated.brews.insert(brew, at: 0)
                store.update(updated)
            }
            .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $isAddingBrew, onDismiss: {
            seedFromRecipe = false
            seedFromSuggestion = nil
            seedFromSize = nil
            brewAgainSeed = nil
        }) {
            BrewSheet(
                card: live,
                brew: prefilled(),
                recipe: seedFromSuggestion,
                onSave: { brew in
                    var updated = live
                    updated.brews.insert(brew, at: 0)
                    store.update(updated)
                }
            )
            .appEnvironment(appEnvironment)
        }
        .sheet(item: $brewToEdit) { brew in
            BrewSheet(
                card: live,
                brew: brew,
                onSave: { edited in
                    var updated = live
                    if let i = updated.brews.firstIndex(where: { $0.id == edited.id }) {
                        updated.brews[i] = edited
                    }
                    store.update(updated)
                },
                onDelete: {
                    var updated = live
                    updated.brews.removeAll { $0.id == brew.id }
                    store.update(updated)
                }
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
                brewAgainSeed = seed.again()
                isAddingBrew = true
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

    /// Pre-fills a new brew from the card's printed recipe when asked, else
    /// from the most recent brew, so repeating a recipe is just a tap.
    private func prefilled() -> Brew {
        if let brewAgainSeed {
            return brewAgainSeed
        }
        if let seedFromSuggestion {
            return seedFromSuggestion.seededBrew(size: seedFromSize)
        }
        if seedFromRecipe, let recipe = live.recipeSuggestion {
            return Brew(
                method: recipe.method ?? live.brewMethod,
                dose: recipe.dose,
                water: recipe.water,
                seconds: recipe.seconds,
                grind: recipe.grind,
                temperature: recipe.temperature
            )
        }
        if let last = live.brews.first {
            if let saved = last.nextTimeSuggestion,
               let suggestion = BrewDiagnosis.candidates(for: last)
                   .first(where: { $0.change == saved }) {
                return BrewDiagnosis.draft(
                    from: last,
                    applying: suggestion,
                    grinder: setup.preferredGrinder(for: last.method)
                )
            }
            return last.again()
        }
        return Brew(method: live.brewMethod)
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
