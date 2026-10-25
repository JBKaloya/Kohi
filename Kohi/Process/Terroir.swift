import Foundation
import os

/// Ground per origin, process energy, roast value and sky, from `card-terroir.json`.
nonisolated enum Terroir {
    enum ProcessKey: String, Codable, CaseIterable, Sendable {
        case washed
        case natural
        case honey
        case anaerobic
        case wetHulled
        case unknown

        /// Asset key of the process seal. Nil when the process is unknown.
        var sealKey: String? {
            switch self {
            case .washed: "washed"
            case .natural: "natural"
            case .honey: "honey"
            case .anaerobic: "anaerobic"
            case .wetHulled: "wethulled"
            case .unknown: nil
            }
        }
    }

    struct Land: Decodable, Equatable, Sendable {
        var ground: String
        var tone1: String
        var tone2: String
    }

    struct ExtraBlob: Decodable, Equatable, Sendable {
        var color: String
        var weight: Double
        var sigma: Double
    }

    struct ProcessSettings: Decodable, Equatable, Sendable {
        var warp: Double
        var grainOverlay: Double
        var chroma: Double
        var sharpness: Double
        var swirl: Double
        var warmShift: Double
        var darken: Double
        var extraBlob: ExtraBlob?
    }

    struct Sky: Decodable, Equatable, Sendable {
        var lowAltitude: String
        var highAltitude: String
        var tintFromLightestNote: Double
        var minL: Double
        var altitudeRange: [Double]
    }

    struct Document: Decodable, Sendable {
        var origins: [String: Land]
        var unknownOrigin: Land
        var process: [String: ProcessSettings]
        var roastLightness: [String: Double]
        var roastUnknown: Double
        var sky: Sky
    }

    static let document: Document = load()

    static func land(iso: String?) -> Land {
        guard let iso, let land = document.origins[iso.uppercased()] else { return document.unknownOrigin }
        return land
    }

    static func settings(_ key: ProcessKey) -> ProcessSettings {
        document.process[key.rawValue] ?? document.process[ProcessKey.unknown.rawValue] ?? fallbackProcess
    }

    static func roastLightness(_ level: RoastLevel?) -> Double {
        guard let level else { return document.roastUnknown }
        return document.roastLightness[level.rawValue] ?? document.roastUnknown
    }

    /// First match wins, in this order: fermentations, wet-hulled, honey, natural, washed.
    static func classify(process raw: String) -> ProcessKey {
        let p = AromaPalette.normalize(raw)
        guard !p.isEmpty else { return .unknown }
        let rules: [(String, ProcessKey)] = [
            ("anaer|carbon|macera|thermal|co ?ferm|infus|lactic|yeast|koji|experimental|double", .anaerobic),
            ("wet ?hull|giling", .wetHulled),
            ("honey|miel|pulped|semi ?wash", .honey),
            ("natur|dry|sun ?dried", .natural),
            ("wash|lavad|lave|fully", .washed),
        ]
        for (pattern, key) in rules where p.range(of: pattern, options: .regularExpression) != nil {
            return key
        }
        return .unknown
    }

    /// The 3 and 4 digit numbers of the field, spaces and dots removed. "1800-1900" gives the mean.
    static func altitudeMeters(_ raw: String) -> Double? {
        let compact = raw.filter { !$0.isWhitespace && $0 != "." }
        guard let regex = try? NSRegularExpression(pattern: "\\d{3,4}") else { return nil }
        let range = NSRange(compact.startIndex..., in: compact)
        let values = regex.matches(in: compact, range: range).prefix(2).compactMap { match -> Double? in
            Range(match.range, in: compact).flatMap { Double(compact[$0]) }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Share of air above the coffee: 900 m → 0, 2 200 m → 1. Unknown → 0.5.
    static func altitudeShare(_ raw: String) -> Double {
        guard let meters = altitudeMeters(raw) else { return 0.5 }
        let range = document.sky.altitudeRange
        let low = range.first ?? 900, high = range.last ?? 2200
        return min(1, max(0, (meters - low) / (high - low)))
    }

    private static let fallbackProcess = ProcessSettings(
        warp: 0.08, grainOverlay: 0.36, chroma: 1.05, sharpness: 1.4, swirl: 0, warmShift: 0, darken: 0, extraBlob: nil
    )

    private static func load() -> Document {
        let empty = Document(
            origins: [:],
            unknownOrigin: Land(ground: "#3A2E26", tone1: "#B98552", tone2: "#6B4E36"),
            process: [:],
            roastLightness: [:],
            roastUnknown: 0.02,
            sky: Sky(lowAltitude: "#F4DDB7", highAltitude: "#EAF1EF", tintFromLightestNote: 0.18, minL: 0.9, altitudeRange: [900, 2200])
        )
        guard let url = Bundle.main.url(forResource: "card-terroir", withExtension: "json") else {
            Log.app.error("card-terroir.json is missing from the bundle")
            return empty
        }
        do {
            return try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        } catch {
            Log.app.error("could not read card-terroir.json: \(error)")
            return empty
        }
    }
}
