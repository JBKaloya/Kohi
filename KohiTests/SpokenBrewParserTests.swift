import Foundation
import Testing

@testable import Kohi

/// The small grammar behind dictation. It runs before any model is asked and
/// it is the whole feature when the experimental layer is off, so it is pinned
/// hard: what it understands, what it refuses to guess, and where the rest of
/// the sentence ends up.
struct SpokenBrewParserTests {
    // MARK: - The everyday sentence

    @Test func theWholeSentenceLandsInFields() {
        let result = SpokenBrewParser.parse(
            "18 grams of coffee, 250 of water, 2:45, four stars"
        )

        #expect(result.dose == 18)
        #expect(result.water == 250)
        #expect(result.seconds == 165)
        #expect(result.rating == 4)
        #expect(result.leftover.isEmpty)
    }

    @Test func spokenNumbersReadTheSameAsDigits() {
        let spoken = SpokenBrewParser.parse(
            "eighteen grams of coffee, two hundred and fifty of water"
        )
        let typed = SpokenBrewParser.parse("18 grams of coffee, 250 of water")

        #expect(spoken.dose == typed.dose)
        #expect(spoken.water == typed.water)
    }

    @Test func aSpokenHundredFoldsIntoOneNumber() {
        #expect(SpokenBrewParser.normalize("two hundred fifty") == "250")
        #expect(SpokenBrewParser.normalize("three hundred") == "300")
    }

    // MARK: - Time

    @Test func aClockTimeIsReadAsMinutesAndSeconds() {
        #expect(SpokenBrewParser.parse("2:45").seconds == 165)
    }

    @Test func aDurationInWordsWorksToo() {
        #expect(SpokenBrewParser.parse("165 seconds").seconds == 165)
        #expect(SpokenBrewParser.parse("3 minutes").seconds == 180)
    }

    /// The form the hint in the brew sheet promises, so it had better work.
    @Test func aTimeReadOutLikeAClockIsStillATime() {
        #expect(SpokenBrewParser.parse("two forty-five").seconds == 165)
        #expect(SpokenBrewParser.parse("three thirty").seconds == 210)
        #expect(SpokenBrewParser.parse("one twenty five").seconds == 85)
    }

    /// "two fifty of water" is 250 g, not 2:50 — the noun after the words is
    /// what tells the two apart, and getting it wrong would fill two fields.
    @Test func aQuantitySaidTheSameWayStaysAQuantity() {
        let result = SpokenBrewParser.parse("18 in, two fifty of water")

        #expect(result.water == 250)
        #expect(result.seconds == nil)
        #expect(result.dose == 18)
    }

    /// Tens and units said as two words are one number wherever they land.
    @Test func aNumberSaidInTwoWordsIsOneNumber() {
        #expect(SpokenBrewParser.parse("forty five seconds").seconds == 45)
        #expect(SpokenBrewParser.parse("grind twenty two clicks").grind == "22 clicks")
    }

    /// The trap this grammar exists to avoid: "2:45" must not be read as a
    /// two and a forty-five looking for units.
    @Test func aTimeIsNotMistakenForTwoNumbers() {
        let result = SpokenBrewParser.parse("18 in, 2:45")

        #expect(result.seconds == 165)
        #expect(result.dose == 18)
        #expect(result.water == nil)
    }

    // MARK: - Which number is which

    @Test func doseAndWaterAreToldApartByTheirNoun() {
        let result = SpokenBrewParser.parse("water 300, dose 20")

        #expect(result.dose == 20)
        #expect(result.water == 300)
    }

    @Test func anEspressoSaysWhatCameOut() {
        let result = SpokenBrewParser.parse("espresso, 18 in, 36 out, 28 seconds")

        #expect(result.method == .espresso)
        #expect(result.dose == 18)
        #expect(result.beverage == 36)
        #expect(result.seconds == 28)
    }

    @Test func aBareNumberIsNotAssignedToAnything() {
        let result = SpokenBrewParser.parse("that one was 40")

        #expect(result.dose == nil)
        #expect(result.water == nil)
        #expect(result.temperature == nil)
    }

    @Test func anImpossibleTemperatureIsRefused() {
        #expect(SpokenBrewParser.parse("water at 940 degrees").temperature == nil)
        #expect(SpokenBrewParser.parse("94 degrees").temperature == 94)
    }

    // MARK: - Grind and method

    @Test func aClickCountIsAGrindSetting() {
        #expect(SpokenBrewParser.parse("22 clicks").grind == "22 clicks")
    }

    @Test func aWordyGrindIsKeptInItsOwnWords() {
        #expect(SpokenBrewParser.parse("medium fine").grind == "medium fine")
    }

    @Test func aBareGrindNumberGetsItsUnitBack() {
        #expect(SpokenBrewParser.parse("grind 3.5").grind == "3.5 clicks")
    }

    @Test func methodsAreRecognisedByTheirCommonNames() {
        #expect(SpokenBrewParser.parse("a v60 this morning").method == .v60)
        #expect(SpokenBrewParser.parse("pulled a shot").method == .espresso)
        #expect(SpokenBrewParser.parse("french press").method == .frenchPress)
    }

    // MARK: - What it does not understand

    /// The rule that makes dictation trustworthy: nothing is dropped. What
    /// found no field is kept verbatim and lands in Notes.
    @Test func whatIsNotUnderstoodSurvivesAsText() {
        let result = SpokenBrewParser.parse(
            "18 in, 250 of water, reminded me of the last bag"
        )

        #expect(result.dose == 18)
        #expect(result.leftover.contains("reminded"))
        #expect(result.leftover.contains("last bag"))
    }

    /// A tasting word is a field, not a note. "Burnt toast" leaves as a
    /// flavour and does not turn up in Notes as well.
    @Test func aTastingWordIsLiftedOutOfTheSentence() {
        let result = SpokenBrewParser.parse("tasted like burnt toast")

        #expect(result.flavors.contains("Burnt"))
        #expect(!result.leftover.contains("burnt"))
    }

    @Test func fillerWordsAreNotNotes() {
        let result = SpokenBrewParser.parse("18 grams of coffee and 250 of water")

        #expect(result.leftover.isEmpty)
    }

    @Test func aSentenceWithNothingInItIsEmpty() {
        let result = SpokenBrewParser.parse("um okay so")

        #expect(result.isEmpty)
        #expect(result.confidence < 0.5)
    }

    /// Confidence is what decides whether the model is asked at all, so the
    /// two ends of the scale are pinned.
    @Test func aFullyUnderstoodSentenceIsConfident() {
        let result = SpokenBrewParser.parse("18 grams of coffee, 250 of water, 2:45")

        #expect(result.confidence > 0.5)
    }

    @Test func aRamblingSentenceIsNot() {
        let result = SpokenBrewParser.parse(
            "I think this one was better than the last one but I am not sure why"
        )

        #expect(result.confidence < 0.5)
    }

    // MARK: - Applying it

    @Test func dictationFillsOnlyWhatIsEmpty() {
        var brew = Brew(method: .v60, dose: 15, grind: "20 clicks")
        let result = SpokenBrewParser.parse("18 grams of coffee, 250 of water, 22 clicks")

        SpokenBrewParser.apply(result, to: &brew)

        // Typed by hand, so left alone.
        #expect(brew.dose == 15)
        #expect(brew.grind.display() == "20 clicks")
        // Empty, so filled.
        #expect(brew.water == 250)
    }

    @Test func applyingMarksHowTheBrewWasCaptured() {
        var brew = Brew()
        SpokenBrewParser.apply(SpokenBrewParser.parse("250 of water"), to: &brew)

        #expect(brew.captureSource == .dictated)
    }

    @Test func theLeftoverIsAppendedToExistingNotes() {
        var brew = Brew(notes: "Second attempt.")
        SpokenBrewParser.apply(SpokenBrewParser.parse("reminded me of the last bag"), to: &brew)

        #expect(brew.notes.contains("Second attempt."))
        #expect(brew.notes.contains("last bag"))
    }

    @Test func flavoursFromTheWheelAreRecognised() {
        let result = SpokenBrewParser.parse("lots of jasmine and some peach")

        #expect(result.flavors.contains("Jasmine"))
        #expect(result.flavors.contains("Peach"))
    }

    @Test func aNumericAxisIsRead() {
        let result = SpokenBrewParser.parse("acidity 7, high sweetness")
        #expect(result.taste[.acidity] == 7)
        #expect(result.taste[.sweetness] == 7)
    }

    @Test func aSwirlIsAgitation() {
        #expect(SpokenBrewParser.parse("swirled at the end").agitation == .swirl)
    }

    @Test func cleanSetsClarity() {
        #expect(SpokenBrewParser.parse("clean cup").taste[.clarity] == 8)
    }

    @Test func bloomAndPourMassesAreStepsNotWater() {
        let result = SpokenBrewParser.parse("bloom 50 then pour to 150")
        #expect(result.spokenSteps.count == 2)
        #expect(result.spokenSteps[0].action == .bloom)
        #expect(result.spokenSteps[0].mass == 50)
        #expect(result.spokenSteps[1].action == .pour)
        #expect(result.spokenSteps[1].mass == 150)
        #expect(result.water == nil)
    }

    @Test func aFrenchPourIsAStep() {
        let result = SpokenBrewParser.parse("verse à 150")
        #expect(result.spokenSteps.contains { $0.action == .pour && $0.mass == 150 })
    }

    @Test func theLexiconRestoresCoffeeSpellings() {
        let rewritten = SpokenLexicon.rewrite(
            "bloom on the v 60 then aero press",
            terms: SpokenLexicon.coffeeWords
        )
        #expect(rewritten.contains("V60"))
        #expect(rewritten.contains("AeroPress"))
        #expect(!rewritten.localizedCaseInsensitiveContains("v 60"))
        let cafec = SpokenLexicon.rewrite("cafec abaca", terms: ["Cafec"])
        #expect(cafec.contains("Cafec"))
    }
}
