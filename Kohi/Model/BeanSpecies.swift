import Foundation

/// Botanical species of the bean. Recorded on the card when the roaster prints
/// it; no control in the form, and no longer used for any estimate.
nonisolated enum BeanSpecies: String, Codable, CaseIterable, Identifiable, Sendable {
    case arabica
    case robusta

    var id: String { rawValue }

    var label: String {
        switch self {
        case .arabica: "Arabica"
        case .robusta: "Robusta"
        }
    }
}
