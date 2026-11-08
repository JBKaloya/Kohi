import Foundation
import Testing

@testable import Kohi

/// Build 14: one classification of methods, shared by the tasting and the
/// brew. The reference is docs/methodes-extraction.md.

struct TastingMethodFamilyTests {
    private static let userID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    @Test func theFirstLevelFollowsTheDecidedOrder() {
        #expect(TastingMethod.families.map(\.label) == ["Hand brew", "Batch brew", "Espresso", "Cold brew", "Other"])
    }

    @Test func theSecondLevelSitsUnderHandBrewAndEspressoOnly() {
        #expect(TastingMethod.handBrew.devices.map(\.label) == ["V60", "Flat dripper", "Chemex", "AeroPress", "French press"])
        #expect(TastingMethod.espresso.devices.map(\.deviceLabel) == ["Machine", "Moka"])
        #expect(TastingMethod.handBrew.devices.map(\.deviceLabel) == TastingMethod.handBrew.devices.map(\.label))
        #expect(TastingMethod.batch.devices.isEmpty)
        #expect(TastingMethod.coldBrew.devices.isEmpty)
        #expect(TastingMethod.other.devices.isEmpty)
        for method in TastingMethod.allCases {
            #expect(method.root.devices.contains(method) || method.root == method)
        }
    }

    /// Tapping Espresso lands on the machine, so its chip is lit at once.
    @Test func espressoAloneIsTheMachine() {
        #expect(TastingMethod.espresso.root == .espresso)
        #expect(TastingMethod.espresso.devices.first == .espresso)
        #expect(TastingMethod.espresso.brewer == .espresso)
        #expect(TastingMethod.espresso.line == "Espresso")
    }

    @Test func kalitaReadsFlatDripper() {
        #expect(TastingMethod.kalita.label == "Flat dripper")
        #expect(TastingMethod.kalita.line == "Hand brew · Flat dripper")
    }

    @Test func everyMethodSurvivesTheDraftAndTheRow() {
        for method in TastingMethod.allCases {
            var draft = TastingDraft()
            draft.coffee.name = "Gesha"
            draft.method = method
            if method == .other { draft.methodNote = "Siphon" }
            let saved = draft.tasting(base: nil)
            let synced = TastingRow(tasting: saved, userID: Self.userID).toTasting()
            #expect(synced.method == saved.method)
            #expect(synced.brewer == saved.brewer)
            #expect(synced.isBatch == saved.isBatch)
            #expect(TastingDraft(synced).method == method, "\(method)")
        }
    }

    @Test func anOldFilterWithoutDripperNowReadsHandBrew() {
        let old = Tasting(context: .home(brewID: nil), method: .filter)
        #expect(TastingDraft(old).method == .handBrew)
        #expect(old.methodLine == "Hand brew")
    }

    @Test func aTastingShowsFamilyThenDevice() {
        let cases: [(Tasting, String)] = [
            (Tasting(context: .home(brewID: nil), method: .filter, brewer: .v60), "Hand brew · V60"),
            (Tasting(context: .home(brewID: nil), method: .filter, brewer: .flat), "Hand brew · Flat dripper"),
            (Tasting(context: .home(brewID: nil), method: .filter, brewer: .immersionSwitch), "Hand brew · Immersion"),
            (Tasting(context: .home(brewID: nil), method: .frenchPress, brewer: .frenchPress), "Hand brew · French press"),
            (Tasting(context: .home(brewID: nil), method: .filter, isBatch: true), "Batch brew"),
            (Tasting(context: .home(brewID: nil), method: .espresso, brewer: .espresso), "Espresso"),
            (Tasting(context: .home(brewID: nil), method: .moka, brewer: .moka), "Espresso · Moka"),
            (Tasting(context: .home(brewID: nil), method: .coldBrew, brewer: .coldBrew), "Cold brew"),
            (Tasting(context: .home(brewID: nil), method: .moka), "Espresso · Moka"),
            (Tasting(context: .home(brewID: nil), methodNote: "Siphon"), "Siphon"),
        ]
        for (tasting, line) in cases {
            #expect(tasting.methodLine == line)
        }
    }

    @Test func theCollapsedSummaryUsesTheSameLine() {
        var draft = TastingDraft()
        draft.method = .moka
        #expect(draft.detailSummary == "Espresso · Moka")
        draft.method = .other
        draft.methodNote = "Siphon"
        #expect(draft.detailSummary == "Siphon")
    }

    @Test func menuWordsStayWhereTheyWere() {
        #expect(TastingMethod(word: "filtre") == .batch)
        #expect(TastingMethod(word: "Kalita") == .kalita)
        #expect(TastingMethod(word: "ristretto") == .espresso)
    }

    @Test func thePickerHasTwoLevels() throws {
        let fields = try String(
            contentsOf: DevBrief10.kohiRoot.appending(path: "Tastings/TastingFields.swift"),
            encoding: .utf8
        )
        #expect(fields.contains("ForEach(TastingMethod.families)"))
        #expect(fields.contains("ForEach(root.devices)"))
        #expect(!fields.contains("ForEach(TastingMethod.allCases)"))
    }
}

@MainActor
struct BrewFamilyTests {
    private func store(_ name: String) -> SetupStore {
        SetupStore(files: JSONDocumentStore(filename: "\(name)-\(UUID().uuidString).json"))
    }

    @Test func theKitTitleSaysDripperExceptOnEspresso() {
        #expect(BrewerFamily.handBrew.kitTitle == "Dripper")
        #expect(BrewerFamily.batch.kitTitle == "Dripper")
        #expect(BrewerFamily.coldBrew.kitTitle == "Dripper")
        #expect(BrewerFamily.espresso.kitTitle == "Machine")
    }

    @Test func aBatchBrewStaysOnBatchWithoutAMachine() {
        let setup = store("batch-none")
        let v60 = Equipment(kind: .brewer, brand: "Hario", model: "V60", brewerType: "V60")
        setup.add(v60)
        let session = BrewSession(card: CoffeeCard(name: "Test"), setup: setup)
        session.apply(family: .batch, setup: setup)
        #expect(session.brew.method == .filter)
        #expect(BrewKit.activeBrewer(on: session.brew, in: setup) == nil)
        #expect(session.tab(in: setup) == .batch)
        session.apply(family: .handBrew, setup: setup)
        #expect(session.tab(in: setup) == .handBrew)
        #expect(BrewKit.activeBrewer(on: session.brew, in: setup)?.id == v60.id)
    }

    @Test func aBatchMachineSetsTheTabOnItsOwn() {
        let setup = store("batch-kit")
        let batch = Equipment(kind: .brewer, brand: "Moccamaster", model: "KBG", brewerType: "Batch")
        setup.add(batch)
        var brew = Brew(method: .filter, equipmentIDs: [batch.id])
        #expect(BrewKit.tab(for: brew, in: setup) == .batch)
        BrewPrefill.ensureMatchingBrewer(on: &brew, setup: setup)
        #expect(brew.equipmentIDs.contains(batch.id))
    }

    @Test func aStaleHintGivesWayToTheMethod() {
        #expect(BrewKit.tab(for: .espresso, hint: .batch) == .espresso)
        #expect(BrewKit.tab(for: .filter, hint: .batch) == .batch)
        #expect(BrewKit.tab(for: .filter) == .handBrew)
        #expect(BrewKit.tab(for: .coldBrew) == .coldBrew)
    }

    @Test func theBatchTabListsFilterRecipesOnly() {
        let filter = Recipe(name: "Batch 1 L", method: .filter, dose: 60, water: 1000)
        let v60 = Recipe(name: "Ultimate", method: .v60, dose: 15, water: 250)
        #expect(RecipePickerMatch.belongs(filter, to: .batch))
        #expect(!RecipePickerMatch.belongs(v60, to: .batch))
        #expect(RecipePickerMatch.belongs(v60, to: .handBrew))
    }

    @Test func aRecipeWithoutKitKeepsItsOldSequence() {
        let legacy: [BrewMethod: BrewerType] = [
            .v60: .v60, .filter: .v60,
            .aeropress: .frenchPress, .frenchPress: .frenchPress, .coldBrew: .frenchPress,
            .espresso: .espresso, .moka: .espresso,
        ]
        for (method, type) in legacy {
            let recipe = Recipe(name: "R", method: method, dose: 15, water: 250, seconds: 180)
            let filled = DefaultSequence.filling(recipe)
            let expected = DefaultSequence.make(
                family: method.family, brewerType: type,
                dose: 15, water: 250, beverage: nil, targetTime: 180
            )
            #expect(filled.steps.map(\.action) == expected.map(\.action), "\(method)")
            #expect(filled.steps.map(\.targetMass) == expected.map(\.targetMass), "\(method)")
        }
    }

    @Test func eachBrewerKeepsItsOwnSequence() {
        for type in BrewerType.allCases {
            let recipe = Recipe(name: "R", method: type.method, dose: 15, water: 250, seconds: 180)
            let filled = DefaultSequence.filling(recipe, type: type)
            let expected = DefaultSequence.make(
                family: .handBrew, brewerType: type,
                dose: 15, water: 250, beverage: nil, targetTime: 180
            )
            #expect(filled.steps.map(\.action) == expected.map(\.action), "\(type)")
        }
    }
}

struct MethodsDocTests {
    @Test func theDocNamesEveryMethodAndBrewer() throws {
        let doc = try String(
            contentsOf: DevBrief10.kohiRoot
                .deletingLastPathComponent()
                .appending(path: "docs/methodes-extraction.md"),
            encoding: .utf8
        )
        for method in TastingMethod.allCases {
            #expect(doc.contains("`\(method.rawValue)`"), "\(method)")
            #expect(doc.contains(method.label), "\(method)")
        }
        for type in BrewerType.allCases {
            #expect(doc.contains("`\(type.rawValue)`"), "\(type)")
        }
        for family in BrewerFamily.allCases {
            #expect(doc.contains(family.label))
        }
    }
}
