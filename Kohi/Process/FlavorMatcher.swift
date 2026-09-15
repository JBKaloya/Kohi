import Foundation

/// Deterministic mapping from a tasting-note string onto wheel ids.
///
/// Exact synonym, then prefix, then edit distance ≤ 1 on words of at least
/// six letters. A level-2 match stays at level 2. Unrecognised fragments
/// become `custom:` tags.
nonisolated enum FlavorMatcher {
    struct Match: Equatable, Sendable {
        var tags: [FlavorTag]
        var unmatched: [String]
    }

    static func match(_ notes: String) -> Match {
        match([notes])
    }

    static func match(_ notes: [String]) -> Match {
        var tags: [FlavorTag] = []
        var unmatched: [String] = []
        var seen = Set<String>()
        for fragment in notes.flatMap({ fragments(in: $0) }) {
            let trimmed = fragment.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let node = lookup(trimmed) {
                if seen.insert(node.id).inserted {
                    tags.append(FlavorTag(id: node.id))
                }
            } else {
                unmatched.append(trimmed)
                let tag = FlavorTag(custom: trimmed)
                if seen.insert(tag.id).inserted { tags.append(tag) }
            }
        }
        return Match(tags: tags, unmatched: unmatched)
    }

    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let lowered = folded.lowercased()
        let stripped = lowered.replacingOccurrences(
            of: #"[^\p{L}\p{N}\s]"#,
            with: " ",
            options: .regularExpression
        )
        let collapsed = stripped.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return singularize(collapsed)
    }

    static func fragments(in text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",/;·&")
        let replaced = text
            .replacingOccurrences(of: " et ", with: ",")
            .replacingOccurrences(of: " and ", with: ",")
        return replaced
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func lookup(_ fragment: String) -> FlavorNode? {
        let key = normalize(fragment)
        guard !key.isEmpty else { return nil }
        if let exact = FlavorWheel.shared.matchSynonym(fragment) ?? FlavorWheel.shared.matchSynonym(key) {
            return exact
        }
        let candidates = FlavorWheel.shared.nodes
        if let prefix = candidates.first(where: { node in
            node.synonyms.contains { normalize($0).hasPrefix(key) && key.count >= 3 }
                || normalize(node.en).hasPrefix(key)
                || normalize(node.fr).hasPrefix(key)
        }) {
            return prefix
        }
        if key.count >= 6 {
            return candidates.first { node in
                ([node.en, node.fr] + node.synonyms).contains {
                    let other = normalize($0)
                    return other.count >= 6 && editDistance(key, other) <= 1
                }
            }
        }
        return nil
    }

    /// Very small singulariser: trailing "ies" → "y", trailing "s" dropped
    /// when the stem is long enough. Enough for "blueberries" / "notes".
    private static func singularize(_ word: String) -> String {
        guard word.count > 4 else { return word }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("s") && !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(prev[j] + 1, current[j - 1] + 1, prev[j - 1] + cost)
            }
            prev = current
        }
        return prev[b.count]
    }
}
