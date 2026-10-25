import Foundation

/// How dark the roaster took the coffee, on the six notches the trade prints.
///
/// The single most useful field for suggesting a recipe: it sets the starting
/// water temperature and nudges the ratio (annexe G3). Optional on purpose —
/// plenty of cards never say.
nonisolated enum RoastLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case superLight
    case light
    case mediumLight
    case medium
    case mediumDark
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .superLight: "Super light"
        case .light: "Light"
        case .mediumLight: "Medium light"
        case .medium: "Medium"
        case .mediumDark: "Medium dark"
        case .dark: "Dark"
        }
    }

    /// Position on the scale, 0 (lightest) to 5 (darkest). What the recipe
    /// rules interpolate over.
    var notch: Int {
        switch self {
        case .superLight: 0
        case .light: 1
        case .mediumLight: 2
        case .medium: 3
        case .mediumDark: 4
        case .dark: 5
        }
    }

    /// Median Agtron for the cran, used to pre-fill when the bag did not print one.
    var suggestedAgtron: Int {
        switch self {
        case .superLight: 95
        case .light: 85
        case .mediumLight: 75
        case .medium: 65
        case .mediumDark: 55
        case .dark: 45
        }
    }
}
