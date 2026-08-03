import CoreGraphics
import Foundation

/// How many cards sit across the screen. Pinching moves between these.
enum GridDensity: Int, CaseIterable, Comparable, Sendable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4

    var columns: Int { rawValue }

    /// Whitespace is what makes the grid read as endless, so it stays generous
    /// even at the tightest density.
    var spacing: CGFloat {
        switch self {
        case .one: 56
        case .two: 34
        case .three: 24
        case .four: 17
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .one: 44
        case .two: 30
        case .three: 22
        case .four: 16
        }
    }

    /// Where a pinch lands. Magnifying past 1 means bigger cards, so fewer columns.
    func stepped(by magnification: CGFloat) -> GridDensity {
        guard magnification > 0 else { return self }
        let target = (Double(columns) / Double(magnification)).rounded()
        let clamped = Int(min(max(target, 1), Double(GridDensity.four.rawValue)))
        return GridDensity(rawValue: clamped) ?? self
    }

    static func < (lhs: GridDensity, rhs: GridDensity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
