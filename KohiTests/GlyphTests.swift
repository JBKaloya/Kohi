import SwiftUI
import Testing
@testable import Kohi

struct GlyphTests {
    @Test func everyGlyphDrawsInsideTheGrid() {
        for glyph in EquipmentGlyph.allCases {
            let path = glyph.path
            #expect(!path.isEmpty, "\(glyph.rawValue) is empty")
            let bounds = path.boundingRect
            #expect(bounds.minX >= -0.6, "\(glyph.rawValue) minX \(bounds.minX)")
            #expect(bounds.minY >= -0.6, "\(glyph.rawValue) minY \(bounds.minY)")
            #expect(bounds.maxX <= 24.6, "\(glyph.rawValue) maxX \(bounds.maxX)")
            #expect(bounds.maxY <= 24.6, "\(glyph.rawValue) maxY \(bounds.maxY)")
        }
    }

    @Test func aFamilyMapsOntoABrewMethod() {
        #expect(BrewerType.v60.method == .v60)
        #expect(BrewerType.flat.method == .filter)
        #expect(BrewerType.chemex.method == .filter)
        #expect(BrewerType.immersionSwitch.method == .filter)
        #expect(BrewerType.batch.method == .filter)
        #expect(BrewerType.espresso.equipmentKind == .espressoMachine)
        #expect(BrewerType.v60.equipmentKind == .brewer)
        #expect(BrewerType.moka.family == .espresso)
        #expect(BrewerType.aeropress.family == .immersion)
    }

    @Test func brewerTypeRoundTripsThroughTheFamily() {
        for type in BrewerType.allCases {
            #expect(BrewerType.parse(type.storageValue) == type)
        }
        #expect(BrewerType.parse("Kalita Wave") == .flat)
        #expect(BrewerType.parse("Hario Switch") == .immersionSwitch)
        #expect(EquipmentGlyph.forKit(.brewer, family: .v60) == .coneDripper)
        #expect(EquipmentGlyph.forKit(.kettle, family: nil) == .gooseneckKettle)
    }
}
