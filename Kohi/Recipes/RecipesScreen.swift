import SwiftUI

/// Recipes as three views: every brew, the saved recipes, the reference catalogue.
struct RecipesScreen: View {
    @Environment(CardStore.self) private var store
    @Environment(RecipeStore.self) private var recipes
    @Environment(SetupStore.self) private var setup
    @Environment(AIFlags.self) private var flags
    @Environment(LooseBrewStore.self) private var looseBrews
    @Environment(\.appEnvironment) private var appEnvironment

    var onOpen: ((CoffeeCard) -> Void)?
    var onOpenBrew: ((CoffeeCard?, Brew) -> Void)?
    var onAgainBrew: ((CoffeeCard?, Brew) -> Void)?
    var onReadBrew: ((CoffeeCard?, Brew) -> Void)?
    /// Set for the parcours export. The remembered tab is left untouched.
    private let locksTab: Bool

    init(
        onOpen: ((CoffeeCard) -> Void)? = nil,
        onOpenBrew: ((CoffeeCard?, Brew) -> Void)? = nil,
        onAgainBrew: ((CoffeeCard?, Brew) -> Void)? = nil,
        onReadBrew: ((CoffeeCard?, Brew) -> Void)? = nil,
        initialTab: RecipeTab? = nil
    ) {
        self.onOpen = onOpen
        self.onOpenBrew = onOpenBrew
        self.onAgainBrew = onAgainBrew
        self.onReadBrew = onReadBrew
        self.locksTab = initialTab != nil
        if let initialTab {
            _tab = State(initialValue: initialTab)
        }
    }

    @State private var isAsking = false
    @State private var isShowingProfile = false
    @State private var tab: RecipeTab = .all
    @State private var filters: [RecipeTab: RecipeFilterState] = [:]
    @State private var showingMore = false
    @State private var opened: OpenedRecipe?
    @State private var didRestoreTab = false
    @State private var showFilters = false
    @State private var isNewRecipe = false
    @State private var editingRecipe: Recipe?
    /// A brew with no coffee yet, open on Add the coffee.
    @State private var addingCoffee: LooseCoffee?

    private struct LooseCoffee: Identifiable {
        let id: UUID
        var coffee: TastedCoffee
    }

    private struct OpenedRecipe: Identifiable {
        let id = UUID()
        let recipe: Recipe
        var scaled: ScaledRecipe?
        var card: CoffeeCard?
        var adjustments: [RecipeAdjustment] = []
        var provenance: RecipeProvenance?
        var grindShift = 0
        var isMine = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecipeTabs(
                selection: $tab,
                showsAsk: flags.isOn(.ask),
                onAsk: { isAsking = true }
            )
            .padding(.horizontal, 26)
            .padding(.top, 10)

            if tab != .all {
                HStack {
                    Button(Copy.filters) { showFilters = true }
                        .catalogueLabel()
                        .touchTarget()
                    Spacer()
                    if tab == .mine {
                        Button(Copy.newRecipe) { isNewRecipe = true }
                            .catalogueLabel()
                            .touchTarget()
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 12)
            }

            if tab != .all, !currentFilter.summary.isEmpty {
                Text(currentFilter.summary)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.horizontal, 26)
                    .padding(.top, 6)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch tab {
                    case .all: allContent
                    case .reference: referenceContent
                    case .mine: mineContent
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 8)
                .padding(.bottom, 190)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear(perform: restore)
        .onChange(of: tab) { _, value in
            guard !locksTab else { return }
            UserDefaults.standard.set(value.rawValue, forKey: Self.tabKey)
        }
        .sheet(isPresented: $isAsking) {
            AskSheet()
                .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $isShowingProfile) {
            ProfileSheet()
                .appEnvironment(appEnvironment)
        }
        .sheet(item: $opened) { opened in
            RecipeDetailSheet(
                recipe: opened.recipe,
                scaled: opened.scaled,
                adjustments: opened.adjustments,
                provenance: opened.provenance,
                forYourGrinder: grindState(opened.scaled?.recipe ?? opened.recipe, shift: opened.grindShift),
                card: opened.card,
                onDelete: opened.isMine ? { recipes.delete(opened.recipe) } : nil
            )
            .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $showFilters) {
            RecipeFilterSheet(state: filterBinding, grinders: authorGrinders)
                .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $isNewRecipe) {
            RecipeEditSheet()
                .appEnvironment(appEnvironment)
        }
        .sheet(item: $editingRecipe) { recipe in
            RecipeEditSheet(recipe: recipe)
                .appEnvironment(appEnvironment)
        }
        .sheet(item: $addingCoffee, onDismiss: keepToldCoffee) { _ in
            LinkCoffeeSheet(coffee: toldCoffee) { card in
                guard let id = addingCoffee?.id else { return }
                looseBrews.link(id, to: card.id, in: store)
                addingCoffee = nil
            }
            .appEnvironment(appEnvironment)
        }
    }

    private var toldCoffee: Binding<TastedCoffee> {
        Binding(
            get: { addingCoffee?.coffee ?? TastedCoffee() },
            set: { addingCoffee?.coffee = $0 }
        )
    }

    /// What was written about the coffee stays on the brew, linked or not.
    private func keepToldCoffee() {
        guard let told = addingCoffee, var brew = looseBrews.brew(id: told.id) else { return }
        addingCoffee = nil
        guard brew.coffee != told.coffee else { return }
        brew.coffee = told.coffee
        looseBrews.save(brew)
    }

    // MARK: - All

    private var hasBrew: Bool {
        store.cards.contains { !$0.brews.isEmpty } || !looseBrews.isEmpty
    }

    private var logged: [LoggedBrew] {
        BrewArchive.recent(in: store.cards, loose: looseBrews.brews)
    }

    /// The per-coffee block. On All the recipe filters are hidden, so they
    /// do not narrow it. On Mine they do.
    private var suggestionItems: [(card: CoffeeCard, suggestion: RecipeSuggestion)] {
        var list = RecipeSuggestions.items(
            from: store.cards,
            method: tab == .all ? nil : currentFilter.method,
            mine: recipes.recipes,
            neighbours: store.cards
        )
        if tab != .all, let roast = currentFilter.roast {
            list = list.filter { roast.matches($0.card.roastLevel) }
        }
        return list
    }

    private var suggestionHome: RecipeSuggestions.BlockHome {
        RecipeSuggestions.blockHome(hasBrew: hasBrew, count: suggestionItems.count)
    }

    private var visibleSuggestions: [(card: CoffeeCard, suggestion: RecipeSuggestion)] {
        showingMore ? suggestionItems : Array(suggestionItems.prefix(RecipeSuggestions.visibleCap))
    }

    @ViewBuilder
    private var allContent: some View {
        if suggestionHome == .all {
            suggestionBlock
        } else {
            brewArchive
        }
    }

    @ViewBuilder
    private var suggestionBlock: some View {
        if suggestionItems.isEmpty {
            if store.cards.isEmpty {
                Text("Scan a coffee first")
                    .font(Typography.body)
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.top, 8)
            }
        } else {
            ForEach(visibleSuggestions, id: \.card.id) { item in
                let scaled = RecipeScaling.scaled(item.suggestion.recipe, to: currentFilter.size)
                SuggestedRow(
                    suggestion: item.suggestion,
                    title: store.title(for: item.card),
                    compactLine: scaled.recipe.compactLine,
                    scaledFrom: scaled.scaledFromLabel ?? "",
                    onOpen: { onOpen?(item.card) }
                )
            }
            if !showingMore, suggestionItems.count > RecipeSuggestions.visibleCap {
                Button("More") { showingMore = true }
                    .catalogueLabel()
                    .padding(.top, 8)
            }
        }
    }

    private var brewArchive: some View {
        let rows = logged
        return BrewLog(
            brews: rows.map(\.brew),
            coffeeName: { brew in
                guard let row = rows.first(where: { $0.brew.id == brew.id }) else { return nil }
                guard let card = row.card else {
                    let told = row.brew.coffee?.trimmedName ?? ""
                    return told.isEmpty ? Copy.noCoffeeYet : told
                }
                return store.title(for: card)
            },
            onSelect: { brew in open(brew, with: onOpenBrew) },
            onAgain: onAgainBrew == nil ? nil : { brew in open(brew, with: onAgainBrew) },
            onRead: onReadBrew == nil ? nil : { brew in open(brew, with: onReadBrew) },
            onAddCoffee: { brew in
                addingCoffee = LooseCoffee(id: brew.id, coffee: brew.coffee ?? TastedCoffee())
            },
            needsCoffee: { brew in rows.first { $0.brew.id == brew.id }?.card == nil }
        )
    }

    private func open(_ brew: Brew, with action: ((CoffeeCard?, Brew) -> Void)?) {
        guard let row = logged.first(where: { $0.brew.id == brew.id }) else { return }
        action?(row.card, brew)
    }

    // MARK: - Reference

    private var filteredReferences: [Recipe] {
        var list = ReferenceBase.recipes
        if let method = currentFilter.method {
            list = list.filter { $0.method == method }
        }
        if let roast = currentFilter.roast {
            list = list.filter { recipe in
                recipe.notes.localizedCaseInsensitiveContains(roast.label)
                    || recipe.name.localizedCaseInsensitiveContains(roast.label)
            }
        }
        if let profile = currentFilter.profile {
            list = list.filter { $0.profileTags.contains(profile.rawValue) }
        }
        if let grinder = currentFilter.authorGrinder {
            list = list.filter { $0.authorGrinder == grinder }
        }
        return list
    }

    @ViewBuilder
    private var referenceContent: some View {
        ForEach(filteredReferences) { recipe in
            let scaled = RecipeScaling.scaled(recipe, to: currentFilter.size)
                RecipeRowView(
                    recipe: scaled.recipe,
                    attribution: recipe.attribution,
                    scaledFrom: scaled.scaledFromLabel ?? ""
                ) {
                opened = OpenedRecipe(
                    recipe: recipe,
                    scaled: scaled,
                    provenance: .reference(recipe.attribution)
                )
            }
        }

        Button("Edit kit") { isShowingProfile = true }
            .catalogueLabel()
            .padding(.top, 22)
    }

    // MARK: - Mine

    private var filteredMine: [Recipe] {
        var list = recipes.recipes
        if let method = currentFilter.method {
            list = list.filter { $0.method == method }
        }
        if let source = currentFilter.source {
            list = list.filter { source.matches($0) }
        }
        return list
    }

    @ViewBuilder
    private var mineContent: some View {
        if suggestionHome == .mine {
            suggestionBlock
                .padding(.bottom, 22)
        }
        if filteredMine.isEmpty {
            Text("Save a brew as a recipe to keep it here")
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
                .padding(.top, 8)
        } else {
            ForEach(filteredMine) { recipe in
                let scaled = RecipeScaling.scaled(recipe, to: currentFilter.size)
                RecipeRowView(
                    recipe: scaled.recipe,
                    attribution: recipe.attribution.isEmpty
                        ? CatalogueDate.happened(recipe.createdAt)
                        : recipe.attribution,
                    scaledFrom: scaled.scaledFromLabel ?? ""
                ) {
                    opened = OpenedRecipe(
                        recipe: recipe,
                        scaled: scaled,
                        card: recipe.cardID.flatMap { store.card(id: $0) },
                        provenance: .mine(recipe.name),
                        isMine: true
                    )
                }
                // Edit and Delete via swipe — discoverable without opening the detail.
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        recipes.delete(recipe)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        editingRecipe = recipe
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(Palette.ink)
                }
            }
        }

        insightsSection
    }

    @ViewBuilder
    private var insightsSection: some View {
        let insights = InsightsEngine.insights(
            for: store.cards,
            equipment: setup.equipment,
            water: setup.waterProfiles
        )
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Insights").catalogueLabel()
                    .padding(.top, 28)
                VStack(spacing: 0) {
                    ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                        if index > 0 {
                            Rectangle().fill(Palette.hairline).frame(height: 1)
                        }
                        InsightRow(insight: insight)
                    }
                }
            }
        }
    }

    // MARK: - Filters & restore

    private var currentFilter: RecipeFilterState {
        filters[tab] ?? seededFilter
    }

    private var seededFilter: RecipeFilterState {
        var state = RecipeFilterState()
        state.dripper = DripperChip.allCases.first { $0.method == setup.preferredRecipeMethod }
        return state
    }

    private var authorGrinders: [String] {
        Array(Set(ReferenceBase.recipes.compactMap(\.authorGrinder))).sorted()
    }

    private var filterBinding: Binding<RecipeFilterState> {
        Binding(
            get: { currentFilter },
            set: { filters[tab] = $0 }
        )
    }

    private var kitMethods: [BrewMethod] {
        var seen = Set<BrewMethod>()
        var ordered: [BrewMethod] = []
        for item in setup.equipment {
            for method in item.isDefaultFor where seen.insert(method).inserted {
                ordered.append(method)
            }
            if let family = item.brewerFamily, seen.insert(family.method).inserted {
                ordered.append(family.method)
            }
        }
        return ordered
    }

    private func restore() {
        guard !didRestoreTab else { return }
        didRestoreTab = true
        if !locksTab {
            if let raw = UserDefaults.standard.string(forKey: Self.tabKey),
               let stored = RecipeTab(rawValue: raw) {
                tab = stored
            } else {
                tab = .all
            }
        }
        if filters[.reference] == nil { filters[.reference] = seededFilter }
        if filters[.mine] == nil { filters[.mine] = seededFilter }
    }

    private func grindState(_ recipe: Recipe, shift: Int = 0) -> ForYourGrinder {
        GrindConversion.forYourGrinder(
            recipe: recipe,
            grinder: setup.preferredGrinder(for: recipe.method),
            calibrations: setup.calibrations,
            shift: shift
        )
    }

    private static let tabKey = "recipes.tab"
}
