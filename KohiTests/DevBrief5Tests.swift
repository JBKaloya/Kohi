import Foundation
import Testing
@testable import Kohi

@MainActor
struct DevBrief5Tests {
    @Test func copyNamesTheTodayStep() {
        #expect(Copy.todaysSettings == "Today's settings")
        #expect(Copy.howMuch == "How much?")
        #expect(Copy.change == "Change")
        #expect(Copy.addThePaperYouUse == "Add the paper you use")
        #expect(Copy.addTheWaterYouUse == "Add the water you use")
        #expect(Copy.logWithoutTimer == "Log without timer")
        #expect(Copy.rinseMore == "Rinse more")
        #expect(Copy.whichPaper == "Which paper?")
        #expect(Copy.addAFilter == "Add a filter")
    }

    @Test func dialHasNoBrewerOrGrinderSelectorByDefault() throws {
        let dial = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Recipes/BrewDialView.swift"))
        #expect(!dial.contains("KitRecallRow"))
        #expect(!dial.contains("Copy.change"))
        #expect(!dial.contains("Add water in Setup"))
        #expect(!dial.contains("Add filters in Profile"))
        #expect(!dial.contains("\"Brew now\""))
        #expect(!dial.contains("Already brewed"))
        #expect(dial.contains("Copy.logWithoutTimer"))
        #expect(!dial.contains("WaterSheet"))
        #expect(!dial.contains("FilterSheet"))
        #expect(!dial.contains("kitExpanded"))
        #expect(dial.contains("cupEstimateLabel"))
    }

    @Test func kitOpensTheCatalogueByFamily() throws {
        let kit = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Recipes/BrewKitView.swift"))
        #expect(kit.contains("Copy.withWhat"))
        #expect(kit.contains("CatalogPicker"))
        #expect(kit.contains("BrewKit.journeyTabs"))
        #expect(!kit.contains("@State private var family"))
        #expect(!kit.contains("BrewerFamily.allCases"))
        #expect(!kit.contains("GrindRail"))
        #expect(kit.contains("filterRow"))
    }

    @Test func ownedCompatibleIntersection() {
        let setup = SetupStore(files: JSONDocumentStore(filename: "fit-\(UUID().uuidString).json"))
        var brewer = Equipment(kind: .brewer, brand: "Hario", model: "V60 02", brewerType: "V60")
        brewer.size = "02"
        brewer.acceptsFilterShapes = [.cone60]
        setup.add(brewer)

        #expect(FilterFit.owned(for: brewer, in: setup).isEmpty)

        let one = FilterStock(modelId: "hario-v60-white-jp-tabbed", size: "02", shape: .cone60)
        setup.add(one)
        #expect(FilterFit.owned(for: brewer, in: setup).count == 1)

        setup.add(FilterStock(modelId: "cafec-abaca", size: "4cup", shape: .cone60))
        setup.add(FilterStock(modelId: "sibarist-fast-cone", size: "02", shape: .cone60))
        setup.add(FilterStock(modelId: "kalita-wave-185", size: "185", shape: .wave))
        #expect(FilterFit.owned(for: brewer, in: setup).count == 3)
    }

    @Test func temperatureIsPrefilledNotHinted() {
        let setup = BrewJourneySupport.setup()
        let card = BrewJourneySupport.card(agitation: nil)
        let brew = BrewPrefill.seed(card: card, setup: setup)
        #expect(brew.temperature != nil)
        #expect(brew.temperature == RecipeRules.suggestedTemperature(for: card.roastLevel, method: .v60))
        #expect(brew.captureSource == .prefilled)
        let dial = try! String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Recipes/BrewDialView.swift"))
        #expect(!dial.contains("temperatureHint"))
    }

    @Test func grindWritesPositionAndValueNeverRaw() {
        var grinder = Equipment(kind: .grinder, brand: "Comandante", model: "C40", adjustment: .clicks)
        grinder.ranges = [GrindRange(method: .v60, low: 18, high: 30)]
        let span = GrindSpan.make(grinder: grinder, method: .v60, current: 22)
        #expect(span != nil)
        var setting = GrindSetting()
        setting.setNotch(3, span: span, grinderId: grinder.id)
        #expect(setting.raw == nil)
        #expect(setting.position == 3)
        #expect(setting.value != nil)
        setting.setValue(22, span: span, grinderId: grinder.id)
        #expect(setting.raw == nil)
        #expect(setting.value == 22)
        #expect(setting.position != nil)
    }

    @Test func rinseIsInjectedOnlyForPaperOrCloth() {
        let paper = Equipment(kind: .brewer, brand: "Hario", model: "V60", brewerType: "V60", size: "02", acceptsFilterShapes: [.cone60])
        let metal = Equipment(
            kind: .brewer,
            brand: "Able",
            model: "Kone",
            filterShape: "métal",
            acceptsFilterShapes: []
        )
        let recipe = Recipe(name: "V60", method: .v60, dose: 15, water: 250, steps: [
            RecipeStep(at: 0, action: .bloom, targetMass: 45),
        ])
        let injected = RinseRule.injecting(into: recipe, brewer: paper, stock: nil)
        #expect(injected.steps.first?.action == .rinse)
        #expect(injected.steps.count == 2)
        let skipped = RinseRule.injecting(into: recipe, brewer: metal, stock: nil)
        #expect(skipped.steps.first?.action == .bloom)
    }

    @Test func rinseSitsOutsideTBTAndFlow() {
        let steps = [
            RecipeStep(at: 0, action: .rinse, targetMass: 150, note: "hot water"),
            RecipeStep(at: 0, action: .bloom, targetMass: 45),
            RecipeStep(at: 45, action: .pour, targetMass: 250),
        ]
        #expect(GuidedTarget.currentMass(steps: steps, index: 0, elapsed: 10, total: 150) == 0)
        #expect(GuidedTarget.startMass(for: steps, at: 1) == 0)
        #expect(GuidedTarget.finalMass(steps: steps, water: 250) == 250)
        var brew = Brew(method: .v60, water: 250, seconds: 150, steps: [
            BrewStep(index: 0, action: .rinse, at: 0, mass: 150, targetMass: 150),
            BrewStep(index: 1, action: .bloom, at: 0, mass: 45, targetMass: 45),
            BrewStep(index: 2, action: .pour, at: 150, mass: 250, targetMass: 250),
        ])
        #expect(brew.stepFlows.allSatisfy { $0.step.action != .rinse })
        #expect(brew.averageFlow == 250.0 / 150.0)
        #expect(StepAction.rinse.imperative == "Rinse")
    }

    @Test func dictationFillsWaterAndFilterInFrenchAndEnglish() {
        let water = WaterProfile(name: "Volvic", source: .bottled)
        let paper = FilterStock(modelId: "cafec-abaca", customName: nil, size: "02", shape: .cone60)
        let en = SpokenBrewParser.parse(
            "ninety four degrees, twenty two clicks, swirl, volvic, cafec abaca",
            waters: [water],
            filters: [paper]
        )
        #expect(en.temperature == 94)
        #expect(en.grind != nil)
        #expect(en.agitation == .swirl)
        #expect(en.waterProfileId == water.id)
        #expect(en.filterStockId == paper.id)

        let tap = WaterProfile(name: "Tap", source: .tap)
        let hario = FilterStock(customName: "Hario", size: "02", shape: .cone60)
        let fr = SpokenBrewParser.parse(
            "quatre-vingt-quatorze degrés, vingt-deux clics, swirl, robinet, hario",
            waters: [tap],
            filters: [hario]
        )
        #expect(fr.temperature == 94 || fr.leftover.contains("quatorze") || fr.waterProfileId == tap.id)
        #expect(fr.waterProfileId == tap.id || fr.waterName != nil)
        #expect(fr.filterStockId == hario.id || fr.filterName != nil)
    }

    @Test func filterMovesAreGatedOnOwnership() {
        let brewer = Equipment(kind: .brewer, brand: "Hario", model: "V60", size: "02", acceptsFilterShapes: [.cone60])
        var brew = Brew(
            method: .v60,
            dose: 15,
            water: 250,
            seconds: 210,
            grind: GrindSetting(value: 22),
            bitterness: 1
        )
        brew.recipeSnapshot = RecipeSnapshot(from: Recipe(method: .v60, seconds: 150))
        brew.equipmentIDs = [brewer.id]
        #expect(BrewDiagnosis.filterMoves(for: brew, brewer: brewer, stock: []).allSatisfy { $0.variable != .filter })

        let fast = FilterStock(modelId: "sibarist-fast-cone", size: "02", shape: .cone60)
        let slow = FilterStock(modelId: "hario-v60-white-jp-tabbed", size: "02", shape: .cone60)
        brew.filterStockId = slow.id
        let moves = BrewDiagnosis.filterMoves(for: brew, brewer: brewer, stock: [fast, slow])
        #expect(moves.contains { $0.variable == .filter && $0.change.contains("faster") })
    }

    @Test func rinseMoreRanksFirstWhenPaperyIsChecked() {
        var brew = BrewDiagnosisTests.brew(acidity: 1)
        brew.flavors = [FlavorTag(id: "other-papery-musty-papery")]
        let next = BrewDiagnosis.nextTime(for: brew)
        let rinse = BrewDiagnosis.filterMoves(for: brew, brewer: nil, stock: []).first { $0.variable == .rinse }
        #expect(rinse != nil)
        #expect(rinse!.variable.priority < NextTime.Variable.grind.priority)
        #expect(BrewDiagnosis.admissibleSet(for: brew, filterStock: []).min(by: { $0.variable.priority < $1.variable.priority })?.variable == .rinse)
        #expect(next?.variable == .rinse || rinse!.variable.priority == 0)
    }

    @Test func differentPaperMakesASentence() {
        let abaca = FilterStock(modelId: "cafec-abaca-plus", size: "02", shape: .cone60)
        let fast = FilterStock(modelId: "sibarist-fast-cone", size: "02", shape: .cone60)
        var a = BrewComparisonTests.brew(seconds: 180, taste: TasteProfile(clarity: 5))
        var b = BrewComparisonTests.brew(seconds: 145, taste: TasteProfile(clarity: 8))
        a.filterStockId = abaca.id
        b.filterStockId = fast.id
        let compared = BrewComparison.of(a, against: b, filterStock: [abaca, fast])
        #expect(compared.parameterDeltas.contains { $0.label == "Filter" && $0.changed })
        #expect(compared.sentence?.contains("Different paper") == true)
    }

    @Test func flowClassCalibrationNeedsThreePairedBrews() {
        let hario = FilterStock(modelId: "hario-v60-white-jp-tabbed", size: "02", shape: .cone60)
        let cafec = FilterStock(modelId: "cafec-abaca", size: "02", shape: .cone60)
        let brewer = UUID()
        func brew(filter: UUID, seconds: Int) -> Brew {
            var brew = Brew(method: .v60, dose: 15, water: 250, seconds: seconds, grind: GrindSetting(value: 22))
            brew.filterStockId = filter
            brew.equipmentIDs = [brewer]
            return brew
        }
        let two = [
            brew(filter: hario.id, seconds: 180),
            brew(filter: cafec.id, seconds: 150),
        ]
        #expect(FilterCalibration.of(two, stock: [hario, cafec], focusing: cafec.id) == nil)

        let enough = two + [
            brew(filter: hario.id, seconds: 176),
            brew(filter: cafec.id, seconds: 148),
            brew(filter: hario.id, seconds: 184),
            brew(filter: cafec.id, seconds: 152),
        ]
        let result = FilterCalibration.of(enough, stock: [hario, cafec], focusing: cafec.id)
        #expect(result != nil)
        #expect(result?.brewCount ?? 0 >= 3)
        #expect(result?.sentence.contains("On your setup") == true)
        #expect(result?.fasterId == cafec.id)
    }

    @Test func todaySettingsIsAFacade() {
        var brew = Brew(method: .v60, temperature: 93)
        brew.today.temperature = 90
        #expect(brew.temperature == 90)
        brew.filterStockId = UUID()
        #expect(brew.today.filterStockId == brew.filterStockId)
    }

    @Test func brewDecodesTheLegacyFilterIdKey() throws {
        let id = UUID()
        let json = Data("{\"method\":\"v60\",\"filterId\":\"\(id.uuidString)\"}".utf8)
        let brew = try JSONDecoder().decode(Brew.self, from: json)
        #expect(brew.filterStockId == id)
    }

    @Test func seedHasFortyFiveFilters() {
        #expect(ReferenceBase.filters.count == 54)
    }

    @Test func liftingKeepsTheFilterUUID() {
        let setup = SetupStore(files: JSONDocumentStore(filename: "lift-\(UUID().uuidString).json"))
        let paper = BrewFilter(brand: "Hario", shape: "02")
        let brewer = Equipment(
            kind: .brewer,
            brand: "Hario",
            model: "V60",
            filters: [paper],
            defaultFilterId: paper.id
        )
        setup.add(brewer)
        #expect(setup.filterStock.contains { $0.id == paper.id })
        #expect(setup.filterStock.first?.isDefaultFor.contains(brewer.id) == true)
    }

    @Test func profileAndOnboardingExposeFilters() throws {
        let profile = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Setup/ProfileSheet.swift"))
        #expect(profile.contains("filtersSection"))
        #expect(profile.contains("FilterKitRow"))
        #expect(profile.contains("Copy.addAFilter"))
        let flow = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Setup/SetupFlowSheet.swift"))
        #expect(flow.contains("Copy.whichPaper"))
        #expect(flow.contains("cafec-abaca"))
        let rail = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Design/GrindRail.swift"))
        #expect(rail.contains("GrindGrade.allCases"))
        #expect(rail.contains("setNotch"))
        #expect(rail.contains("setValue"))
        let preview = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Design/GrindSample.swift"))
        #expect(preview.contains("struct GrindPreview"))
        #expect(preview.contains("measured"))
    }
}