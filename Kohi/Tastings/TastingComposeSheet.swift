import PhotosUI
import SwiftUI

/// Adding or editing a coffee had in a coffee shop. One screen, place first.
///
/// Where, then what, then the details behind a disclosure, then how it was.
/// A coffee name and a place are required, because a tasting without either
/// is not a tasting anyone can find again. Save is always there; tapping it
/// early marks what is missing instead of hiding the way forward.
struct TastingComposeSheet: View {
    var editing: Tasting? = nil
    /// Snapshot and tests pass a list instead of asking for a fix.
    var previewSuggestions: [SeedPlace]? = nil
    var requestsLocation = true
    var onSaved: (Tasting) -> Void = { _ in }

    @Environment(TastingStore.self) private var tastings
    @Environment(CardStore.self) private var store
    @Environment(RoasterStore.self) private var roasters
    @Environment(PlaceIndex.self) private var places
    @Environment(AIFlags.self) private var flags
    @Environment(AIEventLog.self) private var events
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TastingDraft
    @State private var nearby = NearbyPlaces()
    @State private var choosingPlace = false
    @State private var pickingFromCollection = false
    @State private var pickedCard: CoffeeCard?
    @State private var showsDetails: Bool
    @State private var showsMore = false
    @State private var isScanning = false
    @State private var reader = TastingReader()
    @State private var saveTrigger = 0
    @State private var rejectTrigger = 0
    @State private var flagged: Set<TastingField> = []
    /// The currency put on a new tasting, while nobody has picked another.
    @State private var proposedCurrency: String?
    @FocusState private var nameFocused: Bool

    init(
        editing: Tasting? = nil,
        previewSuggestions: [SeedPlace]? = nil,
        requestsLocation: Bool = true,
        onSaved: @escaping (Tasting) -> Void = { _ in }
    ) {
        self.editing = editing
        self.previewSuggestions = previewSuggestions
        self.requestsLocation = requestsLocation
        self.onSaved = onSaved
        var draft = editing.map(TastingDraft.init) ?? TastingDraft()
        if editing == nil {
            draft.currency = LocalCurrency.shared.proposed
            _proposedCurrency = State(initialValue: draft.currency)
        }
        _draft = State(initialValue: draft)
        _showsDetails = State(initialValue: editing != nil && draft.detailSummary != nil)
    }

    private var isEditing: Bool { editing != nil }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        PlaceSelectorRow(
                            place: draft.place,
                            suggestion: draft.place == nil ? topSuggestion : nil,
                            isMissing: flagged.contains(.place),
                            onAccept: { draft.choose($0.place, $0.placeID) },
                            onChoose: {
                                nearby.start()
                                choosingPlace = true
                            }
                        )
                        .id(TastingField.place)

                        what
                            .id(TastingField.coffee)

                        details

                        VStack(alignment: .leading, spacing: 28) {
                            Text(Copy.yourTasting).catalogueLabel()
                            SensoryEvaluationSection(
                                rating: $draft.rating,
                                taste: $draft.taste,
                                flavors: $draft.flavors,
                                previousTaste: previousTaste,
                                previousCaption: Copy.previousCupIsLighter,
                                declared: draft.coffee.declaredFlavors,
                                recent: recentFlavors
                            )
                            VStack(alignment: .leading, spacing: 10) {
                                Text(Copy.noteToSelf).catalogueLabel()
                                TextField("", text: $draft.note, axis: .vertical)
                                    .font(Typography.body)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(2...6)
                                DictationField(text: $draft.note, vocabulary: {
                                    CoffeeLexicon.coffees(cards: store.cards, roasters: roasters.roasters.map(\.name))
                                })
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 12)
                    .padding(.bottom, 48)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .background(Palette.paper.ignoresSafeArea())
                .navigationTitle(isEditing ? Copy.editTasting : Copy.addTasting)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.light, for: .navigationBar)
                .tint(Palette.ink)
                .keyboardDoneButton()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save(scroller) }
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .presentationBackground(Palette.paper)
        .haptic(.saved, trigger: saveTrigger)
        .haptic(.deleted, trigger: rejectTrigger)
        .onAppear(perform: load)
        .onDisappear {
            // The scanner covers the sheet without closing it.
            guard !isScanning else { return }
            reader.answerModels(saved: nil)
        }
        .onChange(of: topSuggestion, initial: true) { _, suggestion in
            guard !isEditing, nearby.coordinate != nil, let suggestion else { return }
            draft.autofill(suggestion.place, suggestion.placeID)
        }
        .onChange(of: LocalCurrency.shared.proposed) { _, proposed in
            guard let proposedCurrency, draft.currency == proposedCurrency else { return }
            draft.currency = proposed
            self.proposedCurrency = proposed
        }
        .onChange(of: draft.missing) { _, missing in
            withAnimation(Motion.snappy) { flagged.formIntersection(missing) }
        }
        .task {
            guard requestsLocation, previewSuggestions == nil, !isEditing, PlaceLocator.isAuthorized else { return }
            nearby.start()
        }
        .task(id: nearby.coordinate?.latitude) {
            guard previewSuggestions == nil, nearby.coordinate != nil else { return }
            places.beginGeocoding()
            await nearby.searchCafes()
        }
        .sheet(isPresented: $choosingPlace) {
            WhereSheet(
                roaster: draft.coffee.roaster,
                nearby: nearby,
                previewSuggestions: previewSuggestions,
                requestsLocation: requestsLocation
            ) { place, placeID in
                draft.choose(place, placeID)
            }
            .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $pickingFromCollection) {
            RecipeCoffeePicker(picked: $pickedCard)
                .appEnvironment(appEnvironment)
        }
        .onChange(of: pickedCard) { _, card in
            guard let card else { return }
            draft.link(card)
            pickedCard = nil
            pickingFromCollection = false
        }
        .fullScreenCover(isPresented: $isScanning) {
            ScanScreen(
                onScan: { scan in
                    isScanning = false
                    Task {
                        await reader.read(
                            scan,
                            into: $draft,
                            roasters: knownRoasterNames(roasters),
                            cards: store.cards,
                            flags: flags,
                            events: events
                        )
                        if reader.couldNotRead { nameFocused = true }
                    }
                },
                onCancel: { isScanning = false }
            )
            .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $reader.showsMenu, onDismiss: reader.menuDismissed) {
            MenuPickSheet(
                candidates: reader.candidates,
                isModelReading: reader.isAskingModel,
                onPick: { candidate in
                    reader.apply(candidate, into: $draft, cards: store.cards)
                    if candidate.fields.contains(where: { $0.kind != .name && $0.confidence == .read }) {
                        showsDetails = true
                    }
                }
            )
        }
        .alert(
            Copy.alreadyInCollection,
            isPresented: Binding(get: { reader.linkOffer != nil }, set: { if !$0 { reader.linkOffer = nil } }),
            presenting: reader.linkOffer
        ) { card in
            Button("Link") { draft.link(card) }
            Button("Not now", role: .cancel) {}
        } message: { card in
            Text(store.title(for: card))
        }
    }

    // MARK: - What

    private var what: some View {
        VStack(alignment: .leading, spacing: 12) {
            TastingCoffeeFields(
                draft: $draft,
                reader: reader,
                editingID: editing?.id,
                nameFocused: $nameFocused,
                nameMissing: flagged.contains(.coffee)
            )

            if reader.couldNotRead {
                Text(Copy.couldntReadThis)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }

            HStack(spacing: 18) {
                if !store.cards.isEmpty {
                    action(Copy.fromCoffeeCollection) { pickingFromCollection = true }
                }
                action(Copy.scanTheCard) { isScanning = true }
                if reader.isReading {
                    ProgressView().controlSize(.mini)
                }
            }
        }
    }

    private func action(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).catalogueLabel()
        }
        .buttonStyle(.plain)
        .touchTarget()
    }

    // MARK: - Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button {
                withAnimation(Motion.snappy) { showsDetails.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(Copy.details).catalogueLabel()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Palette.inkMuted)
                        .rotationEffect(.degrees(showsDetails ? 90 : 0))
                    Spacer()
                    if !showsDetails, let line = draft.detailSummary {
                        Text(line)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            if showsDetails {
                VStack(alignment: .leading, spacing: 20) {
                    TastingTextField(label: "Roaster", text: $draft.coffee.roaster)

                    Button {
                        withAnimation(Motion.snappy) { showsMore.toggle() }
                    } label: {
                        Text(Copy.moreAboutThisCoffee)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.ink)
                    }
                    .buttonStyle(.plain)

                    if showsMore || draft.coffee.hasMore {
                        TastingIdentityFields(draft: $draft, showsRoaster: false)
                    }

                    TastingMadeFields(draft: $draft, showsDate: true)
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Sensory context

    private var previousTaste: TasteProfile? {
        let name = SeedPlace.fold(draft.coffee.name)
        guard !name.isEmpty else { return nil }
        return SensoryScored.previous(
            tastings.tastings
                .filter { $0.id != draft.id && SeedPlace.fold($0.coffee.name) == name }
                .map(\.taste)
        )
    }

    private var recentFlavors: [FlavorTag] {
        SensoryScored.recent(tastings.tastings.filter { $0.id != draft.id }.map(\.flavors))
    }

    private var topSuggestion: PlaceSuggestion? {
        nearby.suggestions(
            roaster: draft.coffee.roaster,
            index: places,
            tastings: tastings.tastings,
            preview: previewSuggestions
        ).first
    }

    // MARK: - Save

    private func load() {
        if !isEditing { nameFocused = draft.place != nil }
    }

    private func save(_ scroller: ScrollViewProxy) {
        let missing = draft.missing
        guard missing.isEmpty else {
            rejectTrigger += 1
            withAnimation(Motion.snappy) { flagged = missing }
            if let first = TastingField.allCases.first(where: missing.contains) {
                withAnimation(Motion.snappy) { scroller.scrollTo(first, anchor: .top) }
                if first == .coffee { nameFocused = true }
            }
            return
        }
        saveTrigger += 1
        reader.answerModels(saved: draft)
        let tasting = TastingSaver.save(draft, editing: editing, tastings: tastings, roasters: roasters, places: places)
        onSaved(tasting)
        dismiss()
    }
}

/// How the cup was made, in the words a café uses. Maps onto the brew
/// vocabulary without adding a method: V60 is filter on a V60, batch is
/// filter with `isBatch`.
enum TastingMethod: String, CaseIterable, Identifiable, Sendable {
    case espresso
    case v60
    case kalita
    case chemex
    case aeropress
    case batch
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .espresso: "Espresso"
        case .v60: "V60"
        case .kalita: "Kalita"
        case .chemex: "Chemex"
        case .aeropress: "AeroPress"
        case .batch: "Batch"
        case .other: "Other"
        }
    }

    var method: BrewMethod? {
        switch self {
        case .espresso: .espresso
        case .v60, .kalita, .chemex, .batch: .filter
        case .aeropress: .aeropress
        case .other: nil
        }
    }

    var brewer: BrewerType? {
        switch self {
        case .espresso: .espresso
        case .v60: .v60
        case .kalita: .flat
        case .chemex: .chemex
        case .aeropress: .aeropress
        case .batch, .other: nil
        }
    }

    init?(method: BrewMethod?, brewer: BrewerType?, isBatch: Bool, note: String?) {
        if isBatch { self = .batch; return }
        switch brewer {
        case .espresso: self = .espresso; return
        case .v60: self = .v60; return
        case .flat: self = .kalita; return
        case .chemex: self = .chemex; return
        case .aeropress: self = .aeropress; return
        case .batch: self = .batch; return
        default: break
        }
        switch method {
        case .espresso: self = .espresso
        case .v60: self = .v60
        case .aeropress: self = .aeropress
        default:
            if let note, !note.trimmingCharacters(in: .whitespaces).isEmpty {
                self = .other
            } else {
                return nil
            }
        }
    }

    /// From a word on a menu.
    init?(word: String) {
        let folded = SeedPlace.fold(word)
        switch folded {
        case "espresso", "expresso", "ristretto": self = .espresso
        case "v60", "hario", "hariov60": self = .v60
        case "kalita", "kalitawave", "wave": self = .kalita
        case "chemex": self = .chemex
        case "aeropress": self = .aeropress
        case "batch", "batchbrew", "filtre", "filter", "drip": self = .batch
        default: return nil
        }
    }
}

/// What Save waits on, in screen order.
enum TastingField: CaseIterable, Hashable {
    case place
    case coffee
}

/// The form's working copy. Strings where the user types, values on save.
struct TastingDraft: Equatable {
    var id = UUID()
    var date = Date.now
    var place: Place?
    var placeID: String?
    var cardID: UUID?
    var coffee = TastedCoffee()
    var method: TastingMethod?
    var methodNote = ""
    var priceText = ""
    var currency = "EUR"
    var photos: [String] = []
    var rating: Int?
    var taste = TasteProfile()
    var flavors: [FlavorTag] = []
    var note = ""

    init() {}

    init(_ tasting: Tasting) {
        id = tasting.id
        date = tasting.date
        place = tasting.place
        placeID = tasting.placeID
        cardID = tasting.cardID
        coffee = tasting.coffee
        method = TastingMethod(method: tasting.method, brewer: tasting.brewer, isBatch: tasting.isBatch, note: tasting.methodNote)
        methodNote = tasting.methodNote ?? ""
        if let price = tasting.price {
            priceText = NSDecimalNumber(decimal: price.amount).stringValue
            currency = price.currency
        }
        photos = tasting.photos
        rating = tasting.rating
        taste = tasting.taste
        flavors = tasting.flavors
        note = tasting.note ?? ""
    }

    /// Set when the place came from the location fix rather than a tap, so a
    /// better suggestion may still replace it and a chosen one never is.
    var placeIsAutomatic = false

    /// Name and place. Nothing else is required.
    var missing: Set<TastingField> {
        var fields: Set<TastingField> = []
        if place == nil { fields.insert(.place) }
        if coffee.trimmedName.isEmpty { fields.insert(.coffee) }
        return fields
    }

    var canSave: Bool { missing.isEmpty }

    var notesText: String {
        get { coffee.tastingNotes.joined(separator: ", ") }
        set {
            coffee.tastingNotes = newValue
                .split(whereSeparator: { $0 == "," || $0 == "\n" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }

    var price: CupPrice? {
        let cleaned = priceText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let amount = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")),
              amount > 0 else { return nil }
        return CupPrice(amount: amount, currency: currency)
    }

    /// Collapsed Details header: "Fève · V60 · 5,50 €".
    var detailSummary: String? {
        var parts: [String] = []
        let roaster = coffee.roaster.trimmingCharacters(in: .whitespaces)
        if !roaster.isEmpty { parts.append(roaster) }
        if let method { parts.append(method == .other ? methodNote : method.label) }
        if let price { parts.append(price.formatted) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    mutating func choose(_ place: Place, _ placeID: String?) {
        self.place = place
        self.placeID = placeID
        placeIsAutomatic = false
    }

    /// The nearest place, taken for you. Never over a place you picked.
    mutating func autofill(_ place: Place, _ placeID: String?) {
        guard self.place == nil || placeIsAutomatic else { return }
        self.place = place
        self.placeID = placeID
        placeIsAutomatic = true
    }

    /// Links a card and copies it into the snapshot, once.
    mutating func link(_ card: CoffeeCard) {
        cardID = card.id
        let typed = coffee.trimmedName
        coffee = TastedCoffee(card: card)
        if coffee.trimmedName.isEmpty || coffee.name == "Untitled lot" { coffee.name = typed }
    }

    /// A bag read fills what is still empty and never overwrites.
    mutating func fill(from parsed: ParsedFields) {
        func fill(_ keyPath: WritableKeyPath<TastedCoffee, String>, _ value: String?) {
            guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty,
                  coffee[keyPath: keyPath].trimmingCharacters(in: .whitespaces).isEmpty else { return }
            coffee[keyPath: keyPath] = value
        }
        fill(\.name, parsed.name)
        fill(\.roaster, parsed.roaster)
        fill(\.country, parsed.country)
        fill(\.region, parsed.region)
        fill(\.farm, parsed.producer)
        fill(\.variety, parsed.variety)
        fill(\.process, parsed.process)
        if coffee.tastingNotes.isEmpty { coffee.tastingNotes = parsed.tastingNotes }
    }

    /// What a menu line adds to a card read: same rule as `fill`, only what is
    /// still empty. Guesses are handed back to be confirmed, never applied.
    @discardableResult
    mutating func fill(extra fields: [MenuField]) -> [MenuField] {
        var toConfirm: [MenuField] = []
        for field in fields {
            guard field.confidence == .read else {
                toConfirm.append(field)
                continue
            }
            switch field.kind {
            case .method: if method == nil { apply(field) }
            case .price: if priceText.trimmingCharacters(in: .whitespaces).isEmpty { apply(field) }
            case .notes: if coffee.tastingNotes.isEmpty { apply(field) }
            case .name, .roaster, .country, .process, .variety:
                if value(of: field.kind).trimmingCharacters(in: .whitespaces).isEmpty { apply(field) }
            }
        }
        return toConfirm
    }

    private func value(of kind: MenuField.Kind) -> String {
        switch kind {
        case .name: coffee.name
        case .roaster: coffee.roaster
        case .country: coffee.country
        case .process: coffee.process
        case .variety: coffee.variety
        case .notes: notesText
        case .method: method?.label ?? ""
        case .price: priceText
        }
    }

    /// Anything typed or chosen beyond the place the fix picked. Closing the
    /// flow with this true asks first.
    var hasContent: Bool {
        !coffee.trimmedName.isEmpty || !coffee.roaster.trimmingCharacters(in: .whitespaces).isEmpty
            || !coffee.country.isEmpty || !coffee.process.isEmpty || !coffee.variety.isEmpty
            || !coffee.tastingNotes.isEmpty || cardID != nil || method != nil
            || !priceText.trimmingCharacters(in: .whitespaces).isEmpty || !photos.isEmpty
            || rating != nil || taste != TasteProfile() || !flavors.isEmpty
            || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (place != nil && !placeIsAutomatic)
    }

    mutating func apply(_ field: MenuField) {
        switch field.kind {
        case .name: coffee.name = field.value
        case .roaster: coffee.roaster = field.value
        case .country: coffee.country = field.value
        case .process: coffee.process = field.value
        case .variety: coffee.variety = field.value
        case .notes: notesText = field.value
        case .method: method = TastingMethod(word: field.value) ?? method
        case .price:
            if let parsed = BagFieldParser.price(in: field.value) {
                priceText = String(format: "%.2f", parsed.0)
                currency = parsed.1
            }
        }
    }

    func tasting(base: Tasting?) -> Tasting {
        var tasting = base ?? Tasting(id: id, context: .home(brewID: nil), createdAt: .now)
        tasting.date = date
        if let place { tasting.context = .out(place: place, placeID: placeID) }
        tasting.cardID = cardID
        var coffee = coffee
        coffee.name = coffee.trimmedName
        coffee.roaster = coffee.roaster.trimmingCharacters(in: .whitespaces)
        tasting.coffee = coffee
        tasting.method = method?.method
        tasting.brewer = method?.brewer
        tasting.isBatch = method == .batch
        let note = methodNote.trimmingCharacters(in: .whitespaces)
        tasting.methodNote = method == .other && !note.isEmpty ? note : nil
        tasting.price = price
        tasting.photos = photos
        tasting.rating = rating
        tasting.taste = taste
        tasting.flavors = flavors
        let trimmed = self.note.trimmingCharacters(in: .whitespacesAndNewlines)
        tasting.note = trimmed.isEmpty ? nil : trimmed
        return tasting
    }
}
