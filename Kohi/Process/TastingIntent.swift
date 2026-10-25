import Foundation

/// One thing the tasting note actually said, shown before any rule uses it.
nonisolated struct TastingIntent: Equatable, Sendable, Identifiable {
    enum Axis: String, Sendable {
        case sweetness, complexity, acidity, bitterness, body, clarity
    }

    var id: String { "\(axis.rawValue)-\(direction)" }
    var axis: Axis
    var direction: Int
    var strength: Int

    /// Local lexicon first. The note on screen is this list, not a rewrite.
    static func extract(_ note: String) -> [TastingIntent] {
        let text = note.lowercased()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var found: [TastingIntent] = []
        func add(_ axis: Axis, _ direction: Int, phrases: [String]) {
            guard phrases.contains(where: { text.contains($0) }) else { return }
            if found.contains(where: { $0.axis == axis }) { return }
            found.append(TastingIntent(axis: axis, direction: direction, strength: 1))
        }
        add(.sweetness, -1, phrases: ["no sweetness", "not enough sweetness", "manque de douceur", "peu de douceur", "flat", "plat", "dull"])
        add(.complexity, -1, phrases: ["lacks complexity", "no complexity", "trop peu de complexité", "peu de complexité", "simple", "one note"])
        add(.acidity, 1, phrases: ["sour", "sharp", "acide", "aigre"])
        add(.acidity, -1, phrases: ["flat acidity", "no acid", "peu d'acidité"])
        add(.bitterness, 1, phrases: ["bitter", "harsh", "astringent", "amer", "âpre"])
        add(.body, -1, phrases: ["thin", "watery", "aqueux", "léger"])
        add(.body, 1, phrases: ["heavy", "muddy", "lourd", "boueux"])
        add(.clarity, -1, phrases: ["muddy", "unclear", "trouble"])
        if isNeutral(text), found.isEmpty { return [] }
        return found
    }

    static func understoodLine(_ intents: [TastingIntent]) -> String? {
        if intents.isEmpty { return nil }
        let parts = intents.map { intent in
            let mark = intent.direction < 0 ? "−" : intent.direction > 0 ? "+" : "ok"
            return "\(intent.axis.rawValue) \(mark)"
        }
        return "Understood: " + parts.joined(separator: ", ")
    }

    /// What the comment screen shows. A neutral note says so; an unrecognized
    /// note stays quiet rather than inventing a reading.
    static func understoodLine(for note: String, dropping: Set<String> = []) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let intents = extract(note).filter { !dropping.contains($0.id) }
        if let line = understoodLine(intents) { return line }
        if isNeutral(trimmed.lowercased()) || !dropping.isEmpty {
            return "Understood: nothing to correct"
        }
        return nil
    }

    static func confirmed(from note: String, dropping: Set<String> = []) -> [TastingIntent] {
        extract(note).filter { !dropping.contains($0.id) }
    }

    static func moves(of intents: [TastingIntent]) -> [NextTime] {
        intents.compactMap { intent in
            switch (intent.axis, intent.direction) {
            case (.sweetness, -1):
                return NextTime(
                    change: "grind finer",
                    reason: "the note says sweetness is short",
                    variable: .grind,
                    direction: -1,
                    evidence: .practice
                )
            default:
                // Complexity is a wish, not a move: see `prefill`.
                return nil
            }
        }
    }

    /// What the note asks for, written onto the brew's wishes where they are
    /// still unanswered. "Lacks complexity" means "more complexity", which
    /// the evidence-gated rules then answer, or decline to.
    static func prefill(_ brew: inout Brew, from intents: [TastingIntent]) {
        for intent in intents {
            switch (intent.axis, intent.direction) {
            case (.complexity, let direction) where brew.complexity == nil:
                BrewWish.set(.complexity, wish: -direction, on: &brew)
            default:
                continue
            }
        }
    }

    private static func isNeutral(_ text: String) -> Bool {
        let neutral = ["bon", "good", "nice", "ok", "okay", "fine"]
        let words = text.split { !$0.isLetter }
        return words.count <= 3 && words.contains { neutral.contains(String($0)) }
    }
}
