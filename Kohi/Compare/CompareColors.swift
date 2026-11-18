import SwiftUI

/// The colour of each series in a comparison. A coffee keeps the main colour
/// of its card; a series without a card takes the palette, primary first.
/// When two colours read as one, the later is moved: lighter for the second,
/// darker for the third. Line style and marker still tell them apart.
nonisolated enum CompareColors {
    /// Below this OKLab distance two inks read as the same on paper.
    static let minimumDistance = 0.09
    /// How far one shift moves the lightness.
    static let lightnessStep = 0.14

    static let primary = OKLab.fromSRGB(130 / 255, 78 / 255, 52 / 255)
    static let secondary = OKLab.fromSRGB(61 / 255, 92 / 255, 86 / 255)

    /// One ink per series, in order. `cardInks[i]` is nil when the series has
    /// no card.
    static func inks(_ cardInks: [SIMD3<Double>?]) -> [SIMD3<Double>] {
        var fallbacks = [primary, secondary].makeIterator()
        var out: [SIMD3<Double>] = []
        for (index, card) in cardInks.enumerated() {
            var ink = card ?? fallbacks.next() ?? primary
            var tries = 0
            while tries < 3, out.contains(where: { distance($0, ink) < minimumDistance }) {
                let step = index == 1 ? lightnessStep : -lightnessStep
                ink.x = min(max(ink.x + step, 0.2), 0.9)
                tries += 1
            }
            out.append(ink)
        }
        return out
    }

    static func distance(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let d = a - b
        return (d * d).sum().squareRoot()
    }

    static func color(_ ink: SIMD3<Double>) -> Color {
        let rgb = OKLab.toSRGB(ink)
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
}

/// How a series is told apart without its colour.
nonisolated enum SeriesStyle: Int, CaseIterable, Sendable {
    case solid, dashed, dotted

    static func at(_ index: Int) -> SeriesStyle {
        allCases[index % allCases.count]
    }

    var dash: [CGFloat] {
        switch self {
        case .solid: []
        case .dashed: [5, 3]
        case .dotted: [1.2, 2.6]
        }
    }

    enum Marker: Sendable { case circle, square, triangle }

    var marker: Marker {
        switch self {
        case .solid: .circle
        case .dashed: .square
        case .dotted: .triangle
        }
    }

    var spoken: String {
        switch self {
        case .solid: "solid line, round points"
        case .dashed: "dashed line, square points"
        case .dotted: "dotted line, triangle points"
        }
    }
}
