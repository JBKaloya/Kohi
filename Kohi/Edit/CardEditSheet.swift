import os
import SwiftUI
import Translation

/// The one form in the app. Quiet rows, quick picks where a card has a small
/// vocabulary, free text everywhere else.
struct CardEditSheet: View {
    @State private var draft: CoffeeCard
    private let isNew: Bool
    private let extract: (@Sendable () async -> ParsedFields)?
    private let onSave: (CoffeeCard) -> Void
    private let onDiscard: (() -> Void)?

    @Environment(RoasterStore.self) private var roasters
    @Environment(AccountStore.self) private var account
    @Environment(LotFlags.self) private var lotFlags
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var isReading = false
    @State private var readOutcome: ReadOutcome = .none
    @State private var isSearchingPlace = false
    @State private var saveTrigger = 0
    @State private var isScanningAttachment = false
    @State private var isIngestingAttachment = false
    @State private var attachmentReadingID: UUID?
    /// The bag group starts closed, and opens itself when the scan found
    /// something in it.
    @State private var isAddingRoaster = false
    /// Non-nil starts an on-device translation of the CJK fields.
    @State private var translationConfig: TranslationSession.Configuration?
    /// New cards only: generate the stamp flyer after save. Washed vs plain
    /// scan is chosen earlier, on the review screen.
    @State private var generateFlyer = true

    @State private var dictation = Dictation()
    @State private var dictatedTrigger = 0
    @State private var notesBeforeDictation: String?

    /// What the scan turned up, once the read has finished. Only the two
    /// unhelpful cases are worth saying out loud.
    private enum ReadOutcome {
        case none
        /// Barely any text on the image, so probably not a card at all.
        case notACard
        /// Text, but nothing this parser recognised as a field.
        case unreadable
    }

    /// A label has more lines than this even when it is sparse. Below it, the
    /// photo is a wall, a cup, or a thumb over the lens.
    private static let cardLineFloor = 4

    init(
        card: CoffeeCard,
        isNew: Bool,
        extract: (@Sendable () async -> ParsedFields)? = nil,
        onSave: @escaping (CoffeeCard) -> Void,
        onDiscard: (() -> Void)? = nil
    ) {
        _draft = State(initialValue: card)
        self.isNew = isNew
        self.extract = extract
        self.onSave = onSave
        self.onDiscard = onDiscard
    }

    private static let processPicks = [
        "Washed", "Natural", "Honey", "Anaerobic", "Carbonic Maceration", "Wet Hulled",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    if readOutcome != .none, !isReading {
                        readNotice
                    }

                    if isNew, CardPoster.isAvailable {
                        flyerPicker
                    }

                    FieldGroup(title: "Card") {
                        field("Coffee", text: $draft.name, placeholder: Placeholders.text(.cardCoffee), presence: .useful)
                        roasterField
                        field("Process", text: $draft.process, placeholder: Placeholders.text(.cardProcess), presence: .useful)
                        FlowLayout {
                            ForEach(Self.processPicks, id: \.self) { pick in
                                TagChip(text: pick, isSelected: draft.process == pick) {
                                    draft.process = draft.process == pick ? "" : pick
                                }
                            }
                        }
                    }

                    FieldGroup(title: "Origin") {
                        field("Country", text: $draft.country, placeholder: Placeholders.text(.cardCountry))
                        field("Region", text: $draft.region, placeholder: Placeholders.text(.cardRegion))
                        field("Producer", text: $draft.producer, placeholder: Placeholders.text(.cardProducer))
                        field("Altitude", text: $draft.altitude, placeholder: Placeholders.text(.cardAltitude))
                        field("Variety", text: $draft.variety, placeholder: Placeholders.text(.cardVariety))
                    }

                    if !isReading, CardVision.isAvailable {
                        rescanButton
                    }

                    FieldGroup(title: "Tasting notes") {
                        TagField(tags: $draft.tastingNotes)
                        if lotFlags.isOn(.flavorWheel) {
                            matchToWheel
                        }
                    }

                    FieldGroup(title: Copy.onTheBag) {
                        roastLevelPicker
                        NumberRow("Agtron", value: $draft.agtron, unit: "", labelWidth: 74)
                        roastedOnRow
                        group("Date") {
                            DatePicker("", selection: $draft.date, displayedComponents: .date)
                                .labelsHidden()
                        }
                        priceRow
                        bagWeightPicker
                    }

                    FieldGroup(title: "Lot") {
                        field("Lot", text: bagText(\.lot), placeholder: Placeholders.text(.bagLot))
                        field("Harvest", text: bagText(\.harvest), placeholder: Placeholders.text(.bagHarvest))
                        NumberRow(
                            "Cupping",
                            value: $draft.cuppingScore,
                            unit: "pts",
                            placeholder: Placeholders.text(.bagCupping),
                            labelWidth: 74
                        )
                        field("Farm", text: bagText(\.farm))
                        field("Station", text: bagText(\.washStation))
                        productURLRow
                        decafToggle
                        if draft.isDecaf { decafMethodPicker }
                    }

                    FieldGroup(title: "Brew method") {
                        FlowLayout {
                            ForEach(BrewMethod.allCases) { method in
                                TagChip(text: method.label, isSelected: draft.brewMethod == method) {
                                    draft.brewMethod = draft.brewMethod == method ? nil : method
                                }
                            }
                        }
                    }

                    if let recipe = draft.recipeSuggestion {
                        recipeSection(recipe)
                    }

                    attachmentSection

                    FieldGroup(title: Copy.boughtAt) {
                        placeRow
                        placeTypePicker
                    }

                    FieldGroup(title: Copy.noteToSelf) {
                        TextField(Placeholders.text(.cardNoteToSelf), text: $draft.personalNotes, axis: .vertical)
                            .font(Typography.body)
                            .lineLimit(3...8)
                            .guessHighlight(trigger: dictatedTrigger, onUndo: undoDictation)
                        DictationField(text: $draft.personalNotes)
                    }

                    if let onDiscard {
                        Button {
                            onDiscard()
                            dismiss()
                        } label: {
                            Text(isNew ? "Discard this scan" : "Remove from archive")
                                .catalogueLabel()
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 14)
                .padding(.bottom, 60)
                .fieldKeyboardClearance()
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(isNew ? "New card" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // A new card confirms itself by landing in the grid a
                        // moment later; a second haptic here steps on it.
                        if !isNew { saveTrigger += 1 }
                        if isNew {
                            draft.poster = generateFlyer && CardPoster.isAvailable ? .pending : .none
                        }
                        matchRoasterIfObvious()
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
            .sheet(isPresented: $isSearchingPlace) {
                PlaceSearchView(place: $draft.place)
            }
            .sheet(isPresented: $isAddingRoaster) {
                RoasterSheet(name: draft.roaster) { created in
                    link(created)
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
        }
        .tint(Palette.ink)
        .haptic(.saved, trigger: saveTrigger)
        .task { await prefill() }
        // Dismissing the sheet mid-sentence must not leave the microphone on.
        .onDisappear { dictation.cancel() }
        .translationTask(translationConfig) { session in
            if let translated = await FieldTranslator.translate(draft, using: session) {
                withAnimation(Motion.snappy) { draft = translated }
            }
        }
    }

    // MARK: - Pieces

    private func group(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).catalogueLabel()
            content()
        }
    }

    /// Label always visible beside the value, matching the detail view's
    /// catalogue block. Shows a shimmer skeleton while the OCR read is in
    /// progress and the field has not been filled yet.
    private func field(
        _ label: String,
        text: Binding<String>,
        placeholder: String = "",
        presence: FieldPresence = .optional
    ) -> some View {
        TextRow(
            label: label,
            text: text,
            placeholder: placeholder,
            labelWidth: 74,
            presence: presence,
            isPending: isReading && text.wrappedValue.isEmpty
        )
    }

    private func row(
        _ label: String,
        presence: FieldPresence = .optional,
        isEmpty: Bool = false,
        @ViewBuilder content: () -> some View
    ) -> some View {
        FormField(
            label: label,
            labelWidth: 74,
            presence: presence,
            isEmpty: isEmpty
        ) {
            content()
        }
    }

    // MARK: - Origin
    // MARK: - Roaster

    /// The roaster field, with the shared index offered underneath.
    ///
    /// The typed text stays authoritative: picking a suggestion sets
    /// `roasterId` and normalises the spelling, but declining to pick costs
    /// nothing. Offline, this is just a text field, and the match happens on
    /// the next sync.
    private var roasterField: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("Roaster", text: $draft.roaster, placeholder: Placeholders.text(.cardRoaster), presence: .useful)

            if let linked = draft.roasterId.flatMap({ roasters.roaster(id: $0) }) {
                HStack(spacing: 6) {
                    Text(linked.summary)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(1)
                    Button {
                        draft.roasterId = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Palette.inkMuted)
                    }
                    .buttonStyle(.plain)
                }
            } else if !roasterSuggestions.isEmpty {
                FlowLayout {
                    ForEach(roasterSuggestions) { roaster in
                        TagChip(text: roaster.name) { link(roaster) }
                    }
                }
            } else if canAddRoaster {
                Button {
                    isAddingRoaster = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Add \(draft.roaster) to the index")
                            .font(Typography.tag)
                    }
                    .foregroundStyle(Palette.inkMuted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var roasterSuggestions: [Roaster] {
        guard draft.roasterId == nil else { return [] }
        return roasters.suggestions(for: draft.roaster)
    }

    /// Offered only once the name is worth indexing and the index does not
    /// already know it.
    private var canAddRoaster: Bool {
        let name = draft.roaster.trimmingCharacters(in: .whitespaces)
        guard name.count >= 3, draft.roasterId == nil else { return false }
        return roasters.match(name: name, country: "") == nil
    }

    private func link(_ roaster: Roaster) {
        withAnimation(Motion.snappy) {
            draft.roasterId = roaster.id
            draft.roaster = roaster.name
        }
    }

    /// On save, link the card when the index knows exactly one roastery by
    /// that name. Anything less certain is left alone: a wrong link is worse
    /// than no link, and the card still reads correctly either way.
    private func matchRoasterIfObvious() {
        guard draft.roasterId == nil, !draft.roaster.isEmpty else { return }
        guard let match = roasters.match(name: draft.roaster, country: "") else { return }
        draft.roasterId = match.id
    }

    private var placeRow: some View {
        Button {
            isSearchingPlace = true
        } label: {
            row("Place", presence: .useful, isEmpty: draft.place == nil) {
                Text(draft.place?.summary ?? Placeholders.text(.cardPlace))
                    .font(Typography.value)
                    .foregroundStyle(draft.place == nil ? Palette.hairline : Palette.ink)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    /// Scan stays on the shelf, or an AI flyer is generated after save.
    /// Washed / not washed is the review-screen filter, not this choice.
    private var flyerPicker: some View {
        group("On the shelf") {
            FlowLayout {
                TagChip(text: "Scan", isSelected: !generateFlyer) {
                    generateFlyer = false
                }
                TagChip(text: "AI flyer", isSelected: generateFlyer) {
                    generateFlyer = true
                }
            }
            Text(
                generateFlyer
                    ? "A 4:5 stamp flyer is generated after save. A couple of minutes."
                    : "The scan — washed or not — stays on the home grid."
            )
            .font(Typography.tag)
            .foregroundStyle(Palette.inkMuted)
        }
    }

    private var readNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(Palette.inkMuted)
            Text(
                readOutcome == .notACard
                    ? "This does not look like a card"
                    : "Nothing recognised on this scan"
            )
            .catalogueLabel()
        }
        .transition(.opacity)
    }

    /// Sends the card image to the vision model on demand — for the scans the
    /// local read got wrong, or cards saved before the model existed.
    private var rescanButton: some View {
        Button(action: rescanWithAI) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                Text("Read again with AI")
                    .font(Typography.tag)
            }
            .foregroundStyle(Palette.ink)
        }
        .buttonStyle(.plain)
    }


    /// What is filled in, shown on the closed header so nothing hides.
    private var bagSummary: String? {
        var parts: [String] = []
        if let level = draft.roastLevel { parts.append(level.label) }
        if let days = draft.daysOffRoast() { parts.append("\(days) d") }
        if let price = draft.priceLine { parts.append(price) }
        if draft.isDecaf { parts.append(draft.decafMethod?.label ?? "Decaf") }
        return parts.isEmpty ? nil : parts.prefix(2).joined(separator: " · ")
    }

    private var matchToWheel: some View {
        VStack(alignment: .leading, spacing: 10) {
            let matched = draft.declaredFlavors
            if !matched.isEmpty {
                Text("On the wheel")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                FlowLayout {
                    ForEach(matched) { tag in
                        TagChip(text: tag.displayName, isSelected: false) {}
                    }
                }
            }
        }
    }

    private var productURLRow: some View {
        field("Link", text: bagText(\.productURL), placeholder: Placeholders.text(.bagLink))
    }

    private var decafMethodPicker: some View {
        group("Decaf method") {
            FlowLayout {
                ForEach(DecafMethod.allCases) { method in
                    TagChip(text: method.label, isSelected: draft.decafMethod == method) {
                        draft.decafMethod = draft.decafMethod == method ? nil : method
                    }
                }
            }
        }
    }

    /// Bridges an optional model string to the plain-text `field` row: empty
    /// means absent, so clearing the field clears the record.
    private func bagText(_ keyPath: WritableKeyPath<CoffeeCard, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private var roastLevelPicker: some View {
        group("Roast") {
            FlowLayout {
                ForEach(RoastLevel.allCases) { level in
                    TagChip(text: level.label, isSelected: draft.roastLevel == level) {
                        draft.roastLevel = draft.roastLevel == level ? nil : level
                    }
                }
            }
        }
    }

    private var roastedOnRow: some View {
        row(Copy.roastedOn, isEmpty: draft.roastedOn == nil) {
            HStack(spacing: 12) {
                if let roastedOn = draft.roastedOn {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { roastedOn },
                            set: { draft.roastedOn = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()

                    if let days = draft.daysOffRoast() {
                        Text(days == 0 ? "today" : "\(days) d")
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }

                    Button {
                        draft.roastedOn = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.inkMuted)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Set date") { draft.roastedOn = .now }
                        .font(Typography.value)
                        .foregroundStyle(Palette.inkMuted)
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private static let currencyPicks = ["EUR", "USD", "GBP", "JPY"]

    private var priceRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            NumberRow(
                "Price",
                value: $draft.price,
                unit: draft.currency ?? "—",
                placeholder: Placeholders.text(.bagPrice),
                labelWidth: 74
            )
            if draft.price != nil {
                FlowLayout {
                    ForEach(Self.currencyPicks, id: \.self) { code in
                        TagChip(text: code, isSelected: draft.currency == code) {
                            draft.currency = draft.currency == code ? nil : code
                        }
                    }
                }
            }
        }
    }

    private static let bagWeightPicks: [Double] = [100, 200, 250, 340, 500, 1000]

    private var bagWeightPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            NumberRow(
                "Bag",
                value: $draft.bagWeightG,
                unit: "g",
                placeholder: Placeholders.text(.bagWeight),
                labelWidth: 74
            )
            FlowLayout {
                ForEach(Self.bagWeightPicks, id: \.self) { grams in
                    TagChip(
                        text: CoffeeCard.grams(grams),
                        isSelected: draft.bagWeightG == grams
                    ) {
                        draft.bagWeightG = draft.bagWeightG == grams ? nil : grams
                    }
                }
            }
            if let perKilo = draft.pricePerKilo {
                Text(CoffeeCard.money(perKilo, currency: draft.currency) + "/kg")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
        }
    }

    private var decafToggle: some View {
        row("Decaf") {
            Toggle("", isOn: $draft.isDecaf)
                .labelsHidden()
                .tint(Palette.ink)
        }
    }

    private var placeTypePicker: some View {
        group("Place type") {
            FlowLayout {
                ForEach(PlaceType.allCases) { type in
                    TagChip(text: type.label, isSelected: draft.placeType == type) {
                        draft.placeType = draft.placeType == type ? nil : type
                    }
                }
            }
        }
    }

    private func recipeSection(_ recipe: Brew) -> some View {
        group("Recipe on card") {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(recipe.recipeLine)
                    .font(Typography.value)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    withAnimation(Motion.snappy) { draft.recipeSuggestion = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.inkMuted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func rescanWithAI() {
        guard !isReading else { return }
        withAnimation(Motion.snappy) {
            isReading = true
            readOutcome = .none
        }
        let cardID = draft.id
        Task {
            let vision = await Task.detached(priority: .userInitiated) {
                await CardVision.read(cardID: cardID)
            }.value
            withAnimation(Motion.snappy) {
                isReading = false
                if let vision {
                    merge(vision)
                } else {
                    readOutcome = .unreadable
                }
            }
        }
    }

    // MARK: - OCR

    /// Fills empty fields from the scan. Anything already typed wins, so a slow
    /// read never overwrites what you are in the middle of writing.
    private func prefill() async {
        guard let extract else { return }
        withAnimation(Motion.snappy) { isReading = true }
        let parsed = await extract()
        withAnimation(Motion.snappy) {
            isReading = false
            readOutcome = outcome(for: parsed)
            merge(parsed)
        }
    }

    private func outcome(for parsed: ParsedFields) -> ReadOutcome {
        guard parsed.isEmpty else { return .none }
        return parsed.linesRead < Self.cardLineFloor ? .notACard : .unreadable
    }

    /// Dictating the note to self. Only the note: the fields above come off a
    /// label, and reading them out loud is slower than scanning them.
    private func toggleDictation() async {
        guard dictation.isListening else {
            await dictation.start()
            return
        }
        let transcript = await dictation.stop()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }

        notesBeforeDictation = draft.personalNotes
        withAnimation(Motion.snappy) {
            draft.personalNotes = draft.personalNotes.isEmpty
                ? transcript.capitalizedFirst
                : draft.personalNotes + "\n" + transcript.capitalizedFirst
            dictatedTrigger += 1
        }
    }

    private func undoDictation() {
        guard let notesBeforeDictation else { return }
        withAnimation(Motion.snappy) { draft.personalNotes = notesBeforeDictation }
        self.notesBeforeDictation = nil
    }

    private func merge(_ parsed: ParsedFields) {
        func fill(_ keyPath: WritableKeyPath<CoffeeCard, String>, _ value: String?) {
            guard let value, draft[keyPath: keyPath].isEmpty else { return }
            draft[keyPath: keyPath] = value
        }
        fill(\.name, parsed.name)
        fill(\.roaster, parsed.roaster)
        fill(\.country, parsed.country)
        fill(\.region, parsed.region)
        fill(\.producer, parsed.producer)
        fill(\.altitude, parsed.altitude)
        fill(\.variety, parsed.variety)
        fill(\.process, parsed.process)
        if draft.tastingNotes.isEmpty { draft.tastingNotes = parsed.tastingNotes }
        if draft.labelCode == nil { draft.labelCode = parsed.labelCode }
        if draft.productURL == nil { draft.productURL = parsed.productURL }
        if draft.recipeSuggestion == nil { draft.recipeSuggestion = parsed.recipe }
        if draft.sourceLanguage == nil { draft.sourceLanguage = parsed.sourceLanguage }
        draft.originalFields.merge(parsed.originalFields) { current, _ in current }
        mergeBagFields(parsed)

        // Whatever CJK text remains after the table translations goes through
        // the on-device translator, original kept alongside.
        if FieldTranslator.needsTranslation(draft) {
            translationConfig = TranslationSession.Configuration(
                source: draft.sourceLanguage.map { Locale.Language(identifier: $0) },
                target: Locale.Language(identifier: "en")
            )
        }
    }

    /// Same rule as the origin fields: only fill what is still empty. Opens the
    /// group when something landed, so a read is never invisible.
    private func mergeBagFields(_ parsed: ParsedFields) {
        func fill<Value>(_ keyPath: WritableKeyPath<CoffeeCard, Value?>, _ value: Value?) {
            guard let value, draft[keyPath: keyPath] == nil else { return }
            draft[keyPath: keyPath] = value
        }
        fill(\.roastLevel, parsed.roastLevel)
        fill(\.agtron, parsed.agtron)
        fill(\.roastedOn, parsed.roastedOn)
        fill(\.harvest, parsed.harvest)
        fill(\.cuppingScore, parsed.cuppingScore)
        fill(\.price, parsed.price)
        fill(\.currency, parsed.currency)
        fill(\.bagWeightG, parsed.bagWeightG)
        fill(\.lot, parsed.lot)
        fill(\.decafMethod, parsed.decafMethod)
        fill(\.productURL, parsed.productURL)

        if parsed.isDecaf == true, !draft.isDecaf {
            draft.isDecaf = true
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
                cardID: draft.id,
                attachments: draft.attachments,
                onAdd: { isScanningAttachment = true },
                onSelect: { attachment in
                    if let i = draft.attachments.firstIndex(where: { $0.id == attachment.id }) {
                        cycleRole(at: i)
                    }
                }
            )
        }
    }

    private func cycleRole(at index: Int) {
        let roles = CardAttachment.Role.allCases
        guard let current = roles.firstIndex(of: draft.attachments[index].role) else { return }
        let next = roles[(current + 1) % roles.count]
        draft.attachments[index].role = next
    }

    private func ingestAttachment(_ scan: ScanResult) async {
        do {
            let attachment = try await Task.detached(priority: .userInitiated) {
                try await ImagePipeline.ingestAttachment(scan, cardID: draft.id)
            }.value

            withAnimation(Motion.snappy) {
                draft.attachments.insert(attachment, at: 0)
                isIngestingAttachment = false
            }

            if attachment.role.feedsFields {
                attachmentReadingID = attachment.id
                await mergeAttachmentOCR(attachmentID: attachment.id)
                attachmentReadingID = nil
            }
        } catch {
            isIngestingAttachment = false
            Log.app.error("attachment ingest failed: \(error)")
        }
    }

    /// Runs OCR on a page-role attachment and merges results into empty fields.
    private func mergeAttachmentOCR(attachmentID: UUID) async {
        let cardID = draft.id
        let parsed = await Task.detached(priority: .userInitiated) {
            let url = ImageStore.shared.url(for: cardID, kind: .attachment(attachmentID))
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                return ParsedFields()
            }

            let lines = await TextExtractor.readFromURL(url)
            var fields = FieldParser.parse(lines)
            fields.linesRead = lines.count

            return fields
        }.value

        withAnimation(Motion.snappy) {
            merge(parsed)
        }
    }
}
