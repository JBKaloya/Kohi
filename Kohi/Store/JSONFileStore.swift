import Foundation
import os

/// One JSON file per collection, on the same terms as the archive: ISO dates,
/// pretty-printed, readable by hand, and a decode failure costs the cache
/// rather than the app.
///
/// `CardFileStore` stays separate — it is bound to the image store's index URL
/// and is the one file that must never be silently emptied.
nonisolated struct JSONFileStore<Element: Codable & Sendable>: Sendable {
    let url: URL

    init(filename: String) {
        url = URL.applicationSupportDirectory
            .appending(path: filename, directoryHint: .notDirectory)
    }

    func load() -> [Element] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([Element].self, from: data)
        } catch {
            Log.app.error("could not read \(url.lastPathComponent): \(error)")
            return []
        }
    }

    func save(_ elements: [Element]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(elements)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

/// Same terms, for a file that holds one document rather than a list — Setup
/// keeps several collections together in `setup.json`.
nonisolated struct JSONDocumentStore<Document: Codable & Sendable>: Sendable {
    let url: URL

    init(filename: String) {
        url = URL.applicationSupportDirectory
            .appending(path: filename, directoryHint: .notDirectory)
    }

    func load() -> Document? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Document.self, from: data)
        } catch {
            Log.app.error("could not read \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    func save(_ document: Document) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
