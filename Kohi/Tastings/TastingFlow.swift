import CoreLocation
import SwiftUI

/// One question per screen, for a new coffee-shop tasting.
nonisolated enum TastingStep: Int, CaseIterable, Sendable {
    case place
    case source
    case coffee
    case made
    case rating
    case remember
}

/// Which steps the flow walks and where it stands. Pure: the place step drops
/// out when the place is already known, and Save now only shows once there is
/// something worth saving and nothing left that is required.
nonisolated struct TastingFlowSteps: Equatable, Sendable {
    let steps: [TastingStep]
    private(set) var index: Int

    init(placeKnown: Bool, startingAt start: TastingStep? = nil) {
        let walked = placeKnown ? TastingStep.allCases.filter { $0 != .place } : TastingStep.allCases
        steps = walked
        index = start.flatMap { walked.firstIndex(of: $0) } ?? 0
    }

    var current: TastingStep { steps[index] }
    var total: Int { steps.count }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == steps.count - 1 }

    mutating func go(to step: TastingStep) {
        if let target = steps.firstIndex(of: step) { index = target }
    }

    mutating func next() {
        index = min(index + 1, steps.count - 1)
    }

    /// False at the first step: there is nowhere to go back to.
    @discardableResult
    mutating func back() -> Bool {
        guard index > 0 else { return false }
        index -= 1
        return true
    }

    /// The bonus steps (how it was made, how it was) can be cut short.
    func offersSaveNow(canSave: Bool) -> Bool {
        canSave && (current == .made || current == .rating)
    }
}

/// A new tasting, one question at a time: where, what is in the cup, which
/// coffee, how it was made, how it was, anything to remember. Editing a
/// tasting stays on `TastingComposeSheet`, where one field is one tap away.
struct TastingFlow: View {
    /// Known before the flow opens: the scan from home was made at this place.
    var place: PlaceSuggestion?
    /// A scan taken before the flow opened. The flow starts on Which coffee?
    /// and reads it.
    var scan: ScanResult?
    /// Snapshot and tests pass a list instead of asking for a fix.
    var previewSuggestions: [SeedPlace]?
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
    @State private var steps: TastingFlowSteps
    @State private var reader = TastingReader()
    @State private var nearby = NearbyPlaces()
    @State private var cameFromScan: Bool
    @State private var isScanning = false
    @State private var choosingPlace = false
    @State private var searchingPlace = false
    @State private var searchedPlace: Place?
    @State private var searchedPlaceID: String?
    @State private var pickingFromCollection = false
    @State private var pickedCard: CoffeeCard?
    @State private var confirmsDiscard = false
    @State private var saveTrigger = 0
    @FocusState private var nameFocused: Bool

    init(
        place: PlaceSuggestion? = nil,
        scan: ScanResult? = nil,
        previewSuggestions: [SeedPlace]? = nil,
        requestsLocation: Bool = true,
        startsAt: TastingStep? = nil,
        draft: TastingDraft? = nil,
        reader: TastingReader? = nil,
        onSaved: @escaping (Tasting) -> Void = { _ in }
    ) {
        if let reader { _reader = State(initialValue: reader) }
        self.place = place
        self.scan = scan
        self.previewSuggestions = previewSuggestions
        self.requestsLocation = requestsLocation
        self.onSaved = onSaved
        var initial = draft ?? TastingDraft()
        if draft == nil { initial.currency = CupPrice.localCurrency }
        if let place { initial.autofill(place.place, place.placeID) }
        _draft = State(initialValue: initial)
        _steps = State(initialValue: TastingFlowSteps(
            placeKnown: place != nil,
            startingAt: startsAt ?? (scan == nil ? nil : .coffee)
        ))
        _cameFromScan = State(initialValue: scan != nil)
    }

    var body: some View {
        Group {
            switch steps.current {
            case .place: placeStep
            case .source: sourceStep
            case .coffee: coffeeStep
            case .made: madeStep
            case .rating: ratingStep
            case .remember: rememberStep
            }
        }
        .animation(Motion.snappy, value: steps)
        .background(Palette.paper.ignoresSafeArea())
        .haptic(.saved, trigger: saveTrigger)
        .confirmationDialog(Copy.discardTasting, isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button(Copy.discard, role: .destructive) { dismiss() }
            Button(Copy.keepGoing, role: .cancel) {}
        }
        .task {
            if let scan { await read(scan) }
        }
        .task {
            guard place == nil, requestsLocation, previewSuggestions == nil, PlaceLocator.isAuthorized else { return }
            nearby.start()
        }
        .task(id: nearby.coordinate?.latitude) {
            guard previewSuggestions == nil, nearby.coordinate != nil else { return }
            places.beginGeocoding()
            await nearby.searchCafes()
        }
        .onChange(of: topSuggestion, initial: true) { _, suggestion in
            guard place == nil, nearby.coordinate != nil || previewSuggestions != nil, let suggestion else { return }
            draft.autofill(suggestion.place, suggestion.placeID)
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
        .sheet(isPresented: $searchingPlace) {
            PlaceSearchView(place: $searchedPlace, placeID: $searchedPlaceID)
                .appEnvironment(appEnvironment)
        }
        .onChange(of: searchedPlace) { _, place in
            guard let place else { return }
            draft.choose(place, searchedPlaceID)
            searchedPlace = nil
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
            cameFromScan = false
            steps.go(to: .coffee)
        }
        .fullScreenCover(isPresented: $isScanning) {
            ScanScreen(
                onScan: { scan in
                    isScanning = false
                    cameFromScan = true
                    steps.go(to: .coffee)
                    Task { await read(scan) }
                },
                onCancel: { isScanning = false }
            )
            .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $reader.showsMenu) {
            MenuPickSheet(
                candidates: reader.candidates,
                canAskModel: flags.isOn(.menuExtract),
                onAskModel: { await reader.askModel(flags: flags, events: events) },
                onPick: { reader.apply($0, into: $draft, cards: store.cards) }
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

    // MARK: - Steps

    private var placeStep: some View {
        StepFlow(
            step: steps.index,
            total: steps.total,
            question: Copy.whereAreYou,
            onClose: close,
            nextEnabled: draft.place != nil,
            onNext: advance
        ) {
            VStack(alignment: .leading, spacing: 18) {
                if let chosen = draft.place {
                    Button { choosingPlace = true } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(chosen.name)
                                    .font(Typography.subtitle)
                                    .foregroundStyle(Palette.ink)
                                if let line = placeDetail(chosen) {
                                    Text(line)
                                        .font(Typography.tag)
                                        .foregroundStyle(Palette.inkMuted)
                                }
                            }
                            Spacer(minLength: 8)
                            Text(Copy.change).catalogueLabel()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Change the place")
                } else if let suggestion = topSuggestion {
                    TagChip(text: Copy.placeSuggestion(suggestion.place.name), isSelected: false) {
                        draft.choose(suggestion.place, suggestion.placeID)
                    }
                }

                Button(action: otherPlace) {
                    Text(draft.place == nil && topSuggestion == nil ? Copy.choosePlace : Copy.placeOther)
                        .catalogueLabel()
                }
                .buttonStyle(.plain)
                .touchTarget()
            }
        }
    }

    private var sourceStep: some View {
        StepFlow(
            step: steps.index,
            total: steps.total,
            question: Copy.whatsInTheCup,
            onBack: back,
            onClose: close
        ) {
            VStack(alignment: .leading, spacing: 0) {
                sourceRow(Copy.scanTheCard, detail: Copy.scanTheCardSubtitle, systemName: "viewfinder") {
                    isScanning = true
                }
                Rectangle().fill(Palette.hairline).frame(height: 1)
                sourceRow(
                    Copy.fromMyCoffeeCollection,
                    detail: store.cards.isEmpty ? Copy.collectionIsEmpty : "\(store.cards.count) coffees",
                    systemName: "square.grid.2x2",
                    enabled: !store.cards.isEmpty
                ) {
                    pickingFromCollection = true
                }
                Rectangle().fill(Palette.hairline).frame(height: 1)
                sourceRow(Copy.typeItIn, detail: Copy.dictate, systemName: "character.cursor.ibeam") {
                    cameFromScan = false
                    steps.go(to: .coffee)
                    nameFocused = true
                }
            }
        }
    }

    private var coffeeStep: some View {
        StepFlow(
            step: steps.index,
            total: steps.total,
            question: Copy.whichCoffee,
            onBack: back,
            onClose: close,
            nextEnabled: !draft.coffee.trimmedName.isEmpty,
            onNext: advance,
            secondaryTitle: cameFromScan ? Copy.rescan : nil,
            onSecondary: cameFromScan ? { isScanning = true } : nil
        ) {
            VStack(alignment: .leading, spacing: 18) {
                if reader.isReading {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Copy.readingTheCard)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                        ShimmerBar(width: 180)
                        ShimmerBar(width: 120)
                    }
                } else if reader.couldNotRead {
                    Text(Copy.couldntReadThis)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }

                TastingCoffeeFields(
                    draft: $draft,
                    reader: reader,
                    nameFocused: $nameFocused,
                    showsIdentity: true
                )
                DictationField(text: $draft.coffee.name, mode: .replace)
            }
            .padding(.bottom, 24)
        }
        .onAppear {
            if !cameFromScan, draft.coffee.trimmedName.isEmpty { nameFocused = true }
        }
    }

    private var madeStep: some View {
        StepFlow(
            step: steps.index,
            total: steps.total,
            question: Copy.howWasItMade,
            onBack: back,
            onClose: close,
            onSkip: advance,
            onNext: advance,
            secondaryTitle: saveNowTitle,
            onSecondary: saveNowAction
        ) {
            TastingMadeFields(draft: $draft)
                .padding(.bottom, 24)
        }
    }

    private var ratingStep: some View {
        StepFlow(
            step: steps.index,
            total: steps.total,
            question: Copy.howWasIt,
            onBack: back,
            onClose: close,
            onSkip: advance,
            onNext: advance,
            secondaryTitle: saveNowTitle,
            onSecondary: saveNowAction
        ) {
            VStack(alignment: .leading, spacing: 28) {
                RatingPicker(rating: $draft.rating)
                FlavorsBlock(
                    selection: $draft.flavors,
                    declared: draft.coffee.declaredFlavors,
                    recent: SensoryScored.recent(tastings.tastings.filter { $0.id != draft.id }.map(\.flavors))
                )
            }
            .padding(.bottom, 24)
        }
    }

    private var rememberStep: some View {
        StepFlow(
            step: steps.index,
            total: steps.total,
            question: Copy.anythingToRemember,
            onBack: back,
            onClose: close,
            primaryTitle: "Save",
            onPrimary: save
        ) {
            VStack(alignment: .leading, spacing: 28) {
                TasteBlock(
                    taste: $draft.taste,
                    previous: previousTaste,
                    previousCaption: Copy.previousCupIsLighter
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
            .padding(.bottom, 24)
        }
    }

    private func sourceRow(
        _ title: String,
        detail: String,
        systemName: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Palette.hairline, lineWidth: 1)
                        .frame(width: 44, height: 44)
                    Image(systemName: systemName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(enabled ? Palette.ink : Palette.inkMuted)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.value)
                        .foregroundStyle(enabled ? Palette.ink : Palette.inkMuted)
                    Text(detail)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 52)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Moves

    private var saveNowTitle: String? {
        steps.offersSaveNow(canSave: draft.canSave) ? Copy.saveNow : nil
    }

    private var saveNowAction: (() -> Void)? {
        guard steps.offersSaveNow(canSave: draft.canSave) else { return nil }
        return { save() }
    }

    private func advance() {
        nameFocused = false
        steps.next()
    }

    private func back() {
        nameFocused = false
        steps.back()
    }

    private func close() {
        if draft.hasContent {
            confirmsDiscard = true
        } else {
            dismiss()
        }
    }

    private func otherPlace() {
        if nearby.isDenied {
            searchingPlace = true
        } else {
            if requestsLocation { nearby.start() }
            choosingPlace = true
        }
    }

    private func read(_ scan: ScanResult) async {
        await reader.read(scan, into: $draft, roasters: knownRoasterNames(roasters), cards: store.cards)
        if reader.couldNotRead { nameFocused = true }
    }

    private func save() {
        guard draft.canSave else { return }
        saveTrigger += 1
        let tasting = TastingSaver.save(draft, editing: nil, tastings: tastings, roasters: roasters, places: places)
        onSaved(tasting)
        dismiss()
    }

    // MARK: - Context

    private var topSuggestion: PlaceSuggestion? {
        nearby.suggestions(
            roaster: draft.coffee.roaster,
            index: places,
            tastings: tastings.tastings,
            preview: previewSuggestions
        ).first
    }

    private var previousTaste: TasteProfile? {
        let name = SeedPlace.fold(draft.coffee.name)
        guard !name.isEmpty else { return nil }
        return SensoryScored.previous(
            tastings.tastings
                .filter { $0.id != draft.id && SeedPlace.fold($0.coffee.name) == name }
                .map(\.taste)
        )
    }

    private func placeDetail(_ place: Place) -> String? {
        let parts = [place.address, place.city ?? ""]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
