import Foundation

/// A way of pouring said once instead of step by step: "je verse par palier
/// de 40, j'attends 20 secondes entre chaque, jusqu'à 200". It becomes the
/// pours it describes, from the mass already reached, one interval apart.
nonisolated enum StepPattern {
    struct Match {
        var steps: [SpokenBrewParser.TimedStep]
        var range: Range<String.Index>
    }

    /// When the interval is not said.
    static let defaultInterval = 20
    /// A runaway pattern ("par palier de 1") stops here.
    static let maxPours = 12

    private static let grams = #"\s*(?:g|grams|grammes|gramme)?\b"#
    private static let notTime = #"(?!\s*(?:secondes?|seconds?|secs?|s|minutes?|mins?)\b)"#

    /// `text` is already normalized: lowercased, numbers as digits.
    static func expand(_ text: String, at: Int, reached: Double?, water: Double?) -> Match? {
        let step = #"\b(?:paliers?|pulses?|tranches?|steps?|increments?|coups?)\s+(?:de\s+|d'|of\s+)?(\d+(?:\.\d+)?)"# + grams + notTime
        guard let stepRange = text.range(of: step, options: .regularExpression),
              let size = number(in: text[stepRange]), size > 0
        else { return nil }

        var ranges = [stepRange]
        let intervalPatterns = [
            #"\b(?:toutes les|tous les|every|j'attends|attends|attendre|wait|waiting|entre|between)\D{0,24}?(\d+)\s*(?:secondes?|seconds?|secs?|s)\b(?:\s+(?:entre chaque|between each|between))?"#,
            #"\b(\d+)\s*(?:secondes?|seconds?|secs?|s)\s+(?:entre chaque|entre|between each|between|apart|d'intervalle)\b"#,
        ]
        var interval = defaultInterval
        for pattern in intervalPatterns {
            if let range = text.range(of: pattern, options: .regularExpression),
               let value = number(in: text[range]), value > 0 {
                interval = Int(value)
                ranges.append(range)
                break
            }
        }

        var total = water
        let target = #"\b(?:jusqu'à|jusqu'a|jusqua|up to|until|to)\s+(\d+(?:\.\d+)?)"# + grams + notTime
        if let range = text.range(of: target, options: .regularExpression, range: stepRange.upperBound..<text.endIndex),
           let value = number(in: text[range]) {
            total = value
            ranges.append(range)
        }
        let verb = #"\b(?:vers(?:e|é|ée|er|ez|ons|ant)s?|pour(?:ed|ing)?)\b"#
        if let range = text.range(of: verb, options: .regularExpression, range: text.startIndex..<stepRange.lowerBound) {
            ranges.append(range)
        }

        let base = reached ?? 0
        var mass = base + size
        var time = at
        var steps: [SpokenBrewParser.TimedStep] = []
        if let total, total > mass {
            while mass < total - 0.5, steps.count < maxPours - 1 {
                steps.append(.init(at: time, action: .pour, mass: mass))
                mass += size
                time += interval
            }
            steps.append(.init(at: time, action: .pour, mass: total))
        } else {
            steps.append(.init(at: time, action: .pour, mass: mass))
        }

        let lower = ranges.map(\.lowerBound).min() ?? stepRange.lowerBound
        let upper = ranges.map(\.upperBound).max() ?? stepRange.upperBound
        return Match(steps: steps, range: lower..<upper)
    }

    private static func number(in text: Substring) -> Double? {
        guard let match = text.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(text[match])
    }
}
