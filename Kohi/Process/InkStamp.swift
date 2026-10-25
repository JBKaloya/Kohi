import CoreGraphics
import Foundation

/// How the user wants the pack symbol drawn in the card's ground. Auto decides from the mark.
enum SymbolStyle: String, Codable, CaseIterable, Sendable {
    case auto
    case emboss
    case ink
    case halftone
    case pattern
    case none

    /// Brief 7 files said "sticker" or "watermark".
    nonisolated init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "sticker": self = .auto
        case "watermark": self = .emboss
        default: self = SymbolStyle(rawValue: raw) ?? .auto
        }
    }

    var label: String {
        switch self {
        case .auto: Copy.symbolAuto
        case .emboss: Copy.symbolEmboss
        case .ink: Copy.symbolInk
        case .halftone: Copy.symbolHalftone
        case .pattern: Copy.symbolPattern
        case .none: Copy.symbolNone
        }
    }
}

/// The ink drawing taken off a scan. A view of the pack, not a stored fact
/// beyond this file, `stamp.png` and `stamp-shape.json`.
nonisolated struct InkStamp: Codable, Equatable, Sendable {
    /// What the measurement saw. Auto reads it alongside the metrics.
    enum Placement: String, Codable, Sendable {
        case watermark
        case sticker
    }

    enum Source: String, Codable, Sendable {
        case auto
        case manual
        /// A mark fetched once from the roaster's site, not cut from the scan.
        case library
    }

    struct Metrics: Codable, Equatable, Sendable {
        var coverage: Double
        var areaRatio: Double
        var components: Int
        /// Long side of the crop in the measured scan, in pixels.
        var cropLongSide: Int? = nil
    }

    /// Current ink chain. Bump to regenerate on the next render.
    static let pipelineVersion = 3

    /// Normalized rect in the scan, Vision space (origin at the bottom left).
    var rect: CGRect
    var placement: Placement
    var source: Source
    var version: Int
    var metrics: Metrics
}

/// On-disk decision for one card. `stamp == nil` means the chain ran and
/// the pack did not clear the gates.
nonisolated struct StampFile: Codable, Equatable, Sendable {
    var style: SymbolStyle
    var stamp: InkStamp?
    var scanRevision: String
    var pipelineVersion: Int
    var manualRect: CGRect?
    /// Title colour measured from the pack. Nil when the pack had no frank ink;
    /// the card then uses the flavour-wheel family of the first note.
    var inkRed: Double? = nil
    var inkGreen: Double? = nil
    var inkBlue: Double? = nil
    /// `MarkShape.version` of `stamp-shape.json`. Nil: no shape, the bitmap is drawn.
    var vectorVersion: Int? = nil

    /// What the ground shows. `draw` is the card's fifth symbol draw.
    func treatment(draw: Double) -> SymbolTreatment {
        guard let stamp, stamp.source != .library else { return .none }
        switch style {
        case .none: return .none
        case .emboss: return .emboss
        case .ink: return .ink
        case .halftone: return .halftone
        case .pattern: return .pattern
        case .auto: return SymbolRule.auto(stamp.metrics, draw: draw)
        }
    }

    var shownVersion: Int {
        guard stamp != nil, style != .none else { return 0 }
        return stamp?.version ?? 0
    }
}

/// The auto treatment. A tiny mark reads better repeated than enlarged.
nonisolated enum SymbolRule {
    static func isTiny(_ metrics: InkStamp.Metrics) -> Bool {
        if metrics.areaRatio < 0.02 { return true }
        if let side = metrics.cropLongSide, side < 160 { return true }
        return false
    }

    static func auto(_ metrics: InkStamp.Metrics, draw: Double) -> SymbolTreatment {
        if isTiny(metrics) { return .pattern }
        if metrics.coverage < 0.30 { return draw < 0.55 ? .emboss : .ink }
        return draw < 0.60 ? .emboss : .halftone
    }
}

/// Coverage, area, component count, and the "no words" rule.
nonisolated enum InkStampGates {
    static func placement(areaRatio: Double, coverage: Double) -> InkStamp.Placement {
        if areaRatio > 0.20 || coverage > 0.25 { return .watermark }
        return .sticker
    }

    /// False when the drawing is empty, a slab, noise, or still contains a word.
    static func accepted(_ metrics: InkStamp.Metrics, words: [String]) -> Bool {
        guard (0.03...0.45).contains(metrics.coverage) else { return false }
        guard (0.06...0.60).contains(metrics.areaRatio) else { return false }
        guard metrics.components < 400, metrics.components > 0 else { return false }
        guard !words.contains(where: { $0.count >= 3 }) else { return false }
        return true
    }

    static func words(in text: String) -> [String] {
        text.unicodeScalars
            .split { !CharacterSet.letters.contains($0) }
            .map { String($0) }
    }
}
