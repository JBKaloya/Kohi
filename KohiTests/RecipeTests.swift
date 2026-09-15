import Foundation
import Testing

@testable import Kohi

struct RecipeTests {
    // MARK: - The bundled base (annexe A)

    /// The verification gate: a recipe with no author is a rumour, and one with
    /// no parameters is not a recipe. Nothing seeded may be either.
    @Test func everyReferenceRecipeIsAttributedAndBrewable() {
        #expect(ReferenceBase.recipes.count >= 15)
        for recipe in ReferenceBase.recipes {
            #expect(!recipe.name.isEmpty)
            #expect(!recipe.attribution.isEmpty, "\(recipe.name) has no attribution")
            #expect(recipe.dose != nil, "\(recipe.name) has no dose")
            #expect(recipe.source == .reference)
        }
    }

    /// A recipe whose figures came from the author's own source is a different
    /// claim from common practice, and the record says which.
    @Test func aVerifiedRecipeCitesItsSource() {
        for recipe in ReferenceBase.recipes where recipe.evidence != .practice {
            #expect(recipe.sourceURL?.isEmpty == false, "\(recipe.name) has no source URL")
        }
    }

    @Test func commonPracticeIsNotAttributedToAPerson() {
        for recipe in ReferenceBase.recipes where recipe.evidence == .practice {
            #expect(recipe.sourceURL == nil || recipe.attribution != "common practice")
        }
    }

    /// The ids have to survive a relaunch: a recipe referenced by a brew, or
    /// selected in a picker, cannot change identity between launches.
    @Test func referenceIDsAreStableAndUnique() {
        let ids = ReferenceBase.recipes.map(\.id)
        #expect(Set(ids).count == ids.count)

        let keys = ReferenceBase.recipes.compactMap(\.referenceID)
        #expect(keys.count == ReferenceBase.recipes.count)
        #expect(ReferenceBase.stableID("a1-v60-ultimate") == ReferenceBase.stableID("a1-v60-ultimate"))
        #expect(ReferenceBase.stableID("a1") != ReferenceBase.stableID("a2"))
    }

    @Test func stepsRunForwardInTime() {
        for recipe in ReferenceBase.recipes {
            var previous = -1
            for step in recipe.steps {
                #expect(step.at >= previous, "\(recipe.name) steps go backwards")
                previous = step.at
                if let until = step.untilSeconds {
                    #expect(until >= step.at, "\(recipe.name) has a step finishing before it starts")
                }
            }
        }
    }

    @Test func waitAndCustomAreNamedForTheTimer() {
        #expect(StepAction.wait.label == "Wait")
        #expect(StepAction.custom.label == "Step")
        #expect(BrewStep(action: .custom, note: "Swirl the bed").actionLabel == "Swirl the bed")
        #expect(BrewStep(action: .custom).actionLabel == "Step")
    }

    /// Pours are cumulative in the vessel, the way a scale reads them, so the
    /// target mass can only go up.
    @Test func pourTargetsAccumulate() {
        for recipe in ReferenceBase.recipes {
            var previous = 0.0
            for step in recipe.steps {
                guard step.action == .pour || step.action == .bloom,
                      let mass = step.targetMass else { continue }
                #expect(mass >= previous, "\(recipe.name) pours backwards")
                previous = mass
            }
            if let water = recipe.water, previous > 0 {
                #expect(previous <= water, "\(recipe.name) pours more than its water")
            }
        }
    }

    @Test func everyRecipeRatioIsPlausibleForItsMethod() {
        for recipe in ReferenceBase.recipes {
            guard let ratio = recipe.ratioValue else { continue }
            let band = RecipeRules.ratio(for: recipe.method)
            // Cupping is 1:18.2 against a 1:15–17 filter band, so the check is
            // deliberately loose: it catches a decimal in the wrong place, not
            // a considered choice.
            #expect(
                ratio >= band.lowerBound * 0.7 && ratio <= band.upperBound * 1.3,
                "\(recipe.name) ratio \(ratio) is far outside \(band)"
            )
        }
    }

    @Test func filteringByMethodFindsRecipes() {
        #expect(!ReferenceBase.recipes(for: .v60).isEmpty)
        #expect(!ReferenceBase.recipes(for: .espresso).isEmpty)
        #expect(ReferenceBase.recipe(referenceID: "a1-v60-ultimate")?.dose == 30)
    }

    // MARK: - Formatting

    @Test func theRatioUsesWaterForFilterAndBeverageForEspresso() {
        let filter = Recipe(method: .v60, dose: 30, water: 500)
        #expect(filter.ratio == "1:16.7")

        let espresso = Recipe(method: .espresso, dose: 18, beverage: 36)
        #expect(espresso.ratio == "1:2.0")
    }

    @Test func longSteepsReadInHours() {
        #expect(Recipe(seconds: 210).timeLabel == "3:30")
        #expect(Recipe(seconds: 50_400).timeLabel == "14 h")
    }

    @Test func aTemperatureRangeIsShownAsARange() {
        #expect(Recipe(temperature: 93).temperatureLabel == "93 °C")
        #expect(Recipe(temperature: 92, temperatureMax: 94).temperatureLabel == "92–94 °C")
        // A "range" of one value is not a range.
        #expect(Recipe(temperature: 93, temperatureMax: 93).temperatureLabel == "93 °C")
    }

    @Test func stepInstructionsReadAsInstructions() {
        #expect(RecipeStep(at: 0, action: .bloom, targetMass: 60).instruction == "Bloom 60 g")
        #expect(RecipeStep(at: 45, action: .pour, targetMass: 300).instruction == "Pour to 300 g")
        #expect(RecipeStep(at: 90, action: .swirl).instruction == "Swirl")
        #expect(RecipeStep(at: 105, action: .stir).timeLabel == "1:45")
    }

    @Test func aRecipeSeedsABrewWithEveryParameterItHas() {
        let brew = ReferenceBase.recipe(referenceID: "a1-v60-ultimate")?.seededBrew()
        #expect(brew?.method == .v60)
        #expect(brew?.dose == 30)
        #expect(brew?.water == 500)
        #expect(brew?.temperature == 99)
        #expect(brew?.grind.display() == "medium-fine")
    }

    @Test func completenessMeansSomethingToWeighAndSomethingToPour() {
        #expect(Recipe(dose: 30, water: 500).isComplete)
        #expect(Recipe(dose: 18, beverage: 36).isComplete)
        #expect(!Recipe(dose: 30).isComplete)
        #expect(!Recipe(water: 500).isComplete)
    }

    // MARK: - Store

    private func emptyStore() -> RecipeStore {
        RecipeStore(files: JSONFileStore(filename: "recipes-test-\(UUID().uuidString).json"))
    }

    @Test func savingABrewAsARecipeNamesItAfterTheCoffee() {
        let store = emptyStore()
        var card = CoffeeCard(name: "Ethiopia Chelbesa")
        card.process = "Washed"
        let brew = Brew(method: .v60, dose: 18, water: 300, seconds: 165, grind: "22 clicks", rating: 5)

        let recipe = store.save(brew: brew, from: card)
        #expect(recipe.name == "Ethiopia Chelbesa · V60")
        #expect(recipe.source == .mine)
        #expect(recipe.dose == 18)
        #expect(recipe.cardID == card.id)
        #expect(recipe.brewID == brew.id)
    }

    @Test func aSecondRecipeForTheSameCoffeeIsNumbered() {
        let store = emptyStore()
        let card = CoffeeCard(name: "Ethiopia Chelbesa")
        let brew = Brew(method: .v60, dose: 18, water: 300)

        _ = store.save(brew: brew, from: card)
        let second = store.save(brew: brew, from: card)
        #expect(second.name == "Ethiopia Chelbesa · V60 (2)")
    }

    @Test func deletingARecipeLeavesTheRest() {
        let store = emptyStore()
        let card = CoffeeCard(name: "Kenya")
        let first = store.save(brew: Brew(method: .v60, dose: 18), from: card)
        _ = store.save(brew: Brew(method: .aeropress, dose: 11), from: card)

        store.delete(first)
        #expect(store.recipes.count == 1)
        #expect(store.recipe(id: first.id) == nil)
    }

    @Test func allCombinesYoursAndTheReferenceBase() {
        let store = emptyStore()
        _ = store.save(brew: Brew(method: .v60, dose: 18), from: CoffeeCard(name: "Kenya"))

        let v60 = store.all(for: .v60)
        #expect(v60.count == ReferenceBase.recipes(for: .v60).count + 1)
        // Yours come first: they are the ones you meant.
        #expect(v60.first?.source == .mine)
    }

    @Test func mergeKeepsTheNewerEdit() {
        let store = emptyStore()
        var local = Recipe(name: "Mine", method: .v60, dose: 18)
        local.updatedAt = Date(timeIntervalSince1970: 2_000)
        _ = store.add(local)

        var stale = local
        stale.name = "From another device"
        stale.updatedAt = Date(timeIntervalSince1970: 1_000)
        store.merge([stale])
        #expect(store.recipe(id: local.id)?.name == "Mine")

        var fresh = local
        fresh.name = "Renamed"
        fresh.updatedAt = Date(timeIntervalSince1970: 3_000)
        store.merge([fresh])
        #expect(store.recipe(id: local.id)?.name == "Renamed")
    }

    // MARK: - Row parity

    private func fullRecipe() -> Recipe {
        Recipe(
            name: "V60, my way",
            method: .v60,
            dose: 18,
            water: 300,
            beverage: 280,
            temperature: 94,
            temperatureMax: 96,
            seconds: 165,
            grindLabel: "medium-fine",
            grindMicronsLow: 400,
            grindMicronsHigh: 700,
            steps: [
                RecipeStep(at: 0, action: .bloom, targetMass: 50, note: "swirl"),
                RecipeStep(at: 45, action: .pour, targetMass: 300, untilSeconds: 75),
            ],
            source: .mine,
            evidence: .practice,
            attribution: "me",
            sourceURL: "https://example.com",
            notes: "sweeter with a longer bloom",
            cardID: UUID(),
            brewID: UUID(),
            referenceID: "a1-v60-ultimate",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
    }

    @Test func recipeSurvivesTheRowRoundTrip() {
        let original = fullRecipe()
        let restored = RecipeRow(recipe: original, userID: UUID()).toRecipe()
        #expect(restored == original)
    }

    @Test func recipePropertiesAreAllAccountedFor() {
        let mapped: Set<String> = [
            "id", "name", "method", "dose", "water", "beverage", "temperature",
            "temperatureMax", "seconds", "grindLabel", "grindMicronsLow",
            "grindMicronsHigh", "steps", "source", "evidence", "attribution",
            "sourceURL", "notes", "cardID", "brewID", "referenceID",
            "profileTags", "authorGrinder", "autoAdvance",
            "createdAt", "updatedAt",
        ]
        let actual = Set(Mirror(reflecting: fullRecipe()).children.compactMap(\.label))
        #expect(actual.subtracting(mapped).isEmpty, "unmapped Recipe properties")
    }

    @Test func stepPropertiesAreAllAccountedFor() {
        let step = RecipeStep(at: 45, action: .pour, targetMass: 300, untilSeconds: 75, note: "swirl")
        let mapped: Set<String> = ["id", "at", "action", "targetMass", "untilSeconds", "note"]
        let actual = Set(Mirror(reflecting: step).children.compactMap(\.label))
        #expect(actual.subtracting(mapped).isEmpty, "unmapped RecipeStep properties")
    }

    @Test func aRecipeFromAnOlderBuildStillDecodes() throws {
        let json = Data(#"{"name":"V60","method":"v60","dose":18}"#.utf8)
        let recipe = try JSONDecoder().decode(Recipe.self, from: json)
        #expect(recipe.name == "V60")
        #expect(recipe.steps.isEmpty)
        #expect(recipe.evidence == .practice)
    }

    @Test func aRecipeRowFromBeforeProfileTagsStillDecodes() throws {
        let data = try JSONEncoder().encode(RecipeRow(recipe: fullRecipe(), userID: UUID()))
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "profile_tags")
        object.removeValue(forKey: "author_grinder")
        object.removeValue(forKey: "auto_advance")
        let restored = try JSONDecoder().decode(
            RecipeRow.self,
            from: try JSONSerialization.data(withJSONObject: object)
        ).toRecipe()
        #expect(restored.profileTags.isEmpty)
        #expect(restored.autoAdvance)
    }
}
