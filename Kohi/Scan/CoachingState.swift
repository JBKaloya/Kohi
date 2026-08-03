import CoreGraphics
import Foundation

/// Everything the auto-capture behaviour is tuned by, in one place. These are
/// feel decisions, not physics, and they are meant to be nudged.
nonisolated enum ScanTuning {
    /// Below this share of the frame the card is too small to read.
    static let minimumAreaFraction: CGFloat = 0.22
    /// Opposite edges may differ by this ratio before the angle is too steep.
    static let maximumSkew: CGFloat = 1.42
    /// Mean corner movement between frames, as a fraction of frame width.
    static let maximumDrift: CGFloat = 0.014
    /// How many recent quads the steadiness check looks at.
    static let driftWindow = 6
    /// Luminance above which a pixel counts as blown out.
    static let glareLevel: CGFloat = 0.97
    /// Share of blown-out pixels that counts as glare.
    static let glareFraction: CGFloat = 0.03
    /// How long everything must stay good before the shutter fires.
    static let lockDuration: TimeInterval = 0.6
    /// Detections below this are ignored entirely.
    static let minimumConfidence: Float = 0.35
    /// Smoothing applied to the drawn quad. Higher follows the card faster.
    static let smoothing: CGFloat = 0.45
}

/// What the overlay is telling you to do. Ordered by how much it matters, so
/// only one thing is ever on screen.
nonisolated enum CoachingState: Equatable, Sendable {
    case searching
    case closer
    case straighten
    case glare
    case holdStill
    case locking(progress: Double)

    var message: String {
        switch self {
        case .searching: "Place a card on a flat surface"
        case .closer: "Move closer"
        case .straighten: "Hold the phone level"
        case .glare: "Tilt away from the light"
        case .holdStill: "Hold still"
        case .locking: "Hold still"
        }
    }

    /// True once a card is in frame at all, which is when the overlay appears.
    var hasCard: Bool {
        self != .searching
    }

    var progress: Double {
        if case .locking(let progress) = self { return progress }
        return 0
    }
}
