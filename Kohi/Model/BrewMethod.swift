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
        case .filter: "Pour Over"
        case .aeropress: "AeroPress"
        case .moka: "Moka"
        case .frenchPress: "French Press"
        case .coldBrew: "Cold Brew"
        }
    }

    /// Paper or metal that you swap between cups. Espresso baskets, a moka
    /// plate, a press mesh and a cold-brew cloth live on the brewer itself.
    var usesInterchangeableFilter: Bool {
        switch self {
        case .v60, .filter, .aeropress: true
        case .espresso, .moka, .frenchPress, .coldBrew: false
        }
    }
}
