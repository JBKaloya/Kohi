import Foundation

nonisolated enum DecafMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case swissWater
    case co2
    case sugarcaneEA
    case mountainWater
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .swissWater: "Swiss Water"
        case .co2: "CO₂"
        case .sugarcaneEA: "Sugarcane EA"
        case .mountainWater: "Mountain Water"
        case .other: "Other"
        }
    }

    /// Tokens that BagFieldParser already recognises as decaf, mapped here.
    static func matching(_ text: String) -> DecafMethod? {
        let lowered = text.lowercased()
        if lowered.contains("swiss") { return .swissWater }
        if lowered.contains("mountain water") || lowered.contains("descafeinado") && lowered.contains("mountain") {
            return .mountainWater
        }
        if lowered.contains("sugarcane") || lowered.contains("ethyl acetate") || lowered.contains("ea ")
            || lowered.contains("e.a") {
            return .sugarcaneEA
        }
        if lowered.contains("co2") || lowered.contains("co₂") || lowered.contains("carbon dioxide") {
            return .co2
        }
        return nil
    }
}
