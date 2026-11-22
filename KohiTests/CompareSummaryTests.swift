import Foundation
import Testing
@testable import Kohi

/// The sentence under the comparison radar: what is sent, when it is asked
/// again, and when there is no block at all.
@MainActor
struct CompareSummaryTests {
    private func series(
        _ title: String,
        acidity: Int,
        body: Int? = nil,
        flavors: [String] = [],
        rating: Int? = nil
    ) -> CompareSeries {
        CompareSeries(
            source: .tasting(UUID()),
            title: title,
            detail: "12 Nov",
            taste: TasteProfile(acidity: acidity, body: body),
            cardInk: nil,
            brew: nil,
            flavors: flavors,
            ratingHalves: rating
        )
    }

    @Test func thePicksAreSentInOrderWithTheirNumbers() {
        let payload = CompareSummary.payload([
            series("Kenya", acidity: 8, flavors: ["Blackcurrant"], rating: 9),
            series("Brazil", acidity: 3, body: 7),
        ])
        #expect(payload.series.map(\.number) == [1, 2])
        #expect(payload.series.map(\.title) == ["Kenya", "Brazil"])
        #expect(payload.series[0].axes == ["acidity": 8])
        #expect(payload.series[1].axes == ["acidity": 3, "body": 7])
        #expect(payload.series[0].flavors == ["Blackcurrant"])
        #expect(payload.series[0].rating == 4.5)
        #expect(payload.series[1].rating == nil)
    }

    @Test func theSamePicksAreNotAskedTwiceButARescoreIs() {
        let kenya = series("Kenya", acidity: 8)
        let brazil = series("Brazil", acidity: 3)
        let again = [series("Kenya", acidity: 8), series("Brazil", acidity: 3)]
        #expect(CompareSummary.cacheKey([kenya, brazil]) == CompareSummary.cacheKey(again))
        #expect(CompareSummary.cacheKey([kenya, brazil]) != CompareSummary.cacheKey([brazil, kenya]))
        #expect(CompareSummary.cacheKey([kenya, brazil])
            != CompareSummary.cacheKey([series("Kenya", acidity: 9), brazil]))
        #expect(CompareSummary.cacheKey([kenya, brazil])
            != CompareSummary.cacheKey([series("Kenya", acidity: 8, flavors: ["Lime"]), brazil]))
    }

    @Test func thereIsNoBlockWhenTheSwitchIsOffOrNothingCanBeAsked() {
        let two = [series("Kenya", acidity: 8), series("Brazil", acidity: 3)]
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let flags = AIFlags(defaults: defaults)
        flags.setOn(.compareSummary, false)
        #expect(!CompareSummary.isAvailable(two, flags: flags))
        #expect(!CompareSummary.isAvailable(two, flags: nil))
        flags.setOn(.compareSummary, true)
        #expect(!CompareSummary.isAvailable([two[0]], flags: flags))
    }

    @Test func aCoffeeIsKnownForItsMostNotedFlavours() {
        let jasmine = FlavorTag(id: "floral-floral-jasmine")
        let peach = FlavorTag(id: "fruity-other-fruit-peach")
        let lime = FlavorTag(custom: "Lime")
        let noted = CompareSeries.mostNoted([[peach, lime], [jasmine, peach], [lime, peach]])
        #expect(noted == [peach.displayName, lime.displayName, jasmine.displayName])
    }

    @Test func askReadsTheQuestionAgainstTheComparison() {
        let context = CompareSummary.context(
            [series("Kenya", acidity: 8, rating: 9), series("Brazil", acidity: 3)],
            summary: "No. 1 is brighter."
        )
        #expect(context.contains("No. 1: Kenya"))
        #expect(context.contains("Acidity 8"))
        #expect(context.contains("rated 4.5 of 5"))
        #expect(context.hasSuffix("Summary shown: No. 1 is brighter."))
    }

    @Test func askWithoutAComparisonSendsNoContext() throws {
        let plain = Ask.payload(question: "Why sour?", topic: nil, context: nil)
        let blank = Ask.payload(question: "Why sour?", topic: nil, context: "   ")
        #expect(plain.context == nil)
        #expect(blank.context == nil)
        let json = try #require(String(data: JSONEncoder().encode(plain), encoding: .utf8))
        #expect(!json.contains("context"))
    }

    @Test func theSummaryIsATesterFeature() {
        #expect(AIFeature.compareSummary.isTesterOnly)
        #expect(AIFeature.compareSummary.isExperimental)
        #expect(!AIFeature.ask.isTesterOnly)
    }

    @Test func aSlowSummaryGivesUpAtTheDeadline() async {
        let started = Date.now
        do {
            _ = try await CompareSummary.withDeadline(0.05) {
                try await Task.sleep(for: .seconds(300))
                return "too late"
            }
            Issue.record("a call past the deadline should not return")
        } catch {
            #expect(error is CompareSummary.DeadlineExceeded)
        }
        // Far under the call's 300 s. The margin is wide on purpose: with the
        // whole suite running, snapshot tests hold the main actor for about
        // 17 s, and this test resumes on it.
        let elapsed = Date.now.timeIntervalSince(started)
        #expect(elapsed < 60, "gave up after \(elapsed) s")
    }

    @Test func aQuickSummaryArrivesBeforeTheDeadline() async throws {
        let value = try await CompareSummary.withDeadline(5) { "No. 1 is brighter." }
        #expect(value == "No. 1 is brighter.")
    }

    @Test func theRadarWaitsTwelveSecondsAtMost() {
        #expect(CompareSummary.deadline == 12)
    }

    @Test func theSummaryCarriesAUsefulnessScale() throws {
        let view = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Kohi/Compare/CompareView.swift"), encoding: .utf8)
        #expect(view.contains("AIFeedbackScale(eventID: summary.eventID, feature: .compareSummary"))
    }
}
