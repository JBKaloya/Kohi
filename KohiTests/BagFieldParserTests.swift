import Foundation
import Testing
@testable import Kohi

/// What the packaging says beyond the origin story, and the traps around it:
/// best-before dates posing as roast dates, a brewing card's water mass posing
/// as a bag weight, a lot number posing as the coffee's name.
struct BagFieldParserTests {
    /// Fixed "now" so the plausibility window does not drift with the calendar.
    static let now = Date(timeIntervalSince1970: 1_764_000_000) // 2025-11-24

    static func parse(_ lines: [String]) -> ParsedFields {
        var fields = ParsedFields()
        BagFieldParser.parse(lines, into: &fields)
        return fields
    }

    private func lines(_ texts: [String]) -> [TextExtractor.Line] {
        texts.enumerated().map { index, text in
            TextExtractor.Line(text: text, y: Double(index) * 0.03, x: 0)
        }
    }

    // MARK: - Roast date

    @Test func roastDateReadsCommonFormats() throws {
        let iso = try #require(BagFieldParser.date(in: "2025-11-02", now: Self.now))
        #expect(Calendar.current.component(.month, from: iso) == 11)
        #expect(Calendar.current.component(.day, from: iso) == 2)

        let european = try #require(BagFieldParser.date(in: "02/11/2025", now: Self.now))
        #expect(Calendar.current.component(.month, from: european) == 11)
        #expect(Calendar.current.component(.day, from: european) == 2)

        let japanese = try #require(BagFieldParser.date(in: "2025年11月2日", now: Self.now))
        #expect(Calendar.current.component(.day, from: japanese) == 2)

        let spelled = try #require(BagFieldParser.date(in: "2 November 2025", now: Self.now))
        #expect(Calendar.current.component(.month, from: spelled) == 11)
    }

    /// A day past 12 can only be the day, whatever the order says.
    @Test func unambiguousMonthFirstDateIsNotReadBackwards() throws {
        let date = try #require(BagFieldParser.date(in: "11/22/2025", now: Self.now))
        #expect(Calendar.current.component(.month, from: date) == 11)
        #expect(Calendar.current.component(.day, from: date) == 22)
    }

    @Test func roastDateFollowsItsLabel() throws {
        let fields = Self.parse(["ROASTED ON 02.11.2025", "Ethiopia"])
        let roasted = try #require(fields.roastedOn)
        #expect(Calendar.current.component(.day, from: roasted) == 2)
    }

    @Test func roastDateOnTheNextLineIsPickedUp() throws {
        let fields = Self.parse(["焙煎日", "2025/11/02"])
        #expect(fields.roastedOn != nil)
    }

    /// The trap this parser exists for: bags print both dates, one above the
    /// other, and only one of them tells you how to brew.
    @Test func bestBeforeIsNotARoastDate() {
        #expect(Self.parse(["BEST BEFORE 02/11/2026"]).roastedOn == nil)
        #expect(Self.parse(["賞味期限 2026/11/02"]).roastedOn == nil)
    }

    @Test func futureDateIsRejected() {
        #expect(Self.parse(["Roasted on 02/11/2027"]).roastedOn == nil)
    }

    @Test func aDateWithNoLabelIsNotARoastDate() {
        #expect(Self.parse(["02/11/2025", "Washed"]).roastedOn == nil)
    }

    // MARK: - Roast level

    @Test func roastLevelReadsWordsNotPurpose() {
        #expect(Self.parse(["MEDIUM-DARK ROAST"]).roastLevel == .mediumDark)
        #expect(Self.parse(["Light roast"]).roastLevel == .light)
        #expect(Self.parse(["深煎り"]).roastLevel == .dark)
        #expect(Self.parse(["MEDIUM"]).roastLevel == .medium)
        // Says what the roast is for, not how dark it is.
        #expect(Self.parse(["Espresso roast"]).roastLevel == nil)
        #expect(Self.parse(["Omni roast"]).roastLevel == nil)
    }

    /// "medium-dark" must not be read as "medium".
    @Test func longestRoastLevelTokenWins() {
        #expect(Self.parse(["Medium light roast"]).roastLevel == .mediumLight)
    }

    // MARK: - Price

    @Test func priceNeedsACurrency() throws {
        let euro = Self.parse(["18,50 €"])
        #expect(euro.price == 18.5)
        #expect(euro.currency == "EUR")

        let dollar = Self.parse(["$22.00"])
        #expect(dollar.price == 22)
        #expect(dollar.currency == "USD")

        let yen = Self.parse(["¥1,500"])
        #expect(yen.price == 1500)
        #expect(yen.currency == "JPY")

        // A bare number is a weight far more often than a price.
        #expect(Self.parse(["250"]).price == nil)
    }

    // MARK: - Bag weight

    @Test func bagWeightConvertsUnits() {
        #expect(Self.parse(["250g"]).bagWeightG == 250)
        #expect(Self.parse(["NET WT 1 kg"]).bagWeightG == 1000)

        let ounces = Self.parse(["Net weight 12 oz"])
        #expect(ounces.bagWeightG.map { Int($0.rounded()) } == 340)

        #expect(Self.parse(["内容量 200g"]).bagWeightG == 200)
    }

    /// A brewing card's water mass is not a bag size.
    @Test func recipeWaterIsNotABagWeight() {
        #expect(Self.parse(["お湯の量 250g"]).bagWeightG == nil)
        #expect(Self.parse(["Water 250 g"]).bagWeightG == nil)
        #expect(Self.parse(["Dose 18 g"]).bagWeightG == nil)
    }

    // MARK: - Score, agtron, decaf

    @Test func cuppingScoreStaysInRange() {
        #expect(Self.parse(["SCA score 87.5"]).cuppingScore == 87.5)
        #expect(Self.parse(["Cupping score: 86"]).cuppingScore == 86)
        // Moisture content, not a cup score.
        #expect(Self.parse(["Score 11%"]).cuppingScore == nil)
        #expect(Self.parse(["Score 42"]).cuppingScore == nil)
    }

    @Test func agtronIsReadWhenNamed() {
        #expect(Self.parse(["Agtron 62/78"]).agtron == 62)
        #expect(Self.parse(["62"]).agtron == nil)
    }

    @Test func decafIsOnlyEverSetTrue() {
        #expect(Self.parse(["Decaf — Swiss Water"]).isDecaf == true)
        #expect(Self.parse(["Decaf — Swiss Water"]).decafMethod == .swissWater)
        #expect(Self.parse(["Sugarcane EA"]).decafMethod == .sugarcaneEA)
        #expect(Self.parse(["デカフェ"]).isDecaf == true)
        #expect(Self.parse(["Ethiopia Chelbesa"]).isDecaf == nil)
    }

    // MARK: - Through the full parser

    /// The collision this chantier had to undo: `lot` was mapped onto the
    /// coffee's name, so "Lot: 24-118" named the card after its batch number.
    @Test func lotNoLongerBecomesTheName() {
        let parsed = FieldParser.parse(lines([
            "Coffee: Chelbesa",
            "Lot: 24-118",
            "Harvest: 2025/26",
        ]))
        #expect(parsed.name == "Chelbesa")
        #expect(parsed.lot == "24-118")
        #expect(parsed.harvest == "2025/26")
    }

    @Test func bagFieldsRideAlongWithTheOriginFields() throws {
        let parsed = FieldParser.parse(lines([
            "ETHIOPIA",
            "Producer: Chelbesa washing station",
            "Process: Washed",
            "MEDIUM-LIGHT ROAST",
            "Roasted on 02/11/2025",
            "250g",
            "18,50 €",
        ]))
        #expect(parsed.country == "Ethiopia")
        #expect(parsed.roastLevel == .mediumLight)
        #expect(parsed.bagWeightG == 250)
        #expect(parsed.price == 18.5)
        #expect(parsed.currency == "EUR")
        #expect(parsed.roastedOn != nil)
    }

    // MARK: - Derived values

    @Test func priceLineComparesBagsBySize() {
        var card = CoffeeCard(name: "Chelbesa")
        card.price = 14
        card.currency = "EUR"
        card.bagWeightG = 250
        #expect(card.pricePerKilo == 56)
        #expect(card.priceLine == "14 € · 250 g · 56 €/kg")
    }

    @Test func priceLineDropsWhatIsMissing() {
        var card = CoffeeCard(name: "Chelbesa")
        #expect(card.priceLine == nil)
        card.bagWeightG = 250
        #expect(card.priceLine == "250 g")
    }

    @Test func daysOffRoastCountsCalendarDays() {
        var card = CoffeeCard(name: "Chelbesa")
        card.roastedOn = Self.now
        #expect(card.daysOffRoast(asOf: Self.now) == 0)
        #expect(card.daysOffRoast(asOf: Self.now.addingTimeInterval(3 * 86400)) == 3)
    }
}
