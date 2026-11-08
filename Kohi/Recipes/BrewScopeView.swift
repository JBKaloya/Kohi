import SwiftUI

/// Recipe selection: pick a family, pick a recipe, or build your own.
/// Format and Parameters moved to Today's settings.
struct BrewScopeView: View {
    @Bindable var session: BrewSession
    var onBack: () -> Void
    var onClose: () -> Void
    var onNext: () -> Void

    @Environment(SetupStore.self) private var setup
    @Environment(RecipeStore.self) private var recipes
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var tapCount = 0
    @State private var showBuilder = false
    @State private var showEditor = false

    var body: some View {
        StepFlow(
            step: session.progressIndex,
            total: session.progressTotal,
            question: Copy.whichRecipe,
            onBack: onBack,
            onClose: onClose,
            nextTitle: "Next",
            nextEnabled: true,
            onNext: onNext
        ) {
            VStack(alignment: .leading, spacing: 28) {
                // Family + provenance rails
                VStack(alignment: .leading, spacing: 16) {
                    TabRail(
                        tabs: BrewKit.journeyTabs,
                        selection: Binding(
                            get: { session.tab(in: setup) },
                            set: { family in
                                tapCount += 1
                                session.apply(family: family, setup: setup)
                            }
                        ),
                        underline: .active,
                        title: \.label
                    )
                    TabRail(
                        tabs: Array(RecipePickerList.Lane.allCases),
                        selection: lane,
                        underline: .active,
                        title: \.label
                    )
                }

                // Recipe list — no size scaling here; scaling happens on Dial.
                RecipePickerList(
                    card: session.card,
                    method: session.brew.method,
                    family: session.tab(in: setup),
                    size: nil,
                    selected: session.recipe,
                    lane: session.recipeLane
                ) { recipe in
                    tapCount += 1
                    session.apply(recipe: recipe, setup: setup)
                }

                if session.recipeLane == .mine, recipes.recipes.isEmpty {
                    Text(Copy.recipesYouSave)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }

                // Edit selected express/mine recipe, or build a new one.
                HStack(spacing: 20) {
                    if let selected = session.recipe,
                       (selected.source == .express || selected.source == .mine) {
                        Button("Edit recipe") {
                            tapCount += 1
                            showEditor = true
                        }
                        .catalogueLabel()
                    }
                    Button("Build an express recipe") { showBuilder = true }
                        .catalogueLabel()
                }
            }
            .padding(.bottom, 24)
        }
        .haptic(.tap, trigger: tapCount)
        .sheet(isPresented: $showBuilder) {
            StepBuilderSheet(
                draft: expressDraft,
                onSave: { recipe in
                    recipes.add(recipe)
                    session.apply(recipe: recipe, setup: setup)
                    showBuilder = false
                }
            )
            .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $showEditor) {
            if let selected = session.recipe {
                StepBuilderSheet(
                    draft: selected,
                    onSave: { edited in
                        tapCount += 1
                        session.apply(recipe: edited, setup: setup)
                        showEditor = false
                    }
                )
                .appEnvironment(appEnvironment)
            }
        }
    }

    private var lane: Binding<RecipePickerList.Lane> {
        Binding(
            get: { session.recipeLane },
            set: { session.recipeLane = $0 }
        )
    }

    private var expressDraft: Recipe {
        var recipe = Recipe(
            name: Recipe.expressTitle(family: session.tab(in: setup), card: session.card),
            method: session.brew.method ?? .v60,
            dose: session.brew.dose,
            water: session.brew.water,
            beverage: session.brew.beverage,
            temperature: session.brew.temperature,
            seconds: session.brew.seconds,
            grindLabel: session.brew.grind.display(),
            source: .express,
            evidence: .unverified,
            cardID: session.card.id
        )
        return DefaultSequence.filling(recipe, roastLevel: session.card.roastLevel)
    }
}
