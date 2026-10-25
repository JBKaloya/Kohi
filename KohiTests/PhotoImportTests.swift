import CoreGraphics
import Foundation
import Testing
@testable import Kohi

struct PhotoImportTests {
    @Test func aFragmentOfTheFrameIsTooSmallToTrust() {
        let size = CGSize(width: 1000, height: 1000)
        let fragment = Quad(
            topLeft: CGPoint(x: 100, y: 100),
            topRight: CGPoint(x: 180, y: 100),
            bottomRight: CGPoint(x: 180, y: 220),
            bottomLeft: CGPoint(x: 100, y: 220)
        )
        #expect(fragment.areaFraction(in: size) < ScanTuning.minimumImportAreaFraction)
    }

    @Test func aCardFillingTheFramePassesTheImportGuard() {
        let size = CGSize(width: 1000, height: 1000)
        let card = Quad.inset(in: size, by: 0.08)
        #expect(card.areaFraction(in: size) >= ScanTuning.minimumImportAreaFraction)
        #expect(card.skew <= ScanTuning.maximumSkew)
    }
}

struct RoastLevelTests {
    @Test func labelsHaveNoHyphens() {
        for level in RoastLevel.allCases {
            #expect(!level.label.contains("-"))
        }
        #expect(RoastLevel.superLight.label == "Super light")
        #expect(RoastLevel.mediumLight.label == "Medium light")
        #expect(RoastLevel.mediumDark.label == "Medium dark")
    }

    @Test func aCranSuggestsAnAgtronWithoutMappingTheBag() {
        #expect(RoastLevel.superLight.suggestedAgtron == 95)
        #expect(RoastLevel.light.suggestedAgtron == 85)
        #expect(RoastLevel.dark.suggestedAgtron == 45)
    }
}
