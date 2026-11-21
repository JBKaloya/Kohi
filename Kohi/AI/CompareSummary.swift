import Foundation
import Supabase
import os

/// A sentence or two under the comparison radar, saying what sets the picks
/// apart, each named by its number.
///
/// The radar stands without it: off, offline or failed, there is no block,
/// never a placeholder that stays.
nonisolated enum CompareSummary {
    struct Summary: Sendable, Hashable {
        var text: String
        var eventID: UUID
    }

    /// One series as the model reads it, numbered as its badge.
    struct SeriesBody: Encodable, Equatable, Sendable {
        let number: Int
        let title: String
        let detail: String
        /// Axis to score, the scored ones only.
        let axes: [String: Int]
        let flavors: [String]
        /// Out of 5, in half points: 3.5.
        let rating: Double?
    }

    struct Payload: Encodable, Equatable, Sendable {
        let series: [SeriesBody]
    }

    private struct Response: Decodable, Sendable {
        var summary: String
        var model: String
        var inputTokens: Int?
        var outputTokens: Int?
        var latencyMs: Int?
    }

    /// In pick order, numbered from 1 like the badges.
    static func payload(_ series: [CompareSeries]) -> Payload {
        Payload(series: series.enumerated().map { index, one in
            SeriesBody(
                number: index + 1,
                title: one.title,
                detail: one.detail,
                axes: Dictionary(uniqueKeysWithValues: one.taste.scoredAxes.compactMap { axis in
                    one.taste[axis].map { (axis.rawValue, $0) }
                }),
                flavors: one.flavors,
                rating: one.ratingHalves.map(HalfRating.points)
            )
        })
    }

    /// What was sent, not which ids: the same picks re-scored ask again.
    static func cacheKey(_ series: [CompareSeries]) -> String {
        payload(series).series.map { body in
            [
                String(body.number),
                body.title,
                TasteAxis.allCases.map { axis in body.axes[axis.rawValue].map(String.init) ?? "-" }
                    .joined(separator: ","),
                body.flavors.joined(separator: ","),
                body.rating.map { String($0) } ?? "-",
            ].joined(separator: "\u{1f}")
        }.joined(separator: "\u{1e}")
    }

    /// Testers, the switches, a server to ask, and two to three picks.
    @MainActor
    static func isAvailable(_ series: [CompareSeries], flags: AIFlags?) -> Bool {
        guard let flags, TesterBuild.isTester, flags.isOn(.compareSummary),
              SupabaseConfig.current != nil else { return false }
        return CompareSelection.canCompare(series.count)
    }

    /// The comparison and its summary, for Coffee Intelligence to read the
    /// question against.
    static func context(_ series: [CompareSeries], summary: String?) -> String {
        var lines = ["Comparing \(series.count) coffees, numbered as on the radar (0 to 10 per axis):"]
        for body in payload(series).series {
            var parts = ["No. \(body.number): \(body.title) (\(body.detail))"]
            let axes = TasteAxis.allCases.compactMap { axis in
                body.axes[axis.rawValue].map { "\(axis.label) \($0)" }
            }
            if !axes.isEmpty { parts.append(axes.joined(separator: ", ")) }
            if !body.flavors.isEmpty { parts.append("flavours: " + body.flavors.joined(separator: ", ")) }
            if let rating = body.rating { parts.append("rated \(HalfRating.meanText(rating)) of 5") }
            lines.append(parts.joined(separator: "; "))
        }
        if let summary { lines.append("Summary shown: \(summary)") }
        return lines.joined(separator: "\n")
    }

    @MainActor
    static func summary(
        of series: [CompareSeries],
        flags: AIFlags,
        events: AIEventLog
    ) async -> Summary? {
        guard isAvailable(series, flags: flags), let client = SupabaseConfig.current else { return nil }
        let key = cacheKey(series)
        if let cached = AICallCache.compareSummary(for: key) { return cached }

        let started = Date.now
        do {
            let response: Response = try await client.functions.invoke(
                "compare-summary",
                options: FunctionInvokeOptions(body: payload(series))
            )
            let eventID = events.record(AIEvent(
                feature: .compareSummary,
                model: response.model,
                inputTokens: response.inputTokens,
                outputTokens: response.outputTokens,
                latencyMs: response.latencyMs ?? FieldExtract.elapsed(since: started)
            ))
            guard let text = response.summary.trimmed else { return nil }
            let summary = Summary(text: text, eventID: eventID)
            AICallCache.store(summary, for: key)
            return summary
        } catch {
            events.record(AIEvent(
                feature: .compareSummary,
                model: "unknown",
                latencyMs: FieldExtract.elapsed(since: started),
                accepted: false,
                failure: "\(error)"
            ))
            Log.app.notice("compare summary failed, the radar stands alone (\(error))")
            return nil
        }
    }
}
