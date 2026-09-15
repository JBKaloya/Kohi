import Foundation
import Testing

@testable import Kohi

struct GrindConversionTests {
    // MARK: - Fixtures

    private func clicky(
        _ model: String = "Comandante C40",
        ranges: [GrindRange] = [],
        micronsPerStep: Double? = 30
    ) -> Equipment {
        Equipment(
            kind: .grinder,
            brand: "",
            model: model,
            adjustment: .clicks,
            makerMicronsPerStep: micronsPerStep,
            ranges: ranges
        )
    }

    private func stepless(
        _ model: String = "Niche Zero",
        ranges: [GrindRange] = []
    ) -> Equipment {
        Equipment(
            kind: .grinder,
            brand: "",
            model: model,
            adjustment: .stepless,
            ranges: ranges
        )
    }

    private func v60Recipe(low: Double? = nil, high: Double? = nil) -> Recipe {
        Recipe(
            method: .v60,
            dose: 30,
            water: 500,
            grindLabel: "medium-fine",
            grindMicronsLow: low,
            grindMicronsHigh: high
        )
    }

    // MARK: - Within one grinder (annexe G8, stage 1)

    @Test func settingsScaleByTheMakerStepWithinOneGrinder() {
        let grinder = clicky(micronsPerStep: 30)
        #expect(GrindConversion.micronProxy(setting: 22, grinder: grinder) == 660)
        #expect(GrindConversion.micronProxy(setting: 11, grinder: grinder) == 330)
    }

    /// No published step size means no proxy. Inventing one would put a number
    /// with a unit next to a grind, which reads as a measurement.
    @Test func withoutAMakerStepThereIsNoProxy() {
        #expect(GrindConversion.micronProxy(setting: 22, grinder: clicky(micronsPerStep: nil)) == nil)
        #expect(GrindConversion.micronProxy(setting: 22, grinder: stepless()) == nil)
    }

    @Test func aProportionalShiftRoundsToTheNotchOnADetentedGrinder() {
        let grinder = clicky()
        // 22 clicks, 10 % coarser, is 24.2 — but there is no 24.2.
        #expect(GrindConversion.settingShift(from: 22, by: 0.1, grinder: grinder) == 24)
    }

    @Test func aProportionalShiftKeepsItsDecimalOnASteplessGrinder() {
        #expect(GrindConversion.settingShift(from: 4.0, by: 0.1, grinder: stepless()) == 4.4)
    }

    // MARK: - Between grinders (annexe G8, stage 2)

    @Test func mappingRangesPutsTheSameRelativePositionOnTheOtherGrinder() {
        let source = clicky("A", ranges: [GrindRange(method: .v60, low: 20, high: 26)])
        let target = clicky("B", ranges: [GrindRange(method: .v60, low: 80, high: 110)])

        // 23 sits halfway through 20–26, so the answer sits halfway through
        // 80–110.
        let middle = GrindConversion.translate(
            setting: 23, method: .v60, from: source, to: target
        )
        #expect(middle?.setting == 95)
        #expect(middle?.basis == .declaredRanges)
        #expect(middle?.wasClamped == false)

        #expect(GrindConversion.translate(
            setting: 20, method: .v60, from: source, to: target
        )?.setting == 80)
        #expect(GrindConversion.translate(
            setting: 26, method: .v60, from: source, to: target
        )?.setting == 110)
    }

    /// A setting outside the declared range still gets an answer, at the edge,
    /// and the answer admits it was pulled back. Extrapolating past the range
    /// would be arithmetic with nothing behind it.
    @Test func aSettingBeyondTheRangeIsClampedAndSaysSo() {
        let source = clicky("A", ranges: [GrindRange(method: .v60, low: 20, high: 26)])
        let target = clicky("B", ranges: [GrindRange(method: .v60, low: 80, high: 110)])

        let coarse = GrindConversion.translate(
            setting: 40, method: .v60, from: source, to: target
        )
        #expect(coarse?.setting == 110)
        #expect(coarse?.wasClamped == true)
        #expect(coarse?.detailedLabel.contains("edge of your range") == true)

        let fine = GrindConversion.translate(
            setting: 5, method: .v60, from: source, to: target
        )
        #expect(fine?.setting == 80)
        #expect(fine?.wasClamped == true)
    }

    @Test func withNoRangeOnEitherSideThereIsNoConversion() {
        let source = clicky("A")
        let target = clicky("B", ranges: [GrindRange(method: .v60, low: 80, high: 110)])
        #expect(GrindConversion.translate(
            setting: 22, method: .v60, from: source, to: target
        ) == nil)
        #expect(GrindConversion.translate(
            setting: 22, method: .v60, from: target, to: source
        ) == nil)
    }

    /// A range declared for the V60 says nothing about espresso.
    @Test func aRangeForOneMethodDoesNotAnswerForAnother() {
        let source = clicky("A", ranges: [GrindRange(method: .v60, low: 20, high: 26)])
        let target = clicky("B", ranges: [GrindRange(method: .v60, low: 80, high: 110)])
        #expect(GrindConversion.translate(
            setting: 22, method: .espresso, from: source, to: target
        ) == nil)
    }

    /// A single-setting range has no inside, so the target's midpoint is the
    /// only defensible answer.
    @Test func aDegenerateSourceRangeLandsInTheMiddleOfTheTarget() {
        let source = clicky("A", ranges: [GrindRange(method: .v60, low: 22, high: 22)])
        let target = clicky("B", ranges: [GrindRange(method: .v60, low: 80, high: 110)])
        #expect(GrindConversion.translate(
            setting: 22, method: .v60, from: source, to: target
        )?.setting == 95)
    }

    @Test func aSteplessTargetKeepsItsDecimal() {
        let source = clicky("A", ranges: [GrindRange(method: .v60, low: 20, high: 26)])
        let target = stepless("B", ranges: [GrindRange(method: .v60, low: 3, high: 6)])
        // 21 is a sixth of the way in, so 3 + 0.5 = 3.5.
        #expect(GrindConversion.translate(
            setting: 21, method: .v60, from: source, to: target
        )?.setting == 3.5)
    }

    @Test func aDetentedTargetRoundsToTheNearestNotch() {
        let source = stepless("A", ranges: [GrindRange(method: .v60, low: 3, high: 6)])
        let target = clicky("B", ranges: [GrindRange(method: .v60, low: 20, high: 26)])
        // 3.5 of 3–6 is a sixth in: 20 + 1 = 21.
        #expect(GrindConversion.translate(
            setting: 3.5, method: .v60, from: source, to: target
        )?.setting == 21)
    }

    // MARK: - Calibration

    /// A calibration is the only figure in this module that came from coffee,
    /// so it wins over any range arithmetic and stops the hedging.
    @Test func aCalibrationOverridesTheRangeMapping() {
        let source = clicky("A", ranges: [GrindRange(method: .v60, low: 20, high: 26)])
        let target = clicky("B", ranges: [GrindRange(method: .v60, low: 80, high: 110)])
        let calibration = GrindCalibration(
            grinderID: target.id, method: .v60, setting: 97, micronsProxy: 700
        )

        let translation = GrindConversion.translate(
            setting: 23,
            method: .v60,
            from: source,
            to: target,
            calibrations: [calibration]
        )
        #expect(translation?.setting == 97)
        #expect(translation?.basis == .calibration)
        #expect(translation?.basis.isYours == true)
    }

    @Test func aCalibrationForAnotherMethodDoesNotApply() {
        let source = clicky("A", ranges: [GrindRange(method: .v60, low: 20, high: 26)])
        let target = clicky("B", ranges: [GrindRange(method: .v60, low: 80, high: 110)])
        let espresso = GrindCalibration(grinderID: target.id, method: .espresso, setting: 12)

        let translation = GrindConversion.translate(
            setting: 23, method: .v60, from: source, to: target, calibrations: [espresso]
        )
        #expect(translation?.basis == .declaredRanges)
    }

    @Test func aCalibrationForAnotherGrinderDoesNotApply() {
        let source = clicky("A", ranges: [GrindRange(method: .v60, low: 20, high: 26)])
        let target = clicky("B", ranges: [GrindRange(method: .v60, low: 80, high: 110)])
        let elsewhere = GrindCalibration(grinderID: source.id, method: .v60, setting: 22)

        let translation = GrindConversion.translate(
            setting: 23, method: .v60, from: source, to: target, calibrations: [elsewhere]
        )
        #expect(translation?.basis == .declaredRanges)
    }

    // MARK: - Reading a recipe in your terms

    @Test func aRecipeReadsInYourGrinderWhenYouHaveDeclaredARange() {
        let mine = clicky("Mine", ranges: [GrindRange(method: .v60, low: 20, high: 26)])
        let translation = GrindConversion.translate(recipe: v60Recipe(), to: mine)

        // No microns on the recipe: the middle of your range is the answer.
        #expect(translation?.setting == 23)
        #expect(translation?.label == "≈ 23 clicks")
    }

    /// A recipe with a fine grind for its method lands at the fine end of your
    /// range, not in the middle.
    @Test func theRecipesPlaceInItsMethodBandCarriesOver() {
        let mine = clicky("Mine", ranges: [GrindRange(method: .v60, low: 20, high: 26)])

        // The V60 band is 400–700 µm; 400–450 sits near the fine end, so the
        // answer is near 20 rather than at the middle of the range.
        let fine = GrindConversion.translate(recipe: v60Recipe(low: 400, high: 450), to: mine)
        #expect(fine?.setting == 21)
        #expect(fine?.basis == .methodRange)

        let coarse = GrindConversion.translate(recipe: v60Recipe(low: 650, high: 700), to: mine)
        #expect(coarse?.setting == 26)
    }

    @Test func withNoRangeThereIsNothingToReadItIn() {
        #expect(GrindConversion.translate(recipe: v60Recipe(), to: clicky("Mine")) == nil)
    }

    /// The decaf rule from the recipe rules arrives here as a shift, and it
    /// has to land on a real notch.
    @Test func aGrindShiftMovesTheAnswerOnANotchedGrinder() {
        let mine = clicky("Mine", ranges: [GrindRange(method: .v60, low: 20, high: 26)])
        let coarser = GrindConversion.translate(recipe: v60Recipe(), to: mine, shift: 1)
        #expect(coarser?.setting == 24)
    }

    @Test func aGrindShiftOnASteplessGrinderMovesProportionally() {
        let mine = stepless("Mine", ranges: [GrindRange(method: .v60, low: 3, high: 6)])
        let base = GrindConversion.translate(recipe: v60Recipe(), to: mine)
        let coarser = GrindConversion.translate(recipe: v60Recipe(), to: mine, shift: 1)
        #expect(base?.setting == 4.5)
        #expect(coarser?.setting == 4.7)
    }

    @Test func aShiftedAnswerStaysInsideTheRange() {
        let mine = clicky("Mine", ranges: [GrindRange(method: .v60, low: 20, high: 26)])
        let translation = GrindConversion.translate(
            recipe: v60Recipe(low: 650, high: 700), to: mine, shift: 3
        )
        #expect(translation?.setting == 26)
        #expect(translation?.wasClamped == true)
    }

    // MARK: - Honesty of the label

    /// The approximation sign is not decoration. Every number this module
    /// produces is a mapping, and none of them is a measurement.
    @Test func everyLabelIsApproximate() {
        let mine = clicky("Mine", ranges: [GrindRange(method: .v60, low: 20, high: 26)])
        let fromRange = GrindConversion.translate(recipe: v60Recipe(), to: mine)
        #expect(fromRange?.label.hasPrefix("≈") == true)

        let calibrated = GrindConversion.translate(
            recipe: v60Recipe(),
            to: mine,
            calibrations: [GrindCalibration(grinderID: mine.id, method: .v60, setting: 22)]
        )
        #expect(calibrated?.label.hasPrefix("≈") == true)
    }

    /// A number from a published range and a number from your own calibration
    /// have to be distinguishable at a glance, or the distinction is worthless.
    @Test func theBasisIsAlwaysStated() {
        for basis in [
            GrindTranslation.Basis.calibration,
            .declaredRanges,
            .methodRange,
            .makerStep,
        ] {
            let translation = GrindTranslation(
                setting: 22, adjustment: .clicks, basis: basis, wasClamped: false
            )
            #expect(!translation.basis.label.isEmpty)
            #expect(translation.detailedLabel.contains(basis.label))
        }
        #expect(GrindTranslation.Basis.calibration.isYours)
        #expect(!GrindTranslation.Basis.methodRange.isYours)
    }

    @Test func theLabelUsesTheGrindersOwnVocabulary() {
        #expect(GrindTranslation(setting: 22, adjustment: .clicks, basis: .calibration, wasClamped: false)
            .label == "≈ 22 clicks")
        #expect(GrindTranslation(setting: 4.5, adjustment: .dial, basis: .calibration, wasClamped: false)
            .label == "≈ 4.5 on the dial")
        #expect(GrindTranslation(setting: 4.5, adjustment: .stepless, basis: .calibration, wasClamped: false)
            .label == "≈ 4.5")
    }

    // MARK: - Falling back to the reference base

    /// With nothing declared, the reference base's hint is used — and the
    /// basis says "from range" so the difference stays visible.
    @Test func theReferenceHintFillsInForAnUndeclaredRange() throws {
        let reference = try #require(ReferenceBase.grinder(id: "1zpresso-j-ultra"))
        let grinder = Equipment(reference: reference)

        // The seeded base carries no unverified ranges, so there is nothing to
        // fall back to — which is the gate working, not a bug.
        #expect(GrindConversion.range(for: .v60, on: grinder) == nil)

        var declared = grinder
        declared.ranges = [GrindRange(method: .v60, low: 20, high: 26)]
        #expect(GrindConversion.range(for: .v60, on: declared)?.low == 20)
    }

    @Test func forYourGrinderHasThreeStates() {
        let recipe = v60Recipe()
        #expect(GrindConversion.forYourGrinder(recipe: recipe, grinder: nil) == .addGrinder)

        let unnamed = clicky("Comandante C40")
        #expect(GrindConversion.forYourGrinder(recipe: recipe, grinder: unnamed) == .noRange)

        let withRange = Equipment(
            kind: .grinder,
            brand: "Comandante",
            model: "C40 MK4",
            adjustment: .clicks,
            ranges: [GrindRange(method: .v60, low: 20, high: 26)]
        )
        let translated = GrindConversion.forYourGrinder(recipe: recipe, grinder: withRange)
        guard case .translated(_, let name) = translated else {
            Issue.record("expected a click translation")
            return
        }
        #expect(name == "Comandante")
        #expect(translated.line.hasPrefix("≈"))
        #expect(translated.line.contains("Comandante"))
    }

    private func emptyStore() -> SetupStore {
        SetupStore(files: JSONDocumentStore(filename: "setup-grind-\(UUID().uuidString).json"))
    }

    @Test func oneCalibrationPerGrinderAndMethod() {
        let store = emptyStore()
        let grinder = clicky()
        store.add(grinder)

        store.record(GrindCalibration(grinderID: grinder.id, method: .v60, setting: 22))
        store.record(GrindCalibration(grinderID: grinder.id, method: .v60, setting: 24))
        store.record(GrindCalibration(grinderID: grinder.id, method: .espresso, setting: 10))

        #expect(store.calibrations.count == 2)
        #expect(store.calibration(grinderID: grinder.id, method: .v60)?.setting == 24)
        #expect(store.calibrations(grinderID: grinder.id).count == 2)
    }

    @Test func calibrationSummaryDropsWhatYouDidNotClaim() {
        let bare = GrindCalibration(grinderID: UUID(), method: .v60, setting: 22)
        #expect(bare.summary == "22")

        let measured = GrindCalibration(
            grinderID: UUID(), method: .v60, setting: 22, micronsProxy: 700
        )
        #expect(measured.summary == "22 ≈ 700 µm")
    }

    @Test func calibrationSurvivesTheRowRoundTrip() {
        let original = GrindCalibration(
            grinderID: UUID(),
            method: .aeropress,
            setting: 18,
            micronsProxy: 620,
            note: "matched the shop's grind",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let restored = GrindCalibrationRow(calibration: original, userID: UUID()).toCalibration()
        #expect(restored == original)
    }

    @Test func calibrationPropertiesAreAllAccountedFor() {
        let calibration = GrindCalibration(
            grinderID: UUID(), method: .v60, setting: 22, micronsProxy: 700, note: "x"
        )
        let mapped: Set<String> = [
            "id", "grinderID", "method", "setting", "micronsProxy", "note",
            "createdAt", "updatedAt",
        ]
        let actual = Set(Mirror(reflecting: calibration).children.compactMap(\.label))
        #expect(actual.subtracting(mapped).isEmpty, "unmapped GrindCalibration properties")
    }
}
