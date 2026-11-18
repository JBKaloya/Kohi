import SwiftUI

/// Live first, then a recipe from Mine or the pros. New recipe heads Mine;
/// Adjust starts again from the selected one.
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
    @State private var showEditor = false
    @State private var showCreation = false
    @State private var adjustDraft: Recipe?

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
                JourneyChoiceRow(
                    systemName: "waveform",
                    title: Copy.live,
                    detail: Copy.liveDetail
                ) {
                    tapCount += 1
                    session.startLive()
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text(Copy.chooseARecipe).catalogueLabel()
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
                    lane: session.recipeLane,
                    onCreate: {
                        tapCount += 1
                        showCreation = true
                    }
                ) { recipe in
                    tapCount += 1
                    session.apply(recipe: recipe, setup: setup)
                }

                if let selected = session.nominalRecipe ?? session.recipe {
                    Button(RecipeCreation.isYours(selected) ? Copy.edit : Copy.editACopy) {
                        tapCount += 1
                        adjust(selected)
                    }
                    .catalogueLabel()
                }
            }
            .padding(.bottom, 24)
        }
        .haptic(.tap, trigger: tapCount)
        .onAppear {
            guard session.opensCreation else { return }
            session.opensCreation = false
            showCreation = true
        }
        .sheet(isPresented: $showCreation) {
            StepBuilderSheet.creation(
                draft: newRecipeDraft,
                onBrewOnce: { recipe in
                    session.applyOnce(recipe: recipe, setup: setup)
                    showCreation = false
                },
                onSave: { recipe in
                    keepInMine(recipe)
                    showCreation = false
                }
            )
            .appEnvironment(appEnvironment)
        }
        .sheet(item: $adjustDraft) { draft in
            StepBuilderSheet.copying(draft: draft) { recipe in
                keepInMine(recipe)
                adjustDraft = nil
            }
            .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $showEditor) {
            if let selected = session.nominalRecipe ?? session.recipe {
                StepBuilderSheet.adjusting(draft: selected) { edited in
                    tapCount += 1
                    if recipes.recipe(id: edited.id) != nil {
                        recipes.update(edited)
                    } else {
                        recipes.add(edited)
                    }
                    session.applyCreated(recipe: edited, setup: setup)
                    showEditor = false
                }
                .appEnvironment(appEnvironment)
            }
        }
    }

    /// Yours is edited in place; anyone else's is copied into Mine first.
    private func adjust(_ selected: Recipe) {
        if RecipeCreation.isYours(selected) {
            showEditor = true
        } else {
            adjustDraft = RecipeCreation.adjusting(selected)
        }
    }

    private func keepInMine(_ recipe: Recipe) {
        var mine = recipe
        mine.source = .mine
        recipes.add(mine)
        session.applyCreated(recipe: mine, setup: setup)
    }

    private var lane: Binding<RecipePickerList.Lane> {
        Binding(
            get: { session.recipeLane },
            set: { session.recipeLane = $0 }
        )
    }

    /// A recipe of yours, started from today's numbers. Kept in Mine.
    private var newRecipeDraft: Recipe {
        RecipeCreation.draft(
            from: session.brew,
            family: session.tab(in: setup),
            card: session.hasCard ? session.card : nil,
            roastLevel: session.card.roastLevel
        )
    }
}
