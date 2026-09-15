import Testing
@testable import Kohi

/// The KOFFEE MAMEYA brewing card, and the guard rails around what counts as
/// a recipe at all.
struct RecipeParserTests {
    @Test func mameyaBilingualRecipeCard() throws {
        let recipe = try #require(RecipeParser.parse([
            "KOFFEE MAMEYA",
            "BREWING RECIPE",
            "Drip",
            "豆量 :", "Beans", "14", "g",
            "お湯の量:", "Hot Water", "15", "210", "ml",
            "6pours x35ml",
            "抽出時間", "Total brew time", "140", "sec",
            "お湯の温度", "Temperature", "90",
            "挽き目", "Grind", "Medium fine",
            "Code Black Coffee",
        ]))

        #expect(recipe.dose == 14)
        #expect(recipe.water == 210)
        #expect(recipe.seconds == 140)
        #expect(recipe.temperature == 90)
        #expect(recipe.grind.display() == "Medium fine")
        #expect(recipe.method == .filter)
    }

    @Test func timeFormatsParse() throws {
        let colonTime = try #require(RecipeParser.parse(["Dose: 15g", "Time: 2:30"]))
        #expect(colonTime.seconds == 150)

        let minutes = try #require(RecipeParser.parse(["Dose: 15g", "Time: 3 min"]))
        #expect(minutes.seconds == 180)
    }

    @Test func ratioDerivesWater() throws {
        let recipe = try #require(RecipeParser.parse(["Dose: 15g", "Ratio: 1:16", "Temperature: 92"]))
        #expect(recipe.water == 240)
    }

    /// The pour schedule prints right under the grind setting on Chinese
    /// cards. "①滴滤/浸泡" is not a grind.
    @Test func pourScheduleIsNotAGrindSetting() throws {
        let recipe = try #require(RecipeParser.parse([
            "粉重: 15 g",
            "注水量: 220g",
            "研磨度:",
            "①滴滤/浸泡 30 100克 92℃",
        ]))

        #expect(recipe.grind.isEmpty)
        #expect(recipe.dose == 15)
        #expect(recipe.water == 220)
    }

    @Test func ordinaryCardIsNotARecipe() {
        #expect(RecipeParser.parse([
            "Ethiopia Nano Challa",
            "Region : Geera, Jimma",
            "Altitude : 2048 Masl",
            "250g",
        ]) == nil)
    }

    @Test func singleQuantityIsNotARecipe() {
        #expect(RecipeParser.parse(["Beans", "14", "g"]) == nil)
    }
}
