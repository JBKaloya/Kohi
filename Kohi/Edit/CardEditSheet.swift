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
    @Environment(PlaceIndex.self) private var places
    @Environment(CardStore.self) private var cards
    @Environment(AccountStore.self) private var account
    @Environment(AIEventLog.self) private var events
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var isReading = false
    @State private var readOutcome: ReadOutcome = .none
    @State private var isSearchingPlace = false
    @State private var saveTrigger = 0
    @State private var isScanningAttachment = false
    @State private var isIngestingAttachment = false
    @State private var attachmentReadingID: UUID?
    @State private var nextAttachmentRole: CardAttachment.Role = .page
    /// The bag group starts closed, and opens itself when the scan found
    /// something in it.
    @State private var isAddingRoaster = false
    @State private var isBrowsingRoasters = false
    /// Set when Browse's "Add manually" is tapped, so the form opens once
    /// the catalogue sheet has finished dismissing.
    @State private var addRoasterAfterBrowse = false
    /// The person agreed to remember that this café serves this roaster.
    @State private var willRememberServe = false
    /// Non-nil starts an on-device translation of the CJK fields.
    @State private var translationConfig: TranslationSession.Configuration?
    /// What the vision model put in this draft, answered for when the sheet
    /// closes: kept if a value is still there at save, refused otherwise.
    @State private var modelFills: [ModelFill] = []

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

                    FieldGroup(title: "Card") {
                        field("Coffee", text: $draft.name, placeholder: Placeholders.text(.cardCoffee), presence: .useful)
                        roasterField
                        field("Process", text: $draft.process, placeholder: Placeholders.text(.cardProcess), presence: .useful)
                        ChipRail {
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
                    }

                    FieldGroup(title: Copy.onTheBag) {
                        roastLevelPicker
                        RollingCounter("Agtron", value: $draft.agtron, range: .agtron, labelWidth: 74)
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
                        RollingCounter(
                            "Cupping",
                            value: $draft.cuppingScore,
                            range: .cupping,
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

                    if let recipe = draft.recipeSuggestion {
                        recipeSection(recipe)
                    }

                    boughtAtSection

                    FieldGroup(title: Copy.noteToSelf) {
                        TextField(Placeholders.text(.cardNoteToSelf), text: $draft.personalNotes, axis: .vertical)
                            .font(Typography.body)
                            .lineLimit(3...8)
                        DictationField(text: $draft.personalNotes, vocabulary: {
                            CoffeeLexicon.coffees(cards: cards.cards, roasters: roasters.roasters.map(\.name))
                        })
                    }

                    attachmentSection

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
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // A new card confirms itself by landing in the grid a
                        // moment later; a second haptic here steps on it.
                        if !isNew { saveTrigger += 1 }
                        if willRememberServe, let offer = serveOffer {
                            places.remember(placeID: offer.placeID, roasterID: offer.roasterID)
                        }
                        matchRoasterIfObvious()
                        answerModelFills(saved: draft)
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
            .sheet(isPresented: $isSearchingPlace) {
                PlaceSearchView(place: $draft.place, placeID: $draft.placeID)
            }
            .sheet(isPresented: $isBrowsingRoasters, onDismiss: {
                if addRoasterAfterBrowse {
                    addRoasterAfterBrowse = false
                    isAddingRoaster = true
                }
            }) {
                roasterBrowser
            }
            .onChange(of: draft.placeID) { _, newID in
                willRememberServe = false
                applyServedRoaster(newID)
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
        .onDisappear {
            // The attachment scanner covers the sheet without closing it.
            guard !isScanningAttachment else { return }
            answerModelFills(saved: nil)
        }
        .onChange(of: draft.price) { old, new in
            guard isNew, old == nil, new != nil, draft.currency == nil else { return }
            draft.currency = LocalCurrency.shared.proposed
        }
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

            Button(Copy.browse) { isBrowsingRoasters = true }
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
                .buttonStyle(.plain)

            if let linked = draft.roasterId.flatMap({ roasters.roaster(id: $0) }) {
                VStack(alignment: .leading, spacing: 4) {
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
                    if let provenance = roasters.provenance(of: linked) {
                        Text(provenance)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }
                }
            } else if roasterIsEmpty, !servedHere.isEmpty {
                Text(Copy.servedHere).catalogueLabel()
                ChipRail {
                    ForEach(servedHere) { roaster in
                        TagChip(text: roaster.name) { link(roaster) }
                    }
                }
            } else if !roasterSuggestions.isEmpty {
                ChipRail {
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

    private var roasterIsEmpty: Bool {
        draft.roaster.trimmingCharacters(in: .whitespaces).isEmpty && draft.roasterId == nil
    }

    /// Roasters the chosen place serves, when there is more than one to offer.
    private var servedHere: [Roaster] {
        guard let placeID = draft.placeID else { return [] }
        let ids = places.servedRoasterIDs(for: placeID)
        guard ids.count > 1 else { return [] }
        return ids.compactMap { roasters.roaster(servedID: $0) }
    }

    /// FROM YOUR ARCHIVE, then every roaster, busiest Paris cafés first.
    private var roasterCatalog: [CatalogEntry] {
        let used = Set(cards.cards.compactMap(\.roasterId))
        return roasters.roasters
            .sorted { lhs, rhs in
                let left = roasters.shopsServed(lhs)
                let right = roasters.shopsServed(rhs)
                if left != right { return left > right }
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
            .map { roaster in
                let aliases = roasters.seedBySlug[roaster.seedID ?? ""]?.aliases ?? []
                let terms = ([roaster.name, roaster.city, roaster.country] + aliases)
                    .joined(separator: " ")
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                let subtitle = [roaster.city, roaster.country]
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                return CatalogEntry(
                    id: roaster.id.uuidString,
                    title: roaster.name,
                    subtitle: subtitle,
                    subfamily: "",
                    searchTerms: terms,
                    owned: used.contains(roaster.id)
                )
            }
    }

    private var placeTags: [String] {
        guard let placeID = draft.placeID, let place = places.place(id: placeID) else {
            if let name = draft.place?.name, let match = places.match(name: name), let tag = match.statusTag {
                return [tag]
            }
            return []
        }
        var tags = [Copy.fromSpecialtyCoffeeParis(place.fetchedAt)]
        if let tag = place.statusTag { tags.append(tag) }
        return tags
    }

    /// A café with no known roaster, and a card that now has one.
    private var serveOffer: (placeID: String, place: String, roasterID: String, roaster: String)? {
        guard let placeID = draft.placeID,
              let place = places.place(id: placeID),
              places.servedRoasterIDs(for: placeID).isEmpty,
              let linkedID = draft.roasterId,
              let roaster = roasters.roaster(id: linkedID)
        else { return nil }
        return (placeID, place.name, roaster.seedID ?? roaster.id.uuidString, roaster.name)
    }

    private func link(_ roaster: Roaster) {
        withAnimation(Motion.snappy) {
            draft.roasterId = roaster.id
            draft.roaster = roaster.name
        }
        publishIfSeeded(roaster)
    }

    /// On save, link the card when the index knows exactly one roastery by
    /// that name. Anything less certain is left alone: a wrong link is worse
    /// than no link, and the card still reads correctly either way.
    private func matchRoasterIfObvious() {
        guard draft.roasterId == nil, !draft.roaster.isEmpty else { return }
        guard let match = roasters.match(name: draft.roaster, country: "") else { return }
        draft.roasterId = match.id
        publishIfSeeded(match)
    }

    /// One served roaster fills the empty field. A roastery shop is typed as
    /// one; every other Paris place is a café until someone says otherwise.
    private func applyServedRoaster(_ placeID: String?) {
        guard let placeID else { return }
        if draft.placeType == nil {
            draft.placeType = roasters.ownsShop(placeID) ? .roastery : .cafe
        }
        let served = places.servedRoasterIDs(for: placeID)
        guard let servedID = PlaceRoasterFill.link(servedIDs: served, roasterIsEmpty: roasterIsEmpty),
              let roaster = roasters.roaster(servedID: servedID) else { return }
        link(roaster)
    }

    private func publishIfSeeded(_ roaster: Roaster) {
        guard roaster.seedID != nil, roaster.createdBy == nil else { return }
        roasters.publish(roaster.id)
    }

    private var boughtAtSection: some View {
        FieldGroup(title: Copy.boughtAt) {
            placeRow
            if !placeTags.isEmpty {
                Text(placeTags.joined(separator: " · "))
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
            if let offer = serveOffer {
                Button {
                    willRememberServe.toggle()
                } label: {
                    Text(rememberLabel(offer))
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
                .buttonStyle(.plain)
            }
            placeTypePicker
        }
    }

    private func rememberLabel(_ offer: (placeID: String, place: String, roasterID: String, roaster: String)) -> String {
        willRememberServe
            ? Copy.willRememberServes(offer.place, offer.roaster)
            : Copy.rememberServes(offer.place, offer.roaster)
    }

    private var roasterBrowser: some View {
        CatalogPicker(
            title: "Roaster",
            entries: roasterCatalog,
            selectedID: draft.roasterId?.uuidString,
            confirmation: "",
            ownedSectionTitle: Copy.fromYourArchive,
            onPick: { entry in
                guard let id = UUID(uuidString: entry.id),
                      let roaster = roasters.roaster(id: id) else { return }
                link(roaster)
            },
            onAddManually: { addRoasterAfterBrowse = true }
        )
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
        CoffeeIntelligenceButton(action: rescanWithAI)
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

    private var productURLRow: some View {
        field("Link", text: bagText(\.productURL), placeholder: Placeholders.text(.bagLink))
    }

    private var decafMethodPicker: some View {
        group("Decaf method") {
            ChipRail {
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
            RoastRail(level: $draft.roastLevel, onChange: applyRoast)
        }
    }

    private func applyRoast(_ next: RoastLevel?) {
        let previous = draft.roastLevel
        if draft.agtron == nil || draft.agtron == previous?.suggestedAgtron {
            draft.agtron = next?.suggestedAgtron
        }
        draft.roastLevel = next
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

    /// The currency sits beside the price from the start, so the counter
    /// never changes width; it only opens once there is a price to qualify.
    private var priceRow: some View {
        CounterRow(
            "Price",
            value: $draft.price,
            range: .price(in: draft.currency),
            placeholder: Placeholders.text(.bagPrice),
            labelWidth: 74,
            notice: NumberRange.price(in: draft.currency).priceNotice(for: draft.price, currency: draft.currency)
        ) {
            CurrencyPicker(code: $draft.currency)
                .disabled(draft.price == nil)
                .opacity(draft.price == nil ? 0.35 : 1)
        }
    }

    private static let bagWeightPicks: [Double] = [100, 200, 250, 340, 500, 1000]

    private var bagWeightPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            RollingCounter(
                "Bag",
                value: $draft.bagWeightG,
                range: .bagWeight,
                unit: "g",
                placeholder: Placeholders.text(.bagWeight),
                labelWidth: 74,
                hint: draft.pricePerKilo.map { CoffeeCard.money($0, currency: draft.currency) + "/kg" }
            )
            ChipRail {
                ForEach(Self.bagWeightPicks, id: \.self) { grams in
                    TagChip(
                        text: CoffeeCard.grams(grams),
                        isSelected: draft.bagWeightG == grams
                    ) {
                        draft.bagWeightG = draft.bagWeightG == grams ? nil : grams
                    }
                }
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
            ChipRail {
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
            let reading = await Task.detached(priority: .userInitiated) {
                await CardVision.read(cardID: cardID)
            }.value
            let eventID = reading.map { events.record($0.event) }
            withAnimation(Motion.snappy) {
                isReading = false
                if let vision = reading?.fields, let eventID {
                    var fields = vision
                    fields.modelFill = ModelFill(eventID: eventID, values: FieldValues.of(vision))
                    merge(fields)
                } else {
                    readOutcome = .unreadable
                }
            }
        }
    }

    /// Once per fill: the first close answers, a second is a no-op.
    private func answerModelFills(saved: CoffeeCard?) {
        let current = saved.map(FieldValues.of) ?? [:]
        for fill in modelFills {
            events.setAccepted(fill.kept(in: current), for: fill.eventID)
        }
        modelFills = []
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

    private func merge(_ parsed: ParsedFields) {
        let before = FieldValues.of(draft)
        defer {
            if let fill = parsed.modelFill {
                modelFills.append(fill.narrowed(before: before, after: FieldValues.of(draft)))
            }
        }
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
        if let price = parsed.price, NumberRange.price(in: parsed.currency ?? draft.currency).contains(price) {
            fill(\.price, price)
        }
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
                    Text(Copy.addingPage)
                        .catalogueLabel()
                }
            }

            AttachmentStrip(
                cardID: draft.id,
                attachments: draft.attachments,
                title: Copy.theRestOfTheBag,
                showsAddButton: false,
                onAdd: { addAttachment(role: .page) },
                onSelect: { attachment in
                    if let i = draft.attachments.firstIndex(where: { $0.id == attachment.id }) {
                        cycleRole(at: i)
                    }
                }
            )

            Button(Copy.scanBackLabel) { addAttachment(role: .bag) }
                .catalogueLabel()
            Button(Copy.scanRoasterRecipe) { addAttachment(role: .recipe) }
                .catalogueLabel()
        }
    }

    private func addAttachment(role: CardAttachment.Role) {
        nextAttachmentRole = role
        isScanningAttachment = true
    }

    private func cycleRole(at index: Int) {
        let roles = CardAttachment.Role.allCases
        guard let current = roles.firstIndex(of: draft.attachments[index].role) else { return }
        let next = roles[(current + 1) % roles.count]
        draft.attachments[index].role = next
    }

    private func ingestAttachment(_ scan: ScanResult) async {
        do {
            var attachment = try await Task.detached(priority: .userInitiated) {
                try await ImagePipeline.ingestAttachment(scan, cardID: draft.id)
            }.value
            attachment.role = nextAttachmentRole

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
