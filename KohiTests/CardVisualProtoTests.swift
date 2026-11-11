import Foundation
import SwiftUI
import Testing
@testable import Kohi

/// The hybrid face shipped with a single Kohi cards switch on the coffees
/// bar. Only the fiche's own switch is still a debug prototype.
struct CardVisualProtoTests {
    @Test func theFicheSwitchIsDebugOnly() throws {
        let proto = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Grid/CardVisualProto.swift"))
        #expect(proto.hasPrefix("#if DEBUG"))
        #expect(!proto.contains("CardVisualMenu"))
        #expect(!proto.contains("Originals"))
    }

    @Test func aScanFaceIsTheHybrid() throws {
        let tile = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Grid/CardTile.swift"))
        #expect(tile.contains("if face == .scan {\n                    HybridCardFace(card: card, width: width)"))
        #expect(!tile.contains("#if DEBUG"))
        let hybrid = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Grid/HybridCardFace.swift"))
        #expect(hybrid.contains("aspect: 4.0 / 5.0, fills: true"))
    }

    @Test func theBarSitsAboveTheGridOutsideItsScroll() throws {
        let grid = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Grid/GridScreen.swift"))
        #expect(grid.contains("CoffeesBar()\n                                if shouldShowSearch { searchChips }\n                                grid"))
        #expect(!grid.contains("CardVisualMenu"))
        let bar = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Grid/CoffeesBar.swift"))
        #expect(bar.contains("LiquidToggle(isOn: kohiCards, label: Copy.kohiCards"))
    }

    @MainActor
    @Test func theSwitchWritesTheGlobalFace() {
        let defaults = UserDefaults(suiteName: "CardVisualProtoTests.\(UUID().uuidString)")!
        let looks = CardLookStore(defaults: defaults)
        looks.global = .scan
        #expect(looks.resolved(cardID: UUID(), hasScan: true) == .scan)
        looks.global = .kohi
        #expect(looks.resolved(cardID: UUID(), hasScan: true) == .kohi)
        #expect(looks.resolved(cardID: UUID(), hasScan: false) == .kohi)
    }

    @Test func cropOnlyWithAFixedRatio() throws {
        let view = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Grid/CardImageView.swift"))
        #expect(view.contains("if fills, aspect != nil"))
        #expect(view.contains(".scaledToFill()"))
        #expect(view.contains(".clipped()"))
    }

    @MainActor
    @Test(arguments: [false, true])
    func coffeesBarReadsAsASwitch(kohi: Bool) {
        let defaults = UserDefaults(suiteName: "CoffeesBar.\(UUID().uuidString)")!
        let looks = CardLookStore(defaults: defaults)
        looks.global = kohi ? .kohi : .scan
        SnapshotSupport.image(
            of: CoffeesBar().environment(looks),
            height: 48,
            named: kohi ? "kohiCards" : "hybrid"
        )
    }

    @Test func theToggleKeepsBenchoProportions() throws {
        let toggle = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Design/LiquidToggle.swift"))
        #expect(toggle.contains("height * 36 / 46"))
        #expect(toggle.contains("stiffness: 170 - (50 - speed) * 1.1"))
        #expect(toggle.contains("damping: 21.5"))
        #expect(toggle.contains(".accessibilityAddTraits(.isToggle)"))
    }
}
