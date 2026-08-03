import SwiftUI

/// Museum-catalogue typography: monospaced small-caps labels against plain values.
enum Typography {
    /// Field labels in the caption block. Uppercase, tracked, monospaced.
    static let label = Font.system(size: 10, weight: .medium, design: .monospaced)

    /// Field values sitting opposite a label.
    static let value = Font.system(size: 14, weight: .regular)

    /// The coffee name at the head of the caption block.
    static let title = Font.system(size: 20, weight: .medium)

    /// Roaster line under the title.
    static let subtitle = Font.system(size: 13, weight: .regular)

    /// Body copy for personal notes.
    static let body = Font.system(size: 14, weight: .regular)

    /// Tasting note tags and other pill-shaped chrome.
    static let tag = Font.system(size: 11, weight: .medium, design: .monospaced)

    /// Coaching messages in the scan overlay.
    static let coaching = Font.system(size: 15, weight: .medium)

    /// Tracking applied to every uppercase label.
    static let labelTracking: CGFloat = 0.9
}

extension View {
    /// Applies the catalogue label treatment: uppercase, tracked, muted.
    func catalogueLabel() -> some View {
        font(Typography.label)
            .tracking(Typography.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(Palette.inkMuted)
    }
}
