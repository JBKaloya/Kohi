import SwiftUI
import UIKit

/// Named haptics for the moments that matter, so the vocabulary stays small and
/// each one keeps meaning the same thing.
enum Haptic: Sendable {
    /// The document tracker locked onto a card.
    case detectionLock
    /// The shutter fired.
    case capture
    /// A card was written to the archive.
    case saved
    /// A card touched down in the grid.
    case landing
    /// A card was removed.
    case deleted
    /// Grid density snapped to a new column count.
    case densityChange
    /// A card turned past its edge and showed its other face.
    case flip

    var feedback: SensoryFeedback {
        switch self {
        case .detectionLock: .impact(weight: .light)
        case .capture: .impact(weight: .medium)
        case .saved: .success
        case .landing: .impact(flexibility: .soft)
        case .deleted: .warning
        case .densityChange: .selection
        // Rigid: card stock is stiff, and the tap is the edge going past you.
        case .flip: .impact(flexibility: .rigid, intensity: 0.7)
        }
    }
}

enum Haptics {
    private static let warmup = UIImpactFeedbackGenerator(style: .light)

    /// Brings the Taptic Engine out of idle at launch so the first haptic of a
    /// session lands on time. `sensoryFeedback` owns its own generators; this
    /// only has to wake the hardware.
    static func prepare() {
        warmup.prepare()
    }
}

extension View {
    /// Fires a named haptic whenever `trigger` changes.
    func haptic<T: Equatable>(_ haptic: Haptic, trigger: T) -> some View {
        sensoryFeedback(haptic.feedback, trigger: trigger)
    }
}
