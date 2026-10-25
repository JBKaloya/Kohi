import PhotosUI
import SwiftUI

/// Adding or editing a coffee had in a coffee shop. One screen, place first.
///
/// Where, then what, then the details behind a disclosure, then how it was.
/// Save only appears once there is a coffee name and a place: the one place
/// in Kohi where something is required, because a tasting without either is
/// not a tasting anyone can find again.
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
    @State private var scanning: TastingScanKind?
    @State private var isReading = false
    @State private var menuCandidates: [MenuCandidate] = []
    @State private var showsMenu = false
    @State private var uncertain: [MenuField] = []
    @State private var linkOffer: CoffeeCard?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var saveTrigger = 0
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
        if editing == nil { draft.currency = CupPrice.localCurrency }
        _draft = State(initialValue: draft)
        _showsDetails = State(initialValue: editing != nil && draft.detailSummary != nil)
    }

    private var isEditing: Bool { editing != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    PlaceSelectorRow(
                        place: draft.place,
                        suggestion: draft.place == nil ? topSuggestion : nil,
                        onAccept: { draft.choose($0.place, $0.placeID) },
                        onChoose: {
                            nearby.start()
                            choosingPlace = true
                        }
                    )

                    what

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
                            DictationField(text: $draft.note)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if draft.canSave {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .fontWeight(.medium)
                    }
                }
            }
            .animation(Motion.quick, value: draft.canSave)
        }
        .presentationBackground(Palette.paper)
        .haptic(.saved, trigger: saveTrigger)
        .onAppear(perform: load)
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
        .fullScreenCover(item: $scanning) { kind in
            ScanScreen(
                onScan: { scan in
                    scanning = nil
                    Task { await read(scan, as: kind) }
                },
                onCancel: { scanning = nil }
            )
            .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $showsMenu) {
            MenuPickSheet(
                candidates: menuCandidates,
                canAskModel: flags.isOn(.menuExtract),
                onAskModel: askModelForMenu,
                onPick: apply
            )
        }
        .alert(
            Copy.alreadyInCollection,
            isPresented: Binding(get: { linkOffer != nil }, set: { if !$0 { linkOffer = nil } }),
            presenting: linkOffer
        ) { card in
            Button("Link") { draft.link(card) }
            Button("Not now", role: .cancel) {}
        } message: { card in
            Text(store.title(for: card))
        }
        .onChange(of: photoItems) { _, items in
            Task { await importPhotos(items) }
        }
    }

    // MARK: - What

    private var what: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Copy.coffeeName).catalogueLabel()
            TextField(Placeholders.text(.cardCoffee), text: $draft.coffee.name)
                .font(Typography.subtitle)
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($nameFocused)
                .submitLabel(.done)

            if nameFocused, !suggestions.isEmpty {
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
                    Button("Unlink") { draft.cardID = nil }
                        .font(Typography.tag)
                        .foregroundStyle(Palette.ink)
                }
            }

            if !uncertain.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Copy.toConfirm).catalogueLabel()
                    FlowLayout {
                        ForEach(uncertain) { field in
                            TagChip(text: "\(field.kind.label): \(field.value)?", isSelected: false) {
                                draft.apply(field)
                                uncertain.removeAll { $0.id == field.id }
                            }
                        }
                    }
                }
            }

            HStack(spacing: 18) {
                if !store.cards.isEmpty {
                    action(Copy.fromCoffeeCollection) { pickingFromCollection = true }
                }
                action(Copy.scanBag) { scanning = .bag }
                action(Copy.scanMenu) { scanning = .menu }
                if isReading {
                    ProgressView().controlSize(.mini)
                }
            }
        }
        .animation(Motion.quick, value: nameFocused)
    }

    private func action(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title).catalogueLabel()
        }
        .buttonStyle(.plain)
        .touchTarget()
    }

    private var suggestions: [CoffeeSuggestions.Suggestion] {
        CoffeeSuggestions.suggest(
            draft.coffee.name,
            cards: store.cards,
            tastings: tastings.tastings.filter { $0.id != editing?.id },
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
            showsDetails = true
        }
        nameFocused = false
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
                    field("Roaster", text: $draft.coffee.roaster)

                    Button {
                        withAnimation(Motion.snappy) { showsMore.toggle() }
                    } label: {
                        Text(Copy.moreAboutThisCoffee)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.ink)
                    }
                    .buttonStyle(.plain)

                    if showsMore || draft.coffee.hasMore {
                        VStack(alignment: .leading, spacing: 14) {
                            field("Country", text: $draft.coffee.country, lexicon: CoffeeSuggestions.origins)
                            field("Region", text: $draft.coffee.region)
                            field("Farm", text: $draft.coffee.farm)
                            field("Variety", text: $draft.coffee.variety, lexicon: CoffeeSuggestions.varieties)
                            field("Process", text: $draft.coffee.process, lexicon: CoffeeSuggestions.processes)
                            field(Copy.onThePack, text: $draft.notesText)
                        }
                    }

                    methodPicker
                    pricePicker

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Date").catalogueLabel()
                        DatePicker("", selection: $draft.date, in: ...Date.now, displayedComponents: .date)
                            .labelsHidden()
                    }

                    photosRow
                }
                .transition(.opacity)
            }
        }
    }

    private func field(
        _ label: String,
        text: Binding<String>,
        lexicon: ((String) -> [String])? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).catalogueLabel()
            TextField("", text: text)
                .font(Typography.value)
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            if let lexicon {
                let words = lexicon(text.wrappedValue)
                if !words.isEmpty {
                    HStack(spacing: 7) {
                        ForEach(words, id: \.self) { word in
                            TagChip(text: word, isSelected: false) { text.wrappedValue = word }
                        }
                    }
                }
            }
            Rectangle().fill(Palette.hairline).frame(height: 1)
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

    // MARK: - Capture

    private func read(_ scan: ScanResult, as kind: TastingScanKind) async {
        isReading = true
        defer { isReading = false }
        let lines = await TextExtractor.read(image: scan.image)
        switch kind {
        case .bag:
            let parsed = FieldParser.parse(lines)
            draft.fill(from: parsed)
            if let hit = CardMatch.find(
                roaster: parsed.roaster ?? draft.coffee.roaster,
                name: parsed.name ?? draft.coffee.name,
                origin: parsed,
                in: store.cards
            ), draft.cardID != hit.card.id {
                linkOffer = hit.card
            }
        case .menu:
            menuText = lines.map(\.text)
            menuCandidates = MenuParser.parse(
                menuText,
                roasters: roasters.roasters.map(\.name) + ReferenceBase.roasterSeeds.map(\.name)
            )
            showsMenu = true
        }
    }

    @State private var menuText: [String] = []

    private func askModelForMenu() async -> [MenuCandidate] {
        guard let read = await FieldExtract.menu(lines: menuText, flags: flags, events: events) else {
            return menuCandidates
        }
        return MenuParser.grounded(read.value, in: menuText)
    }

    private func apply(_ candidate: MenuCandidate) {
        showsMenu = false
        for field in candidate.fields where field.confidence == .read {
            draft.apply(field)
        }
        uncertain = candidate.fields.filter { $0.confidence == .uncertain }
        if candidate.fields.contains(where: { $0.kind != .name && $0.confidence == .read }) {
            showsDetails = true
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

    // MARK: - Save

    private func load() {
        if !isEditing { nameFocused = draft.place != nil }
    }

    private func save() {
        guard draft.canSave else { return }
        saveTrigger += 1
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
        rememberServes(tasting)
        onSaved(tasting)
        dismiss()
    }

    /// A seed place now known to serve this roaster, as the card-era flow did.
    private func rememberServes(_ tasting: Tasting) {
        guard let placeID = tasting.placeID,
              let roasterID = tasting.coffee.roasterId,
              let roaster = roasters.roaster(id: roasterID) else { return }
        places.remember(placeID: placeID, roasterID: roaster.seedID ?? roaster.id.uuidString)
    }
}

enum TastingScanKind: String, Identifiable {
    case bag
    case menu

    var id: String { rawValue }
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

    /// Name and place. Nothing else is required.
    var canSave: Bool {
        !coffee.trimmedName.isEmpty && place != nil
    }

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
