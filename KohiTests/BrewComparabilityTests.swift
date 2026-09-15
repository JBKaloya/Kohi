import Foundation
import Testing
@testable import Kohi

struct BrewComparabilityTests {
    @Test func aFullRecipeIsComparable() {
        let brew = Brew(
            method: .v60,
            dose: 15,
            water: 250,
            seconds: 165,
            grind: "22 clicks",
            rating: 4
        )
        #expect(brew.isComparable)
        #expect(brew.completeness == .complete)
        #expect(brew.completeness.tag == "Comparable")
    }

    @Test func missingFieldsAreNamed() {
        let brew = Brew(method: .v60, dose: 15)
        #expect(!brew.isComparable)
        if case .missing(let fields) = brew.completeness {
            #expect(fields.contains(.output))
            #expect(fields.contains(.time))
            #expect(fields.contains(.grind))
            #expect(fields.contains(.rating))
        } else {
            Issue.record("expected missing fields")
        }
        #expect(brew.completeness.tag == "missing output · time · grind · rating")
    }

    @Test func aWholeRatioDropsTheDecimal() {
        #expect(Brew(dose: 15, water: 240).ratio == "1:16")
        #expect(Brew(dose: 15, water: 214.5).ratio == "1:14.3")
    }

    @Test func againClearsJudgementAndKeepsTheRecipe() {
        let original = Brew(
            method: .v60,
            dose: 15,
            water: 250,
            seconds: 165,
            grind: "22 clicks",
            agitation: .swirl,
            taste: TasteProfile(acidity: 7),
            flavors: [FlavorTag(custom: "jasmine")],
            rating: 4,
            notes: "good"
        )
        let copy = original.again()

        #expect(copy.method == .v60)
        #expect(copy.dose == 15)
        #expect(copy.grind.value == 22)
        #expect(copy.agitation == .swirl)
        #expect(copy.rating == nil)
        #expect(copy.taste.isEmpty)
        #expect(copy.flavors.isEmpty)
        #expect(copy.captureSource == .prefilled)
        #expect(copy.id != original.id)
    }
}
