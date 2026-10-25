import Foundation
import os

/// One colour per tasting note, from `aroma-palette.json`. An unknown note has no colour:
/// the card never invents one.
nonisolated final class AromaPalette: Sendable {
    struct Entry: Decodable, Equatable, Sendable {
        var id: String
        var color: String
        var family: String
        var synonyms: [String]
    }

    private struct Document: Decodable {
        var entries: [Entry]
    }

    static let shared = AromaPalette.load()

    let entries: [Entry]
    private let byID: [String: Entry]

    init(entries: [Entry]) {
        self.entries = entries
        var byID: [String: Entry] = [:]
        for entry in entries where byID[entry.id] == nil { byID[entry.id] = entry }
        self.byID = byID
    }

    /// The wheel first, when it lands on an id the palette knows. Then the longest
    /// synonym contained in the note ("Winey Blueberry" → blueberry).
    func entry(forNote note: String) -> Entry? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let tag = FlavorMatcher.match(trimmed).tags.first(where: { !$0.isCustom }),
           let hit = byID[tag.id] {
            return hit
        }
        return synonymMatch(trimmed)
    }

    func color(forNote note: String) -> SIMD3<Double>? {
        entry(forNote: note).map { OKLab.fromHex($0.color) }
    }

    func synonymMatch(_ note: String) -> Entry? {
        let n = " " + Self.normalize(note) + " "
        guard !n.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var best: Entry?
        var bestLength = 0
        for entry in entries {
            for synonym in entry.synonyms {
                let length = synonym.count
                guard length > bestLength else { continue }
                if n.contains(" " + synonym + " ") || (length > 4 && n.contains(" " + synonym)) {
                    best = entry
                    bestLength = length
                }
            }
        }
        return best
    }

    /// Lowercase, no accents, anything but a-z0-9 becomes a single space.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        var out = ""
        var pendingSpace = false
        for scalar in folded.unicodeScalars {
            let isWord = ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
            if isWord {
                if pendingSpace, !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.unicodeScalars.append(scalar)
            } else {
                pendingSpace = true
            }
        }
        return out
    }

    private static func load() -> AromaPalette {
        guard let url = Bundle.main.url(forResource: "aroma-palette", withExtension: "json") else {
            Log.app.error("aroma-palette.json is missing from the bundle")
            return AromaPalette(entries: [])
        }
        do {
            let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
            return AromaPalette(entries: document.entries)
        } catch {
            Log.app.error("could not read aroma-palette.json: \(error)")
            return AromaPalette(entries: [])
        }
    }
}
