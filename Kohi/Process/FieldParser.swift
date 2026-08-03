import Foundation

/// Best-effort metadata read off a card. Every field is optional and every field
/// is wrong sometimes; the edit sheet is the real answer.
nonisolated struct ParsedFields: Sendable {
    var name: String?
    var roaster: String?
    var country: String?
    var region: String?
    var producer: String?
    var altitude: String?
    var variety: String?
    var process: String?
    var tastingNotes: [String] = []

    var isEmpty: Bool {
        name == nil && roaster == nil && country == nil && region == nil
            && producer == nil && altitude == nil && variety == nil
            && process == nil && tastingNotes.isEmpty
    }
}

/// Label matching, nothing cleverer. Works well on cards laid out as
/// "Altitude: 1800m" and not at all on cards written as prose, which is the
/// deliberate trade: the failure mode is empty fields, not wrong ones.
nonisolated enum FieldParser {
    // Computed rather than stored: a key path table is not `Sendable`, and
    // rebuilding this handful of strings costs nothing next to the OCR.
    private static var fieldLabels: [(keys: [String], field: WritableKeyPath<ParsedFields, String?>)] {[
        (["coffee", "lot", "name"], \.name),
        (["roaster", "roasted by", "roastery"], \.roaster),
        (["farmer", "producer", "grower", "farm", "cooperative", "co-op", "washing station"], \.producer),
        (["region", "origin", "terroir"], \.region),
        (["country"], \.country),
        (["altitude", "elevation", "height", "masl"], \.altitude),
        (["variety", "varietal", "varieties", "cultivar"], \.variety),
        (["process", "processing", "preparation"], \.process),
    ]}

    private static let noteLabels = [
        "notes", "tasting notes", "flavour notes", "flavor notes",
        "cupping notes", "we taste", "taste",
    ]

    /// Enough origins to catch the common cases. A miss just leaves the field
    /// empty, so this does not need to be exhaustive.
    private static let countries = [
        "Ethiopia", "Kenya", "Rwanda", "Burundi", "Tanzania", "Uganda", "Congo",
        "Colombia", "Brazil", "Peru", "Bolivia", "Ecuador", "Guatemala", "Honduras",
        "El Salvador", "Nicaragua", "Costa Rica", "Panama", "Mexico", "Jamaica",
        "Indonesia", "Sumatra", "Java", "Sulawesi", "Papua New Guinea", "Timor",
        "India", "Vietnam", "Thailand", "China", "Yemen", "Myanmar", "Laos",
    ]

    static func parse(_ lines: [TextExtractor.Line]) -> ParsedFields {
        var fields = ParsedFields()
        let texts = lines.map(\.text)
        var index = 0

        while index < texts.count {
            let line = texts[index]

            if let (field, inlineValue) = match(line, in: fieldLabels) {
                let value = inlineValue ?? nextValue(after: index, in: texts)
                if let value, fields[keyPath: field] == nil {
                    fields[keyPath: field] = value
                }
                index += 1
                continue
            }

            if let inline = matchNotes(line) {
                let collected = inline.isEmpty ? collectNotes(after: index, in: texts) : split(inline)
                if fields.tastingNotes.isEmpty { fields.tastingNotes = collected }
                index += 1
                continue
            }

            index += 1
        }

        resolveOrigin(&fields, lines: texts)
        return fields
    }

    // MARK: - Label matching

    private static func match(
        _ line: String,
        in table: [(keys: [String], field: WritableKeyPath<ParsedFields, String?>)]
    ) -> (WritableKeyPath<ParsedFields, String?>, String?)? {
        for entry in table {
            for key in entry.keys {
                guard let remainder = remainder(of: line, afterLabel: key) else { continue }
                return (entry.field, remainder.isEmpty ? nil : remainder)
            }
        }
        return nil
    }

    private static func matchNotes(_ line: String) -> String? {
        for key in noteLabels {
            if let remainder = remainder(of: line, afterLabel: key) { return remainder }
        }
        return nil
    }

    /// Returns what follows a label, or nil if the line does not start with it.
    /// Requires a colon or an exact match so a line of prose beginning with
    /// "Process" does not swallow the paragraph.
    private static func remainder(of line: String, afterLabel label: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix(label) else { return nil }
        let rest = String(trimmed.dropFirst(label.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: " :–-\t"))
        if rest.isEmpty { return trimmed.count <= label.count + 2 ? "" : nil }
        // A label followed by a lot of words is prose, not a value.
        guard rest.split(separator: " ").count <= 8 else { return nil }
        return rest
    }

    private static func isLabel(_ line: String) -> Bool {
        match(line, in: fieldLabels) != nil || matchNotes(line) != nil
    }

    private static func nextValue(after index: Int, in texts: [String]) -> String? {
        let next = index + 1
        guard next < texts.count, !isLabel(texts[next]) else { return nil }
        let value = texts[next].trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, value.split(separator: " ").count <= 8 else { return nil }
        return value
    }

    private static func collectNotes(after index: Int, in texts: [String]) -> [String] {
        var notes: [String] = []
        var cursor = index + 1
        while cursor < texts.count, notes.count < 6 {
            let line = texts[cursor]
            guard !isLabel(line) else { break }
            let candidate = line.trimmingCharacters(in: .whitespaces)
            // Notes are short. A long line is the roaster's blurb.
            guard !candidate.isEmpty, candidate.split(separator: " ").count <= 3 else { break }
            notes.append(contentsOf: split(candidate))
            cursor += 1
        }
        return notes
    }

    private static func split(_ value: String) -> [String] {
        value
            .split(whereSeparator: { ",;/•·".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Origin

    /// Cards very often print "Nyeri, Kenya" against a single Region label, and
    /// otherwise mention the country somewhere loose in the text.
    private static func resolveOrigin(_ fields: inout ParsedFields, lines: [String]) {
        if let region = fields.region {
            for country in countries where region.localizedCaseInsensitiveContains(country) {
                fields.country = fields.country ?? country
                let trimmed = region
                    .replacingOccurrences(of: country, with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,–-"))
                fields.region = trimmed.isEmpty ? nil : trimmed
                break
            }
        }

        guard fields.country == nil else { return }
        for line in lines {
            for country in countries where line.localizedCaseInsensitiveContains(country) {
                fields.country = country
                return
            }
        }
    }
}
