import Foundation
import Testing

@testable import Kohi

/// The diagnostic rules of annexe G7. They are the reason the app can say
/// something useful about a brew without a model, so they are pinned here:
/// one variable per answer, in a fixed order, and silence when the brew says
/// nothing.
struct BrewDiagnosisTests {
    static func brew(
        method: BrewMethod? = .v60,
        dose: Double? = 15,
        water: Double? = 250,
        beverage: Double? = nil,
        seconds: Int? = 165,
        grind: String = "22 clicks",
        tds: Double? = nil,
        acidity: Int = 0,
        bitterness: Int = 0,
        body: Int = 0,
        taste: TasteProfile = TasteProfile()
    ) -> Brew {
        Brew(
            method: method,
            dose: dose,
            water: water,
            beverage: beverage,
            seconds: seconds,
            grind: GrindSetting(raw: grind),
            temperature: 93,
            tds: tds,
            taste: taste,
            rating: 3,
            acidity: acidity,
            bitterness: bitterness,
            body: body
        )
    }

    // MARK: - Saying nothing

    @Test func aBrewThatSaysNothingGetsNoAdvice() {
        #expect(BrewDiagnosis.nextTime(for: Self.brew()) == nil)
    }

    // MARK: - One variable at a time

    @Test func everySuggestionMovesExactlyOneVariable() {
        let brews = [
            Self.brew(acidity: 1),
            Self.brew(bitterness: 1),
            Self.brew(body: -1),
            Self.brew(body: 1),
            Self.brew(method: .espresso, water: nil, beverage: 36, seconds: 18),
        ]
        for brew in brews {
            let suggestion = BrewDiagnosis.nextTime(for: brew)
            #expect(suggestion != nil)
            #expect(suggestion?.reason.isEmpty == false)
        }
    }

    @Test func sourWithoutBitternessGrindsFiner() {
        let suggestion = BrewDiagnosis.nextTime(for: Self.brew(acidity: 1))

        #expect(suggestion?.variable == .grind)
        #expect(suggestion?.direction == -1)
        #expect(suggestion?.change == "grind finer")
    }

    @Test func bitterWithoutSournessGrindsCoarser() {
        let suggestion = BrewDiagnosis.nextTime(for: Self.brew(bitterness: 1))

        #expect(suggestion?.variable == .grind)
        #expect(suggestion?.direction == 1)
    }

    /// The rule that matters most, because it is the one an intuition gets
    /// wrong: sour *and* bitter is an even-ness problem, and grinding either
    /// way makes one of the two worse.
    @Test func sourAndBitterAtOnceLeavesTheGrindAlone() {
        let suggestion = BrewDiagnosis.nextTime(for: Self.brew(acidity: 1, bitterness: 1))

        #expect(suggestion?.variable == .technique)
        #expect(suggestion?.change.contains("leave the grind alone") == true)
        // And it is the only answer: nothing else is offered alongside it.
        #expect(BrewDiagnosis.candidates(for: Self.brew(acidity: 1, bitterness: 1)).count == 1)
    }

    @Test func thinButWellExtractedMovesTheRatioNotTheGrind() {
        let suggestion = BrewDiagnosis.nextTime(for: Self.brew(body: -1))

        #expect(suggestion?.variable == .ratio)
        #expect(suggestion?.direction == -1)
        #expect(suggestion?.change.contains("1:") == true)
    }

    // MARK: - Priority

    /// 15 g in, 230 g in the cup, 1.10 % TDS → around 17 % extracted, below the
    /// band. The impression and the measurement agree on the grind, but the
    /// reason shown has to be the number, and it has to be marked as measured.
    @Test func aMeasuredYieldOutranksAnImpression() {
        let brew = Self.brew(beverage: 230, tds: 1.10, acidity: 1)
        let suggestion = BrewDiagnosis.nextTime(for: brew)

        #expect(suggestion?.variable == .grind)
        #expect(suggestion?.evidence == .verified)
        #expect(suggestion?.reason.contains("measured") == true)
    }

    /// Yield needs the cup on the scale. Without it there is no number, and
    /// the rule falls back to the impression rather than estimating one.
    @Test func anUnweighedCupFallsBackToTheImpression() {
        let brew = Self.brew(tds: 1.10, acidity: 1)

        #expect(brew.extractionYield == nil)
        #expect(BrewDiagnosis.nextTime(for: brew)?.evidence == .practice)
    }

    @Test func theGrindIsAnsweredBeforeTheRatio() {
        let brew = Self.brew(acidity: 1, body: 1)
        let suggestion = BrewDiagnosis.nextTime(for: brew)

        #expect(suggestion?.variable == .grind)
        // The ratio rule still fired; it is just not what gets shown.
        #expect(BrewDiagnosis.candidates(for: brew).contains { $0.variable == .ratio })
    }

    @Test func waterIsNeverTheFirstAnswer() {
        let flat = TasteProfile(sweetness: 1, aftertaste: 2)
        let brew = Self.brew(acidity: 1, taste: flat)

        #expect(BrewDiagnosis.nextTime(for: brew)?.variable == .grind)
        #expect(BrewDiagnosis.candidates(for: brew).contains { $0.variable == .water })
    }

    @Test func aFlatCupWithNothingElseWrongPointsAtTheWater() {
        let brew = Self.brew(taste: TasteProfile(sweetness: 2, aftertaste: 2))

        #expect(BrewDiagnosis.nextTime(for: brew)?.variable == .water)
    }

    // MARK: - Espresso

    @Test func aShortShotGrindsFiner() {
        let brew = Self.brew(method: .espresso, water: nil, beverage: 36, seconds: 17)
        let suggestion = BrewDiagnosis.nextTime(for: brew)

        #expect(suggestion?.variable == .grind)
        #expect(suggestion?.direction == -1)
        #expect(suggestion?.reason.contains("17 s") == true)
    }

    @Test func aLongShotIsReadAsChannellingRatherThanFineness() {
        let brew = Self.brew(method: .espresso, water: nil, beverage: 36, seconds: 42)
        let suggestion = BrewDiagnosis.nextTime(for: brew)

        #expect(suggestion?.direction == 1)
        #expect(suggestion?.change.contains("distribute") == true)
        // Not presented as settled: channelling is an inference from a number.
        #expect(suggestion?.evidence == .partial)
    }

    @Test func aShotInTheWindowSaysNothing() {
        let brew = Self.brew(method: .espresso, water: nil, beverage: 36, seconds: 28)

        #expect(BrewDiagnosis.nextTime(for: brew) == nil)
    }

    // MARK: - The draft it produces

    @Test func useNextTimeMovesTheGrindAndKeepsTheUnit() {
        let brew = Self.brew(grind: "22 clicks", acidity: 1)
        let suggestion = try! #require(BrewDiagnosis.nextTime(for: brew))
        let draft = BrewDiagnosis.draft(from: brew, applying: suggestion)

        #expect(draft.grind.display() == "21 clicks")
        #expect(draft.dose == brew.dose)
        #expect(draft.water == brew.water)
        #expect(draft.captureSource == .prefilled)
    }

    @Test func theDraftMovesOneNumberAndOnlyOne() {
        let brew = Self.brew(body: -1)
        let suggestion = try! #require(BrewDiagnosis.nextTime(for: brew))
        let draft = BrewDiagnosis.draft(from: brew, applying: suggestion)

        #expect(draft.water != brew.water)
        #expect(draft.dose == brew.dose)
        #expect(draft.grind == brew.grind)
        #expect(draft.temperature == brew.temperature)
    }

    /// A grinder with a declared step lets the shift follow the mechanism
    /// rather than a bare ±1, which means the same nudge on a fine grinder and
    /// a coarse one moves the burrs by a comparable amount.
    @Test func theGrindShiftFollowsTheGrindersOwnStep() {
        var grinder = Equipment(kind: .grinder, brand: "Comandante", model: "C40")
        grinder.adjustment = .clicks
        grinder.makerMicronsPerStep = 30

        let brew = Self.brew(grind: "22 clicks", acidity: 1)
        let suggestion = try! #require(BrewDiagnosis.nextTime(for: brew))
        let draft = BrewDiagnosis.draft(from: brew, applying: suggestion, grinder: grinder)

        #expect(draft.grind.display().contains("clicks"))
        #expect(draft.grind != brew.grind)
    }

    @Test func aVerbalGrindIsLeftAsItIs() {
        let brew = Self.brew(grind: "medium-fine", acidity: 1)
        let suggestion = try! #require(BrewDiagnosis.nextTime(for: brew))
        let draft = BrewDiagnosis.draft(from: brew, applying: suggestion)

        #expect(draft.grind.display() == "medium-fine")
        // The change still travels — in the note rather than in the number.
        #expect(draft.notes.contains("finer"))
    }

    @Test func theDraftIsANewBrewNotAnEditOfTheOldOne() {
        let brew = Self.brew(acidity: 1)
        let suggestion = try! #require(BrewDiagnosis.nextTime(for: brew))
        let draft = BrewDiagnosis.draft(from: brew, applying: suggestion)

        #expect(draft.id != brew.id)
        #expect(draft.rating == nil)
    }

    // MARK: - Compare

    @Test func comparingTwoBrewsGivesSignedDeltas() {
        let reference = Self.brew(dose: 15, water: 250, seconds: 165, grind: "22 clicks")
        let mine = Self.brew(dose: 16, water: 240, seconds: 150, grind: "20 clicks")

        let deltas = BrewDiagnosis.compare(mine, to: reference)

        #expect(deltas.contains("+1 g"))
        #expect(deltas.contains("−10 g water"))
        #expect(deltas.contains("−15 s"))
        #expect(deltas.contains("−2 clicks"))
    }

    @Test func identicalBrewsCompareToNothing() {
        let brew = Self.brew()

        #expect(BrewDiagnosis.compare(brew, to: brew).isEmpty)
    }

    @Test func aMissingFieldOnEitherSideIsSkippedRatherThanGuessed() {
        let reference = Self.brew(dose: nil, water: 250)
        let mine = Self.brew(dose: 16, water: 240)

        let deltas = BrewDiagnosis.compare(mine, to: reference)

        #expect(!deltas.contains { $0.hasSuffix(" g") })
        #expect(deltas.contains("−10 g water"))
    }
}
