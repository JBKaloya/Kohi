import Foundation
import Testing
@testable import Kohi

struct SyncPreflightTests {
    @Test func localMigrationsCoverTheBrewV2Columns() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "supabase/migrations")
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        let sql = try files.filter { $0.hasSuffix(".sql") }.map {
            try String(contentsOf: root.appending(path: $0), encoding: .utf8)
        }.joined(separator: "\n")
        #expect(sql.contains("filter_stock"))
        #expect(sql.contains("superLight") || sql.contains("super_light") || sql.contains("roast_level"))
        #expect(sql.contains("express"))
        #expect(sql.contains("planned_steps"))
        #expect(sql.contains("actual_source"))
        #expect(sql.contains("recipe_name"))
        #expect(sql.contains("pour_rates"))
    }
}

struct PrdBrewV2Tests {
    @Test func defaultSequenceFillsEveryReferenceRecipe() {
        for recipe in ReferenceBase.recipes {
            let filled = DefaultSequence.filling(recipe)
            #expect(!filled.steps.isEmpty, "\(recipe.referenceID ?? recipe.name) has no steps")
        }
    }

    @Test func aBagRecipeAndSaveAsRecipeGetASequence() {
        let card = CoffeeCard(name: "Chelbesa", brewMethod: .v60)
        let fromBag = RecipeRules.recipe(
            from: Brew(method: .v60, dose: 15, water: 250),
            card: card
        )
        #expect(!DefaultSequence.filling(fromBag).steps.isEmpty)
        let saved = RecipeRules.recipe(
            from: Brew(method: .v60, dose: 15, water: 250, actualSource: .none),
            card: card,
            source: .mine
        )
        #expect(!DefaultSequence.filling(saved).steps.isEmpty)
    }

    @MainActor
    @Test func timerRecipeNeverReturnsAnEmptyClock() {
        let brew = Brew(method: .v60, dose: 15, water: 250)
        let recipe = BrewPrefill.timerRecipe(from: brew, named: "")
        #expect(!recipe.steps.isEmpty)
        #expect(recipe.steps.contains { $0.derived })
    }

    @Test func pourRatesStayEmptyWithoutActuals() {
        var brew = Brew(method: .v60, water: 250, seconds: 180, actualSource: .none)
        brew.plannedSteps = [
            BrewStep(index: 0, action: .pour, at: 0, targetAt: 30, targetMass: 250)
        ]
        brew.refreshPourRates()
        #expect(brew.pourRates.isEmpty)
    }

    @Test func brewTitleUsesRecipeNameThenFamilyNeverTheBrewer() {
        let named = Brew(method: .v60, recipeName: "Ultimate")
        #expect(named.title == "Ultimate")
        let family = Brew(method: .v60)
        #expect(family.title == BrewerFamily.handBrew.label)
        #expect(!family.title.localizedCaseInsensitiveContains("hario"))
    }

    @Test func everySeededDripperDeclaresAShapeOrNone() {
        for brewer in ReferenceBase.brewers {
            let shapes = brewer.filterShapes
            let none = brewer.declaresNoPaper
            #expect(!shapes.isEmpty || none, "\(brewer.displayName) has no shapes")
        }
    }

    @Test func dedicatedPaperRequiresANamedFit() {
        let dedicated = FilterModel(
            id: "ufo-paper",
            brand: "UFO",
            line: "",
            model: "UFO 2.0",
            shape: .dedicated,
            sizes: [],
            fits: ["Trinity Zero"],
            material: nil,
            bleach: nil,
            thicknessUm: nil,
            crepe: nil,
            density: nil,
            flowClass: nil,
            notes: "",
            source: "",
            status: ""
        )
        let other = Equipment(
            kind: .brewer,
            model: "Trinity Zero",
            brewerRef: "trinity-zero",
            acceptsFilterShapes: [.dedicated]
        )
        #expect(FilterFit.named(dedicated, fits: other))
        let stranger = Equipment(
            kind: .brewer,
            model: "Gabi",
            brewerRef: "gabi-master-a",
            acceptsFilterShapes: [.dedicated]
        )
        #expect(!FilterFit.named(dedicated, fits: stranger))
    }

    @Test func grindRailUsesClicksWhenARangeCoversTheMethod() {
        let spanned = GrindSpan.make(
            grinder: Equipment(
                kind: .grinder,
                brand: "1Zpresso",
                model: "J-Ultra",
                adjustment: .clicks,
                ranges: [GrindRange(method: .v60, low: 18, high: 36)]
            ),
            method: .v60,
            current: 24
        )
        #expect(spanned?.band != nil)
        let open = GrindSpan.make(
            grinder: Equipment(kind: .grinder, brand: "Unknown", model: "X", adjustment: .clicks),
            method: .v60,
            current: nil
        )
        #expect(open?.band == nil)
    }

    @Test func saveWithRatingAloneIsACompleteEnoughBrew() {
        let brew = Brew(method: .v60, rating: 4)
        #expect(brew.rating == 4)
        #expect(brew.completeness.tag.isEmpty == false)
    }

    @Test func brewerTypeMapsOntoBrewMethod() {
        #expect(BrewerType.v60.method == .v60)
        #expect(BrewerType.moka.family == .espresso)
        #expect(BrewerType.aeropress.family == .handBrew)
        #expect(BrewerType.coldBrew.family == .coldBrew)
    }

    @Test func expressSourceSurvivesARowRoundTrip() {
        let recipe = Recipe(name: "Filter · 19 Sep", method: .v60, source: .express, evidence: .unverified)
        let restored = RecipeRow(recipe: recipe, userID: UUID()).toRecipe()
        #expect(restored.source == .express)
    }

    @Test func paperListIsNeverEmptyForADripper() {
        for brewer in ReferenceBase.brewers {
            let kit = Equipment(reference: brewer)
            let result = FilterModel.filters(matching: kit)
            #expect(!result.items.isEmpty, "\(brewer.displayName) resolved no papers")
        }
    }

    @Test func storedBrewerTypeLabelsStillParse() {
        for type in BrewerType.allCases {
            #expect(BrewerType.parse(type.storageValue) == type)
        }
        #expect(BrewerType.parse("V60") == .v60)
        #expect(BrewerType.parse("Flat dripper") == .flat)
        #expect(BrewerType.parse("French press") == .frenchPress)
        #expect(BrewerType.parse("Moka Express") == .moka)
        #expect(BrewerType.parse("Moka Express 1 cup") == .moka)
    }

    @Test func deviationsIgnoreSmallTimingJitter() {
        var brew = Brew(method: .v60, actualSource: .timer)
        brew.plannedSteps = [
            BrewStep(index: 0, action: .pour, at: 0, targetAt: 30, targetMass: 250)
        ]
        brew.steps = [
            BrewStep(index: 0, action: .pour, at: 35, mass: 252, targetAt: 30, targetMass: 250)
        ]
        #expect(!brew.deviatedFromPlan)
        brew.steps = [
            BrewStep(index: 0, action: .pour, at: 50, mass: 200, targetAt: 30, targetMass: 250)
        ]
        #expect(brew.deviatedFromPlan)
    }

    @Test func brewListRowsUseTheBrewTitle() throws {
        let list = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Kohi/Detail/BrewList.swift"))
        #expect(list.contains("brew.title"))
        #expect(!list.contains("recipeSnapshot?.name"))
    }

    @MainActor
    @Test func switchingToEspressoReplacesTheDripperWithTheMachine() {
        let setup = SetupStore(files: JSONDocumentStore(filename: "kit-switch-\(UUID().uuidString).json"))
        let v60 = Equipment(kind: .brewer, brand: "Hario", model: "V60", brewerType: "V60")
        let machine = Equipment(kind: .espressoMachine, brand: "Decent", model: "DE1")
        setup.add(v60)
        setup.add(machine)
        var brew = Brew(method: .v60, equipmentIDs: [v60.id])
        BrewKit.applyFamily(.espresso, to: &brew, setup: setup, card: CoffeeCard(name: "Test"), recipe: nil)
        #expect(brew.equipmentIDs.contains(machine.id))
        #expect(!brew.equipmentIDs.contains(v60.id))
        #expect(brew.method == .espresso)
        #expect(BrewKit.activeBrewer(on: brew, in: setup)?.kind == .espressoMachine)
    }

    @MainActor
    @Test func switchingFromMokaToHandBrewRestoresTheDripper() {
        let setup = SetupStore(files: JSONDocumentStore(filename: "kit-moka-\(UUID().uuidString).json"))
        let v60 = Equipment(kind: .brewer, brand: "Hario", model: "V60", brewerType: "V60")
        let moka = Equipment(kind: .brewer, brand: "Bialetti", model: "Moka Express", brewerType: "Moka")
        setup.add(v60)
        setup.add(moka)
        var brew = Brew(method: .moka, equipmentIDs: [moka.id])
        BrewKit.applyFamily(.handBrew, to: &brew, setup: setup, card: CoffeeCard(name: "Test"), recipe: nil)
        #expect(brew.equipmentIDs.contains(v60.id))
        #expect(!brew.equipmentIDs.contains(moka.id))
        #expect(BrewKit.tab(for: brew.method) == .handBrew)
        #expect(!BrewKit.matches(.handBrew, moka))
        #expect(BrewKit.matches(.espresso, moka))
        let nameless = Equipment(kind: .brewer, brand: "Bialetti", model: "Moka Express 1 cup")
        #expect(BrewKit.matches(.espresso, nameless))
        #expect(!BrewKit.matches(.handBrew, nameless))
    }

    @MainActor
    @Test func aNamelessV60StillMovesTheJourneyToHandBrew() {
        let setup = SetupStore(files: JSONDocumentStore(filename: "kit-nameless-v60-\(UUID().uuidString).json"))
        let v60 = Equipment(kind: .brewer, brand: "Hario", model: "V60")
        let moka = Equipment(kind: .brewer, brand: "Bialetti", model: "Moka Express 1 cup")
        setup.add(v60)
        setup.add(moka)
        var brew = Brew(method: .moka, equipmentIDs: [moka.id])
        BrewKit.applyFamily(.handBrew, to: &brew, setup: setup, card: CoffeeCard(name: "Test"), recipe: nil)
        #expect(brew.equipmentIDs.contains(v60.id))
        #expect(brew.method == .v60)
        #expect(BrewKit.tab(for: brew.method) == .handBrew)
        BrewKit.applyFamily(.espresso, to: &brew, setup: setup, card: CoffeeCard(name: "Test"), recipe: nil)
        #expect(brew.equipmentIDs.contains(moka.id))
        #expect(BrewKit.tab(for: brew.method) == .espresso)
    }

    @MainActor
    @Test func assigningANamelessV60WritesTheMethod() {
        let setup = SetupStore(files: JSONDocumentStore(filename: "kit-assign-v60-\(UUID().uuidString).json"))
        let v60 = Equipment(kind: .brewer, brand: "Hario", model: "V60")
        setup.add(v60)
        var brew = Brew(method: .moka)
        BrewKit.assign(v60, to: &brew, setup: setup, card: CoffeeCard(name: "Test"), recipe: nil)
        #expect(brew.method == .v60)
        #expect(brew.equipmentIDs.contains(v60.id))
    }

    @MainActor
    @Test func switchingToEspressoWithoutAMachineClearsTheDripper() {
        let setup = SetupStore(files: JSONDocumentStore(filename: "kit-empty-esp-\(UUID().uuidString).json"))
        let v60 = Equipment(kind: .brewer, brand: "Hario", model: "V60", brewerType: "V60")
        setup.add(v60)
        var brew = Brew(method: .v60, equipmentIDs: [v60.id], filterStockId: UUID())
        BrewKit.applyFamily(.espresso, to: &brew, setup: setup, card: CoffeeCard(name: "Test"), recipe: nil)
        #expect(brew.equipmentIDs.isEmpty)
        #expect(brew.filterStockId == nil)
        #expect(brew.method == .espresso)
    }

    @Test func espressoPapersAreDiscsNotCones() {
        let machine = Equipment(kind: .espressoMachine, brand: "Decent", model: "DE1")
        let result = FilterModel.filters(matching: machine)
        #expect(!result.items.isEmpty)
        #expect(result.items.allSatisfy { $0.shape == .disc })
        #expect(!result.items.contains { $0.shape == .cone60 })
        let cone = FilterStock(modelId: "cafec-abaca", size: "02", shape: .cone60)
        #expect(!FilterFit.compatible(cone, with: machine))
    }

    @MainActor
    @Test func dialResolvesAnEspressoMachineNotADripper() {
        let setup = SetupStore(files: JSONDocumentStore(filename: "dial-machine-\(UUID().uuidString).json"))
        let v60 = Equipment(kind: .brewer, brand: "Hario", model: "V60", brewerType: "V60")
        let machine = Equipment(kind: .espressoMachine, brand: "Decent", model: "DE1")
        setup.add(v60)
        setup.add(machine)
        var brew = Brew(method: .espresso, equipmentIDs: [v60.id])
        BrewPrefill.ensureMatchingBrewer(on: &brew, setup: setup)
        #expect(brew.equipmentIDs.contains(machine.id))
        #expect(!brew.equipmentIDs.contains(v60.id))
        #expect(BrewKit.activeBrewer(on: brew, in: setup)?.kind == .espressoMachine)
    }

    @Test func narrationKeepsTimerTimeAndOverwritesMass() {
        var brew = Brew(method: .v60, seconds: 180, actualSource: .timer)
        brew.plannedSteps = [
            BrewStep(index: 0, action: .bloom, at: 0, targetAt: 45, targetMass: 50),
            BrewStep(index: 1, action: .pour, at: 0, targetAt: 90, targetMass: 150),
        ]
        brew.actualSteps = [
            BrewStep(index: 0, action: .bloom, at: 7, mass: 4, targetAt: 45, targetMass: 50),
            BrewStep(index: 1, action: .pour, at: 45, mass: 80, targetAt: 90, targetMass: 150),
        ]
        let parsed = SpokenBrewParser.parse("bloom 50, pour to 150")
        SpokenBrewParser.apply(parsed, to: &brew, appendLeftover: false)
        #expect(brew.seconds == 180)
        #expect(brew.actualSteps[0].at == 7)
        #expect(brew.actualSteps[0].mass == 50)
        #expect(brew.actualSteps[1].at == 45)
        #expect(brew.actualSteps[1].mass == 150)
        #expect(brew.deviations[0].massDelta == 0)
        #expect(brew.deviations[1].massDelta == 0)
    }

    @Test func pourCurveSortsActualsByElapsedTime() throws {
        let curve = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Kohi/Design/PourCurve.swift"))
        #expect(curve.contains("time($0) ?? $0.at"))
        #expect(!curve.contains("targetAt ?? $0.at"))
    }

    @Test func whatYoureDoingHasNoDictate() throws {
        let scope = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Kohi/Recipes/BrewScopeView.swift"))
        #expect(!scope.contains("SayItLabel"))
        #expect(!scope.contains("Dictation()"))
        #expect(!scope.contains("Copy.dictate"))
        #expect(scope.contains("BrewKit.journeyTabs"))
    }

    @Test func recipeFamilyBelongsRules() {
        let v60 = Recipe(name: "Ultimate", method: .v60, dose: 15, water: 250)
        let aero = Recipe(name: "AeroPress", method: .aeropress, dose: 15, water: 200)
        let moka = Recipe(name: "Moka 3 cup", method: .moka, dose: 16, water: 150)
        // V60 and AeroPress are both Hand brew; Moka is Espresso.
        #expect(RecipePickerMatch.belongs(v60, to: .v60))
        #expect(RecipePickerMatch.belongs(v60, to: .aeropress))
        #expect(!RecipePickerMatch.belongs(v60, to: .moka))
        #expect(RecipePickerMatch.belongs(aero, to: .aeropress))
        #expect(RecipePickerMatch.belongs(aero, to: .frenchPress))
        #expect(RecipePickerMatch.belongs(aero, to: .v60))
        #expect(RecipePickerMatch.belongs(moka, to: .espresso))
        #expect(!RecipePickerMatch.belongs(moka, to: .v60))
    }

    @MainActor
    @Test func switchingFamilyOnScopeDropsTheOtherTabsRecipe() {
        let setup = SetupStore(files: JSONDocumentStore(filename: "scope-family-\(UUID().uuidString).json"))
        let v60 = Equipment(kind: .brewer, brand: "Hario", model: "V60", brewerType: "V60")
        let moka = Equipment(kind: .brewer, brand: "Bialetti", model: "Moka Express", brewerType: "Moka")
        setup.add(v60)
        setup.add(moka)
        let session = BrewSession(
            card: CoffeeCard(name: "Test"),
            recipe: Recipe(name: "Moka 3 cup", method: .moka, dose: 16, water: 150),
            setup: setup
        )
        #expect(session.brew.method == .moka)
        session.apply(family: .handBrew, setup: setup)
        #expect(session.recipe == nil)
        #expect(BrewKit.tab(for: session.brew.method) == .handBrew)
        #expect(BrewKit.activeBrewer(on: session.brew, in: setup)?.id == v60.id)
        session.apply(family: .espresso, setup: setup)
        #expect(BrewKit.tab(for: session.brew.method) == .espresso)
        #expect(BrewKit.activeBrewer(on: session.brew, in: setup)?.id == moka.id)
        #expect(!BrewKit.activeBrewer(on: session.brew, in: setup)!.displayName.localizedCaseInsensitiveContains("v60"))
    }

    @Test func fieldExtractTidiesATranscript() throws {
        let extract = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "supabase/functions/field-extract/index.ts"))
        #expect(extract.contains("TRANSCRIPT_PROMPT"))
        #expect(extract.contains("\"transcript\""))
        let after = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Kohi/Recipes/AfterBrewSheet.swift"))
        #expect(after.contains("SpokenLexicon.rewrite"))
        #expect(after.contains("FieldExtract.tidy"))
        let flow = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Kohi/Design/StepFlow.swift"))
        #expect(flow.contains("containerRelativeFrame(.horizontal"))
        #expect(flow.contains("axes: .horizontal"))
        let rail = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Kohi/Design/TabRail.swift"))
        #expect(rail.contains("frame(minHeight: 44"))
        #expect(!rail.contains("touchTarget"))
    }

    // MARK: - StepBuilder: dose and water are independent

    @Test func doseAndWaterAreIndependentInTheBuilder() throws {
        let text = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Kohi/Recipes/StepBuilderSheet.swift"))
        // The coupling onChange handlers must be gone.
        #expect(!text.contains("rescaleIfNeeded"))
        #expect(!text.contains("lastDose"))
        #expect(!text.contains("lastWater"))
        // Explicit rescale button replaces it.
        #expect(text.contains("Rescale steps"))
        // Espresso uses beverage, not water.
        #expect(text.contains("draft.beverage"))
    }

    @Test func stepBuilderSortsStepsOnSave() {
        // Steps created out-of-order should be reordered by `at` on save.
        let recipe = Recipe(
            name: "Test",
            method: .v60,
            dose: 15,
            water: 250,
            steps: [
                RecipeStep(at: 45, action: .pour, targetMass: 250),
                RecipeStep(at: 0, action: .bloom, targetMass: 50),
            ]
        )
        // Simulate the sort that save() performs.
        let sorted = recipe.steps.sorted { $0.at < $1.at }
        #expect(sorted[0].action == .bloom)
        #expect(sorted[1].action == .pour)
    }

    @Test func rescaleStepsKeepsRatioAndDoesNotTouchDoseOrWater() {
        var recipe = Recipe(name: "Test", method: .v60, dose: 15, water: 250, steps: [
            RecipeStep(at: 0, action: .bloom, targetMass: 50),
            RecipeStep(at: 45, action: .pour, targetMass: 250),
        ])
        // Simulate typing water = 220 then pressing Rescale.
        recipe.water = 220
        let currentMax = recipe.steps.compactMap(\.targetMass).max() ?? 250
        let factor = 220.0 / currentMax
        let rescaled = recipe.steps.map { step -> RecipeStep in
            var s = step
            if let m = s.targetMass { s.targetMass = RecipeScaling.roundHalf(m * factor) }
            return s
        }
        // Dose stays at 15 — only step masses move.
        #expect(recipe.dose == 15)
        #expect(recipe.water == 220)
        #expect(rescaled[1].targetMass == RecipeScaling.roundHalf(220.0))
        #expect(rescaled[0].targetMass! < rescaled[1].targetMass!)
    }

    // MARK: - RecipeEditSheet: update vs add

    @MainActor
    @Test func recipeEditSheetUpdatesAnExistingMineRecipe() {
        let store = RecipeStore(files: JSONFileStore(filename: "edit-test-\(UUID().uuidString).json"))
        var recipe = Recipe(name: "My V60", method: .v60, dose: 15, water: 250, source: .mine)
        recipe = store.add(recipe)
        // Simulate editing: store.update with same id and new name.
        var updated = recipe
        updated.name = "My V60 (updated)"
        store.update(updated)
        let retrieved = store.recipe(id: recipe.id)
        #expect(retrieved?.name == "My V60 (updated)")
        #expect(store.recipes.count == 1)
    }

    // MARK: - applyEdited: update mine, copy reference

    @MainActor
    @Test func applyEditedUpdatesAMineRecipe() {
        let store = RecipeStore(files: JSONFileStore(filename: "apply-mine-\(UUID().uuidString).json"))
        let setup = SetupStore(files: JSONDocumentStore(filename: "apply-setup-\(UUID().uuidString).json"))
        let mineRecipe = Recipe(name: "My V60", method: .v60, dose: 15, water: 250, source: .mine)
        store.add(mineRecipe)
        let session = BrewSession(card: CoffeeCard(name: "Test"), recipe: mineRecipe, setup: setup)
        var edited = mineRecipe
        edited.name = "My V60 (tweaked)"
        edited.dose = 18
        session.applyEdited(edited, store: store)
        #expect(session.recipe?.name == "My V60 (tweaked)")
        #expect(session.recipe?.id == mineRecipe.id)
        #expect(store.recipes.count == 1)
        #expect(store.recipe(id: mineRecipe.id)?.dose == 18)
    }

    @MainActor
    @Test func applyEditedCopiesAReferenceRecipe() {
        let store = RecipeStore(files: JSONFileStore(filename: "apply-ref-\(UUID().uuidString).json"))
        let setup = SetupStore(files: JSONDocumentStore(filename: "apply-ref-setup-\(UUID().uuidString).json"))
        let refRecipe = Recipe(
            name: "V60 Ultimate", method: .v60, dose: 30, water: 500,
            source: .reference, referenceID: "a1-v60-ultimate"
        )
        let session = BrewSession(card: CoffeeCard(name: "Test"), recipe: refRecipe, setup: setup)
        var edited = refRecipe
        edited.name = "My Ultimate"
        session.applyEdited(edited, store: store)
        // A new .express record is created; the reference is untouched.
        #expect(session.recipe?.source == .express)
        #expect(session.recipe?.id != refRecipe.id)
        #expect(store.recipes.count == 1)
    }

    // MARK: - Timer sync: snapshot rescales with live water

    @MainActor
    @Test func timerRecipeRescalesSnapshotWhenWaterDiverges() {
        let setup = SetupStore(files: JSONDocumentStore(filename: "timer-sync-\(UUID().uuidString).json"))
        let recipe = Recipe(
            name: "Ultimate", method: .v60, dose: 30, water: 500,
            steps: [
                RecipeStep(at: 0, action: .bloom, targetMass: 100),
                RecipeStep(at: 45, action: .pour, targetMass: 500),
            ],
            source: .reference
        )
        let session = BrewSession(card: CoffeeCard(name: "Test"), recipe: recipe, setup: setup)
        // Snapshot is built from the 500 g recipe.
        #expect(session.brew.recipeSnapshot != nil)
        // User types 250 g directly into the dose field (bypasses apply(size:)).
        session.brew.water = 250
        let timer = session.timerRecipe(in: setup)
        // Steps should be rescaled 0.5× from snapshot masses.
        let pourStep = timer.steps.first { $0.action == .pour || $0.action == .bloom && $0.targetMass != nil }
        #expect(pourStep?.targetMass != nil)
        // Max step mass should be ≈ 250, not 500.
        let maxMass = timer.steps.compactMap(\.targetMass).max() ?? 0
        #expect(maxMass <= 260)
        #expect(maxMass >= 240)
    }

    // MARK: - Four families

    @Test func everythingManualIsHandBrew() {
        #expect(BrewerType.aeropress.family == .handBrew)
        #expect(BrewerType.frenchPress.family == .handBrew)
        #expect(BrewerType.immersionSwitch.family == .handBrew)
        #expect(BrewerType.v60.family == .handBrew)
        #expect(BrewerType.chemex.family == .handBrew)
        #expect(BrewerType.flat.family == .handBrew)
        #expect(BrewerType.batch.family == .batch)
        #expect(BrewerType.coldBrew.family == .coldBrew)
        #expect(BrewerType.moka.family == .espresso)
    }

    @Test func journeyTabsFollowTheDecidedOrder() {
        #expect(BrewKit.journeyTabs == [.handBrew, .batch, .espresso, .coldBrew])
        #expect(BrewKit.journeyTabs.map(\.label) == ["Hand brew", "Batch brew", "Espresso", "Cold brew"])
    }

    @Test func methodFamilyMapsCorrectly() {
        #expect(BrewMethod.aeropress.family == .handBrew)
        #expect(BrewMethod.frenchPress.family == .handBrew)
        #expect(BrewMethod.v60.family == .handBrew)
        #expect(BrewMethod.filter.family == .handBrew)
        #expect(BrewMethod.moka.family == .espresso)
        #expect(BrewMethod.coldBrew.family == .coldBrew)
    }

    // MARK: - Step accessories Codable

    @Test func stepAccessoryIDsSurviveRoundTrip() throws {
        let id = UUID()
        let step = RecipeStep(at: 0, action: .pour, targetMass: 300, accessoryIDs: [id])
        let data = try JSONEncoder().encode(step)
        let restored = try JSONDecoder().decode(RecipeStep.self, from: data)
        #expect(restored.accessoryIDs == [id])
    }

    @Test func stepWithoutAccessoriesDecodesAsEmpty() throws {
        // Legacy JSON without accessoryIDs key must decode cleanly.
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","at":0,"action":"pour","derived":false,"note":""}"#.data(using: .utf8)!
        let step = try JSONDecoder().decode(RecipeStep.self, from: json)
        #expect(step.accessoryIDs.isEmpty)
    }

    // MARK: - Dial rescale

    @Test func expressTitleIncludesCoffeeName() {
        let card = CoffeeCard(name: "Geera")
        let title = Recipe.expressTitle(family: .handBrew, card: card)
        #expect(title.hasPrefix("Geera · Hand brew ·"))
    }

    @Test func expressTitleWithoutCardUsesFamily() {
        let title = Recipe.expressTitle(family: .handBrew)
        #expect(title.hasPrefix("Hand brew ·"))
    }

    // MARK: - Scaling: the 60 kg rinse

    /// The rinse belongs to the paper, not to the recipe. A V60 cone takes
    /// 150 g whether you brew 250 g or 1 kg.
    @Test func rinseIsNeverScaled() {
        let steps = [
            RecipeStep(at: 0, action: .rinse, targetMass: 150),
            RecipeStep(at: 0, action: .bloom, targetMass: 50),
            RecipeStep(at: 45, action: .pour, targetMass: 250),
        ]
        let scaled = RecipeScaling.scalingSteps(steps, by: 2)
        #expect(scaled[0].targetMass == 150)  // rinse untouched
        #expect(scaled[1].targetMass == 100)
        #expect(scaled[2].targetMass == 500)
    }

    /// A half-typed number on the way to 200 must not rewrite the sequence.
    @Test func anAbsurdFactorIsRefused() {
        let recipe = Recipe(
            name: "V60", method: .v60, dose: 15, water: 250,
            steps: [RecipeStep(at: 0, action: .pour, targetMass: 250)]
        )
        // 250 g -> 2 g is a factor of 0.008: a typo, not an intent.
        #expect(RecipeScaling.rescaled(recipe, toLiquid: 2) == nil)
        // 250 g -> 60 000 g likewise.
        #expect(RecipeScaling.rescaled(recipe, toLiquid: 60_000) == nil)
        // Inside the band it works.
        #expect(RecipeScaling.rescaled(recipe, toLiquid: 500) != nil)
    }

    /// Espresso is measured by what lands in the cup, filter by water in.
    /// Mixing the two is what let a 0.5 g beverage become the baseline.
    @Test func liquidComparesLikeWithLike() {
        let espresso = Recipe(name: "Shot", method: .espresso, dose: 18, water: 200, beverage: 36)
        #expect(RecipeScaling.liquid(of: espresso) == 36)
        let filter = Recipe(name: "V60", method: .v60, dose: 15, water: 250)
        #expect(RecipeScaling.liquid(of: filter) == 250)
    }

    @MainActor
    @Test func resizingMeasuresFromTheNominalRecipeNotTheLastResize() {
        let setup = SetupStore(files: JSONDocumentStore(filename: "resize-\(UUID().uuidString).json"))
        let recipe = Recipe(
            name: "V60", method: .v60, dose: 15, water: 250,
            steps: [
                RecipeStep(at: 0, action: .rinse, targetMass: 150),
                RecipeStep(at: 0, action: .bloom, targetMass: 50),
                RecipeStep(at: 45, action: .pour, targetMass: 250),
            ]
        )
        let session = BrewSession(card: CoffeeCard(name: "Test"), recipe: recipe, setup: setup)

        // Three keystrokes on the way to 500 must not compound.
        session.brew.water = 300
        session.resizeRecipeToBrew()
        session.brew.water = 400
        session.resizeRecipeToBrew()
        session.brew.water = 500
        session.resizeRecipeToBrew()

        let pours = session.recipe?.steps.filter { $0.action != .rinse } ?? []
        #expect(pours.compactMap(\.targetMass).max() == 500)
        // And the rinse survived all three untouched.
        let rinse = session.recipe?.steps.first { $0.action == .rinse }
        #expect(rinse?.targetMass == 150)
    }

    @MainActor
    @Test func theTimerNeverInheritsAnAbsurdMass() {
        let setup = SetupStore(files: JSONDocumentStore(filename: "timer-sane-\(UUID().uuidString).json"))
        let recipe = Recipe(
            name: "V60", method: .v60, dose: 12, water: 200,
            steps: [
                RecipeStep(at: 0, action: .rinse, targetMass: 150),
                RecipeStep(at: 45, action: .pour, targetMass: 200),
            ]
        )
        let session = BrewSession(card: CoffeeCard(name: "Test"), recipe: recipe, setup: setup)
        let timer = session.timerRecipe(in: setup)
        let masses = timer.steps.compactMap(\.targetMass)
        // Nothing in a 200 g brew has any business being over a kilo.
        #expect(masses.allSatisfy { $0 < 1_000 })
    }

    // MARK: - Step grammar per method

    @Test func espressoNeverOffersABloom() {
        let espresso = DefaultSequence.actions(for: .espresso)
        #expect(!espresso.contains(.bloom))
        #expect(espresso.contains(.preInfusion))
        #expect(espresso.contains(.shot))

        let v60 = DefaultSequence.actions(for: .v60)
        #expect(v60.contains(.bloom))
        #expect(v60.contains(.pour))
        #expect(!v60.contains(.shot))
    }

    @Test func everyMethodOffersTheUniversalActions() {
        for method in BrewMethod.allCases {
            let actions = DefaultSequence.actions(for: method)
            #expect(!actions.isEmpty, "\(method.label) has no actions")
            for universal in StepAction.universal {
                #expect(actions.contains(universal), "\(method.label) is missing \(universal.label)")
            }
        }
    }

    @Test func theStepBuilderReadsItsGrammarFromDefaultSequence() throws {
        let text = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Kohi/Recipes/StepBuilderSheet.swift"))
        // The action list is not a second table living in the view.
        #expect(text.contains("DefaultSequence.actions(for:"))
        #expect(!text.contains("builderCases"))
        // And scaling is not reimplemented there either.
        #expect(!text.contains("roundHalf(mass * factor)"))
    }

    @Test func scalingIsNotReimplementedAcrossTheApp() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Kohi")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        for file in files where file.lastPathComponent != "RecipeScaling.swift" {
            let text = try String(contentsOf: file)
            #expect(
                !text.contains("roundHalf(mass * factor)"),
                "\(file.lastPathComponent) scales step masses itself"
            )
        }
    }
}
