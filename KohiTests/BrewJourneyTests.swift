import Foundation
import SwiftUI
import Testing
@testable import Kohi

/// Isolated kit and stores so the brew journey tests never touch the app's files.
@MainActor
enum BrewJourneySupport {
    static func setup() -> SetupStore {
        let setup = SetupStore(files: JSONDocumentStore(filename: "setup-journey-\(UUID().uuidString).json"))
        let paper = BrewFilter(brand: "Hario", shape: "01")
        let brewer = Equipment(
            kind: .brewer,
            brand: "Hario",
            model: "V60",
            filters: [paper],
            defaultFilterId: paper.id
        )
        let kettle = Equipment(
            kind: .kettle,
            brand: "Fellow",
            model: "Stagg EKG",
            isGooseneck: true
        )
        let grinder = Equipment(
            kind: .grinder,
            brand: "1Zpresso",
            model: "J-Ultra",
            adjustment: .clicks,
            ranges: [GrindRange(method: .v60, low: 18, high: 36)]
        )
        let water = WaterProfile(name: "Tap", source: .tap, isDefault: true)
        setup.add(brewer)
        setup.setDefault(brewer, for: .v60, on: true)
        setup.add(kettle)
        setup.setDefault(kettle, for: .v60, on: true)
        setup.add(grinder)
        setup.setDefault(grinder, for: .v60, on: true)
        setup.add(water)
        setup.makeDefault(water)
        return setup
    }

    static func card(agitation: Agitation? = .swirl) -> CoffeeCard {
        CoffeeCard(
            name: "Chelbesa",
            roaster: "Dak",
            brewMethod: .v60,
            brews: agitation.map { [Brew(method: .v60, dose: 15, water: 250, agitation: $0)] } ?? [],
            roastLevel: .light
        )
    }

    static func wrap<V: View>(_ view: V, setup: SetupStore) -> some View {
        let defaults = UserDefaults(suiteName: "kohi-journey-\(UUID().uuidString)")!
        return view
            .environment(setup)
            .environment(CardStore(files: CardFileStore(url: FileManager.default.temporaryDirectory.appending(path: "cards-\(UUID().uuidString).json"))))
            .environment(RecipeStore(files: JSONFileStore(filename: "recipes-journey-\(UUID().uuidString).json")))
            .environment(TastingStore(
                files: JSONFileStore(filename: "tastings-journey-\(UUID().uuidString).json"),
                ledgerFile: JSONDocumentStore(filename: "tastings-ledger-journey-\(UUID().uuidString).json")
            ))
            .environment(AIFlags(defaults: defaults))
            .environment(LotFlags(defaults: defaults))
            .environment(AIEventLog())
            .environment(AIFeedbackStore(files: JSONFileStore(filename: "feedback-journey-\(UUID().uuidString).json")))
    }

    static func kohiRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Kohi")
    }

    static func appSources() throws -> [(path: String, text: String)] {
        let root = kohiRoot()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [(String, String)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let path = url.path.replacingOccurrences(of: root.path + "/", with: "")
            files.append((path, try String(contentsOf: url)))
        }
        return files
    }
}

@MainActor
struct BrewPrefillTests {
    @Test func aReferenceRecipeGetsTheSameKitAsTheCardPath() {
        let setup = BrewJourneySupport.setup()
        let card = BrewJourneySupport.card()
        let recipe = ReferenceBase.recipe(referenceID: "a1-v60-ultimate")
            ?? Recipe(name: "V60 « Ultimate »", method: .v60, dose: 30, water: 500, grindLabel: "medium-fine")

        let brew = BrewPrefill.seed(card: card, recipe: recipe, setup: setup)

        #expect(brew.waterProfileID == setup.defaultWaterProfile?.id)
        #expect(brew.grind.grinderId == setup.preferredGrinder(for: .v60)?.id)
        #expect(brew.grind.value != nil)
        #expect(brew.agitation == .swirl)
        #expect(brew.filterStockId != nil)
        #expect(brew.captureSource == .prefilled)
        #expect(brew.taste.isEmpty)
        #expect(!brew.equipmentIDs.isEmpty)
        #expect(brew.recipeSnapshot != nil)
    }

    @Test func aSuggestionPrefillsWithoutASnapshot() {
        let setup = BrewJourneySupport.setup()
        let card = BrewJourneySupport.card()
        let recipe = ReferenceBase.recipe(referenceID: "a5-kalita-wave")
            ?? Recipe(name: "Kalita Wave 185", method: .filter, dose: 15, water: 250)

        let brew = BrewPrefill.seed(card: card, recipe: recipe, setup: setup, keepSnapshot: false)

        #expect(brew.recipeSnapshot == nil)
        #expect(brew.dose != nil)
    }

    @Test func finishWritesFlowAndACaptureSource() {
        var brew = Brew(method: .v60, dose: 30, water: 500, seconds: 210)
        brew.captureSource = nil
        let saved = BrewPrefill.finish(brew, events: AIEventLog(), dictationEventID: nil)
        #expect(saved.flowGs == brew.averageFlow)
        #expect(saved.flowGs != nil)
        #expect(saved.captureSource == .typed)
    }

    @Test func aV60WithoutADefaultStillGetsABrewer() {
        let setup = SetupStore(files: JSONDocumentStore(filename: "setup-filter-\(UUID().uuidString).json"))
        let paper = BrewFilter(brand: "Hario", shape: "01")
        let v60 = Equipment(
            kind: .brewer,
            brand: "Hario",
            model: "V60",
            brewerType: "V60",
            filters: [paper]
        )
        setup.add(v60)
        var brew = Brew(method: .v60)
        BrewPrefill.ensureMatchingBrewer(on: &brew, setup: setup)
        #expect(brew.equipmentIDs == [v60.id])
    }

    @Test func espressoDoesNotBorrowAFilterBrewer() {
        let setup = SetupStore(files: JSONDocumentStore(filename: "setup-espresso-\(UUID().uuidString).json"))
        let v60 = Equipment(kind: .brewer, brand: "Hario", model: "V60", brewerType: "V60")
        setup.add(v60)
        var brew = Brew(method: .espresso)
        BrewPrefill.ensureMatchingBrewer(on: &brew, setup: setup)
        #expect(brew.equipmentIDs.isEmpty)
    }

    @Test func interchangeableFiltersFollowTheFamily() {
        let paper = BrewFilter(brand: "Hario", shape: "01")
        let v60 = Equipment(
            kind: .brewer,
            brand: "Hario",
            model: "V60",
            brewerType: "V60",
            filters: [paper]
        )
        let press = Equipment(kind: .brewer, brand: "Bodum", model: "Brazil", brewerType: "French press")
        let machine = Equipment(kind: .espressoMachine, brand: "Decent", model: "DE1")

        #expect(BrewMethod.v60.usesInterchangeableFilter)
        #expect(BrewMethod.filter.usesInterchangeableFilter)
        #expect(BrewMethod.aeropress.usesInterchangeableFilter)
        #expect(!BrewMethod.espresso.usesInterchangeableFilter)
        #expect(!BrewMethod.moka.usesInterchangeableFilter)
        #expect(!BrewMethod.frenchPress.usesInterchangeableFilter)
        #expect(!BrewMethod.coldBrew.usesInterchangeableFilter)

        #expect(BrewPrefill.showsFilter(method: .v60, brewer: v60))
        #expect(BrewPrefill.showsFilter(method: .filter, brewer: nil))
        #expect(!BrewPrefill.showsFilter(method: .espresso, brewer: machine))
        #expect(!BrewPrefill.showsFilter(method: .frenchPress, brewer: press))
        #expect(!BrewPrefill.showsFilter(method: .v60, brewer: press))
    }

    @Test func persistInsertsTheFinishedBrewOnTheCard() {
        let url = FileManager.default.temporaryDirectory.appending(path: "cards-\(UUID().uuidString).json")
        let store = CardStore(files: CardFileStore(url: url))
        var card = BrewJourneySupport.card(agitation: nil)
        store.add(card)
        var brew = Brew(method: .v60, dose: 30, water: 500, seconds: 150)
        brew.captureSource = .prefilled
        BrewPrefill.persist(brew, onto: card, replacing: false, store: store, events: AIEventLog(), dictationEventID: nil)
        let saved = store.card(id: card.id)?.brews.first
        #expect(saved?.id == brew.id)
        #expect(saved?.flowGs == brew.averageFlow)
    }
}

@MainActor
struct BrewSessionJourneyTests {
    @Test func alreadyBrewedSkipsTheTimer() {
        let setup = BrewJourneySupport.setup()
        let session = BrewSession(
            card: BrewJourneySupport.card(),
            recipe: ReferenceBase.recipe(referenceID: "a1-v60-ultimate"),
            setup: setup
        )
        #expect(session.step == .scope)
        #expect(session.progressTotal == 4)
        session.goToDial()
        session.alreadyBrewed(in: setup)
        #expect(session.step == .after)
        #expect(session.logged)
        #expect(session.progressTotal == 3)
    }

    @Test func editOpensAfterWithoutATimer() {
        let setup = BrewJourneySupport.setup()
        let existing = Brew(method: .v60, dose: 30, water: 500, rating: 4)
        let session = BrewSession(
            card: BrewJourneySupport.card(),
            existing: existing,
            mode: .edit,
            start: .after,
            setup: setup
        )
        #expect(session.mode == .edit)
        #expect(session.logged)
        #expect(session.step == .after)
        #expect(session.progressTotal == 3)
        #expect(session.brew.id == existing.id)
    }

    @Test func brewAgainLandsOnAmounts() {
        let setup = BrewJourneySupport.setup()
        let last = Brew(method: .v60, dose: 30, water: 500, grind: GrindSetting(value: 22))
        let session = BrewSession(
            card: BrewJourneySupport.card(),
            existing: last.again(),
            start: .dial,
            setup: setup
        )
        #expect(session.step == .dial)
        #expect(session.mode == .create)
        #expect(!session.logged)
        #expect(session.progressTotal == 4)
        #expect(!session.retreat())
    }

    @Test func aFirstBrewOpensRecipes() {
        let setup = BrewJourneySupport.setup()
        let session = BrewSession(
            card: BrewJourneySupport.card(agitation: nil),
            setup: setup
        )
        #expect(session.step == .scope)
        #expect(!session.includesLauncher)
        #expect(session.recipeLane == .pros)
        #expect(!session.retreat())
    }

    @Test func aRepeatOpensTheLauncherAndReturns() {
        let setup = BrewJourneySupport.setup()
        let session = BrewSession(
            card: BrewJourneySupport.card(),
            suggested: Recipe(name: "Suggested", method: .v60, dose: 15, water: 250),
            setup: setup
        )
        #expect(session.step == .start)
        #expect(session.includesLauncher)
        #expect(session.recipe == nil)
        #expect(session.brew.dose == nil)

        session.openRecipes(.mine)
        #expect(session.recipeLane == .mine)
        #expect(session.retreat())
        #expect(session.step == .start)

        session.openRecipes(.pros)
        #expect(session.recipeLane == .pros)
        session.goToDial()
        #expect(session.step == .dial)
        #expect(session.retreat())
        #expect(session.step == .scope)

        session.openPrevious()
        #expect(session.step == .previous)
        session.repeatLast(in: setup)
        #expect(session.step == .dial)
        #expect(session.brew.dose == 15)
        #expect(session.retreat())
        #expect(session.step == .previous)
    }

    @Test func howMuchEstimatesCupsAndKeepsTheScaleLine() {
        #expect(RecipeScaling.cupEstimateLabel(for: 250) == "About 1 cup")
        #expect(RecipeScaling.cupEstimateLabel(for: 500) == "About 2 cups")
        #expect(RecipeScaling.cupEstimateLabel(for: 960) == "About 4 cups")
        #expect(RecipeScaling.cupEstimateLabel(for: nil) == nil)
        let dial = try! String(
            contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Recipes/BrewDialView.swift")
        )
        #expect(dial.contains("Copy.howMuch"))
        #expect(dial.contains("cupEstimateLabel"))
        #expect(dial.contains("Scaled from"))
        #expect(dial.contains("Steps rescaled"))
        #expect(!dial.contains("RecipeSize"))
        #expect(!dial.contains("GrindRail"))
    }

    @Test func aSuggestedRecipeDoesNotNameTheBrew() {
        let setup = BrewJourneySupport.setup()
        let recipe = ReferenceBase.recipe(referenceID: "a5-kalita-wave")
            ?? Recipe(name: "Kalita Wave 185", method: .filter, dose: 15, water: 250)
        let session = BrewSession(
            card: BrewJourneySupport.card(),
            suggested: recipe,
            setup: setup
        )
        #expect(session.step == .start)
        #expect(session.recipe == nil)
        #expect(session.brew.recipeSnapshot == nil)
        #expect(session.brew.dose == nil)
    }
}

struct RecipePickerJourneyTests {
    @Test func ultimateIsNotListedTwiceAndOffDoseRowsScale() {
        let ultimate = ReferenceBase.recipe(referenceID: "a1-v60-ultimate")
        let oneCup = ReferenceBase.recipe(referenceID: "a2-v60-one-cup")
        let fourSix = ReferenceBase.recipe(referenceID: "a3-v60-46")
        #expect(ultimate != nil && oneCup != nil && fourSix != nil)

        let pool = [ultimate, oneCup, fourSix].compactMap { $0 }
        let deduped = RecipePickerMatch.withoutDuplicate(pool, of: ultimate)
        #expect(deduped.contains { $0.referenceID == "a1-v60-ultimate" } == false)
        #expect(deduped.contains { $0.referenceID == "a2-v60-one-cup" })
        #expect(deduped.contains { $0.referenceID == "a3-v60-46" })

        let scaledCup = RecipeScaling.scaled(oneCup!, to: .twoCups)
        #expect(scaledCup.isScaled)
        #expect(scaledCup.recipe.dose == 30)
        #expect(scaledCup.recipe.water == 500)
        #expect(scaledCup.scaledFromLabel == "scaled from 15 g")

        let scaledFour = RecipeScaling.scaled(fourSix!, to: .twoCups)
        #expect(scaledFour.isScaled)
        #expect(scaledFour.recipe.dose == 33.5)
        #expect(scaledFour.recipe.water == 500)
        #expect(scaledFour.scaledFromLabel == "scaled from 20 g")
    }

    @Test func recipeLanesAreMineAndFromThePros() throws {
        #expect(RecipePickerList.Lane.allCases.map(\.label) == ["Mine", Copy.fromThePros])
        let picker = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Edit/RecipePickerSheet.swift"))
        #expect(!picker.contains("Brewed before"))
        #expect(!picker.contains("case last"))
        #expect(picker.contains("case mine"))
        #expect(picker.contains("Copy.fromThePros"))
    }

    @Test func aScaledSeedKeepsTheTimerOnTheScaledSteps() {
        let oneCup = ReferenceBase.recipe(referenceID: "a2-v60-one-cup")
            ?? Recipe(name: "V60 « 1 cup »", method: .v60, dose: 15, water: 250, steps: [
                RecipeStep(at: 0, action: .bloom, targetMass: 50)
            ])
        let brew = oneCup.seededBrew(size: .twoCups)
        #expect(brew.dose == 30)
        #expect(brew.recipeSnapshot?.dose == 30)
        #expect(brew.recipeSnapshot?.steps.first?.targetMass == 100)
    }
}

@MainActor
struct BrewJourneyInvariantTests {
    @Test func thereIsOnePresenterOneSeedAndOneSave() throws {
        let sources = try BrewJourneySupport.appSources()
        func filesContaining(_ needle: String) -> [String] {
            sources.filter { $0.text.contains(needle) }.map(\.path).sorted()
        }

        #expect(filesContaining("GuidedBrewView(") == ["Recipes/BrewFlowHost.swift"])
        #expect(filesContaining("AfterBrewSheet(") == ["Recipes/BrewFlowHost.swift"])
        #expect(filesContaining("BrewDialView(") == ["Recipes/BrewFlowHost.swift"])
        #expect(filesContaining("struct BrewSheet").isEmpty)
        #expect(filesContaining("struct StepTimer").isEmpty)
        #expect(filesContaining("StepTimer(").isEmpty)

        let seeded = filesContaining("seededBrew(")
        #expect(seeded == ["Model/Recipe.swift", "Process/BrewPrefill.swift"])

        let defaults = filesContaining("setup.defaults(for:")
        #expect(Set(defaults) == ["Process/BrewPrefill.swift", "Setup/ProfileSheet.swift"])

        let flowWriters = filesContaining("flowGs =")
        #expect(Set(flowWriters) == ["Model/Brew.swift", "Process/BrewPrefill.swift"])
        let prefill = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Process/BrewPrefill.swift"))
        #expect(prefill.contains("saved.flowGs = saved.averageFlow"))

        let after = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Recipes/AfterBrewSheet.swift"))
        #expect(!after.contains("confirmationAction"))
        #expect(!after.contains(".toolbar"))
        #expect(after.contains("DictationField"))
        #expect(after.contains("Save as recipe"))
        #expect(after.contains("Compare with"))
        #expect(after.contains("TDS"))
        #expect(after.contains("Delete this brew"))
        #expect(!after.contains("appearCorrection"))
        #expect(!after.contains("SuggestedCorrectionView"))
        #expect(after.contains("SensoryEvaluationSection"))
        #expect(!after.contains("brewAgainButton"))
        #expect(!after.contains("Copy.brewAgain"))
        #expect(!after.contains("var onAgain"))
        #expect(!after.contains("session.brew.notes)\""))
        let flow = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Design/StepFlow.swift"))
        #expect(flow.contains("if !fieldFocused"))
        let correctionView = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "AI/SuggestedCorrectionView.swift"))
        #expect(correctionView.contains("\"Model\""))
        #expect(correctionView.contains("Ask the model"))
    }

    @Test func catalogueSelectionDoesNotUseACheckmark() throws {
        let row = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Recipes/RecipeRowView.swift"))
        let kit = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Setup/KitRow.swift"))
        let picker = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Edit/RecipePickerSheet.swift"))
        let scope = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Recipes/BrewScopeView.swift"))
        #expect(row.contains("CatalogueMark"))
        #expect(row.contains("isSelected"))
        #expect(!row.contains("checkmark"))
        #expect(kit.contains("CatalogueMark"))
        #expect(!kit.contains("checkmark"))
        #expect(picker.contains("isSelected: isSelected(recipe)"))
        #expect(picker.contains("var selected: Recipe?"))
        #expect(scope.contains("selected: session.recipe"))
    }
}
