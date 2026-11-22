import Foundation
import Testing
@testable import Kohi

/// How well the device reads a coffee label on its own, field by field,
/// against what the label really prints. The vision model is measured by
/// scripts/scan-bench.ts on the same fixtures.
///
/// Fixtures are photos of real bags, kept out of git in
/// .private/scan-fixtures/<coffee>/ (1.jpg, 2.jpg…, truth.json; see the
/// script for the format). Without them there is nothing to measure and the
/// test passes; with them it writes .private/scan-bench-device.md. It never
/// fails on a misread: it measures, the parser tests pin.
struct ScanBenchmarkTests {
    private static let fields = ["name", "roaster", "country", "region", "producer", "altitude", "variety", "process"]

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".private/scan-fixtures")
    }

    @Test func deviceReadAgainstTruth() async throws {
        let cases = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var lines = ["# Device read · \(Date.now.formatted(.iso8601))", ""]
        var tally: [String: [String: Int]] = ["card": [:], "every side": [:]]
        var measured = 0

        for folder in cases.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: folder.appending(path: "truth.json")),
                  let truth = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let photos = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.range(of: #"^\d+\.(jpe?g|png|heic)$"#, options: [.regularExpression, .caseInsensitive]) != nil }
                .sorted { (Int($0.deletingPathExtension().lastPathComponent) ?? 0) < (Int($1.deletingPathExtension().lastPathComponent) ?? 0) }
            guard let first = photos.first else { continue }
            measured += 1

            // The card, as the first scan reads it.
            var card = FieldParser.parse(await TextExtractor.readFromURL(first))
            // Then each page added, filling only what is empty, as the edit sheet does.
            var everySide = card
            for page in photos.dropFirst() {
                everySide.fillMissing(from: FieldParser.parse(await TextExtractor.readFromURL(page)))
            }
            card.linesRead = 1

            lines += ["## \(folder.lastPathComponent) (\(photos.count) photo\(photos.count > 1 ? "s" : ""))", ""]
            lines += ["| field | truth | card | every side |", "|---|---|---|---|"]
            for field in Self.fields + ["notes"] {
                let printed = field == "notes"
                    ? ((truth["notes"] as? [String]) ?? []).joined(separator: ", ")
                    : (truth[field] as? String) ?? ""
                var cells: [String] = []
                for (label, read) in [("card", card), ("every side", everySide)] {
                    let value = FieldValues.of(read)[field]?.replacingOccurrences(of: "|", with: ", ") ?? ""
                    let verdict = Self.verdict(field: field, truth: printed, read: value)
                    tally[label, default: [:]][verdict, default: 0] += 1
                    cells.append("\(Self.mark(verdict)) \(value.isEmpty ? "–" : value)")
                }
                if !printed.isEmpty || cells.contains(where: { !$0.hasSuffix("–") }) {
                    lines.append("| \(field) | \(printed.isEmpty ? "–" : printed) | \(cells.joined(separator: " | ")) |")
                }
            }
            lines.append("")
        }

        guard measured > 0 else { return }
        var summary = ["| read | right | wrong | missed | extra |", "|---|---|---|---|---|"]
        for label in ["card", "every side"] {
            let t = tally[label] ?? [:]
            let printed = (t["right"] ?? 0) + (t["wrong"] ?? 0) + (t["missed"] ?? 0)
            func pct(_ key: String) -> String { printed == 0 ? "–" : "\(100 * (t[key] ?? 0) / printed) %" }
            summary.append("| device · \(label) | \(pct("right")) | \(pct("wrong")) | \(pct("missed")) | \(t["extra"] ?? 0) |")
        }
        lines.insert(contentsOf: ["\(measured) coffees", ""] + summary + [""], at: 2)
        try lines.joined(separator: "\n").write(
            to: root.deletingLastPathComponent().appending(path: "scan-bench-device.md"),
            atomically: true, encoding: .utf8
        )
    }

    /// Same rules as scripts/scan-bench.ts: folded containment, an altitude on
    /// its whole numbers, notes as found when most printed notes are there.
    static func verdict(field: String, truth: String, read: String) -> String {
        if truth.isEmpty { return read.isEmpty ? "none" : "extra" }
        if read.isEmpty { return "missed" }
        if field == "altitude" {
            // "1,897M" is 1897: thousands separators go before reading the numbers.
            let numbers = { (s: String) in
                s.replacingOccurrences(of: #"(\d)[,.\s](\d{3})(?!\d)"#, with: "$1$2", options: .regularExpression)
                    .split(whereSeparator: { !$0.isNumber }).map(String.init)
            }
            return numbers(truth).allSatisfy(numbers(read).contains) ? "right" : "wrong"
        }
        if field == "notes" {
            let printed = truth.split(separator: ",").map { folded(String($0)) }
            let found = read.split(separator: ",").map { folded(String($0)) }
            let hits = printed.filter { p in found.contains { $0.contains(p) || p.contains($0) } }
            return hits.count * 2 >= printed.count ? "right" : "wrong"
        }
        let t = folded(truth), r = folded(read)
        return t == r || t.contains(r) || r.contains(t) ? "right" : "wrong"
    }

    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func mark(_ verdict: String) -> String {
        switch verdict {
        case "right": "✓"
        case "wrong": "✗"
        case "missed": "∅"
        case "extra": "+"
        default: ""
        }
    }

    @Test func verdictsFollowTheScriptsRules() {
        #expect(Self.verdict(field: "process", truth: "Washed", read: "175C") == "wrong")
        #expect(Self.verdict(field: "altitude", truth: "1750", read: "1750 masl") == "right")
        #expect(Self.verdict(field: "altitude", truth: "1750", read: "175C") == "wrong")
        #expect(Self.verdict(field: "altitude", truth: "1570-1850", read: "1,570~1,850m") == "right")
        #expect(Self.verdict(field: "country", truth: "DR Congo", read: "Congo") == "right")
        #expect(Self.verdict(field: "notes", truth: "Plum, Molasses, Liquorice", read: "NOTES") == "wrong")
        #expect(Self.verdict(field: "notes", truth: "Plum, Molasses, Liquorice", read: "PLUM, MOLASSES") == "right")
        #expect(Self.verdict(field: "region", truth: "", read: "") == "none")
        #expect(Self.verdict(field: "roaster", truth: "", read: "Process Coffee") == "extra")
    }
}
