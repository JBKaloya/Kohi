import CoreGraphics
import CoreMedia
import Foundation

/// Four corners of a detected card, in image pixel coordinates with a top-left
/// origin.
nonisolated struct Quad: Sendable, Equatable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    /// Rough area as a fraction of an image of `size`.
    func areaFraction(in size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 0 }
        let points = corners
        var area: CGFloat = 0
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            area += a.x * b.y - b.x * a.y
        }
        return abs(area) / 2 / (size.width * size.height)
    }

    /// How far off rectangular the quad is: 1 is square-on, larger is more skewed.
    var skew: CGFloat {
        let top = topLeft.distance(to: topRight)
        let bottom = bottomLeft.distance(to: bottomRight)
        let left = topLeft.distance(to: bottomLeft)
        let right = topRight.distance(to: bottomRight)
        let horizontal = max(top, bottom) / max(min(top, bottom), 0.001)
        let vertical = max(left, right) / max(min(left, right), 0.001)
        return max(horizontal, vertical)
    }

    /// Mean corner displacement against another quad, normalised by `size`.
    func drift(from other: Quad, in size: CGSize) -> CGFloat {
        guard size.width > 0 else { return .greatestFiniteMagnitude }
        let total = zip(corners, other.corners).reduce(CGFloat.zero) { $0 + $1.0.distance(to: $1.1) }
        return total / CGFloat(corners.count) / size.width
    }

    func scaled(by factor: CGFloat) -> Quad {
        Quad(
            topLeft: topLeft.scaled(by: factor),
            topRight: topRight.scaled(by: factor),
            bottomRight: bottomRight.scaled(by: factor),
            bottomLeft: bottomLeft.scaled(by: factor)
        )
    }

    /// The whole of an image of `size`, inset by a fraction of its short edge.
    /// Where the adjustable quad starts when nothing was detected.
    static func inset(in size: CGSize, by fraction: CGFloat = 0.08) -> Quad {
        let margin = min(size.width, size.height) * fraction
        return Quad(
            topLeft: CGPoint(x: margin, y: margin),
            topRight: CGPoint(x: size.width - margin, y: margin),
            bottomRight: CGPoint(x: size.width - margin, y: size.height - margin),
            bottomLeft: CGPoint(x: margin, y: size.height - margin)
        )
    }

    /// Replaces one corner, addressed positionally so a drag can stay generic.
    subscript(index: Int) -> CGPoint {
        get {
            switch index {
            case 0: topLeft
            case 1: topRight
            case 2: bottomRight
            default: bottomLeft
            }
        }
        set {
            switch index {
            case 0: topLeft = newValue
            case 1: topRight = newValue
            case 2: bottomRight = newValue
            default: bottomLeft = newValue
            }
        }
    }
}

nonisolated extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }

    func scaled(by factor: CGFloat) -> CGPoint {
        CGPoint(x: x * factor, y: y * factor)
    }
}

/// A frame on its way from the capture queue to the detector.
///
/// `CMSampleBuffer` is not `Sendable`, but this hand-off is safe by
/// construction: the capture callback drops frames while one is in flight, so
/// exactly one frame is ever owned at a time, and nothing here mutates it.
nonisolated struct VideoFrame: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer
}

/// What a capture hands back, whichever camera produced it.
nonisolated struct CapturedCard: Sendable {
    let image: CGImage
    /// Corners of the card within `image`. Nil when the source already deskewed
    /// the page for us, which is the case for the VisionKit stand-in.
    let quad: Quad?

    /// Pixel size of the still, which is the space `quad` is expressed in.
    var pixelSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }

    /// Accepts the capture exactly as detected, without going through review.
    /// Only the debug auto-scan path uses this.
    func reviewed(enhance: Bool) -> ScanResult {
        ScanResult(image: image, quad: quad ?? .inset(in: pixelSize), enhance: enhance)
    }
}

/// What the review step confirms: the same still, but with corners you have
/// seen and can have moved, and a decision about the scan look.
///
/// Separate from `CapturedCard` on purpose. One is what the camera saw, the
/// other is what you agreed to keep.
nonisolated struct ScanResult: Sendable {
    let image: CGImage
    /// Not optional: review always produces corners, even if they are the
    /// whole frame.
    let quad: Quad
    let enhance: Bool
}

/// Which camera the scan flow uses.
///
/// This exists so the two implementations can be swapped in one place. The
/// VisionKit stand-in got the loop working end to end; the custom camera is what
/// the app is actually for.
nonisolated enum ScanSource: Sendable {
    case visionKit
    case camera

    static let preferred: ScanSource = .camera
}
