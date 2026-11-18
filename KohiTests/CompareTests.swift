import SwiftUI
import Testing
@testable import Kohi

@MainActor
struct CompareTests {
    static let bright = TasteProfile(values: [.acidity: 8, .bitterness: 2, .sweetness: 7, .aroma: 8, .aftertaste: 6, .body: 3, .clarity: 8])
    static let round = TasteProfile(values: [.acidity: 4, .bitterness: 4, .sweetness: 8, .aroma: 6, .aftertaste: 7, .body: 7, .clarity: 5])
    static let dark = TasteProfile(values: [.acidity: 2, .bitterness: 7, .sweetness: 5, .aroma: 5, .aftertaste: 8, .body: 9, .clarity: 3])

    @Test func distinctCardColoursAreKept() {
        let red = OKLab.fromSRGB(0.75, 0.2, 0.15)
        let blue = OKLab.fromSRGB(0.15, 0.3, 0.7)
        #expect(CompareColors.inks([red, blue]) == [red, blue])
    }

    @Test func closeColoursMoveLighterThenDarker() {
        let ink = OKLab.fromSRGB(0.5, 0.3, 0.2)
        let inks = CompareColors.inks([ink, ink, ink])
        #expect(inks[0] == ink)
        #expect(inks[1].x > ink.x)
        #expect(inks[2].x < ink.x)
        for i in inks.indices {
            for j in inks.indices where j > i {
                #expect(CompareColors.distance(inks[i], inks[j]) >= CompareColors.minimumDistance)
            }
        }
    }

    @Test func seriesWithoutACardTakeThePalette() {
        let inks = CompareColors.inks([nil, nil])
        #expect(inks == [CompareColors.primary, CompareColors.secondary])
        let third = CompareColors.inks([nil, nil, nil])
        #expect(CompareColors.distance(third[2], CompareColors.primary) >= CompareColors.minimumDistance)
    }

    @Test func stylesTellSeriesApartWithoutColour() {
        let styles = (0..<3).map(SeriesStyle.at)
        #expect(Set(styles.map(\.rawValue)).count == 3)
        #expect(Set(styles.map(\.spoken)).count == 3)
    }

    @Test func compareTakesTwoToThree() {
        var picked: [Int] = []
        for id in 1...4 { picked = CompareSelection.toggling(id, in: picked) }
        #expect(picked == [1, 2, 3, 4])
        #expect(!CompareSelection.canCompare(picked.count))
        picked = CompareSelection.toggling(2, in: picked)
        #expect(picked == [1, 3, 4])
        #expect(CompareSelection.canCompare(picked.count))
        #expect(!CompareSelection.canCompare(1))
    }

    @Test func aCoffeeIsItsMedian() {
        let card = CoffeeCard(
            name: "Huabal",
            roaster: "Dak",
            brewMethod: .v60,
            brews: [
                Brew(method: .v60, dose: 15, water: 250, taste: Self.bright, rating: 4),
                Brew(method: .v60, dose: 15, water: 250, taste: Self.round, rating: 4),
            ],
            roastLevel: .light
        )
        let series = CompareSeries.coffee(card, ink: nil)
        #expect(series.taste == CardProfileData.medianTaste(of: card))
        #expect(series.taste[.sweetness] == 8)
    }

    // MARK: - Radar

    private func series(_ count: Int) -> [RadarSeries] {
        let tastes = [Self.bright, Self.round, Self.dark]
        let inks = CompareColors.inks([nil, nil, nil])
        return (0..<count).map { index in
            RadarSeries(
                taste: tastes[index],
                color: CompareColors.color(inks[index]),
                style: .at(index),
                label: "Coffee \(index + 1)"
            )
        }
    }

    @Test func radarOneSeries() {
        SnapshotSupport.image(of: TasteRadar(series: series(1), size: 220), height: 320, named: "one")
    }

    @Test func radarTwoSeries() {
        SnapshotSupport.image(of: TasteRadar(series: series(2), size: 220), height: 320, named: "two")
    }

    @Test func radarThreeSeries() {
        SnapshotSupport.image(of: TasteRadar(series: series(3), size: 220), height: 320, named: "three")
    }
}

@MainActor
struct CompareViewSnapshotTests {
    @Test func threeBrewsSideBySide() {
        let card = CoffeeCard(name: "Huabal", roaster: "Dak", brewMethod: .v60)
        let brews = [
            Brew(method: .v60, dose: 15, water: 250, seconds: 170, temperature: 93, taste: CompareTests.bright),
            Brew(method: .v60, dose: 16, water: 250, seconds: 185, temperature: 94, taste: CompareTests.round),
            Brew(method: .v60, dose: 15, water: 240, seconds: 160, temperature: 92, taste: CompareTests.dark),
        ]
        let series = brews.map { CompareSeries.brew($0, on: card, ink: nil) }
        SnapshotSupport.image(of: CompareView(series: series), height: 900, named: "brews")
    }

    @Test func aCoffeeAndATastingMix() {
        let card = CoffeeCard(
            name: "Huabal",
            roaster: "Dak",
            brewMethod: .v60,
            brews: [
                Brew(method: .v60, dose: 15, water: 250, taste: CompareTests.bright),
                Brew(method: .v60, dose: 15, water: 250, taste: CompareTests.round),
            ]
        )
        let tasting = Tasting(
            context: .out(place: Place(name: "Crible", address: "", latitude: 0, longitude: 0), placeID: nil),
            coffee: TastedCoffee(name: "Gesha Village"),
            taste: CompareTests.dark
        )
        let series = [
            CompareSeries.coffee(card, ink: OKLab.fromSRGB(0.62, 0.18, 0.2)),
            CompareSeries.tasting(tasting, card: nil, ink: nil),
        ]
        SnapshotSupport.image(of: CompareView(series: series), height: 700, named: "mixed")
    }
}
