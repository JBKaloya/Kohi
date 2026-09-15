import Foundation
import Testing
@testable import Kohi

struct ReferenceEquipmentTests {
    @Test func everyItemHasAUniqueIdAKnownKindAndASource() {
        let ids = ReferenceBase.kit.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(!ids.isEmpty)
        for item in ReferenceBase.kit {
            #expect(EquipmentKind(rawValue: item.kind.rawValue) != nil)
            #expect(!item.source.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(!item.brand.isEmpty)
            #expect(!item.model.isEmpty)
        }
    }

    @Test func everyBrewerHasAKnownFamily() {
        let brewers = ReferenceBase.kit.filter { $0.kind == .brewer || $0.kind == .espressoMachine }
        #expect(!brewers.isEmpty)
        for item in brewers {
            #expect(item.family != nil)
            if let family = item.family {
                #expect(BrewerFamily.allCases.contains(family))
            }
        }
    }

    @Test func typingHarioFindsTheV60() {
        let matches = ReferenceBase.equipment(kind: .brewer, matching: "Hario V60")
        #expect(matches.contains { $0.model.contains("V60") })
    }

    @Test func theDripperSeedIsSearchable() {
        #expect(ReferenceBase.brewers.count == 80)
        let origami = ReferenceBase.equipment(kind: .brewer, matching: "Origami")
        #expect(origami.contains { $0.brand == "Origami" })
    }

    @Test func grindersSeedCoversTheCatalogue() {
        #expect(ReferenceBase.grinders.count >= 180)
        #expect(ReferenceBase.grinders.contains { $0.brand == "Comandante" })
    }

    @Test func aGrinderQueryStillHitsTheGrinderBase() {
        let matches = ReferenceBase.equipment(kind: .grinder, matching: "1Zpresso")
        #expect(matches.contains { $0.brand == "1Zpresso" })
    }
}
