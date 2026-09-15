import Foundation

/// How the water was filtered, when Source is Filtered. AKVO is a filter
/// first; its minerals live on MineralProduct.
nonisolated enum FiltrationSystem: String, Codable, CaseIterable, Identifiable, Sendable {
    case akvo
    case peakWater = "peak-water"
    case bwtBestmax = "bwt-bestmax"
    case bwtBesttaste = "bwt-besttaste"
    case brita

    var id: String { rawValue }

    var label: String {
        switch self {
        case .akvo: "AKVO"
        case .peakWater: "Peak Water"
        case .bwtBestmax: "BWT Bestmax"
        case .bwtBesttaste: "BWT Besttaste"
        case .brita: "Brita"
        }
    }
}

/// The water the minerals go into, when Source is Recipe.
nonisolated enum WaterBase: String, Codable, CaseIterable, Identifiable, Sendable {
    case distilled
    case ro
    case tap
    case filtered

    var id: String { rawValue }

    var label: String {
        switch self {
        case .distilled: "Distilled"
        case .ro: "RO"
        case .tap: "Tap"
        case .filtered: "Filtered"
        }
    }
}
