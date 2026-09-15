import Foundation
import Testing
@testable import Kohi

struct BrewComparisonTests {
    static func brew(
        dose: Double = 15,
        water: Double = 250,
        seconds: Int = 165,
        grind: GrindSetting = "22 clicks",
        temperature: Double = 93,
        agitation: Agitation? = .swirl,
        taste: TasteProfile = TasteProfile(),
        flavors: [FlavorTag] = [],
        rating: Int = 4
    ) -> Brew {
        Brew(
            method: .v60,
            dose: dose,
            water: water,
            seconds: seconds,
            grind: grind,
            temperature: temperature,
            agitation: agitation,
            taste: taste,
            flavors: flavors,
            rating: rating
        )
    }

    @Test func aSingleGrindChangeMakesASentence() {
        let a = Self.brew(grind: "22 clicks", taste: TasteProfile(acidity: 7, body: 4))
        let b = Self.brew(grind: "20 clicks", taste: TasteProfile(acidity: 4, body: 7))
        let compared = BrewComparison.of(a, against: b)

        #expect(compared.parameterDeltas.contains { $0.label == "Grind" && $0.changed })
        #expect(compared.sentence?.contains("Grind") == true || compared.sentence?.contains("Finer") == true)
    }

    @Test func severalChangesAreHardToAttribute() {
        let a = Self.brew(dose: 15, water: 250, seconds: 165)
        let b = Self.brew(dose: 16, water: 240, seconds: 150)
        let compared = BrewComparison.of(a, against: b)

        #expect(compared.sentence?.contains("Several things changed") == true)
    }

    @Test func flavoursSplitIntoBothAndOnly() {
        let jasmine = FlavorTag(id: "floral-floral-jasmine")
        let peach = FlavorTag(id: "fruity-other-fruit-peach")
        let cocoa = FlavorTag(id: "nutty-cocoa-cocoa")
        let a = Self.brew(flavors: [jasmine, peach])
        let b = Self.brew(flavors: [jasmine, cocoa])
        let compared = BrewComparison.of(a, against: b)

        #expect(compared.common.map(\.id) == ["floral-floral-jasmine"])
        #expect(compared.onlyA.map(\.id) == ["fruity-other-fruit-peach"])
        #expect(compared.onlyB.map(\.id) == ["nutty-cocoa-cocoa"])
    }

    @Test func theSameGrinderReportsClickDelta() {
        let grinder = Equipment(kind: .grinder, brand: "Comandante", model: "C40")
        let a = Self.brew(grind: GrindSetting(grinderId: grinder.id, value: 22, raw: "22 clicks"))
        let b = Self.brew(grind: GrindSetting(grinderId: grinder.id, value: 20, raw: "20 clicks"))
        let compared = BrewComparison.of(a, against: b, equipment: [grinder])
        let grind = compared.parameterDeltas.first { $0.label == "Grind" }

        #expect(grind?.delta.contains("clicks") == true)
        #expect(grind?.changed == true)
    }
}
