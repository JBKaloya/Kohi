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
    private var lines: [String] = []

    func read(
        _ scan: ScanResult,
        into draft: Binding<TastingDraft>,
        roasters: [String],
        cards: [CoffeeCard]
    ) async {
        isReading = true
        couldNotRead = false
        defer { isReading = false }
        let tastingID = draft.wrappedValue.id
        async let photo = Task.detached(priority: .userInitiated) {
            TastingPhotos.save(scan: scan, tastingID: tastingID)
        }.value
        let read = await TextExtractor.read(image: scan.image)
        if let name = await photo, !draft.wrappedValue.photos.contains(name) {
            draft.wrappedValue.photos.append(name)
        }
        lines = read.map(\.text)
        take(TastingCapture.sort(read, roasters: roasters), into: draft, cards: cards)
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
                    FlowLayout {
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
                TastingTextField(label: "Roaster", text: $draft.coffee.roaster)
            }
            TastingTextField(label: "Country", text: $draft.coffee.country, lexicon: CoffeeSuggestions.origins)
            TastingTextField(label: "Region", text: $draft.coffee.region)
            TastingTextField(label: "Farm", text: $draft.coffee.farm)
            TastingTextField(label: "Variety", text: $draft.coffee.variety, lexicon: CoffeeSuggestions.varieties)
            TastingTextField(label: "Process", text: $draft.coffee.process, lexicon: CoffeeSuggestions.processes)
            TastingTextField(label: Copy.onThePack, text: $draft.notesText)
        }
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
                    HStack(spacing: 7) {
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
            FlowLayout {
                ForEach(TastingMethod.allCases) { method in
                    TagChip(text: method.label, isSelected: draft.method == method) {
                        draft.method = draft.method == method ? nil : method
                    }
                }
            }
            if draft.method == .other {
                TextField(Copy.methodOtherPrompt, text: $draft.methodNote)
                    .font(Typography.value)
                    .foregroundStyle(Palette.ink)
            }
        }
    }

    private var pricePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Copy.price).catalogueLabel()
            HStack(spacing: 12) {
                TextField("0,00", text: $draft.priceText)
                    .font(Typography.value)
                    .foregroundStyle(Palette.ink)
                    .keyboardType(.decimalPad)
                    .frame(maxWidth: 120, alignment: .leading)
                Menu {
                    ForEach(CupPrice.commonCurrencies, id: \.self) { code in
                        Button(code) { draft.currency = code }
                    }
                } label: {
                    Text(draft.currency).catalogueLabel().foregroundStyle(Palette.ink)
                }
                if let price = draft.price {
                    Text(price.formatted)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
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
