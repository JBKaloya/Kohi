import Foundation

/// Geometry of a dripper, from the seed. Finer than `BrewerFamily`, which is
/// what a brew records.
nonisolated enum DripperFamily: String, Codable, CaseIterable, Identifiable, Sendable {
    case cone
    case flat
    case flatCone = "flat-cone"
    case hybrid
    case noBypass = "no-bypass"
    case immersion
    case cloth
    case coneDeep = "cone-deep"
    case flatNobypass = "flat-nobypass"
    case other
    case accessory

    var id: String { rawValue }

    var glyph: EquipmentGlyph {
        switch self {
        case .cone, .coneDeep: .coneDripper
        case .flat, .flatCone, .flatNobypass: .flatDripper
        case .hybrid, .immersion: .immersionSwitch
        case .noBypass: .flatDripper
        case .cloth: .chemex
        case .other, .accessory: .accessory
        }
    }

    var brewerFamily: BrewerFamily {
        switch self {
        case .cone, .coneDeep: .v60
        case .flat, .flatCone, .flatNobypass, .noBypass: .flat
        case .hybrid, .immersion: .immersionSwitch
        case .cloth: .chemex
        case .other, .accessory: .flat
        }
    }

    var filterChip: String {
        switch self {
        case .cone, .coneDeep: "V60"
        case .flat, .flatCone, .flatNobypass: "flat"
        case .hybrid, .immersion: "immersion"
        case .noBypass: "no-bypass"
        case .cloth: "cloth"
        case .other, .accessory: "other"
        }
    }
}

/// How much slurry bypasses the bed. Higher bypass reads as more clarity;
/// lower bypass as more body. Used by the dripper move in Suggested correction.
nonisolated enum BypassLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case high
    case medium
    case low
    case veryLow = "very-low"
    case variable
    case controlled
    case lowMedium = "low-medium"

    var id: String { rawValue }

    /// Ordered from most bypass to least. Variable/controlled sit in the middle.
    var rank: Int {
        switch self {
        case .high: 4
        case .medium, .lowMedium: 3
        case .variable, .controlled: 2
        case .low: 1
        case .veryLow: 0
        }
    }
}
