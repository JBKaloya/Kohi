import Foundation

/// Matches OCR lines, or a name already on the card, against the bundled
/// roaster seed. The longest unique hit wins, so "Paris" does not beat "Klover"
/// inside "Klover Coffee Paris".
nonisolated enum RoasterLineMatch {
    /// Words that are both roaster names and field labels. Matching them as a
    /// substring turns "Origin: Ethiopia" into the roaster Origin.
    private static let genericWords: Set<String> = [
        "origin", "region", "country", "process", "variety", "altitude",
        "harvest", "notes", "note", "coffee", "name", "farm", "lot",
    ]

    static func match(lines: [String], seeds: [RoasterSeed] = ReferenceBase.roasterSeeds) -> RoasterSeed? {
        best(in: lines.map(Roaster.fold), seeds: seeds)
    }

    static func match(name: String, seeds: [RoasterSeed] = ReferenceBase.roasterSeeds) -> RoasterSeed? {
        let folded = Roaster.fold(name)
        guard folded.count >= 4 else { return nil }
        return best(in: [folded], seeds: seeds)
    }

    private static func best(in foldedLines: [String], seeds: [RoasterSeed]) -> RoasterSeed? {
        let lines = foldedLines.filter { $0.count >= 4 }
        guard !lines.isEmpty else { return nil }

        var hits: [(seed: RoasterSeed, length: Int)] = []
        for seed in seeds {
            let names = [seed.name] + seed.aliases
            var length = 0
            for name in names {
                let folded = Roaster.fold(name)
                guard folded.count >= 4 else { continue }
                // "Origin" is a roaster and also a label. A label word only
                // matches a line that is that word, not "Origin: Ethiopia".
                let found = lines.contains { line in
                    if genericWords.contains(folded) { return line == folded }
                    return line == folded || line.contains(folded)
                }
                if found { length = max(length, folded.count) }
            }
            if length > 0 {
                hits.append((seed, length))
            }
        }

        guard let longest = hits.map(\.length).max() else { return nil }
        let winners = hits.filter { $0.length == longest }
        let slugs = Set(winners.map(\.seed.slug))
        guard slugs.count == 1 else { return nil }
        return winners[0].seed
    }
}
