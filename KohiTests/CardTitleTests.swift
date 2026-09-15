import Foundation
import Testing
@testable import Kohi

struct CardTitleTests {
    @Test func aNamedCardKeepsItsName() {
        let card = CoffeeCard(name: "Chelbesa", region: "Gedeb", variety: "Heirloom")
        #expect(card.displayName == "Chelbesa")
    }

    @Test func producerBeatsVarietyWhenTheNameIsEmpty() {
        let card = CoffeeCard(
            region: "Gedeb, Gedeo",
            producer: "Chelbesa Washing Station",
            variety: "Heirloom Landrace"
        )
        #expect(card.displayName == "Chelbesa Washing Station, Gedeb, Gedeo")
    }

    @Test func aUniqueCardGetsNoSuffix() {
        let card = CoffeeCard(region: "Gedeb", producer: "Chelbesa Washing Station")
        #expect(CardTitles.title(for: card, among: [card]) == card.displayName)
    }

    @Test func twoStationsWithDifferentRoastersGetDifferentTitles() {
        let a = CoffeeCard(
            roaster: "Townsfolk",
            region: "Gedeb",
            producer: "Chelbesa Washing Station"
        )
        let b = CoffeeCard(
            roaster: "Gardelli",
            region: "Gedeb",
            producer: "Chelbesa Washing Station"
        )
        let titles = CardTitles.index(for: [a, b])
        #expect(titles[a.id] == "Chelbesa Washing Station, Gedeb · Townsfolk")
        #expect(titles[b.id] == "Chelbesa Washing Station, Gedeb · Gardelli")
    }

    @Test func theStoreMirrorsTheIndex() {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "titles-\(UUID().uuidString).json")
        let store = CardStore(files: CardFileStore(url: url))
        let a = CoffeeCard(roaster: "Townsfolk", region: "Gedeb", producer: "Station")
        let b = CoffeeCard(roaster: "Gardelli", region: "Gedeb", producer: "Station")
        store.insert([a, b])
        #expect(store.title(for: a) == "Station, Gedeb · Townsfolk")
        #expect(store.title(for: b) == "Station, Gedeb · Gardelli")
    }
}
