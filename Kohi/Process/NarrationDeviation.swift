import Foundation

/// A mass the narration contradicted. The clock keeps the time; this keeps the mass.
nonisolated struct NarrationDeviation: Identifiable, Equatable, Sendable {
    var id: String { "\(verb)-\(mass)" }
    var verb: String
    var mass: Double
    var summary: String

    static func parse(_ text: String) -> [NarrationDeviation] {
        let pattern = #"(?:instead of|rather than|actually|au lieu de|plutôt que|finalement|plutot que)\s+(\d+(?:[.,]\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let raw = ns.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
            guard let mass = Double(raw) else { return nil }
            let verb = nearbyVerb(in: ns as String, before: match.range.location) ?? "pour"
            return NarrationDeviation(
                verb: verb,
                mass: mass,
                summary: "\(verb) \(GrindRange.number(mass)) g"
            )
        }
    }

    /// A time in the narration that is not the clock's time. It never changes a mass.
    static func clockNotes(in text: String, steps: [BrewStep]) -> [NarrationDeviation] {
        let pattern = #"\b(\d{1,2}):(\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges > 2,
                  let minutes = Int(ns.substring(with: match.range(at: 1))),
                  let seconds = Int(ns.substring(with: match.range(at: 2)))
            else { return nil }
            let said = minutes * 60 + seconds
            guard let step = steps.min(by: { abs($0.at - said) < abs($1.at - said) }),
                  abs(step.at - said) > 5
            else { return nil }
            let clock = String(format: "%d:%02d", step.at / 60, step.at % 60)
            let spoken = String(format: "%d:%02d", minutes, seconds)
            return NarrationDeviation(
                verb: "clock",
                mass: Double(said),
                summary: "Clock says \(clock) · you said \(spoken)"
            )
        }
    }

    static func apply(_ lines: [NarrationDeviation], to brew: inout Brew) {
        for line in lines where line.verb != "clock" {
            guard let index = brew.steps.firstIndex(where: { $0.action.rawValue == line.verb || $0.action.label.lowercased() == line.verb })
                ?? brew.steps.firstIndex(where: { $0.action == .bloom || $0.action == .pour })
            else { continue }
            brew.steps[index].mass = line.mass
        }
        if !lines.isEmpty, brew.actualSource == .timer || brew.actualSource == .none {
            brew.actualSource = .narration
        }
    }

    private static func nearbyVerb(in text: String, before location: Int) -> String? {
        let head = String(text.prefix(location)).lowercased()
        let verbs = ["bloom", "fleur", "pour", "verse", "rinse", "rince"]
        return verbs.last { head.contains($0) }
    }
}
