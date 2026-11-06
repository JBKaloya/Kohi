import SwiftUI

/// The whole app lives on warm paper. Every colour in Kohi comes from here so the
/// archival feel can be retuned from a single file.
enum Palette {
    /// Background for the grid and the detail view. Warm off-white, not pure white.
    static let paper = Color(red: 0.980, green: 0.973, blue: 0.957)

    /// Slightly deeper paper, used behind the grid so cards read as objects laid on it.
    static let paperShade = Color(red: 0.965, green: 0.957, blue: 0.937)

    /// Primary text. Warm near-black rather than pure black.
    static let ink = Color(red: 0.102, green: 0.094, blue: 0.082)

    /// Caption labels, secondary values.
    static let inkMuted = Color(red: 0.541, green: 0.514, blue: 0.471)

    /// Hairline rules in the caption block.
    static let hairline = Color(red: 0.886, green: 0.867, blue: 0.827)

    /// A recess cut into the paper: ink at 5% mixed into paper, so a control
    /// reads as a well rather than a card laid on top. Keys inside it stay `paper`.
    static let well = Color(red: 0.936, green: 0.929, blue: 0.913)

    /// Cast by cards sitting on the paper.
    static let cardShadow = Color(red: 0.30, green: 0.26, blue: 0.20).opacity(0.22)

    /// Scan flow runs dark so the camera image carries the screen.
    static let scanBackdrop = Color(red: 0.055, green: 0.051, blue: 0.047)

    /// Comparison identity for brew A. Not chrome — buttons, tabs, and
    /// selection stay ink. `#824E34`.
    static let primary = Color(red: 130 / 255, green: 78 / 255, blue: 52 / 255)

    /// Comparison identity for brew B. Cooler than primary so the two
    /// overlays read apart on paper. `#3D5C56`.
    static let secondary = Color(red: 61 / 255, green: 92 / 255, blue: 86 / 255)
}
