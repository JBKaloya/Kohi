import Foundation
// @preconcurrency: TranslationSession is not Sendable, but its batch API runs
// off-actor by design; Apple's own usage pattern hands the session across.
@preconcurrency import Translation
import os

/// Translates card fields written in Chinese or Japanese into English with the
/// on-device Translation framework, keeping the original text on the card.
/// Values with fixed vocabularies (countries, processes) never get here — the
/// parser translates those through tables. This handles the free text: names,
/// regions, producers, tasting notes.
nonisolated enum FieldTranslator {
    static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)      // hiragana, katakana
                || (0x4E00...0x9FFF).contains(scalar.value)  // han
        }
    }

    /// Whether the card still carries untranslated CJK text worth a session.
    static func needsTranslation(_ card: CoffeeCard) -> Bool {
        !requests(for: card).isEmpty
    }

    /// Translates every CJK field of the card, returning the updated copy, or
    /// nil when there was nothing to translate or the session failed (no
    /// language pack, simulator, airplane mode during pack download).
    static func translate(_ card: CoffeeCard, using session: TranslationSession) async -> CoffeeCard? {
        let requests = requests(for: card)
        guard !requests.isEmpty else { return nil }

        let responses: [TranslationSession.Response]
        do {
            responses = try await session.translations(from: requests)
        } catch {
            Log.app.notice("field translation failed, keeping the original text (\(error))")
            return nil
        }

        var updated = card
        for response in responses {
            guard let key = response.clientIdentifier else { continue }
            let translated = response.targetText.trimmingCharacters(in: .whitespaces)
            guard !translated.isEmpty else { continue }
            apply(translated, forKey: key, to: &updated)
        }
        return updated
    }

    // MARK: - Requests

    private static func requests(for card: CoffeeCard) -> [TranslationSession.Request] {
        var requests: [TranslationSession.Request] = []

        func add(_ value: String, key: String) {
            guard containsCJK(value), card.originalFields[key] == nil else { return }
            requests.append(TranslationSession.Request(sourceText: value, clientIdentifier: key))
        }

        add(card.name, key: "name")
        add(card.roaster, key: "roaster")
        add(card.region, key: "region")
        add(card.producer, key: "producer")
        add(card.variety, key: "variety")
        add(card.process, key: "process")
        for (index, note) in card.tastingNotes.enumerated() {
            add(note, key: "note:\(index)")
        }
        return requests
    }

    private static func apply(_ translated: String, forKey key: String, to card: inout CoffeeCard) {
        if key.hasPrefix("note:") {
            guard let index = Int(key.dropFirst("note:".count)),
                  card.tastingNotes.indices.contains(index) else { return }
            card.originalFields[key] = card.tastingNotes[index]
            card.tastingNotes[index] = translated
            return
        }

        let paths: [String: WritableKeyPath<CoffeeCard, String>] = [
            "name": \.name, "roaster": \.roaster, "region": \.region,
            "producer": \.producer, "variety": \.variety, "process": \.process,
        ]
        guard let path = paths[key] else { return }
        card.originalFields[key] = card[keyPath: path]
        card[keyPath: path] = translated
    }
}
