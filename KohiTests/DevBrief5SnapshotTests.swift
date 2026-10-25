import SwiftUI
import Testing
@testable import Kohi

@Suite(.serialized)
@MainActor
struct DevBrief5SnapshotTests {
    @Test func todaySettingsWithAGrinder() {
        snapshotDial(setup: BrewJourneySupport.setup(), named: "grinder", testName: #function)
    }

    @Test func todaySettingsWithoutAGrinder() {
        let setup = SetupStore(files: JSONDocumentStore(filename: "dial-nogrinder-\(UUID().uuidString).json"))
        let paper = BrewFilter(brand: "Hario", shape: "02")
        let brewer = Equipment(
            kind: .brewer,
            brand: "Hario",
            model: "V60 02",
            brewerType: "V60",
            filters: [paper],
            defaultFilterId: paper.id,
            size: "02",
            acceptsFilterShapes: [.cone60]
        )
        setup.add(brewer)
        setup.setDefault(brewer, for: .v60, on: true)
        setup.add(WaterProfile(name: "Tap", source: .tap, isDefault: true))
        snapshotDial(setup: setup, named: "no-grinder", testName: #function)
    }

    @Test func todaySettingsWithZeroCompatibleFilters() {
        let setup = SetupStore(files: JSONDocumentStore(filename: "dial-0f-\(UUID().uuidString).json"))
        var brewer = Equipment(kind: .brewer, brand: "Hario", model: "V60 02", brewerType: "V60")
        brewer.size = "02"
        brewer.acceptsFilterShapes = [.cone60]
        setup.add(brewer)
        setup.setDefault(brewer, for: .v60, on: true)
        setup.add(Equipment(kind: .grinder, brand: "Comandante", model: "C40", adjustment: .clicks, ranges: [GrindRange(method: .v60, low: 18, high: 30)]))
        setup.add(WaterProfile(name: "Volvic", source: .bottled, isDefault: true))
        snapshotDial(setup: setup, named: "zero-filters", testName: #function)
    }

    @Test func todaySettingsWithThreeCompatibleFilters() {
        let setup = SetupStore(files: JSONDocumentStore(filename: "dial-3f-\(UUID().uuidString).json"))
        var brewer = Equipment(kind: .brewer, brand: "Hario", model: "V60 02", brewerType: "V60")
        brewer.size = "02"
        brewer.acceptsFilterShapes = [.cone60]
        setup.add(brewer)
        setup.setDefault(brewer, for: .v60, on: true)
        setup.add(Equipment(kind: .grinder, brand: "Comandante", model: "C40", adjustment: .clicks, ranges: [GrindRange(method: .v60, low: 18, high: 30)]))
        setup.add(WaterProfile(name: "Volvic", source: .bottled, isDefault: true))
        setup.add(FilterStock(modelId: "hario-v60-white-jp-tabbed", size: "02", shape: .cone60))
        setup.add(FilterStock(modelId: "cafec-abaca", size: "02", shape: .cone60))
        setup.add(FilterStock(modelId: "sibarist-fast-cone", size: "02", shape: .cone60))
        snapshotDial(setup: setup, named: "three-filters", testName: #function)
    }

    private func snapshotDial(setup: SetupStore, named: String, testName: String) {
        let session = BrewSession(
            card: BrewJourneySupport.card(agitation: nil),
            recipe: ReferenceBase.recipe(referenceID: "a1-v60-ultimate"),
            size: .twoCups,
            start: .dial,
            setup: setup
        )
        SnapshotSupport.image(
            of: BrewJourneySupport.wrap(
                BrewDialView(
                    session: session,
                    onBack: {},
                    onClose: {},
                    onBrewNow: {},
                    onAlreadyBrewed: {}
                ),
                setup: setup
            ),
            height: 980,
            named: named,
            testName: testName
        )
    }
}