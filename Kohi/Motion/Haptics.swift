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
    /// A card was removed, or a save was refused (name too short).
    case deleted
    /// Grid density snapped to a new column count.
    case densityChange
    /// A discrete button press in the brew sheet (chips, rating, axes, More, timer start/stop).
    case tap
    /// One second elapsed on the running brew timer.
    case tick
    /// The guided timer moved to the next step of a recipe.
    case stepAdvance
    /// Dictation started or stopped listening.
    case listening

    var feedback: SensoryFeedback {
        switch self {
        case .detectionLock: .impact(weight: .light)
        case .capture: .impact(weight: .medium)
        case .saved: .success
        case .landing: .impact(flexibility: .soft)
        case .deleted: .warning
        case .densityChange: .selection
        case .tap: .impact(weight: .medium)
        case .tick: .impact(weight: .light)
        case .stepAdvance: .impact(weight: .light)
        case .listening: .selection
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

private struct KohiHapticsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Snapshots turn this off: `sensoryFeedback` traps in the simulator
    /// when the Taptic Engine is still cold.
    var kohiHapticsEnabled: Bool {
        get { self[KohiHapticsEnabledKey.self] }
        set { self[KohiHapticsEnabledKey.self] = newValue }
    }
}

extension View {
    /// Fires a named haptic whenever `trigger` changes.
    func haptic<T: Equatable>(_ haptic: Haptic, trigger: T) -> some View {
        modifier(NamedHaptic(haptic: haptic, trigger: trigger))
    }
}

private struct NamedHaptic<T: Equatable>: ViewModifier {
    var haptic: Haptic
    var trigger: T
    @Environment(\.kohiHapticsEnabled) private var enabled

    func body(content: Content) -> some View {
        if enabled {
            content.sensoryFeedback(haptic.feedback, trigger: trigger)
        } else {
            content
        }
    }
}
