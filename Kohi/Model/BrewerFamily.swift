import Foundation

/// How you brew, in the vocabulary of the cupboard.
///
/// Distinct from `BrewMethod`, which is what a brew and a recipe record and is
/// pinned by a database check. A family is a piece of kit: a Kalita and a
/// Chemex are both `filter` to a brew, and two different shapes on a shelf.
nonisolated enum BrewerFamily: String, Codable, CaseIterable, Identifiable, Sendable {
    case espresso
    case v60
    case flat
    case chemex
    case aeropress
    case immersionSwitch
    case frenchPress
    case moka
    case coldBrew
    case batch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .espresso: "Espresso"
        case .v60: "V60"
        case .flat: "Flat dripper"
        case .chemex: "Chemex"
        case .aeropress: "AeroPress"
        case .immersionSwitch: "Immersion"
        case .frenchPress: "French press"
        case .moka: "Moka"
        case .coldBrew: "Cold brew"
        case .batch: "Batch"
        }
    }

    /// The brew method a log or a recipe uses when this family is chosen.
    var method: BrewMethod {
        switch self {
        case .espresso: .espresso
        case .v60: .v60
        case .flat, .chemex, .immersionSwitch, .batch: .filter
        case .aeropress: .aeropress
        case .frenchPress: .frenchPress
        case .moka: .moka
        case .coldBrew: .coldBrew
        }
    }

    var glyph: EquipmentGlyph {
        switch self {
        case .espresso: .espressoMachine
        case .v60: .coneDripper
        case .flat: .flatDripper
        case .chemex: .chemex
        case .aeropress: .aeropress
        case .immersionSwitch: .immersionSwitch
        case .frenchPress: .frenchPress
        case .moka: .moka
        case .coldBrew: .coldBrew
        case .batch: .flatDripper
        }
    }

    /// What is stored on `Equipment.brewerType`.
    var storageValue: String { label }

    /// Kit kind created for this family: espresso is a machine, the rest are brewers.
    var equipmentKind: EquipmentKind {
        self == .espresso ? .espressoMachine : .brewer
    }

    /// Reads a stored `brewerType`, including older free-text values.
    static func parse(_ raw: String?) -> BrewerFamily? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let exact = BrewerFamily(rawValue: trimmed) { return exact }
        let lowered = trimmed.lowercased()
        if let byLabel = allCases.first(where: { $0.label.lowercased() == lowered }) {
            return byLabel
        }
        if lowered.contains("v60") || lowered.contains("cone") || lowered.contains("pour-over")
            || lowered.contains("pour over") {
            return .v60
        }
        if lowered.contains("kalita") || lowered.contains("origami") || lowered.contains("april")
            || lowered.contains("flat") {
            return .flat
        }
        if lowered.contains("chemex") { return .chemex }
        if lowered.contains("aero") { return .aeropress }
        if lowered.contains("switch") || lowered.contains("immersion") { return .immersionSwitch }
        if lowered.contains("french") || lowered.contains("press") { return .frenchPress }
        if lowered.contains("moka") || lowered.contains("moka") { return .moka }
        if lowered.contains("cold") { return .coldBrew }
        if lowered.contains("batch") || lowered.contains("moccamaster") { return .batch }
        if lowered.contains("espresso") || lowered.contains("lever") { return .espresso }
        return nil
    }
}

nonisolated extension Equipment {
    var brewerFamily: BrewerFamily? {
        if kind == .espressoMachine { return .espresso }
        return BrewerFamily.parse(brewerType)
    }
}
