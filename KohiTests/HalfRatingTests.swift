import Foundation
import Testing

@testable import Kohi

/// The overall score in half points, the same after a brew and for a
/// tasting, and still readable by build 13, which knows only whole dots.
struct HalfRatingTests {
    // MARK: - The gesture

    @Test func tapGivesTheWholeThenTheHalfThenNothing() {
        var halves: Int? = nil
        halves = HalfRating.tap(halves, dot: 3)
        #expect(halves == 6)
        halves = HalfRating.tap(halves, dot: 3)
        #expect(halves == 5)
        halves = HalfRating.tap(halves, dot: 3)
        #expect(halves == nil)
    }

    @Test func twoAndAHalfThenThreeThenCleared() {
        var halves: Int? = HalfRating.tap(HalfRating.tap(nil, dot: 3), dot: 3)
        #expect(halves == 5)
        halves = HalfRating.tap(halves, dot: 2)
        #expect(halves == 4)
        halves = HalfRating.tap(halves, dot: 3)
        #expect(halves == 6)
        halves = HalfRating.tap(HalfRating.tap(halves, dot: 3), dot: 3)
        #expect(halves == nil)
    }

    @Test func theScaleRunsFromHalfADotToFive() {
        #expect(HalfRating.tap(HalfRating.tap(nil, dot: 1), dot: 1) == 1)
        #expect(HalfRating.tap(nil, dot: 5) == 10)
        #expect(HalfRating.range == 1...10)
    }

    @Test func voiceOverMovesByHalfAPoint() {
        #expect(HalfRating.step(nil, by: 1) == 1)
        #expect(HalfRating.step(5, by: 1) == 6)
        #expect(HalfRating.step(10, by: 1) == 10)
        #expect(HalfRating.step(1, by: -1) == nil)
        #expect(HalfRating.spoken(5) == "2.5 out of 5")
        #expect(HalfRating.spoken(nil) == "Not rated")
    }

    @Test func dotsFillWholeThenHalf() {
        #expect((1...5).map { HalfRating.dot($0, of: 5) } == [.full, .full, .half, .empty, .empty])
        #expect((1...5).map { HalfRating.dot($0, of: 1) } == [.half, .empty, .empty, .empty, .empty])
        #expect((1...5).map { HalfRating.dot($0, of: nil) } == Array(repeating: .empty, count: 5))
    }

    @Test func textAndMeans() {
        #expect(HalfRating.text(7) == "3.5")
        #expect(HalfRating.text(8) == "4")
        #expect(HalfRating.text(1) == "0.5")
        #expect(HalfRating.mean([5, 6]) == 2.75)
        #expect(HalfRating.meanText(2.75) == "2.75")
        #expect(HalfRating.meanText(4) == "4.0")
        #expect(HalfRating.meanText(3.5) == "3.5")
        #expect(HalfRating.mean([]) == nil)
    }

    // MARK: - Builds before half points

    @Test func olderBuildsSeeWholeDotsRoundedDown() {
        #expect(HalfRating.whole(5) == 2)
        #expect(HalfRating.whole(1) == 1)
        #expect(HalfRating.whole(10) == 5)
        #expect(HalfRating.whole(nil) == nil)
    }

    @Test func theWholeScoreDecidesWhenTheyDisagree() {
        #expect(HalfRating.resolve(halves: 5, whole: 2) == 5)
        #expect(HalfRating.resolve(halves: 5, whole: 4) == 8)
        #expect(HalfRating.resolve(halves: 5, whole: nil) == nil)
        #expect(HalfRating.resolve(halves: nil, whole: 3) == 6)
        #expect(HalfRating.resolve(halves: 1, whole: 1) == 1)
        #expect(HalfRating.resolve(halves: nil, whole: 0) == nil)
    }

    @Test func wholeHistoricScoresAndNilAreKeptExactly() throws {
        for whole in 1...5 {
            let json = #"{"id":"\#(UUID().uuidString)","context":{"out":{"place":{"name":"A","address":"","latitude":0,"longitude":0}}},"rating":\#(whole)}"#
            let tasting = try JSONDecoder().decode(Tasting.self, from: Data(json.utf8))
            #expect(tasting.ratingHalves == whole * 2)
            #expect(tasting.rating == whole)
        }
        let unrated = #"{"id":"\#(UUID().uuidString)","context":{"out":{"place":{"name":"A","address":"","latitude":0,"longitude":0}}}}"#
        #expect(try JSONDecoder().decode(Tasting.self, from: Data(unrated.utf8)).ratingHalves == nil)
    }

    /// What build 13 decodes: a whole `rating`, nothing else.
    private struct Build13Score: Decodable {
        let rating: Int?
    }

    @Test func aHalfScoreWritesBothKeys() throws {
        var tasting = Tasting(context: .out(place: Place(name: "A", address: "", latitude: 0, longitude: 0), placeID: nil))
        tasting.ratingHalves = 5
        let data = try JSONEncoder().encode(tasting)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["rating"] as? Int == 2)
        #expect(object["ratingHalves"] as? Int == 5)
        #expect(try JSONDecoder().decode(Build13Score.self, from: data).rating == 2)
        #expect(try JSONDecoder().decode(Tasting.self, from: data).ratingHalves == 5)
    }

    @Test func aTastingRowCarriesBothColumns() throws {
        var tasting = Tasting(context: .out(place: Place(name: "A", address: "", latitude: 0, longitude: 0), placeID: nil))
        tasting.ratingHalves = 7
        let row = TastingRow(tasting: tasting, userID: UUID())
        #expect(row.rating == 3)
        #expect(row.rating_halves == 7)
        #expect(row.toTasting().ratingHalves == 7)

        var json = try SyncParityTests.dictionary(from: row)
        #expect(try JSONDecoder().decode(Build13Score.self, from: JSONSerialization.data(withJSONObject: json)).rating == 3)

        json["rating"] = 5
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let edited = try decoder.decode(TastingRow.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(edited.toTasting().ratingHalves == 10)

        json["rating"] = nil
        let cleared = try decoder.decode(TastingRow.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(cleared.toTasting().ratingHalves == nil)
    }

    @Test func aRowBeforeTheMigrationReadsAsWholeDots() throws {
        let tasting = Tasting(context: .out(place: Place(name: "A", address: "", latitude: 0, longitude: 0), placeID: nil), rating: 4)
        var json = try SyncParityTests.dictionary(from: TastingRow(tasting: tasting, userID: UUID()))
        json.removeValue(forKey: "rating_halves")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let row = try decoder.decode(TastingRow.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(row.toTasting().ratingHalves == 8)
    }

    @Test func aBrewUsesTheSameScale() throws {
        var brew = Brew(rating: 3)
        #expect(brew.ratingHalves == 6)
        brew.ratingHalves = 9
        #expect(brew.rating == 4)
        let row = BrewRow(brew: brew, cardID: UUID(), userID: UUID())
        #expect(row.rating == 4)
        #expect(row.rating_halves == 9)
        #expect(row.toBrew().ratingHalves == 9)

        let data = try JSONEncoder().encode(brew)
        #expect(try JSONDecoder().decode(Brew.self, from: data).ratingHalves == 9)
        #expect(try JSONDecoder().decode(Build13Score.self, from: data).rating == 4)
    }

    @Test func clearingTheScoreClearsBoth() {
        var brew = Brew(ratingHalves: 5)
        brew.ratingHalves = nil
        #expect(brew.rating == nil)
        #expect(!brew.isComparable)
    }

    // MARK: - Where it is read

    @Test func meansAreExact() {
        let place = Place(name: "A", address: "", latitude: 0, longitude: 0)
        let tastings = [
            Tasting(context: .out(place: place, placeID: nil), ratingHalves: 5),
            Tasting(context: .out(place: place, placeID: nil), ratingHalves: 6),
            Tasting(context: .out(place: place, placeID: nil)),
        ]
        #expect(TastingScore.line(tastings) == "2.75 · 2 tastings")
        let card = CoffeeCard(name: "Bulga", tastings: tastings)
        #expect(card.tastingScore?.average == 2.75)
        #expect(card.tastingScore?.count == 2)
    }

    @Test func recipeThresholdsAreUnchangedForWholeScores() throws {
        let rules = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Process/RecipeRules.swift"))
        #expect(rules.contains("(brew.ratingHalves ?? 0) >= 8"))
        let suggestions = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Recipes/RecipeSuggestions.swift"))
        #expect(suggestions.contains("(last.ratingHalves ?? 0) <= 4"))
    }

    @Test func oneComponentForBothJourneys() throws {
        let section = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Tastings/SensoryEvaluationSection.swift"))
        #expect(section.contains("RatingPicker(halves: $ratingHalves"))
        let after = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Recipes/AfterBrewSheet.swift"))
        #expect(after.contains("ratingHalves: $session.brew.ratingHalves"))
        let flow = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Tastings/TastingFlow.swift"))
        #expect(flow.contains("RatingPicker(halves: $draft.ratingHalves)"))
    }

    @Test func theMigrationIsAdditive() throws {
        let sql = try String(
            contentsOf: DevBrief10.kohiRoot.deletingLastPathComponent()
                .appending(path: "supabase/migrations/0030_rating_halves.sql")
        )
        #expect(sql.contains("alter table public.tastings\n  add column if not exists rating_halves smallint"))
        #expect(sql.contains("alter table public.brews\n  add column if not exists rating_halves smallint"))
        #expect(!sql.contains("drop column"))
        #expect(!sql.contains("alter column rating"))
    }

    @Test func slidingAlongTheDotsSetsHalves() {
        let width = 270.0
        #expect(HalfRating.slide(x: 10, width: width) == 1)
        #expect(HalfRating.slide(x: 40, width: width) == 2)
        #expect(HalfRating.slide(x: 140, width: width) == 6)
        #expect(HalfRating.slide(x: 269, width: width) == 10)
        #expect(HalfRating.slide(x: -30, width: width) == 1)
        #expect(HalfRating.slide(x: 400, width: width) == 10)
        #expect(HalfRating.slide(x: 50, width: 0) == 1)
    }

    @Test func aTapLandsOnTheDotUnderTheFinger() {
        #expect(StepHit.index(x: 10, width: 270, count: 5) == 1)
        #expect(StepHit.index(x: 120, width: 270, count: 5) == 3)
        #expect(StepHit.index(x: 269, width: 270, count: 5) == 5)
    }

    @Test func ratingAndNotesTickLikeACounter() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Kohi/Design/TastingBlocks.swift"), encoding: .utf8)
        #expect(source.contains(".haptic(.step, trigger: halves)"))
        #expect(source.contains(".haptic(.step, trigger: selection)"))
    }

    @Test func theCupSummaryKeepsASeparatorBetweenFamilies() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Kohi/Edit/FlavorPicker.swift"), encoding: .utf8)
        #expect(source.contains("FlavorWheel.shared.families.flatMap"))
        #expect(!source.contains("return HStack(spacing: 6) {\n            ForEach(families"))
    }
}
