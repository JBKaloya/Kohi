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
        #expect(BrewerFamily.v60.method == .v60)
        #expect(BrewerFamily.flat.method == .filter)
        #expect(BrewerFamily.chemex.method == .filter)
        #expect(BrewerFamily.immersionSwitch.method == .filter)
        #expect(BrewerFamily.batch.method == .filter)
        #expect(BrewerFamily.espresso.equipmentKind == .espressoMachine)
        #expect(BrewerFamily.v60.equipmentKind == .brewer)
    }

    @Test func brewerTypeRoundTripsThroughTheFamily() {
        for family in BrewerFamily.allCases {
            #expect(BrewerFamily.parse(family.storageValue) == family)
        }
        #expect(BrewerFamily.parse("Kalita Wave") == .flat)
        #expect(BrewerFamily.parse("Hario Switch") == .immersionSwitch)
        #expect(EquipmentGlyph.forKit(.brewer, family: .v60) == .coneDripper)
        #expect(EquipmentGlyph.forKit(.kettle, family: nil) == .gooseneckKettle)
    }
}
