import Foundation

/// How dark the roaster took the coffee, on the five notches the trade prints.
///
/// The single most useful field for suggesting a recipe: it sets the starting
/// water temperature and nudges the ratio (annexe G3). Optional on purpose —
/// plenty of cards never say.
nonisolated enum RoastLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case light
    case mediumLight
    case medium
    case mediumDark
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "Light"
        case .mediumLight: "Medium-light"
        case .medium: "Medium"
        case .mediumDark: "Medium-dark"
        case .dark: "Dark"
        }
    }

    /// Position on the scale, 0 (lightest) to 4 (darkest). What the recipe
    /// rules interpolate over.
    var notch: Int {
        switch self {
        case .light: 0
        case .mediumLight: 1
        case .medium: 2
        case .mediumDark: 3
        case .dark: 4
        }
    }
}
