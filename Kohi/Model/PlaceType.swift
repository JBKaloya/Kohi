import Foundation

/// What kind of place a coffee was bought at. Typing the place is what turns a
/// pin into an index: the same roastery seen across many cards.
nonisolated enum PlaceType: String, Codable, CaseIterable, Identifiable, Sendable {
    case roastery
    case cafe
    case shop
    case online

    var id: String { rawValue }

    var label: String {
        switch self {
        case .roastery: "Roastery"
        case .cafe: "Café"
        case .shop: "Shop"
        case .online: "Online"
        }
    }
}
