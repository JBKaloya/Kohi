import Foundation

/// How the cup was made. Chosen by hand, never extracted from the card.
nonisolated enum BrewMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case espresso
    case v60
    case filter
    case aeropress
    case moka
    case frenchPress
    case coldBrew

    var id: String { rawValue }

    var label: String {
        switch self {
        case .espresso: "Espresso"
        case .v60: "V60"
        case .filter: "Filter"
        case .aeropress: "AeroPress"
        case .moka: "Moka"
        case .frenchPress: "French Press"
        case .coldBrew: "Cold Brew"
        }
    }
}
