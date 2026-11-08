import PhotosUI
import SwiftUI

/// Reads one scan into a tasting draft, for the flow and the edit form alike.
/// The text decides what it was (`TastingCapture`); a menu asks which coffee,
/// a card fills what is empty, and a card already on the shelf is offered as
/// a link.
@MainActor
@Observable
final class TastingReader {
    var isReading = false
    /// The last read found nothing that looks like a coffee.
    var couldNotRead = false
    var candidates: [MenuCandidate] = []
    var showsMenu = false
    /// Read as a guess: offered as chips, applied only on a tap.
    var uncertain: [MenuField] = []
    var linkOffer: CoffeeCard?
    /// The menu model is reading; the local candidates are already shown.
    var isAskingModel = false
    private var lines: [String] = []
    private var events: AIEventLog?
    /// The menu read the sheet is showing came from the model, unanswered yet.
    private var menuEventID: UUID?
    /// What the vision model put in the draft, answered for at save.
    private var modelFills: [ModelFill] = []

    /// Reads the photo on device, then lets a model help where that read is
    /// thin: a menu goes to the menu reader, a weak card to the vision model.
    /// Neither asks first, and both only ever fill what is still empty.
    func read(
        _ scan: ScanResult,
        into draft: Binding<TastingDraft>,
        roasters: [String],
        cards: [CoffeeCard],
        flags: AIFlags,
        events: AIEventLog
    ) async {
        self.events = events
        menuDismissed()
        isReading = true
        couldNotRead = false
        defer { isReading = false }
        let tastingID = draft.wrappedValue.id
        let image = scan.image
        async let photo = Task.detached(priority: .userInitiated) {
            TastingPhotos.save(scan: scan, tastingID: tastingID)
        }.value
        async let codes = LabelCodeReader.readAll(image: image)
        let read = await TextExtractor.read(image: scan.image)
        if let name = await photo, !draft.wrappedValue.photos.contains(name) {
            draft.wrappedValue.photos.append(name)
        }
        lines = read.map(\.text)
        let reading = TastingCapture.sort(read, roasters: roasters)
        take(reading, into: draft, cards: cards)

        switch reading {
        case .menu:
            await askModelForMenu(flags: flags, events: events)
        case .fields(var local, _):
            local.linesRead = read.count
            local = await follow(await codes, local: local, into: draft, cards: cards)
            await askForSecondOpinion(scan, local: local, into: draft, cards: cards, flags: flags, events: events)
        case .nothing:
            var local = ParsedFields()
            local.linesRead = read.count
            local = await follow(await codes, local: local, into: draft, cards: cards)
            await askForSecondOpinion(scan, local: local, into: draft, cards: cards, flags: flags, events: events)
        }
    }

    /// A code on the card, and the product page it points to, before any
    /// model: when the page fills the gaps, the second opinion is not asked.
    private func follow(
        _ codes: [LabelCodeReader.Found],
        local: ParsedFields,
        into draft: Binding<TastingDraft>,
        cards: [CoffeeCard]
    ) async -> ParsedFields {
        guard !codes.isEmpty else { return local }
        let linked = await ScanPipeline.linked(codes: codes, local: local)
        let before = FieldValues.of(draft.wrappedValue.coffee)
        draft.wrappedValue.fill(from: linked)
        if FieldValues.of(draft.wrappedValue.coffee) != before {
            couldNotRead = false
            offerLink(for: draft.wrappedValue, origin: linked, cards: cards)
        }
        return linked
    }

    private func askModelForMenu(flags: AIFlags, events: AIEventLog) async {
        guard flags.isOn(.menuExtract) else { return }
        isAskingModel = true
        defer { isAskingModel = false }
        guard let read = await FieldExtract.menu(lines: lines, flags: flags, events: events) else { return }
        let grounded = MenuParser.grounded(read.value, in: lines)
        // Picked from the local list, or closed, before the model answered.
        guard showsMenu, !grounded.isEmpty else {
            events.setAccepted(false, for: read.eventID)
            return
        }
        candidates = grounded
        menuEventID = read.eventID
    }

    private func askForSecondOpinion(
        _ scan: ScanResult,
        local: ParsedFields,
        into draft: Binding<TastingDraft>,
        cards: [CoffeeCard],
        flags: AIFlags,
        events: AIEventLog
    ) async {
        guard let parsed = await ScanPipeline.secondOpinion(
            image: scan.image,
            local: local,
            visionAllowed: flags.isOn(.cardVision),
            events: events
        ), let fill = parsed.modelFill else { return }
        let before = FieldValues.of(draft.wrappedValue.coffee)
        draft.wrappedValue.fill(from: parsed)
        let narrowed = fill.narrowed(before: before, after: FieldValues.of(draft.wrappedValue.coffee))
        modelFills.append(narrowed)
        if !narrowed.values.isEmpty {
            couldNotRead = false
            offerLink(for: draft.wrappedValue, origin: parsed, cards: cards)
        }
    }

    /// Says whether what the models offered survived: the menu pick when one
    /// was made from the model's list, the filled fields when saved unchanged.
    /// Called with nil when the draft is thrown away.
    func answerModels(saved: TastingDraft?) {
        guard let events else { return }
        let current = saved.map { FieldValues.of($0.coffee) } ?? [:]
        for fill in modelFills {
            events.setAccepted(fill.kept(in: current), for: fill.eventID)
        }
        modelFills = []
        menuDismissed()
    }

    /// The menu sheet closed without a pick from the model's list.
    func menuDismissed() {
        guard let menuEventID, let events else { return }
        events.setAccepted(false, for: menuEventID)
        self.menuEventID = nil
    }

    func take(_ reading: TastingCapture.Reading, into draft: Binding<TastingDraft>, cards: [CoffeeCard]) {
        switch reading {
        case .menu(let found):
            candidates = found
            showsMenu = true
        case .fields(let parsed, let extra):
            draft.wrappedValue.fill(from: parsed)
            uncertain = draft.wrappedValue.fill(extra: extra)
            offerLink(for: draft.wrappedValue, origin: parsed, cards: cards)
        case .nothing:
            couldNotRead = true
        }
    }

    func apply(_ candidate: MenuCandidate, into draft: Binding<TastingDraft>, cards: [CoffeeCard]) {
        showsMenu = false
        if let menuEventID {
            events?.setAccepted(true, for: menuEventID)
            self.menuEventID = nil
        }
        for field in candidate.fields where field.confidence == .read {
            draft.wrappedValue.apply(field)
        }
        uncertain = candidate.fields.filter { $0.confidence == .uncertain }
        offerLink(for: draft.wrappedValue, origin: nil, cards: cards)
    }

    func confirm(_ field: MenuField, into draft: Binding<TastingDraft>) {
        draft.wrappedValue.apply(field)
        uncertain.removeAll { $0.id == field.id }
    }

    func askModel(flags: AIFlags, events: AIEventLog) async -> [MenuCandidate] {
        guard let read = await FieldExtract.menu(lines: lines, flags: flags, events: events) else {
            return candidates
        }
        return MenuParser.grounded(read.value, in: lines)
    }

    private func offerLink(for draft: TastingDraft, origin: ParsedFields?, cards: [CoffeeCard]) {
        guard let hit = CardMatch.find(
            roaster: draft.coffee.roaster,
            name: draft.coffee.name,
            origin: origin,
            in: cards
        ), draft.cardID != hit.card.id else { return }
        linkOffer = hit.card
    }
}

/// Writes a draft to the store, the same way from the flow and the form:
/// the roaster linked by name, and a seed place remembered as serving it.
@MainActor
enum TastingSaver {
    @discardableResult
    static func save(
        _ draft: TastingDraft,
        editing: Tasting?,
        tastings: TastingStore,
        roasters: RoasterStore,
        places: PlaceIndex
    ) -> Tasting {
        var tasting = draft.tasting(base: editing)
        if tasting.coffee.roasterId == nil {
            tasting.coffee.roasterId = roasters.roasters.first {
                Roaster.fold($0.name) == Roaster.fold(tasting.coffee.roaster)
            }?.id
        }
        if editing != nil {
            tastings.update(tasting)
        } else {
            tasting = tastings.add(tasting)
        }
        if let placeID = tasting.placeID,
           let roasterID = tasting.coffee.roasterId,
           let roaster = roasters.roaster(id: roasterID) {
            places.remember(placeID: placeID, roasterID: roaster.seedID ?? roaster.id.uuidString)
        }
        return tasting
    }
}

/// Roasters the menu and card readers recognise: yours, then the seed base.
@MainActor
func knownRoasterNames(_ roasters: RoasterStore) -> [String] {
    roasters.roasters.map(\.name) + ReferenceBase.roasterSeeds.map(\.name)
}

// MARK: - Which coffee

/// The coffee's name, with suggestions, the collection link and the values
/// read to confirm. With `showsIdentity`, the fields under it too: roaster,
/// origin, process, variety and the notes printed on the card.
struct TastingCoffeeFields: View {
    @Binding var draft: TastingDraft
    let reader: TastingReader
    var editingID: UUID?
    var nameFocused: FocusState<Bool>.Binding
    var nameMissing = false
    var showsIdentity = false

    @Environment(CardStore.self) private var store
    @Environment(TastingStore.self) private var tastings
    @Environment(RoasterStore.self) private var roasters

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Copy.coffeeName).catalogueLabel(missing: nameMissing)
            TextField(Placeholders.text(.cardCoffee), text: $draft.coffee.name)
                .font(Typography.subtitle)
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused(nameFocused)
                .submitLabel(.done)

            if nameFocused.wrappedValue, !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions) { suggestion in
                        Button { take(suggestion) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .font(Typography.value)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Text([suggestion.subtitle, suggestion.label].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(Typography.tag)
                                    .foregroundStyle(Palette.inkMuted)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity)
            }

            if let cardID = draft.cardID, let card = store.card(id: cardID) {
                HStack(spacing: 8) {
                    Text("\(Copy.inCoffeeCollection) · \(store.title(for: card))")
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(1)
                    Button(Copy.unlink) { draft.cardID = nil }
                        .font(Typography.tag)
                        .foregroundStyle(Palette.ink)
                }
            }

            if !reader.uncertain.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Copy.toConfirm).catalogueLabel()
                    ChipRail {
                        ForEach(reader.uncertain) { field in
                            TagChip(text: "\(field.kind.label): \(field.value)?", isSelected: false) {
                                reader.confirm(field, into: $draft)
                            }
                        }
                    }
                }
            }

            if showsIdentity {
                TastingIdentityFields(draft: $draft)
                    .padding(.top, 14)
            }
        }
        .animation(Motion.quick, value: nameFocused.wrappedValue)
    }

    private var suggestions: [CoffeeSuggestions.Suggestion] {
        CoffeeSuggestions.suggest(
            draft.coffee.name,
            cards: store.cards,
            tastings: tastings.tastings.filter { $0.id != editingID },
            roasters: roasters.roasters.map(\.name)
        )
        .filter { SeedPlace.fold($0.title) != SeedPlace.fold(draft.coffee.name) || $0.source != .tastedBefore }
    }

    private func take(_ suggestion: CoffeeSuggestions.Suggestion) {
        switch suggestion.source {
        case .collection(let cardID):
            if let card = store.card(id: cardID) { draft.link(card) }
        case .tastedBefore:
            draft.coffee = suggestion.coffee
        case .roaster:
            draft.coffee.roaster = suggestion.title
        }
        nameFocused.wrappedValue = false
    }
}

/// Roaster, origin, process, variety and the notes on the card.
struct TastingIdentityFields: View {
    @Binding var draft: TastingDraft
    var showsRoaster = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsRoaster {
                TastingRoasterField(draft: $draft)
            }
            TastingTextField(label: "Country", text: $draft.coffee.country, lexicon: CoffeeSuggestions.origins)
            TastingTextField(label: "Region", text: $draft.coffee.region)
            TastingTextField(label: "Farm", text: $draft.coffee.farm)
            TastingTextField(label: "Variety", text: $draft.coffee.variety, lexicon: CoffeeSuggestions.varieties)
            TastingTextField(label: "Process", text: $draft.coffee.process, lexicon: CoffeeSuggestions.processes)
            TastingNotesField(draft: $draft)
        }
    }
}

/// The pack's notes as chips, one entry line to add more, and wheel flavours
/// offered under it. A comma or Return turns the entry into a chip; anything
/// left in the entry is kept on save. Free text stays possible.
struct TastingNotesField: View {
    @Binding var draft: TastingDraft

    private var offers: [String] {
        FlavorSuggestions.suggest(draft.notesEntry, excluding: draft.coffee.tastingNotes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Copy.onThePack).catalogueLabel()
            if !draft.coffee.tastingNotes.isEmpty {
                FlowLayout {
                    ForEach(draft.coffee.tastingNotes, id: \.self) { note in
                        TagChip(text: note, showsRemove: true) {
                            withAnimation(Motion.quick) { draft.removeNote(note) }
                        }
                    }
                }
            }
            TextField("", text: $draft.notesEntry)
                .font(Typography.value)
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { withAnimation(Motion.snappy) { draft.commitNotesEntry() } }
                .onChange(of: draft.notesEntry) { _, value in
                    if value.contains(",") || value.contains("\n") {
                        withAnimation(Motion.snappy) { draft.commitNotesEntry() }
                    }
                }
            if !offers.isEmpty {
                ChipRail {
                    ForEach(offers, id: \.self) { flavor in
                        TagChip(text: flavor) {
                            withAnimation(Motion.snappy) { draft.pick(suggestion: flavor) }
                        }
                    }
                }
            }
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }
}

/// The roaster, with the index offered underneath: the roasters this place
/// serves while it is empty, the closest names once typing starts. Picking
/// only fixes the spelling; the save links the entry by name.
struct TastingRoasterField: View {
    @Binding var draft: TastingDraft

    @Environment(RoasterStore.self) private var roasters
    @Environment(PlaceIndex.self) private var places

    var body: some View {
        TastingTextField(label: "Roaster", text: $draft.coffee.roaster, lexicon: offers)
    }

    private func offers(_ typed: String) -> [String] {
        let folded = Roaster.fold(typed)
        guard !folded.isEmpty else { return servedHere }
        return roasters.suggestions(for: typed)
            .map(\.name)
            .filter { Roaster.fold($0) != folded }
    }

    private var servedHere: [String] {
        guard let placeID = draft.placeID else { return [] }
        return places.servedRoasterIDs(for: placeID)
            .compactMap { roasters.roaster(servedID: $0)?.name }
            .prefix(4)
            .map { $0 }
    }
}

/// A labelled line field, with chips from a lexicon when one fits.
struct TastingTextField: View {
    let label: String
    @Binding var text: String
    var lexicon: ((String) -> [String])?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).catalogueLabel()
            TextField("", text: $text)
                .font(Typography.value)
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            if let lexicon {
                let words = lexicon(text)
                if !words.isEmpty {
                    ChipRail {
                        ForEach(words, id: \.self) { word in
                            TagChip(text: word, isSelected: false) { text = word }
                        }
                    }
                }
            }
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }
}

// MARK: - How it was made

/// Method, price and photos. The edit form adds the date between price and
/// photos.
struct TastingMadeFields: View {
    @Binding var draft: TastingDraft
    var showsDate = false

    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            methodPicker
            pricePicker
            if showsDate {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Date").catalogueLabel()
                    DatePicker("", selection: $draft.date, in: ...Date.now, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            photosRow
        }
        .onChange(of: photoItems) { _, items in
            Task { await importPhotos(items) }
        }
    }

    private var methodPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Copy.method).catalogueLabel()
            ChipRail {
                ForEach(TastingMethod.families) { family in
                    TagChip(text: family.label, isSelected: draft.method?.root == family) {
                        draft.method = draft.method?.root == family ? nil : family
                    }
                }
            }
            if let root = draft.method?.root, !root.devices.isEmpty {
                Rectangle().fill(Palette.hairline).frame(height: 1)
                ChipRail {
                    ForEach(root.devices) { device in
                        TagChip(text: device.deviceLabel, isSelected: draft.method == device) {
                            draft.method = draft.method == device ? root : device
                        }
                    }
                }
            }
            if draft.method == .other {
                TextField(Copy.methodOtherPrompt, text: $draft.methodNote)
                    .font(Typography.value)
                    .foregroundStyle(Palette.ink)
            }
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }

    private var pricePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Copy.price).catalogueLabel()
            CounterRow(
                value: Binding(
                    get: { draft.price.map { NSDecimalNumber(decimal: $0.amount).doubleValue } },
                    set: { draft.priceText = $0.map { String(format: "%.2f", $0) } ?? "" }
                ),
                range: .cupPrice,
                placeholder: "0.00"
            ) {
                CurrencyPicker(code: $draft.currency)
            }
        }
    }

    private var photosRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Copy.photos).catalogueLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(draft.photos, id: \.self) { name in
                        TastingPhotoThumb(tastingID: draft.id, name: name)
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    draft.photos.removeAll { $0 == name }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Palette.paper)
                                        .padding(5)
                                        .background(Palette.ink, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .padding(4)
                            }
                    }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 64, height: 64)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.hairline, lineWidth: 1))
                    }
                    .accessibilityLabel("Add a photo")
                }
            }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            if let name = TastingPhotos.save(data, tastingID: draft.id) {
                draft.photos.append(name)
            }
        }
        photoItems = []
    }
}
