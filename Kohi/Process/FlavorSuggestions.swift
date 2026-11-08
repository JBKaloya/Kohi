import Foundation

/// Wheel flavours offered under a notes entry, by English name, French name
/// or synonym. Always the English label, which is what the wheel shows.
nonisolated enum FlavorSuggestions {
    static func suggest(
        _ query: String,
        excluding taken: [String] = [],
        wheel: FlavorWheel = .shared,
        limit: Int = 6
    ) -> [String] {
        let key = FlavorMatcher.normalize(query)
        guard key.count >= 2 else { return [] }
        let takenKeys = Set(taken.map(FlavorMatcher.normalize))

        var ranked: [(rank: Int, label: String)] = []
        var seen = Set<String>()
        for node in wheel.nodes {
            let label = node.en
            let labelKey = FlavorMatcher.normalize(label)
            guard !takenKeys.contains(labelKey), labelKey != key else { continue }
            guard let rank = rank(of: key, in: node) else { continue }
            if seen.insert(labelKey).inserted {
                ranked.append((rank, label))
            }
        }
        return ranked
            .sorted { ($0.rank, $0.label.count, $0.label) < ($1.rank, $1.label.count, $1.label) }
            .prefix(limit)
            .map(\.label)
    }

    /// 0 on the English name, 1 on the French, 2 on a synonym. A word inside
    /// the name counts: "lemon" finds "Meyer lemon".
    private static func rank(of key: String, in node: FlavorNode) -> Int? {
        let names = [[node.en], [node.fr], node.synonyms]
        for (rank, group) in names.enumerated() {
            for name in group where starts(FlavorMatcher.normalize(name), with: key) {
                return rank
            }
        }
        return nil
    }

    private static func starts(_ name: String, with key: String) -> Bool {
        guard !name.isEmpty else { return false }
        if name.hasPrefix(key) { return true }
        return name.split(separator: " ").contains { $0.hasPrefix(key) }
    }
}
