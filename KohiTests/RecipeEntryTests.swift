import Foundation
import Testing
@testable import Kohi

/// Two ways into a recipe, named the same everywhere: choose one from the
/// base, or create your own. Creating always lands in Mine.
@MainActor
struct RecipeEntryTests {
    private func source(_ file: String) throws -> String {
        try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: file))
    }

    private func store() -> RecipeStore {
        RecipeStore(files: JSONFileStore(filename: "recipes-entry-\(UUID().uuidString).json"))
    }

    @Test func theCopyNamesTheEntries() {
        #expect(Copy.whichRecipe == "Recipe")
        #expect(Copy.live == "Live")
        #expect(Copy.chooseARecipe == "Choose a recipe")
        #expect(Copy.newRecipe == "New recipe")
        #expect(Copy.adjust == "Adjust")
    }

    @Test func recipeLeadsWithLiveThenTheRecipes() throws {
        let scope = try source("Recipes/BrewScopeView.swift")
        let body = scope.components(separatedBy: "var body").dropFirst().first ?? ""
        let live = body.range(of: "title: Copy.live")
        let choose = body.range(of: "Copy.chooseARecipe")
        #expect(live != nil && choose != nil)
        if let live, let choose { #expect(live.lowerBound < choose.lowerBound) }
        #expect(body.contains("session.startLive()"))
        #expect(!body.contains("Copy.createYourRecipe"))
        #expect(!body.contains("Copy.noRecipesYet"))
    }

    @Test func liveIsAPlainChoiceRow() throws {
        let scope = try source("Recipes/BrewScopeView.swift")
        let body = scope.components(separatedBy: "var body").dropFirst().first ?? ""
        let row = body.components(separatedBy: "JourneyChoiceRow(").dropFirst().first ?? ""
        let call = row.components(separatedBy: "session.startLive()").first ?? ""
        #expect(!call.contains(".overlay"))
        #expect(!call.contains(".background"))
        #expect(!call.contains("stroke"))
    }

    @Test func newRecipeHeadsMineEvenWhenEmpty() throws {
        let picker = try source("Edit/RecipePickerSheet.swift")
        #expect(picker.contains("if shows(.mine), !recipes.recipes.isEmpty || onCreate != nil"))
        let section = picker.components(separatedBy: "private func section(").dropFirst().first ?? ""
        let row = section.range(of: "NewRecipeRow(action: onCreate)")
        let list = section.range(of: "ForEach(list)")
        #expect(row != nil && list != nil)
        if let row, let list { #expect(row.lowerBound < list.lowerBound) }
        let scope = try source("Recipes/BrewScopeView.swift")
        #expect(scope.contains("onCreate: {"))
    }

    @Test func newRecipeLooksLikeAdjust() throws {
        let picker = try source("Edit/RecipePickerSheet.swift")
        let row = picker.components(separatedBy: "struct NewRecipeRow").dropFirst().first?
            .components(separatedBy: "struct RecipePickerSheet").first ?? ""
        #expect(row.contains(".catalogueLabel()"))
        #expect(row.contains("Image(systemName: \"plus\")"))
        #expect(!row.contains("Circle()"))
        #expect(!row.contains("Typography.value"))
        let scope = try source("Recipes/BrewScopeView.swift")
        #expect(scope.contains("Button(Copy.adjust)"))
        #expect(!scope.contains("Button(\"Edit recipe\")"))
    }

    @Test func oneCreationReplacesNewRecipeAndExpress() throws {
        let scope = try source("Recipes/BrewScopeView.swift")
        #expect(!scope.contains("Build an express recipe"))
        #expect(!scope.contains("Copy.newRecipe"))
        #expect(scope.contains("StepBuilderSheet.creation("))
        let recipes = try source("Recipes/RecipesScreen.swift")
        #expect(recipes.contains("StepBuilderSheet.creation(draft: RecipeCreation.blank(), asksMethod: true)"))
    }

    @Test func theLauncherOffersLiveAndChooseARecipe() throws {
        let start = try source("Recipes/BrewStartView.swift")
        let live = start.range(of: "title: Copy.live")
        let choose = start.range(of: "title: Copy.chooseARecipe")
        #expect(live != nil && choose != nil)
        if let live, let choose { #expect(live.lowerBound < choose.lowerBound) }
        #expect(start.contains("session.startLive()"))
        #expect(!start.contains("Copy.createYourRecipe"))
        #expect(!start.contains("session.openRecipes(.pros)"))
    }

    @Test func createFromTheLauncherOpensOnWhichRecipeAndKeepsTheCount() {
        let setup = BrewJourneySupport.setup()
        var card = BrewJourneySupport.card()
        card.brews = [Brew(method: .v60, dose: 15, water: 250)]
        let session = BrewSession(card: card, setup: setup)
        #expect(session.step == .start)
        let total = session.progressTotal
        session.openCreation()
        #expect(session.step == .scope)
        #expect(session.opensCreation)
        #expect(session.progressTotal == total)
        #expect(session.progressIndex == 1)
        #expect(session.retreat())
        #expect(session.step == .start)
    }

    @Test func aCreatedRecipeIsMineAndDrivesTheBrew() {
        let setup = BrewJourneySupport.setup()
        let recipes = store()
        let session = BrewSession(card: BrewJourneySupport.card(), setup: setup)
        let draft = RecipeCreation.draft(
            from: Brew(method: .v60, dose: 15, water: 225),
            family: .handBrew,
            card: session.card,
            roastLevel: nil
        )
        #expect(draft.source == .mine)
        #expect(!draft.steps.isEmpty)
        let saved = recipes.add(draft)
        session.applyCreated(recipe: saved, setup: setup)
        #expect(session.recipe?.id == saved.id)
        #expect(session.brew.dose == 15)
        #expect(session.brew.water == 225)
        #expect(session.brew.scale == nil)
        #expect(session.recipeLane == .mine)
        #expect(recipes.recipe(id: saved.id)?.source == .mine)
    }

    @Test func theScopeAppliesACreationAsWritten() throws {
        let scope = try source("Recipes/BrewScopeView.swift")
        #expect(scope.contains("session.applyCreated(recipe: mine, setup: setup)"))
    }

    @Test func homeTabsUseTheBrewNames() {
        #expect(RecipeTab.mine.label == RecipePickerList.Lane.mine.label)
        #expect(RecipeTab.reference.label == RecipePickerList.Lane.pros.label)
    }

    @Test func homeMineLeadsWithNewRecipe() throws {
        let screen = try source("Recipes/RecipesScreen.swift")
        #expect(!screen.contains("Copy.createYourRecipe"))
        let mine = screen.components(separatedBy: "private var mineContent").dropFirst().first ?? ""
        let row = mine.range(of: "NewRecipeRow")
        let suggestions = mine.range(of: "suggestionBlock")
        let list = mine.range(of: "ForEach(filteredMine)")
        #expect(row != nil && suggestions != nil && list != nil)
        if let row, let suggestions, let list {
            #expect(row.lowerBound < suggestions.lowerBound)
            #expect(row.lowerBound < list.lowerBound)
        }
    }

    @Test func detailOffersOnlyAdjust() throws {
        let detail = try source("Recipes/RecipeDetailSheet.swift")
        #expect(detail.contains("Button(Copy.adjust)"))
        #expect(!detail.contains("Save a copy"))
        #expect(!detail.contains("RecipeEditSheet"))
        #expect(!detail.contains("Button(\"Edit\")"))
        #expect(detail.contains("RecipeCreation.adjusting(recipe)"))
    }

    @Test func brewAndHomeShareTheAdjustEditor() throws {
        for file in ["Recipes/BrewScopeView.swift", "Recipes/RecipesScreen.swift", "Recipes/RecipeDetailSheet.swift"] {
            let text = try source(file)
            #expect(text.contains("StepBuilderSheet.adjusting(draft:"), "\(file)")
            #expect(!text.contains("RecipeEditSheet("), "\(file)")
        }
    }

    @Test func aTabIsNotRepeatedOnItsRows() throws {
        let mine = Recipe(name: "Mine one", method: .v60, source: .mine)
        let express = Recipe(name: "Express one", method: .v60, source: .express)
        let pro = try #require(ReferenceBase.recipes.first)
        #expect(RecipeRowView.provenance(of: mine, under: RecipeTab.mine.label).isEmpty)
        #expect(RecipeRowView.provenance(of: express, under: RecipeTab.mine.label) == RecipeSource.express.label)
        #expect(RecipeRowView.provenance(of: pro, under: RecipeTab.reference.label).isEmpty)
        #expect(RecipeRowView.provenance(of: mine, under: nil) == RecipeSource.mine.label)
        let picker = try source("Edit/RecipePickerSheet.swift")
        let section = picker.components(separatedBy: "private func section(").dropFirst().first ?? ""
        #expect(section.contains("if lane == nil"))
    }

    @Test func aBlankRecipeStartsAtFifteenToOne() {
        let blank = RecipeCreation.blank()
        #expect(blank.dose == 15)
        #expect(blank.water == 225)
        #expect(blank.source == .mine)
        #expect(blank.steps.last { $0.targetMass != nil }?.targetMass == 225)
    }

    @Test func switchingMethodRebuildsUntouchedSteps() {
        let blank = RecipeCreation.blank()
        let espresso = RecipeCreation.switching(blank, to: .espresso)
        #expect(espresso.method == .espresso)
        #expect(espresso.beverage == 30)
        #expect(espresso.steps.contains { $0.action == .shot })

        var edited = blank
        edited.steps[1].derived = false
        let kept = RecipeCreation.switching(edited, to: .frenchPress)
        #expect(kept.steps == edited.steps)
    }
}
