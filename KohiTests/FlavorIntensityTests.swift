import Foundation
import Testing

@testable import Kohi

/// An optional strength, 1 to 5, on a note tasted in the cup. Never on what
/// the pack announces, never invented for a note ticked before it existed.
struct FlavorIntensityTests {
    private let pineapple = "fruity-other-fruit-pineapple"

    @Test func aTickedNoteStartsWithoutAnIntensity() {
        #expect(FlavorTag(id: pineapple).intensity == nil)
        #expect(FlavorTag(custom: "Yuzu kosho").intensity == nil)
    }

    @Test func onlyOneToFiveIsKept() {
        #expect(FlavorTag(id: pineapple, intensity: 3).intensity == 3)
        #expect(FlavorTag(id: pineapple, intensity: 0).intensity == nil)
        #expect(FlavorTag(id: pineapple, intensity: 6).intensity == nil)
    }

    @Test func setThenClearThenRemoveThenAddAgain() {
        var selection = [FlavorTag(id: pineapple), FlavorTag(custom: "Yuzu kosho")]
        selection.setIntensity(4, of: pineapple)
        #expect(selection.first?.intensity == 4)
        selection.setIntensity(nil, of: pineapple)
        #expect(selection.first?.intensity == nil)

        selection.setIntensity(2, of: pineapple)
        selection.removeAll { $0.id == pineapple }
        selection.append(FlavorTag(id: pineapple, intensity: 2).unrated)
        #expect(selection.last?.intensity == nil)
    }

    @Test func aCustomTagTakesAnIntensityToo() {
        let custom = FlavorTag(custom: "Yuzu kosho")
        var selection = [custom]
        selection.setIntensity(5, of: custom.id)
        #expect(selection.first?.intensity == 5)
        #expect(selection.first?.displayName == "Yuzu kosho")
    }

    @Test func anOldNoteDecodesAsTickedWithoutIntensity() throws {
        let old = #"[{"id":"fruity-other-fruit-pineapple"},"custom:yuzu","Pineapple"]"#
        let tags = try JSONDecoder().decode([FlavorTag].self, from: Data(old.utf8))
        #expect(tags.count == 3)
        #expect(tags.allSatisfy { $0.intensity == nil })
    }

    @Test func intensityTravelsWithTheTag() throws {
        let tag = FlavorTag(id: pineapple, intensity: 3)
        let data = try JSONEncoder().encode([tag])
        #expect(try JSONDecoder().decode([FlavorTag].self, from: data) == [tag])

        let unrated = try JSONEncoder().encode([FlavorTag(id: pineapple)])
        #expect(!String(decoding: unrated, as: UTF8.self).contains("intensity"))
    }

    @Test func aTastingRowAndABrewRowKeepIt() {
        var tasting = Tasting(context: .out(place: Place(name: "A", address: "", latitude: 0, longitude: 0), placeID: nil))
        tasting.flavors = [FlavorTag(id: pineapple, intensity: 4)]
        #expect(TastingRow(tasting: tasting, userID: UUID()).toTasting().flavors.first?.intensity == 4)

        var brew = Brew()
        brew.flavors = [FlavorTag(id: pineapple, intensity: 2)]
        #expect(BrewRow(brew: brew, cardID: UUID(), userID: UUID()).toBrew().flavors.first?.intensity == 2)
    }

    @Test func recentNotesAreOfferedWithoutTheirOldIntensity() {
        let recent = SensoryScored.recent([[FlavorTag(id: pineapple, intensity: 5)]])
        #expect(recent.first?.id == pineapple)
        #expect(recent.first?.intensity == nil)
    }

    @Test func aSpokenNoteIsNotAddedTwice() {
        var brew = Brew()
        brew.flavors = [FlavorTag(id: pineapple, intensity: 3)]
        var result = SpokenBrewParser.Result()
        result.flavors = ["pineapple"]
        SpokenBrewParser.apply(result, to: &brew)
        #expect(brew.flavors.count == 1)
        #expect(brew.flavors.first?.intensity == 3)
    }

    @Test func labelsReadFromFaintToStrong() {
        #expect(FlavorTag.intensities.map(FlavorTag.intensityLabel) == ["Very faint", "Faint", "Clear", "Strong", "Very strong"])
    }

    @Test func thePackNeverCarriesAnIntensity() {
        let coffee = TastedCoffee(tastingNotes: ["Pineapple", "Cacao"])
        #expect(coffee.declaredFlavors.allSatisfy { $0.intensity == nil })
    }
}
