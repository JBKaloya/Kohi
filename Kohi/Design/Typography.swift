import SwiftUI

/// Museum-catalogue typography: Angusta titles against SF body.
enum Typography {
    /// Field labels in the caption block. Uppercase, tracked, monospaced.
    static let label = Font.system(size: 10, weight: .medium, design: .monospaced)

    /// Field values sitting opposite a label.
    static let value = Font.system(size: 14, weight: .regular)

    /// Display titles (coffee name, brand wordmark). Angusta DemiBold.
    static let title = Font.custom(AppFonts.angustaDemiBold, size: 25)

    /// Grid navigation wordmark.
    static let brand = Font.custom(AppFonts.angustaDemiBold, size: 28)

    /// Roaster line under the title.
    static let subtitle = Font.system(size: 13, weight: .regular)

    /// Body copy for personal notes.
    static let body = Font.system(size: 14, weight: .regular)

    /// Tasting note tags and other pill-shaped chrome.
    static let tag = Font.system(size: 11, weight: .medium, design: .monospaced)

    /// Coaching messages in the scan overlay.
    static let coaching = Font.system(size: 15, weight: .medium)

    /// The number you act on now: timer clock, pour target. 34 pt.
    static let number = Font.system(size: 34, weight: .regular)

    /// A step question in StepFlow.
    static let question = Font.system(size: 22, weight: .regular)

    /// Tracking applied to every uppercase label.
    static let labelTracking: CGFloat = 0.9
}

extension View {
    /// Invisible 44 pt tap floor that does not change the drawn size.
    func touchTarget(_ size: CGFloat = 44) -> some View {
        frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }
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
