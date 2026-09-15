import Foundation
import Testing
@testable import Kohi

struct FlavorMatcherTests {
    @Test func anExactEnglishLabelHitsTheWheel() {
        let match = FlavorMatcher.match("jasmine")
        #expect(match.tags.map(\.id) == ["floral-floral-jasmine"])
        #expect(match.unmatched.isEmpty)
    }

    @Test func aFrenchLabelHitsTheSameNode() {
        let match = FlavorMatcher.match("jasmin")
        #expect(match.tags.map(\.id) == ["floral-floral-jasmine"])
    }

    @Test func aPluralIsSingularised() {
        let match = FlavorMatcher.match("blueberries")
        #expect(match.tags.contains { $0.displayName == "Blueberry" })
    }

    @Test func aLevelTwoMatchStaysAtLevelTwo() {
        let match = FlavorMatcher.match("berry")
        #expect(match.tags.map(\.id) == ["fruity-berry"])
        #expect(FlavorWheel.shared.node(id: match.tags[0].id)?.level == 2)
    }

    @Test func aOneLetterTypoOnALongWordStillHits() {
        let match = FlavorMatcher.match("jasminn")
        #expect(match.tags.map(\.id) == ["floral-floral-jasmine"])
    }

    @Test func anUnknownFragmentBecomesCustom() {
        let match = FlavorMatcher.match("petrol station")
        #expect(match.tags.first?.isCustom == true)
        #expect(match.unmatched == ["petrol station"])
    }

    @Test func aCommaSeparatedLineSplits() {
        let match = FlavorMatcher.match(["jasmine, peach"])
        #expect(Set(match.tags.map(\.id)) == ["floral-floral-jasmine", "fruity-other-fruit-peach"])
    }
}
