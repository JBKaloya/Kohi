import Foundation
import os

/// Published click ranges. A declared range on the grinder always wins.
nonisolated enum PublishedGrindRanges {
    struct Row: Decodable, Sendable {
        var grinderKey: String
        var method: String
        var min: Double
        var max: Double
        var basis: String
        var sourceUrl: String
        var sourceLabel: String
    }

    static let rows: [Row] = load()

    static func match(grinderRef: String?, method: BrewMethod?) -> Row? {
        guard let grinderRef, let method else { return nil }
        let keys = methodKeys(method)
        return rows.first { $0.grinderKey == grinderRef && keys.contains($0.method) }
    }

    static func range(grinderRef: String?, method: BrewMethod?) -> GrindRange? {
        guard let row = match(grinderRef: grinderRef, method: method) else { return nil }
        return GrindRange(method: method ?? .v60, low: row.min, high: row.max)
    }

    static func caption(grinderRef: String?, method: BrewMethod?) -> String? {
        guard let row = match(grinderRef: grinderRef, method: method) else { return nil }
        return "≈ · from \(row.sourceLabel)"
    }

    private static func methodKeys(_ method: BrewMethod) -> [String] {
        switch method {
        case .v60, .filter: ["pourOver"]
        case .espresso: ["espresso"]
        case .frenchPress: ["frenchPress"]
        case .aeropress: ["aeropress"]
        case .moka: ["moka"]
        case .coldBrew: []
        }
    }

    private static func load() -> [Row] {
        guard let url = Bundle.main.url(forResource: "grinder-ranges", withExtension: "json") else {
            return []
        }
        do {
            return try JSONDecoder().decode([Row].self, from: Data(contentsOf: url))
        } catch {
            Log.app.error("grinder-ranges.json: \(error)")
            return []
        }
    }
}
