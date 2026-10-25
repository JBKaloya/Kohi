import Foundation
import Testing
@testable import Kohi

struct SetupFlowTests {
    private func emptyStore() -> SetupStore {
        SetupStore(files: JSONDocumentStore(filename: "setup-flow-\(UUID().uuidString).json"))
    }

    @Test func skippingTheThreeQuestionsCreatesNothing() {
        let store = emptyStore()
        #expect(store.equipment.isEmpty)
        #expect(store.waterProfiles.isEmpty)
    }

    @Test func v60AGrinderAndTapFillTheKit() {
        let store = emptyStore()
        let family = BrewerType.v60
        let brewer = Equipment(
            kind: family.equipmentKind,
            model: family.label,
            brewerType: family.storageValue
        )
        store.add(brewer)
        store.setDefault(brewer, for: family.method, on: true)
        store.setPreferredRecipeMethod(family.method)

        let mill = Equipment(kind: .grinder, brand: "Comandante", model: "C40 MK4", adjustment: .clicks)
        store.add(mill)
        store.setDefault(mill, for: .v60, on: true)

        let tap = WaterProfile(name: "Tap", source: .tap, isDefault: true)
        store.add(tap)
        store.makeDefault(tap)

        #expect(store.equipment.count == 2)
        #expect(store.equipment.contains { $0.kind == .brewer && $0.brewerFamily == .v60 })
        #expect(store.grinders.count == 1)
        #expect(store.waterProfiles.count == 1)
        #expect(store.defaults(for: .v60).count == 2)
        #expect(store.preferredRecipeMethod == .v60)
    }

    @Test func closingAfterTheFirstQuestionKeepsTheBrewer() {
        let store = emptyStore()
        let brewer = Equipment(kind: .brewer, model: "V60", brewerType: BrewerType.v60.storageValue)
        store.add(brewer)
        store.setDefault(brewer, for: .v60, on: true)

        #expect(store.equipment.count == 1)
        #expect(store.grinders.isEmpty)
        #expect(store.waterProfiles.isEmpty)
    }

    @Test func theEntryStepIsSkippedWhenTheKitIsNotEmpty() {
        let store = emptyStore()
        store.add(Equipment(kind: .brewer, model: "V60", brewerType: "V60"))
        #expect(!store.kitIsEmpty)
    }

    @Test func firstScanFlagIsWhatTriggersTheFlow() {
        let flow = SetupFlowController()
        flow.resetFirstScanFlag()
        #expect(!flow.hasScannedFirstCard)
        #expect(!flow.hasSeenSetupFlow)
        flow.hasScannedFirstCard = true
        flow.hasSeenSetupFlow = true
        #expect(flow.hasScannedFirstCard)
        flow.resetFirstScanFlag()
        #expect(!flow.hasScannedFirstCard)
        #expect(!flow.hasSeenSetupFlow)
    }
}

struct RecipeSuggestionUniquenessTests {
    @Test func oneCardNeverProducesTwoRows() {
        let card = CoffeeCard(name: "Chelchele", roaster: "Townsfolk")
        let items = RecipeSuggestions.items(
            from: [card, card],
            method: .v60,
            mine: [],
            neighbours: [card]
        )
        #expect(Set(items.map(\.card.id)).count == items.count)
    }
}
