import Foundation

/// The notes printed on a pack, put together from more than one read.
nonisolated enum PackNotes {
    /// What is already there keeps its place; a read adds what it found
    /// after, in its own order. Nothing is removed or rewritten, so a note
    /// the brewer typed survives any scan. Two notes are the same when they
    /// land on the same wheel flavour, or read the same once normalised.
    static func merging(_ current: [String], with incoming: [String]) -> [String] {
        var seen = Set(current.map(key))
        var result = current
        for note in incoming {
            let value = note.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, seen.insert(key(value)).inserted else { continue }
            result.append(value)
        }
        return result
    }

    private static func key(_ note: String) -> String {
        if let tag = FlavorMatcher.match([note]).tags.first, !tag.isCustom { return tag.id }
        return FlavorMatcher.normalize(note)
    }
}
