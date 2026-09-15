import Foundation
import Testing

@testable import Kohi

/// The insights, and above all their thresholds. A finding drawn from one cup
/// is the failure mode this whole module is shaped to avoid, so most of what
/// is pinned here is what the engine refuses to say.
struct InsightsEngineTests {
    static func brew(
        rating: Int?,
        grind: String = "22 clicks",
        method: BrewMethod = .v60,
        equipment: [UUID] = [],
        water: UUID? = nil,
        date: Date = .now
    ) -> Brew {
        Brew(
            date: date,
            method: method,
            dose: 15,
            water: 250,
            seconds: 165,
            grind: GrindSetting(raw: grind),
            waterProfileID: water,
            rating: rating
        )
    }

    static func card(
        name: String = "Chelbesa",
        process: String = "Washed",
        roast: RoastLevel? = .light,
        brews: [Brew]
    ) -> CoffeeCard {
        var card = CoffeeCard(name: name, process: process, brews: brews)
        card.roastLevel = roast
        return card
    }

    static func grinder(_ name: String = "C40") -> Equipment {
        Equipment(kind: .grinder, brand: "Comandante", model: name)
    }

    // MARK: - Nothing to say

    @Test func anEmptyArchiveSaysNothing() {
        #expect(InsightsEngine.insights(for: []).isEmpty)
    }

    @Test func brewsWithoutRatingsSayNothing() {
        let card = Self.card(brews: [Self.brew(rating: nil), Self.brew(rating: nil)])

        #expect(InsightsEngine.bestBrew(in: [card]) == nil)
    }

    // MARK: - Thresholds

    /// The rule the section lives by: below the threshold the row exists, but
    /// it states the gap instead of a finding.
    @Test func oneGoodCupIsNotAFinding() {
        let card = Self.card(brews: [Self.brew(rating: 5)])
        let insight = try! #require(InsightsEngine.bestBrew(in: [card]))

        #expect(!insight.isReady)
        #expect(insight.finding.isEmpty)
        #expect(insight.sampleSize == 1)
        #expect(insight.threshold == InsightsEngine.minimumSample)
    }

    @Test func theGapIsCountedOutLoud() {
        let card = Self.card(brews: [Self.brew(rating: 5)])
        let insight = try! #require(InsightsEngine.bestBrew(in: [card]))

        #expect(insight.waiting == "2 more brews and this can be answered")
    }

    @Test func theLastMissingBrewIsSingular() {
        let card = Self.card(brews: [Self.brew(rating: 5), Self.brew(rating: 3)])
        let insight = try! #require(InsightsEngine.bestBrew(in: [card]))

        #expect(insight.waiting == "1 more brew and this can be answered")
    }

    @Test func threeRatedBrewsAreEnough() {
        let card = Self.card(brews: [
            Self.brew(rating: 5), Self.brew(rating: 3), Self.brew(rating: 4),
        ])
        let insight = try! #require(InsightsEngine.bestBrew(in: [card]))

        #expect(insight.isReady)
        #expect(insight.finding == "Chelbesa")
        #expect(!insight.detail.isEmpty)
    }

    // MARK: - Best brew

    @Test func theBestBrewIsTheBestRatedOne() {
        let card = Self.card(brews: [
            Self.brew(rating: 3, grind: "20 clicks"),
            Self.brew(rating: 5, grind: "22 clicks"),
            Self.brew(rating: 4, grind: "24 clicks"),
        ])
        let insight = try! #require(InsightsEngine.bestBrew(in: [card]))

        #expect(insight.detail.contains("15"))
        #expect(insight.scope == "Chelbesa")
    }

    /// It is scoped to one coffee on purpose: comparing a Kenyan to a Brazilian
    /// through a five-point scale compares your mood, not the coffee.
    @Test func theBestBrewIsScopedToOneCoffee() {
        let liked = Self.card(name: "Chelbesa", brews: [
            Self.brew(rating: 5), Self.brew(rating: 5), Self.brew(rating: 4),
        ])
        let other = Self.card(name: "Sertão", brews: [Self.brew(rating: 3)])
        let insight = try! #require(InsightsEngine.bestBrew(in: [liked, other]))

        #expect(insight.scope == "Chelbesa")
        #expect(insight.sampleSize == 3)
    }

    // MARK: - Sweet spot

    @Test func theSweetSpotNeedsSeveralSettingsTried() {
        let grinder = Self.grinder()
        // The same setting five times is a habit, not a spot.
        let card = Self.card(brews: (0..<5).map { _ in
            Self.brew(rating: 5, grind: "22 clicks", equipment: [grinder.id])
        })

        let insight = try! #require(
            InsightsEngine.sweetSpot(in: [card], equipment: [grinder])
        )
        #expect(!insight.isReady)
        #expect(insight.sampleSize == 1)
    }

    @Test func theSweetSpotIsTheBestRatedSetting() {
        let grinder = Self.grinder()
        let card = Self.card(brews: [
            Self.brew(rating: 2, grind: "18 clicks", equipment: [grinder.id]),
            Self.brew(rating: 5, grind: "22 clicks", equipment: [grinder.id]),
            Self.brew(rating: 3, grind: "26 clicks", equipment: [grinder.id]),
        ])

        let insight = try! #require(
            InsightsEngine.sweetSpot(in: [card], equipment: [grinder])
        )
        #expect(insight.isReady)
        #expect(insight.finding.contains("22"))
        #expect(insight.detail.contains("V60"))
    }

    /// The median is the whole reason this is trustworthy: one bad morning on
    /// a good setting should not move the answer.
    @Test func oneBadMorningDoesNotMoveTheSweetSpot() {
        let grinder = Self.grinder()
        let card = Self.card(brews: [
            Self.brew(rating: 5, grind: "22 clicks", equipment: [grinder.id]),
            Self.brew(rating: 5, grind: "22 clicks", equipment: [grinder.id]),
            Self.brew(rating: 1, grind: "22 clicks", equipment: [grinder.id]),
            Self.brew(rating: 4, grind: "18 clicks", equipment: [grinder.id]),
            Self.brew(rating: 4, grind: "26 clicks", equipment: [grinder.id]),
        ])

        let insight = try! #require(
            InsightsEngine.sweetSpot(in: [card], equipment: [grinder])
        )
        // The mean of 5, 5 and 1 is 3.67, below the 4s. The median is 5.
        #expect(insight.finding.contains("22"))
    }

    @Test func theSweetSpotIsPerMethod() {
        let grinder = Self.grinder()
        let card = Self.card(brews: [
            Self.brew(rating: 5, grind: "8 clicks", method: .espresso, equipment: [grinder.id]),
            Self.brew(rating: 5, grind: "10 clicks", method: .espresso, equipment: [grinder.id]),
            Self.brew(rating: 4, grind: "12 clicks", method: .espresso, equipment: [grinder.id]),
            Self.brew(rating: 3, grind: "22 clicks", method: .v60, equipment: [grinder.id]),
        ])

        let insight = try! #require(
            InsightsEngine.sweetSpot(in: [card], equipment: [grinder])
        )
        #expect(insight.detail.contains("Espresso"))
        #expect(insight.scope.contains("Espresso"))
    }

    @Test func aVerbalGrindIsNotASetting() {
        let card = Self.card(brews: [
            Self.brew(rating: 5, grind: "medium-fine"),
            Self.brew(rating: 4, grind: "fine"),
            Self.brew(rating: 3, grind: "coarse"),
        ])

        #expect(InsightsEngine.sweetSpot(in: [card], equipment: []) == nil)
    }

    // MARK: - Water

    @Test func theWaterInsightNeedsBrewsAgainstAProfile() {
        let card = Self.card(brews: [Self.brew(rating: 5)])

        #expect(InsightsEngine.waterInsight(in: [card], profiles: []) == nil)
    }

    @Test func theBestRatedWaterWins() {
        let soft = WaterProfile(name: "Montcalm", source: .bottled)
        let hard = WaterProfile(name: "Tap", source: .tap)
        let card = Self.card(brews: [
            Self.brew(rating: 5, water: soft.id),
            Self.brew(rating: 5, water: soft.id),
            Self.brew(rating: 4, water: soft.id),
            Self.brew(rating: 2, water: hard.id),
        ])

        let insight = try! #require(
            InsightsEngine.waterInsight(in: [card], profiles: [soft, hard])
        )
        #expect(insight.isReady)
        #expect(insight.finding == "Montcalm")
    }

    /// The segment is only named when the archive actually supports it. One
    /// process across every brew is a segment; a mixture is not.
    @Test func theSegmentIsOnlyNamedWhenItIsReal() {
        let profile = WaterProfile(name: "Montcalm", source: .bottled)
        let washed = Self.card(name: "A", process: "Washed", brews: [
            Self.brew(rating: 5, water: profile.id),
            Self.brew(rating: 4, water: profile.id),
            Self.brew(rating: 5, water: profile.id),
        ])
        let mixed = Self.card(name: "B", process: "Natural", brews: [
            Self.brew(rating: 4, water: profile.id),
        ])

        let onlyWashed = try! #require(
            InsightsEngine.waterInsight(in: [washed], profiles: [profile])
        )
        #expect(onlyWashed.detail.contains("all washed"))

        let both = try! #require(
            InsightsEngine.waterInsight(in: [washed, mixed], profiles: [profile])
        )
        #expect(!both.detail.contains("all washed"))
    }

    // MARK: - The median

    @Test func theMedianIsTheMiddleValue() {
        #expect(InsightsEngine.median([1, 5, 3]) == 3)
        #expect(InsightsEngine.median([5]) == 5)
        #expect(InsightsEngine.median([]) == 0)
    }

    @Test func anEvenCountAveragesTheTwoMiddles() {
        #expect(InsightsEngine.median([1, 2, 4, 5]) == 3)
    }

    // MARK: - The whole set

    @Test func theEngineIsAPureFunctionOfTheArchive() {
        let grinder = Self.grinder()
        let profile = WaterProfile(name: "Montcalm", source: .bottled)
        let card = Self.card(brews: [
            Self.brew(rating: 5, grind: "22 clicks", equipment: [grinder.id], water: profile.id),
            Self.brew(rating: 4, grind: "20 clicks", equipment: [grinder.id], water: profile.id),
            Self.brew(rating: 3, grind: "24 clicks", equipment: [grinder.id], water: profile.id),
        ])

        let first = InsightsEngine.insights(
            for: [card], equipment: [grinder], water: [profile]
        )
        let second = InsightsEngine.insights(
            for: [card], equipment: [grinder], water: [profile]
        )

        #expect(first == second)
        #expect(first.count == 4)
        #expect(Set(first.map(\.kind)) == [.bestBrew, .sweetSpot, .water, .trend])
    }

    @Test func aTasteTrendNeedsThreeComparableBrews() {
        let card = Self.card(brews: [
            Self.brew(rating: 3, date: Date(timeIntervalSince1970: 1)).tasted(acidity: 8, body: 3),
            Self.brew(rating: 4, date: Date(timeIntervalSince1970: 2)).tasted(acidity: 6, body: 5),
            Self.brew(rating: 5, date: Date(timeIntervalSince1970: 3)).tasted(acidity: 3, body: 8),
        ])
        let insight = try! #require(InsightsEngine.trend(in: [card]))
        #expect(insight.isReady)
        #expect(insight.finding.contains("acidity ↓"))
        #expect(insight.finding.contains("body ↑"))
    }
}

private extension Brew {
    func tasted(acidity: Int, body: Int) -> Brew {
        var brew = self
        brew.taste = TasteProfile(acidity: acidity, body: body)
        return brew
    }
}
