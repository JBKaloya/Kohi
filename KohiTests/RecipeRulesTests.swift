import Foundation
import Testing

@testable import Kohi

struct RecipeRulesTests {
    // MARK: - Fixtures

    private func card(
        name: String = "Ethiopia Chelbesa",
        roast: RoastLevel? = .medium,
        process: String = "Washed",
        decaf: Bool = false,
        roastedOn: Date? = nil,
        brews: [Brew] = [],
        printed: Brew? = nil
    ) -> CoffeeCard {
        var card = CoffeeCard(name: name)
        card.roastLevel = roast
        card.process = process
        card.isDecaf = decaf
        card.roastedOn = roastedOn
        card.brews = brews
        card.recipeSuggestion = printed
        return card
    }

    private func v60() -> Recipe {
        Recipe(
            name: "V60",
            method: .v60,
            dose: 30,
            water: 500,
            temperature: 99,
            seconds: 210,
            grindLabel: "medium-fine",
            steps: [
                RecipeStep(at: 0, action: .bloom, targetMass: 60),
                RecipeStep(at: 45, action: .pour, targetMass: 300, untilSeconds: 75),
                RecipeStep(at: 75, action: .pour, targetMass: 500),
            ],
            source: .reference,
            attribution: "James Hoffmann"
        )
    }

    // MARK: - Temperature (annexe G3)

    @Test func temperatureFollowsTheRoastLevel() {
        #expect(RecipeRules.temperature(for: .light, method: .v60) == 94...100)
        #expect(RecipeRules.temperature(for: .dark, method: .v60) == 85...90)
        #expect(RecipeRules.temperature(for: .light, method: .espresso) == 94...96)
        #expect(RecipeRules.temperature(for: .dark, method: .espresso) == 88...92)
    }

    /// An unknown roast level is treated as medium rather than skipped: a
    /// number has to go in the kettle either way, and the middle is the least
    /// wrong guess.
    @Test func anUnknownRoastLevelLandsInTheMiddle() {
        #expect(RecipeRules.temperature(for: nil, method: .v60)
            == RecipeRules.temperature(for: .medium, method: .v60))
    }

    @Test func theSuggestedTemperatureIsAWholeDegree() {
        let suggested = RecipeRules.suggestedTemperature(for: .light, method: .v60)
        #expect(suggested == 97)
        #expect(suggested == suggested.rounded())
    }

    // MARK: - Adjustment rules

    @Test func aLightRoastGetsHotterWaterAndALongerRatio() {
        let suggestion = RecipeRules.adjust(v60(), for: card(roast: .light))

        #expect(suggestion.recipe.temperature == 97)
        // 1:16.7 becomes 1:17.7, so 30 g takes 530 g rather than 500.
        #expect(suggestion.recipe.water == 530)
        #expect(suggestion.adjustments.count == 2)
        #expect(suggestion.provenance == .adjustedReference("James Hoffmann"))
    }

    @Test func aDarkRoastGetsCoolerWaterAndAShorterRatio() {
        let suggestion = RecipeRules.adjust(v60(), for: card(roast: .mediumDark))
        #expect(suggestion.recipe.temperature == 90)
        // Only the ends of the scale move the ratio.
        #expect(suggestion.recipe.water == 500)

        let dark = RecipeRules.adjust(v60(), for: card(roast: .dark))
        #expect(dark.recipe.water == 470)
    }

    /// Every change carries a reason. An adjustment nobody can explain is a
    /// number that appeared out of nowhere.
    @Test func everyAdjustmentSaysWhy() {
        let suggestion = RecipeRules.adjust(
            v60(),
            for: card(roast: .light, decaf: true, roastedOn: .now)
        )
        #expect(!suggestion.adjustments.isEmpty)
        for adjustment in suggestion.adjustments {
            #expect(!adjustment.label.isEmpty)
            #expect(!adjustment.reason.isEmpty)
        }
    }

    @Test func decafGoesOneStepCoarserAndTwoDegreesCooler() {
        let plain = RecipeRules.adjust(v60(), for: card(roast: .medium))
        let decaf = RecipeRules.adjust(v60(), for: card(roast: .medium, decaf: true))

        #expect(decaf.grindShift == 1)
        #expect(plain.grindShift == 0)
        #expect(decaf.recipe.temperature == (plain.recipe.temperature ?? 0) - 2)
        #expect(decaf.recipe.grindLabel.contains("coarser"))
    }

    @Test func aFreshCoffeeGetsALongerBloom() {
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: .now)
        let fresh = RecipeRules.adjust(v60(), for: card(roastedOn: threeDaysAgo))

        #expect(fresh.recipe.steps[0].at == 0)
        // Everything after the bloom moves back by the same 15 s.
        #expect(fresh.recipe.steps[1].at == 60)
        #expect(fresh.recipe.steps[1].untilSeconds == 90)
        #expect(fresh.recipe.steps[2].at == 90)
        #expect(fresh.recipe.seconds == 225)
        #expect(fresh.adjustments.contains { $0.label == "bloom +15 s" })
    }

    @Test func aRestedCoffeeKeepsItsBloom() {
        let threeWeeksAgo = Calendar.current.date(byAdding: .day, value: -21, to: .now)
        let rested = RecipeRules.adjust(v60(), for: card(roastedOn: threeWeeksAgo))
        #expect(rested.recipe.steps[1].at == 45)
        #expect(!rested.adjustments.contains { $0.label.contains("bloom") })
    }

    /// A coffee with no roast date is not assumed fresh. Guessing here would
    /// stretch the bloom on a six-month-old bag.
    @Test func noRoastDateMeansNoFreshnessRule() {
        let suggestion = RecipeRules.adjust(v60(), for: card(roastedOn: nil))
        #expect(!suggestion.adjustments.contains { $0.label.contains("bloom") })
    }

    @Test func aRecipeWithoutStepsSurvivesTheFreshnessRule() {
        var espresso = v60()
        espresso.steps = []
        let suggestion = RecipeRules.adjust(espresso, for: card(roastedOn: .now))
        #expect(suggestion.recipe.steps.isEmpty)
    }

    // MARK: - Suggestion order

    @Test func aCompletePrintedRecipeWinsOverEverything() {
        let printed = Brew(method: .v60, dose: 16, water: 250, grind: "medium")
        let suggestion = RecipeRules.suggestion(
            for: card(printed: printed),
            references: [v60()]
        )
        #expect(suggestion?.provenance == .card)
        #expect(suggestion?.recipe.dose == 16)
        #expect(suggestion?.adjustments.isEmpty == true)
    }

    /// A printed recipe with no dose is a fragment, not a recipe: fall through
    /// to something you can actually follow.
    @Test func anIncompletePrintedRecipeIsNotUsed() {
        let fragment = Brew(method: .v60, grind: "medium-fine")
        let suggestion = RecipeRules.suggestion(
            for: card(printed: fragment),
            references: [v60()]
        )
        #expect(suggestion?.provenance != .card)
    }

    @Test func yourOwnGoodBrewOnAComparableCoffeeOutranksAReference() {
        let good = Brew(method: .v60, dose: 18, water: 300, rating: 5, notes: "")
        let neighbour = card(name: "Kenya Tekangu", roast: .medium, process: "Washed", brews: [good])
        let subject = card(name: "Ethiopia Chelbesa", roast: .medium, process: "Washed")

        let suggestion = RecipeRules.suggestion(
            for: subject,
            method: .v60,
            references: [v60()],
            neighbours: [neighbour]
        )
        #expect(suggestion?.provenance == .yourBrew(coffee: "Kenya Tekangu"))
        #expect(suggestion?.recipe.dose == 18)
    }

    @Test func aMediocreBrewIsNotWorthCopying() {
        let average = Brew(method: .v60, dose: 18, water: 300, rating: 3)
        let neighbour = card(name: "Kenya Tekangu", process: "Washed", brews: [average])
        let suggestion = RecipeRules.suggestion(
            for: card(process: "Washed"),
            method: .v60,
            references: [v60()],
            neighbours: [neighbour]
        )
        #expect(suggestion?.provenance != .yourBrew(coffee: "Kenya Tekangu"))
    }

    @Test func aDifferentProcessIsNotComparable() {
        let good = Brew(method: .v60, dose: 18, water: 300, rating: 5)
        let natural = card(name: "Brazil", roast: .medium, process: "Natural", brews: [good])
        #expect(!RecipeRules.isComparable(card(process: "Washed"), to: natural))
    }

    @Test func aDifferentRoastLevelIsNotComparable() {
        let dark = card(roast: .dark, process: "Washed")
        #expect(!RecipeRules.isComparable(card(roast: .light, process: "Washed"), to: dark))
    }

    /// Comparability needs something to compare. Two cards with no process
    /// recorded are not "the same process".
    @Test func anEmptyProcessIsNotAMatch() {
        let unknown = card(process: "")
        #expect(!RecipeRules.isComparable(unknown, to: card(process: "")))
    }

    @Test func aCardIsNotComparableToItself() {
        let one = card()
        #expect(!RecipeRules.isComparable(one, to: one))
    }

    @Test func withNoReferenceForTheMethodThereIsNoSuggestion() {
        let suggestion = RecipeRules.suggestion(
            for: card(),
            method: .moka,
            references: [v60()]
        )
        #expect(suggestion == nil)
    }

    @Test func yourOwnSavedRecipeIsPreferredOverAReference() {
        var mine = v60()
        mine = Recipe(
            name: "My V60",
            method: .v60,
            dose: 22,
            water: 350,
            source: .mine
        )
        let suggestion = RecipeRules.suggestion(
            for: card(),
            method: .v60,
            references: [v60()],
            mine: [mine]
        )
        #expect(suggestion?.recipe.dose == 22)
    }

    @Test func anUnknownRoastLeavesTheAuthorsTemperature() {
        let suggestion = RecipeRules.adjust(v60(), for: card(roast: nil))
        #expect(suggestion.recipe.temperature == 99)
        #expect(suggestion.provenance == .reference("James Hoffmann"))
    }

    @Test func aMokaKeepsBoilingWaterEvenOnALightRoast() {
        let moka = Recipe(
            name: "Moka, 3 cup",
            method: .moka,
            dose: 16,
            temperature: 100,
            attribution: "James Hoffmann"
        )
        let suggestion = RecipeRules.adjust(moka, for: card(roast: .light))
        #expect(suggestion.recipe.temperature == 100)
    }

    @Test func aColdBrewKeepsItsTemperature() {
        let cold = Recipe(
            name: "Cold brew",
            method: .coldBrew,
            dose: 60,
            water: 500,
            temperature: 20,
            attribution: "common practice"
        )
        let suggestion = RecipeRules.adjust(cold, for: card(roast: .light))
        #expect(suggestion.recipe.temperature == 20)
    }

    @Test func aFilterSuggestionPrefersAnInBandPartialOverPracticeAndCupping() {
        let kalita = Recipe(
            name: "Kalita Wave 185",
            method: .filter,
            dose: 15,
            water: 250,
            evidence: .practice
        )
        let cupping = Recipe(
            name: "Cupping, SCA protocol",
            method: .filter,
            dose: 8.25,
            water: 150,
            evidence: .verified
        )
        let batch = Recipe(
            name: "Batch drip",
            method: .filter,
            dose: 15,
            water: 250,
            evidence: .partial
        )
        let suggestion = RecipeRules.suggestion(
            for: card(),
            method: .filter,
            references: [kalita, cupping, batch]
        )
        #expect(suggestion?.recipe.name == "Batch drip")
    }

    // MARK: - Method preference

    @Test func theMethodComesFromTheCardThenTheLastBrew() {
        let printed = Brew(method: .aeropress, dose: 15, water: 250)
        #expect(RecipeRules.preferredMethod(for: card(printed: printed)) == .aeropress)

        let logged = Brew(method: .frenchPress, dose: 30, water: 500)
        #expect(RecipeRules.preferredMethod(for: card(brews: [logged])) == .frenchPress)

        #expect(RecipeRules.preferredMethod(for: card(), references: [v60()]) == .v60)
    }

    // MARK: - Reference tables

    @Test func ratiosAndMicronsCoverEveryMethod() {
        for method in BrewMethod.allCases {
            #expect(!RecipeRules.ratio(for: method).isEmpty)
        }
        // Moka has no published range worth quoting, and saying so beats
        // inventing one.
        #expect(RecipeRules.microns(for: .moka) == nil)
        #expect(RecipeRules.microns(for: .v60) == 400...700)
    }

    @Test func theRestWindowIsLongerForEspresso() {
        #expect(RecipeRules.restWindow(for: .espresso, roast: .light) == 10...30)
        #expect(RecipeRules.restWindow(for: .v60, roast: .light) == 7...21)
        #expect(RecipeRules.restWindow(for: .v60, roast: .dark) == 5...14)
    }
}
