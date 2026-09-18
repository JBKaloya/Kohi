import SwiftUI

/// The one main screen. A vertical grid of cards on paper, a pinch to change how
/// many fit across, and a single button to add another.
struct GridScreen: View {
    let onScan: () -> Void
    var isIngesting = false

    @Environment(RecipeStore.self) private var recipes
    @Environment(CardStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(SetupStore.self) private var setup
    @Environment(IntentRouter.self) private var router
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.displayScale) private var displayScale

    @State private var density: GridDensity = .three
    @State private var densityChanges = 0
    @State private var gridWidth: CGFloat = 0
    /// Live magnification during a pinch. `@GestureState` resets to 1 when the
    /// gesture ends *or is cancelled*, which prevents hit-testing drift.
    @GestureState private var pinch: CGFloat = 1
    @State private var selection: CoffeeCard?
    @State private var searchText = ""
    @State private var methodFilter: BrewMethod?
    @State private var flavorFilter: String?
    @State private var placeFilter: String?
    @State private var scrolledDown = false
    @State private var showProfile = false
    @State private var tab: CatalogueTab = .coffees
    /// A recipe chosen in the Recipes tab, handed to the card it opens.
    @State private var pendingRecipe: Recipe?
    @State private var pendingScale: RecipeSize?
    /// Set when a shortcut asked for a brew rather than a tap.
    @State private var startsBrew = false
    @State private var scrollToSuggested = false
    @State private var isPickingCoffee = false
    @State private var brewCoffee: CoffeeCard?
    @State private var flow: BrewSession?
    @Namespace private var namespace

    private var filteredCards: [CoffeeCard] {
        store.cards.filter { card in
            if let methodFilter {
                guard card.brews.contains(where: { $0.method == methodFilter })
                        || card.brewMethod == methodFilter else { return false }
            }
            if let flavorFilter {
                guard store.flavorIDs(for: card).contains(flavorFilter) else { return false }
            }
            if let placeFilter {
                guard card.place?.name == placeFilter else { return false }
            }
            if searchText.isEmpty { return true }
            return card.name.localizedCaseInsensitiveContains(searchText)
                || card.roaster.localizedCaseInsensitiveContains(searchText)
                || card.country.localizedCaseInsensitiveContains(searchText)
                || card.region.localizedCaseInsensitiveContains(searchText)
                || card.variety.localizedCaseInsensitiveContains(searchText)
                || card.process.localizedCaseInsensitiveContains(searchText)
                || card.tastingNotes.contains { $0.localizedCaseInsensitiveContains(searchText) }
                || (card.place?.name.localizedCaseInsensitiveContains(searchText) ?? false)
                || card.declaredFlavors.contains { $0.displayName.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.paper.ignoresSafeArea()

                VStack(spacing: 0) {
                    if showsTabs {
                        CatalogueTabs(selection: $tab)
                    }

                    switch tab {
                    case .coffees:
                        if store.cards.isEmpty && searchText.isEmpty && methodFilter == nil && flavorFilter == nil && placeFilter == nil {
                            EmptyStateView()
                                .frame(maxHeight: .infinity)
                        } else {
                            VStack(spacing: 0) {
                                if shouldShowSearch { searchChips }
                                grid
                            }
                        }
                    case .recipes:
                        RecipesScreen(
                            onOpen: { card in
                                scrollToSuggested = true
                                selection = card
                            }
                        )
                    }
                }
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 16) {
                    if isIngesting {
                        ProgressView().tint(Palette.inkMuted)
                    }
                    if tab == .coffees {
                        ScanButton(action: onScan)
                    } else {
                        CircleButton(
                            systemName: "cup.and.saucer",
                            accessibilityLabel: "Start a brew"
                        ) {
                            isPickingCoffee = true
                        }
                    }
                }
                .padding(.bottom, 26)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(selection == nil ? .automatic : .hidden, for: .navigationBar)
            .modifier(ConditionalSearchModifier(
                text: $searchText,
                isEnabled: shouldShowSearch
            ))
            .onChange(of: shouldShowSearch) { _, show in
                if !show {
                    searchText = ""
                    methodFilter = nil
                    flavorFilter = nil
                    placeFilter = nil
                }
            }
            .haptic(.densityChange, trigger: densityChanges)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Kohi")
                        .font(Typography.brand)
                        .foregroundStyle(Palette.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showProfile = true
                    } label: {
                        Image(systemName: account.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                    }
                }
            }
            .sheet(isPresented: $showProfile) {
                ProfileSheet()
                    .appEnvironment(appEnvironment)
            }
            .sheet(isPresented: $isPickingCoffee) {
                RecipeCoffeePicker(picked: $brewCoffee)
                    .appEnvironment(appEnvironment)
            }
            .onChange(of: brewCoffee) { _, card in
                guard let card else { return }
                let suggestion = RecipeRules.suggestion(
                    for: card,
                    method: nil,
                    mine: recipes.recipes,
                    neighbours: store.cards
                )
                flow = BrewSession(
                    card: card,
                    recipe: suggestion?.recipe,
                    setup: setup
                )
                brewCoffee = nil
            }
            .fullScreenCover(item: $flow) { session in
                BrewFlowHost(
                    session: session,
                    onDismiss: { flow = nil },
                    onAgain: { seed in
                        flow = BrewSession(
                            card: session.card,
                            existing: seed.again(),
                            start: .kit,
                            setup: setup
                        )
                    }
                )
                .appEnvironment(appEnvironment)
            }
            .navigationDestination(item: $selection) { card in
                CardDetailView(
                    card: card,
                    seedRecipe: pendingRecipe,
                    seedSize: pendingScale,
                    startsBrew: startsBrew,
                    startsAtSuggested: scrollToSuggested
                )
                    .appEnvironment(appEnvironment)
                    .modifier(ZoomTransitionModifier(id: card.id, namespace: namespace))
            }
            .onChange(of: selection) { _, card in
                // The recipe is spent once the card has it; coming back to the
                // card later should not reopen a brew sheet.
                if card == nil {
                    pendingRecipe = nil
                    pendingScale = nil
                    startsBrew = false
                    scrollToSuggested = false
                }
            }
            .task { await openFirstCardIfRequested() }
            .task { handleIntent() }
            .onChange(of: router.pending) { _, _ in handleIntent() }
        }
        .tint(Palette.ink)
    }

    /// A shortcut asked for a brew. It opens the coffee it named, or the one
    /// you last brewed, and lands on the brew sheet — never writing anything
    /// on its own.
    private func handleIntent() {
        guard case .logBrew(let coffee, let method)? = router.take() else { return }

        let card = coffee.flatMap { name in
            store.cards.first { $0.name.localizedCaseInsensitiveContains(name) }
        } ?? preferredCard(for: method)

        guard let card else { return }
        tab = .coffees
        flow = BrewSession(card: card, setup: setup)
    }

    /// The coffee a brew most likely belongs to: the one most recently brewed
    /// with that method, else the most recent card.
    private func preferredCard(for method: BrewMethod?) -> CoffeeCard? {
        guard let method else { return store.cards.first }
        let brewed = store.cards
            .filter { card in card.brews.contains { $0.method == method } }
            .max { a, b in
                (a.brews.first?.date ?? .distantPast) < (b.brews.first?.date ?? .distantPast)
            }
        return brewed ?? store.cards.first
    }

    /// Three pages of a 3-column grid ≈ 20 cards, plus enough scrolling to
    /// signal that the user is browsing, not just glancing. Search reads the
    /// archive, so it belongs to the Coffees side only.
    private var shouldShowSearch: Bool {
        tab == .coffees && store.cards.count >= 20 && (scrolledDown || !searchText.isEmpty || methodFilter != nil || flavorFilter != nil || placeFilter != nil)
    }

    private var searchChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !searchMethods.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(searchMethods) { method in
                            TagChip(text: method.label, isSelected: methodFilter == method) {
                                methodFilter = methodFilter == method ? nil : method
                            }
                        }
                    }
                }
            }
            if !searchFlavors.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(searchFlavors, id: \.id) { tag in
                            TagChip(text: tag.displayName, isSelected: flavorFilter == tag.id) {
                                flavorFilter = flavorFilter == tag.id ? nil : tag.id
                            }
                        }
                    }
                }
            }
            if !searchPlaces.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(searchPlaces, id: \.self) { place in
                            TagChip(text: place, isSelected: placeFilter == place) {
                                placeFilter = placeFilter == place ? nil : place
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var searchMethods: [BrewMethod] {
        BrewMethod.allCases.filter { method in
            store.cards.contains { $0.brews.contains { $0.method == method } || $0.brewMethod == method }
        }
    }

    private var searchFlavors: [FlavorTag] {
        var seen = Set<String>()
        var tags: [FlavorTag] = []
        for card in store.cards {
            for id in store.flavorIDs(for: card) where seen.insert(id).inserted {
                tags.append(FlavorTag(id: id))
            }
        }
        return Array(tags.prefix(16))
    }

    private var searchPlaces: [String] {
        var seen = Set<String>()
        return store.cards.compactMap { card -> String? in
            guard let name = card.place?.name, !name.isEmpty, seen.insert(name).inserted else { return nil }
            return name
        }
    }

    /// An archive of one card does not need a second tab yet; the tabs appear
    /// once there is anything to switch between.
    private var showsTabs: Bool {
        !store.cards.isEmpty
    }

    private var grid: some View {
        GeometryReader { proxy in
            let metrics = Metrics(width: proxy.size.width, density: density)

            ScrollViewReader { scroller in
                ScrollView {
                    LazyVGrid(columns: metrics.columns, spacing: density.spacing) {
                        ForEach(filteredCards) { card in
                            CardTile(
                                card: card,
                                width: metrics.tileWidth,
                                namespace: namespace
                            ) {
                                selection = card
                            }
                            .id(card.id)
                        }
                    }
                    .padding(.horizontal, density.horizontalPadding)
                    .padding(.top, 16)
                    .padding(.bottom, 190)
                }
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y > 200
                } action: { _, past in
                    withAnimation(Motion.snappy) { scrolledDown = past }
                }
                .scaleEffect(pinchScale, anchor: .center)
                .simultaneousGesture(pinchGesture)
                .onChange(of: store.landingCardID) { _, landing in
                    // A new card goes to the top of the archive, so bring the
                    // top of the archive into view to watch it arrive.
                    guard let landing else { return }
                    withAnimation(Motion.gentle) {
                        scroller.scrollTo(landing, anchor: .top)
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: WidthKey.self, value: geo.size.width)
            }
        }
        .onPreferenceChange(WidthKey.self) { gridWidth = $0 }
    }

    /// Damped so a wild pinch does not throw the grid off screen before it snaps.
    private var pinchScale: CGFloat {
        let damped = 1 + (pinch - 1) * Motion.Grid.pinchDamping
        return min(max(damped, Motion.Grid.pinchClamp.lowerBound), Motion.Grid.pinchClamp.upperBound)
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: Motion.Grid.minimumScaleDelta)
            .updating($pinch) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                let target = density.stepped(by: value.magnification)
                if target != density {
                    densityChanges += 1
                    prewarm(for: target)
                }
                withAnimation(Motion.snappy) { density = target }
            }
    }

    /// One and two columns read from the 1024 bucket, three and four from 512,
    /// so only a pinch across that boundary needs anything decoded. When it
    /// happens, get ahead of it for the cards most likely to be on screen.
    private func prewarm(for target: GridDensity) {
        let current = ThumbnailCache.bucket(forWidth: tileWidth(for: density), scale: displayScale)
        let next = ThumbnailCache.bucket(forWidth: tileWidth(for: target), scale: displayScale)
        guard current != next else { return }
        for card in store.cards.prefix(Motion.Grid.prewarmCount) {
            ThumbnailCache.shared.warm(card, buckets: [next])
        }
    }

    private func tileWidth(for density: GridDensity) -> CGFloat {
        Metrics(width: gridWidth, density: density).tileWidth
    }

    /// Development shortcut: `SIMCTL_CHILD_KOHI_OPEN_FIRST=1` opens the newest
    /// card on launch so the detail view can be iterated on without tapping.
    private func openFirstCardIfRequested() async {
        #if DEBUG
        guard DebugHooks.opensFirstCard else { return }
        try? await Task.sleep(for: .seconds(1))
        selection = store.cards.first
        #endif
    }

    private struct Metrics {
        let columns: [GridItem]
        let tileWidth: CGFloat

        init(width: CGFloat, density: GridDensity) {
            let spacing = density.spacing
            let available = width
                - density.horizontalPadding * 2
                - spacing * CGFloat(density.columns - 1)
            tileWidth = max(1, available / CGFloat(density.columns))
            columns = Array(
                repeating: GridItem(.flexible(), spacing: spacing, alignment: .top),
                count: density.columns
            )
        }
    }
}

// MARK: - Backward compatibility helpers

private struct WidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Shows the search bar only when the card collection is large enough to warrant it.
private struct ConditionalSearchModifier: ViewModifier {
    @Binding var text: String
    var isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(
                text: $text,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: Placeholders.text(.searchQuery)
            )
        } else {
            content
        }
    }
}

private struct ZoomTransitionModifier: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}
