import Foundation
import Testing
@testable import Kohi

/// Parts of the water, read off the cumulative masses and written back to
/// them. The grams stay the record; the parts never drift from them.
struct PourSplitTests {
    /// 15 g at 1:15: bloom 30, then to 135, then to 225.
    private func recipe() -> Recipe {
        Recipe(name: "Split", method: .v60, dose: 15, water: 225, steps: [
            RecipeStep(at: 0, action: .rinse, targetMass: 150),
            RecipeStep(at: 0, action: .bloom, targetMass: 30, untilSeconds: 45),
            RecipeStep(at: 45, action: .pour, targetMass: 135, untilSeconds: 75),
            RecipeStep(at: 75, action: .wait, untilSeconds: 100),
            RecipeStep(at: 100, action: .pour, targetMass: 225, untilSeconds: 130),
            RecipeStep(at: 180, action: .wait, note: "Drawdown"),
        ])
    }

    private func masses(_ steps: [RecipeStep]) -> [Double] {
        steps.filter { PourSplit.carriesWater($0.action) }.compactMap(\.targetMass)
    }

    @Test func theRatioGivesTheWater() {
        #expect(PourSplit.water(dose: 15, ratio: 15) == 225)
        #expect(PourSplit.water(dose: 13.3, ratio: 15) == 199.5)
        #expect(PourSplit.water(dose: 0, ratio: 15) == nil)
        #expect(PourSplit.ratio(dose: 15, water: 250) == 16.7)
    }

    @Test func aBloomCountedIsTheFirstService() throws {
        let split = try #require(PourSplit.split(of: recipe(), countsBloom: true))
        #expect(split.services.map(\.grams) == [30, 105, 90])
        #expect(split.percents == [13, 47, 40])
        #expect(split.bloom == nil)
        #expect(split.base == 225)
    }

    @Test func aBloomLeftOutSharesWhatIsLeft() throws {
        let split = try #require(PourSplit.split(of: recipe(), countsBloom: false))
        #expect(split.services.map(\.grams) == [105, 90])
        #expect(split.base == 195)
        #expect(split.bloom?.grams == 30)
        #expect(split.percents.reduce(0, +) == 100)
    }

    @Test func theRinseIsNeverAService() throws {
        let split = try #require(PourSplit.split(of: recipe(), countsBloom: true))
        #expect(!split.services.contains { $0.action == .rinse })
        let steps = PourSplit.applying(shares: [0.1, 0.6, 0.3], to: recipe().steps, total: 225, countsBloom: true)
        #expect(steps.first?.targetMass == 150)
    }

    @Test func gramsToPartsToGramsIsTheSameSequence() throws {
        let original = recipe()
        let split = try #require(PourSplit.split(of: original, countsBloom: true))
        let back = PourSplit.applying(shares: split.services.map(\.share), to: original.steps, total: 225, countsBloom: true)
        #expect(back == original.steps)
    }

    @Test func partsWriteMassesThatEndOnTheTotal() {
        let steps = PourSplit.applying(shares: [0.1, 0.65, 0.25], to: recipe().steps, total: 225, countsBloom: true)
        #expect(masses(steps) == [22.5, 169, 225])
        let times = steps.map(\.at)
        #expect(times == recipe().steps.map(\.at))
    }

    @Test func aBloomLeftOutKeepsItsGrams() {
        let steps = PourSplit.applying(shares: [0.7, 0.3], to: recipe().steps, total: 225, countsBloom: false)
        #expect(masses(steps) == [30, 166.5, 225])
    }

    @Test func oneChangedPartMovesOnlyTheRest() {
        let next = PourSplit.setting(share: 0.65, at: 1, in: [0.1, 0.5, 0.4])
        #expect(next[0] == 0.1)
        #expect(abs(next[1] - 0.65) < 0.0001)
        #expect(abs(next[2] - 0.25) < 0.0001)
        let capped = PourSplit.setting(share: 0.99, at: 1, in: [0.1, 0.5, 0.4])
        #expect(abs(capped[1] - 0.9) < 0.0001)
        #expect(capped[2] == 0)
        #expect(PourSplit.setting(share: 0.5, at: 2, in: [0.1, 0.5, 0.4]) == [0.1, 0.5, 0.4])
    }

    @Test func percentsAlwaysAddUpToAHundred() {
        let third = 1.0 / 3
        #expect(PourSplit.percents(of: [third, third, third]) == [33, 33, 34])
        #expect(PourSplit.percents(of: [0.125, 0.475, 0.4]).reduce(0, +) == 100)
    }

    @Test func aRescaleKeepsTheParts() throws {
        let original = try #require(PourSplit.split(of: recipe(), countsBloom: true))
        var bigger = recipe()
        bigger.steps = RecipeScaling.scalingSteps(bigger.steps, by: 400.0 / 225)
        bigger.water = 400
        let after = try #require(PourSplit.split(of: bigger, countsBloom: true))
        for (a, b) in zip(original.services, after.services) {
            #expect(abs(a.share - b.share) * 400 <= 0.5)
        }
        let resized = try #require(RecipeScaling.rescaled(recipe(), toLiquid: 300))
        let viaHowMuch = try #require(PourSplit.split(of: resized, countsBloom: true))
        #expect(viaHowMuch.percents == original.percents)
        #expect(resized.steps.first?.targetMass == 150)
    }

    @Test func aNewSequenceHasTheServicesAskedFor() throws {
        for count in PourSplit.serviceRange {
            let steps = PourSplit.steps(dose: 15, water: 225, count: count, countsBloom: true, targetTime: 180)
            let split = try #require(PourSplit.split(steps: steps, total: 225, countsBloom: true))
            #expect(split.services.count == count)
            #expect(masses(steps).last == 225)
            #expect(steps.first?.action == .bloom)
            #expect(steps.map(\.at) == steps.map(\.at).sorted())
        }
        let leftOut = PourSplit.steps(dose: 15, water: 225, count: 2, countsBloom: false, targetTime: nil)
        #expect(PourSplit.split(steps: leftOut, total: 225, countsBloom: false)?.services.count == 2)
    }

    @Test func aNewSequenceKeepsTheRinse() {
        let steps = PourSplit.steps(dose: 15, water: 225, count: 3, countsBloom: true, targetTime: nil, keeping: recipe().steps)
        #expect(steps.first?.action == .rinse)
        #expect(steps.first?.targetMass == 150)
    }

    @Test func espressoAndSinglePoursAreNotSplit() {
        let espresso = Recipe(method: .espresso, dose: 18, beverage: 36, steps: [
            RecipeStep(at: 0, action: .preInfusion),
            RecipeStep(at: 8, action: .shot, targetMass: 36),
        ])
        #expect(!PourSplit.isSplittable(espresso))
        let single = Recipe(method: .frenchPress, dose: 15, water: 250, steps: [
            RecipeStep(at: 0, action: .pour, targetMass: 250),
        ])
        #expect(!PourSplit.isSplittable(single))
        #expect(PourSplit.isSplittable(recipe()))
    }

    @Test func noPartIsReadAsATaste() throws {
        let text = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Process/PourSplit.swift"))
        for word in ["acid", "sweet", "body", "bright", "bitter"] {
            #expect(!text.lowercased().contains(word), "\(word) in PourSplit")
        }
    }
}
