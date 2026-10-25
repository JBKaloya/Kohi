import Foundation
import Testing
@testable import Kohi

/// Note first, improve after: the wishes, the extraction reading and the
/// rules that use them.
struct ExtractionReadingTests {
    static let roasted = Date(timeIntervalSince1970: 1_790_000_000)

    static func card(process: String = "Washed", roast: RoastLevel? = .medium) -> CoffeeCard {
        CoffeeCard(
            name: "Chelbesa",
            roaster: "Dak",
            country: "Ethiopia",
            region: "Gedeb",
            altitude: "2100 m",
            process: process,
            roastLevel: roast,
            roastedOn: roasted
        )
    }

    /// Bloom 45 g at 0:30, then 150 g at 0:50: 150 g in 50 s is 3 g/s.
    static func brew(
        steps: [BrewStep] = [
            BrewStep(index: 0, action: .bloom, at: 30, mass: 45),
            BrewStep(index: 1, action: .pour, at: 50, mass: 150),
            BrewStep(index: 2, action: .pour, at: 120, mass: 250),
        ],
        source: ActualSource = .timer,
        bitterness: Int = 0
    ) -> Brew {
        var brew = Brew(
            date: roasted.addingTimeInterval(12 * 86_400),
            method: .v60,
            dose: 15,
            water: 250,
            seconds: 180,
            grind: GrindSetting(raw: "22 clicks"),
            temperature: 93,
            steps: steps,
            actualSource: source,
            rating: 3,
            bitterness: bitterness
        )
        brew.refreshPourRates()
        return brew
    }

    @Test func theFirstMinuteIsTheWaterInByTheLastStepBeforeSixtySeconds() {
        let reading = ExtractionReading.read(Self.brew(), card: Self.card())
        #expect(reading.firstMinuteFlow == 3)
        #expect(reading.agitationBand == .low)
        #expect(reading.bloomRatio == 3)
        #expect(reading.pours == 3)
    }

    @Test func aFastStartIsAHighBand() {
        let steps = [
            BrewStep(index: 0, action: .bloom, at: 10, mass: 60),
            BrewStep(index: 1, action: .pour, at: 40, mass: 250),
        ]
        let reading = ExtractionReading.read(Self.brew(steps: steps), card: Self.card())
        #expect(reading.firstMinuteFlow.map { ($0 * 10).rounded() / 10 } == 6.3)
        #expect(reading.agitationBand == .high)
    }

    @Test func aDefaultSequenceHasNoFirstMinute() {
        let reading = ExtractionReading.read(Self.brew(source: .none), card: Self.card())
        #expect(reading.firstMinuteFlow == nil)
        #expect(reading.agitationBand == nil)
        #expect(reading.pours == 0)
    }

    @Test func restDaysCountFromTheRoast() {
        let reading = ExtractionReading.read(Self.brew(), card: Self.card())
        #expect(reading.restDays == 12)
        #expect(reading.isWashed)
        #expect(reading.isMediumOrDarker)
        #expect(reading.origin == "Gedeb, Ethiopia")
        #expect(ExtractionReading.read(Self.brew(), card: nil).restDays == nil)
    }

    @Test func coffeeFactorsReadTheCard() {
        let rows = ExtractionReading.read(Self.brew(), card: Self.card()).coffeeFactors
        #expect(rows.map(\.label) == ["Process", "Roast", "Rest", "Origin"])
    }
}

struct FirstMinuteRuleTests {
    private let fast = [
        BrewStep(index: 0, action: .bloom, at: 10, mass: 60),
        BrewStep(index: 1, action: .pour, at: 40, mass: 250),
    ]

    @Test func aWashedMediumBitterCupAfterAFastStartSlowsTheStart() {
        let brew = ExtractionReadingTests.brew(steps: fast, bitterness: 1)
        let move = BrewDiagnosis.firstMinuteMove(for: brew, card: ExtractionReadingTests.card())
        #expect(move?.change == "pour slower in the first minute, same grind")
        #expect(move?.variable == .agitation)
        #expect(move?.evidence == .practice)
        #expect(move?.reason.contains("washed") == true)
        #expect(move?.reason.contains("g/s") == true)
        let candidates = BrewDiagnosis.candidates(for: brew, card: ExtractionReadingTests.card())
        #expect(candidates.first?.change == "pour slower in the first minute, same grind")
    }

    @Test func gentlePoursDoNotFireIt() {
        let brew = ExtractionReadingTests.brew(bitterness: 1)
        #expect(BrewDiagnosis.firstMinuteMove(for: brew, card: ExtractionReadingTests.card()) == nil)
    }

    @Test func aNaturalLightRoastDoesNotFireIt() {
        let brew = ExtractionReadingTests.brew(steps: fast, bitterness: 1)
        let card = ExtractionReadingTests.card(process: "Natural", roast: .light)
        #expect(BrewDiagnosis.firstMinuteMove(for: brew, card: card) == nil)
    }

    @Test func notBitterDoesNotFireIt() {
        let brew = ExtractionReadingTests.brew(steps: fast)
        #expect(BrewDiagnosis.firstMinuteMove(for: brew, card: ExtractionReadingTests.card()) == nil)
    }
}

struct BrewWishTests {
    /// A brew saved before the wishes existed: "too acidic" reads as "less
    /// acidity", and complexity is unanswered.
    @Test func aLegacyBrewReadsAsWishes() throws {
        let json = #"{"id":"AAAAAAAA-0000-0000-0000-000000000009","acidity":1,"bitterness":-1,"body":0,"notes":""}"#
        let brew = try JSONDecoder().decode(Brew.self, from: Data(json.utf8))
        #expect(brew.complexity == nil)
        #expect(BrewWish.wish(.acidity, of: brew) == -1)
        #expect(BrewWish.caption(.acidity, wish: -1) == "less acidity")
        #expect(BrewWish.wish(.bitterness, of: brew) == 1)
        #expect(BrewWish.caption(.bitterness, wish: 1) == "more bitterness")
        #expect(BrewWish.wish(.body, of: brew) == 0)
        #expect(BrewWish.caption(.body, wish: 0) == "as is")
        #expect(BrewWish.wish(.complexity, of: brew) == 0)
    }

    @Test func settingAWishStoresTheObservationAndComplexityAsIs() {
        var brew = Brew()
        BrewWish.set(.acidity, wish: -1, on: &brew)
        #expect(brew.acidity == 1)
        BrewWish.set(.complexity, wish: 1, on: &brew)
        #expect(brew.complexity == 1)
        #expect(BrewWish.caption(.complexity, wish: 1) == "more complexity")
        BrewWish.set(.complexity, wish: 0, on: &brew)
        #expect(brew.complexity == nil)
    }

    @Test func aNoteThatLacksComplexityPrefillsTheWishNotAMove() {
        let intents = TastingIntent.extract("trop peu de complexité")
        #expect(TastingIntent.moves(of: intents).isEmpty)
        var brew = Brew()
        TastingIntent.prefill(&brew, from: intents)
        #expect(brew.complexity == 1)

        var answered = Brew(complexity: -1)
        TastingIntent.prefill(&answered, from: intents)
        #expect(answered.complexity == -1)
    }
}

struct ComplexityRuleTests {
    @Test func moreComplexityWithNothingToStandOnSaysNothing() {
        let brew = Brew(method: .v60, dose: 15, water: 250, temperature: 93, rating: 3, complexity: 1)
        #expect(BrewDiagnosis.complexityMoves(for: brew, card: nil).isEmpty)
        #expect(SuggestedCorrection.fallback(from: brew) == nil)
    }

    @Test func aLowMeasuredExtractionGrindsFiner() {
        let brew = Brew(method: .v60, dose: 15, water: 250, beverage: 215, tds: 1.15, rating: 3, complexity: 1)
        let moves = BrewDiagnosis.complexityMoves(for: brew, card: nil)
        #expect(moves.first?.change == "grind finer")
        #expect(moves.first?.evidence == .verified)
    }

    @Test func lowClarityLengthensTheRatio() {
        let brew = Brew(method: .v60, dose: 15, water: 250, taste: TasteProfile(clarity: 3), rating: 3, complexity: 1)
        let moves = BrewDiagnosis.complexityMoves(for: brew, card: nil)
        #expect(moves.first?.variable == .ratio)
    }

    @Test func aBetterPastBrewOfTheSameCoffeePointsAtItsTemperature() {
        let best = Brew(method: .v60, dose: 15, water: 250, temperature: 96, rating: 5)
        let brew = Brew(method: .v60, dose: 15, water: 250, temperature: 92, rating: 3, complexity: 1)
        let card = CoffeeCard(name: "Chelbesa", brews: [brew, best])
        let moves = BrewDiagnosis.complexityMoves(for: brew, card: card)
        #expect(moves.first?.variable == .temperature)
        #expect(moves.first?.direction == 1)
    }

    @Test func noWishNoMove() {
        let brew = Brew(method: .v60, dose: 15, water: 250, beverage: 215, tds: 1.15, rating: 3)
        #expect(BrewDiagnosis.complexityMoves(for: brew, card: nil).isEmpty)
    }
}

/// The rules did not move for anyone who has not used the new rows.
struct NoteThenImproveGoldenTests {
    private static var brews: [Brew] {
        [
            BrewDiagnosisTests.brew(),
            BrewDiagnosisTests.brew(acidity: 1),
            BrewDiagnosisTests.brew(bitterness: 1),
            BrewDiagnosisTests.brew(body: -1),
            BrewDiagnosisTests.brew(body: 1),
            BrewDiagnosisTests.brew(acidity: 1, bitterness: 1),
            BrewDiagnosisTests.brew(tds: 1.2, acidity: 1),
            BrewDiagnosisTests.brew(method: .espresso, dose: 18, water: nil, beverage: 36, seconds: 18),
        ]
    }

    @Test func withoutComplexityOrAFirstMinuteNothingChanges() {
        let card = ExtractionReadingTests.card()
        for brew in Self.brews {
            #expect(brew.complexity == nil)
            let before = BrewDiagnosis.candidates(for: brew)
            let after = BrewDiagnosis.candidates(for: brew, card: card)
            #expect(before == after)
            let fallbackBefore = SuggestedCorrection.fallback(from: brew)
            let fallbackAfter = SuggestedCorrection.fallback(from: brew, card: card)
            #expect(fallbackBefore?.moves.map(\.change) == fallbackAfter?.moves.map(\.change))
            #expect(fallbackBefore?.reading == fallbackAfter?.reading)
        }
    }

    @Test func theKnownAnswersHold() {
        #expect(BrewDiagnosis.nextTime(for: BrewDiagnosisTests.brew()) == nil)
        #expect(BrewDiagnosis.nextTime(for: BrewDiagnosisTests.brew(acidity: 1))?.change == "grind finer")
        #expect(BrewDiagnosis.nextTime(for: BrewDiagnosisTests.brew(bitterness: 1))?.change == "grind coarser")
    }

    @Test func theFallbackSaysWhyAndHowSure() {
        let brew = BrewDiagnosisTests.brew(acidity: 1)
        let move = SuggestedCorrection.fallback(from: brew, card: ExtractionReadingTests.card())?.moves.first
        #expect(move?.confidence == "medium")
        #expect(move?.because?.first == "less acidity")
    }
}

/// Coffee-shop tastings never grew a correction: that lives after a home brew.
struct TastingsStayCorrectionFreeTests {
    @Test func nothingUnderTastingsTalksAboutCorrectionOrComplexity() throws {
        let folder = BrewJourneySupport.kohiRoot().appending(path: "Tastings")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        let banned = ["correction", "complexity", "improveTitle", "BrewReadView", "BrewWish", "CorrectionAxis"]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for word in banned {
                let found = text.range(of: "\\b\(word)", options: [.regularExpression, .caseInsensitive]) != nil
                #expect(!found, "\(file.lastPathComponent) mentions \(word)")
            }
        }
    }
}
