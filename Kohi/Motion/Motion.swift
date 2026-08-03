import SwiftUI

/// Every animation in Kohi comes from this file, and so does every number that
/// describes how something moves, tilts, lifts or casts a shadow. The point is
/// that the feel of the app can be retuned here without opening a single view.
///
/// Springs live at the top level. Everything else is grouped by the surface it
/// belongs to.
enum Motion {

    // MARK: - Springs

    /// Taps, press states, tag toggles. Critically damped, no overshoot.
    static let quick = Animation.spring(response: 0.22, dampingFraction: 1.0)

    /// Density changes, sheet content, coaching label swaps.
    static let snappy = Animation.spring(response: 0.35, dampingFraction: 0.82)

    /// Hero transition and other large surfaces.
    static let gentle = Animation.spring(response: 0.55, dampingFraction: 0.9)

    /// Deliberate overshoot. Reserved for a card landing in the grid.
    static let land = Animation.spring(response: 0.70, dampingFraction: 0.62)

    /// Tracks a finger. Used while a drag is in flight so it stays interruptible.
    static let tracking = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.86)

    /// Staggered delay for a run of elements, capped so long lists never crawl.
    static func stagger(_ index: Int, step: Double = 0.035, cap: Double = 0.28) -> Double {
        min(Double(index) * step, cap)
    }

    // MARK: - Grid tile

    /// A card lying on the paper in the grid, and the way a new one arrives.
    ///
    /// The landing values are all expressed as "where the card starts", and are
    /// interpolated to rest by a single 0-to-1 `landing` progress.
    enum Tile {
        /// Scale while a tile is held down.
        static let pressScale: CGFloat = 0.965

        /// How much bigger the card is at the top of its descent.
        static let landScale: CGFloat = 0.22
        /// How far above its resting place the card starts, in points.
        static let landLift: CGFloat = 34
        /// Opacity at the top of the descent.
        static let landOpacity: Double = 0.2

        /// Shadow opacity, as a fraction of `Palette.cardShadow`, in the air and at rest.
        static let shadowOpacity = (air: 0.55, rest: 1.0)
        /// Shadow radius as a fraction of tile width, in the air and at rest.
        static let shadowRadius = (air: 0.16, rest: 0.045)
        /// Shadow drop as a fraction of tile width, in the air and at rest.
        static let shadowDrop = (air: 0.10, rest: 0.022)

        /// The spring overshoots for a while after contact, so the haptic is
        /// fired on this delay rather than at the end of the animation.
        static let touchdown = Duration.milliseconds(190)
        /// How long a tile stays marked as newly landed.
        static let landingWindow = Duration.milliseconds(1100)

        /// Interpolates an air value to a rest value over the landing progress.
        static func settle(_ pair: (air: Double, rest: Double), _ landing: Double) -> Double {
            pair.air + (pair.rest - pair.air) * landing
        }
    }

    // MARK: - The card as an object in the detail view

    enum Object {
        /// Card width as a fraction of the screen.
        static let widthFraction: CGFloat = 0.68
        /// Resting shadow radius and drop, as fractions of card width.
        static let shadowRadius: CGFloat = 0.06
        static let shadowDrop: CGFloat = 0.03
    }

    // MARK: - Tilting the card with the phone

    enum Parallax {
        /// Device motion samples per second.
        static let updateInterval: TimeInterval = 1.0 / 60.0
        /// Tilt in radians that maps to the full effect. Beyond this it clamps,
        /// so the card never slides off its own shadow.
        static let range: Double = 0.5
        /// Low-pass factor applied to each sample. Lower is smoother and later.
        static let smoothing: Double = 0.12

        /// How far the card slides, in points, at full tilt.
        static let shift: CGFloat = 10
        /// How far the shadow slides against the card, which is what lifts it.
        static let shadowCounterShift: CGFloat = 6
        /// Degrees of 3D rotation at full tilt.
        static let tilt: Double = 5
        /// Perspective for that rotation. Smaller is a longer lens.
        static let perspective: CGFloat = 0.5

        /// Peak opacity of the sheen sliding across the card.
        static let sheenOpacity: Double = 0.16
        /// Width of the sheen band as a fraction of the card.
        static let sheenWidth: CGFloat = 0.55
        /// How far the sheen travels across the card at full tilt.
        static let sheenTravel: CGFloat = 1.1
    }

    // MARK: - Turning the card over

    enum Flip {
        /// Fraction of a full turn a drag must cover to complete the flip.
        static let threshold: Double = 0.25
        /// Drag distance, in points, that maps to a full 180 degree turn.
        static let dragDistance: CGFloat = 220
        /// Perspective during the turn. Stronger than the parallax so the card
        /// visibly has a near and a far edge.
        static let perspective: CGFloat = 0.7
        /// The turn itself. Heavier than `quick`, no overshoot past the face.
        static let animation = Animation.spring(response: 0.45, dampingFraction: 0.86)
        /// A drag must clear this before it counts as a flip rather than a scroll.
        static let minimumDrag: CGFloat = 8
    }

    // MARK: - The grid itself

    enum Grid {
        /// Pinch magnification is damped before it scales the grid, so a fast
        /// gesture does not throw the layout off screen before it snaps.
        static let pinchDamping: CGFloat = 0.55
        static let pinchClamp: ClosedRange<CGFloat> = 0.72...1.5
        static let minimumScaleDelta: CGFloat = 0.02
        /// How many cards to render at the next density before a pinch lands.
        static let prewarmCount = 40
    }

    // MARK: - Scan overlay

    /// The outline tightens as the lock completes, so each of these is a pair
    /// of "searching" and "locked" values.
    enum Overlay {
        static let fillOpacity = (open: 0.06, locked: 0.16)
        static let strokeOpacity = (open: 0.55, locked: 1.0)
        static let strokeWidth = (open: 1.5, locked: 3.0)
        static let tickLength = (open: 16.0, locked: 28.0)
        static let tickWidth = (open: 2.5, locked: 4.0)

        static func settle(_ pair: (open: Double, locked: Double), _ progress: Double) -> Double {
            pair.open + (pair.locked - pair.open) * progress
        }
    }

    // MARK: - Chrome

    enum Chrome {
        /// Scale while the floating scan button is held.
        static let buttonPressScale: CGFloat = 0.92
        /// Scale while the shutter is held.
        static let shutterPressScale: CGFloat = 0.88
        /// The empty state fades up slightly late, so it does not race the grid.
        static let emptyStateRise: CGFloat = 14
        static let emptyStateDelay: Double = 0.12
    }
}
