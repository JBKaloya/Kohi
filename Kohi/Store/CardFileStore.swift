import Foundation
import os

/// Reads and writes the whole archive as one JSON file. At a few hundred cards
/// this is a few hundred kilobytes, and it keeps the archive inspectable.
nonisolated struct CardFileStore: Sendable {
    let url: URL

    init(url: URL = ImageStore.shared.indexURL) {
        self.url = url
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    func load() -> [CoffeeCard] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([CoffeeCard].self, from: data)
        } catch {
            // A corrupt index should not take the app down. The images are still
            // on disk and the file is readable by hand.
            Log.app.error("could not read archive: \(error)")
            return []
        }
    }

    func save(_ cards: [CoffeeCard]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(cards)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
