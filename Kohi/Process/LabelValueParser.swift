import Foundation

/// Splits a line that carries several `[label]value` fields, the layout some
/// bags (Townsfolk among them) print as a single OCR line.
nonisolated enum LabelValueParser {
    static func segments(in line: String) -> [String] {
        let matches = line.matches(of: /\[([^\]]+)\]([^\[\]]+)/)
        guard !matches.isEmpty else { return [line] }
        return matches.compactMap { match in
            let label = String(match.1).trimmingCharacters(in: .whitespaces)
            let value = String(match.2).trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty, !value.isEmpty else { return nil }
            return "\(label): \(value)"
        }
    }
}
