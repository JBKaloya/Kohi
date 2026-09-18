import CoreGraphics
import Foundation
import SwiftUI

/// A little sachet of grounds. Fine is powder; coarse is chips you can count.
/// Same 0…1 as the rail: extra-fine on the left, extra-coarse on the right.
struct GrindSample: View {
    var position: Double
    var isSet = true

    var body: some View {
        let primary = Palette.primary
        let ink = Palette.ink
        let muted = Palette.inkMuted
        let dim = isSet ? 1.0 : 0.4

        Canvas { context, size in
            for grain in GrindSampleField.particles(position: position) {
                var copy = context
                let frame = grain.frame(in: size)
                copy.translateBy(x: frame.midX, y: frame.midY)
                copy.rotate(by: .radians(grain.rotation))
                copy.translateBy(x: -frame.midX, y: -frame.midY)
                copy.opacity = grain.opacity * dim
                copy.fill(Path(ellipseIn: frame), with: .color(Self.ink(grain.shade, primary, ink, muted)))
            }
        }
        .frame(width: 44, height: 44)
        .background(Palette.paperShade)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private static func ink(_ shade: Double, _ primary: Color, _ ink: Color, _ muted: Color) -> Color {
        if shade < 0.35 { return primary }
        if shade < 0.75 { return ink }
        return muted
    }
}

/// Deterministic grounds so the pile does not reshuffle while you drag.
///
/// The module defaults to MainActor (`SWIFT_DEFAULT_ACTOR_ISOLATION`). This
/// type stays off it so tests and the canvas renderer can both ask for a pile.
nonisolated enum GrindSampleField: Sendable {
    struct Grain: Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var rotation: Double
        var opacity: Double
        var shade: Double

        func frame(in size: CGSize) -> CGRect {
            CGRect(
                x: x * size.width - width / 2,
                y: y * size.height - height / 2,
                width: width,
                height: height
            )
        }
    }

    static func count(at position: Double) -> Int {
        Int(lerp(96, 16, clamp(position)).rounded())
    }

    static func particles(position: Double) -> [Grain] {
        let t = clamp(position)
        let count = count(at: t)
        let minSize = lerp(0.7, 3.2, t)
        let maxSize = lerp(1.5, 8.0, t)
        var state: UInt64 = 0x6B6F6869
        func next() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z ^= z >> 31
            return Double(z) / Double(UInt64.max)
        }

        var grains: [Grain] = []
        grains.reserveCapacity(count)

        for _ in 0..<count {
            let u = next()
            let v = next()
            let x = 0.5 + (u - 0.5) * lerp(0.92, 0.78, t)
            let y = 0.5 + (v - 0.5) * lerp(0.92, 0.78, t)
            let size = minSize + next() * (maxSize - minSize)
            let stretch = lerp(1.0, 1.55, t)
            let width = size * (0.75 + next() * stretch)
            let height = size * (0.7 + next() * 0.6)
            let shade = next()
            grains.append(
                Grain(
                    x: min(max(x, 0.06), 0.94),
                    y: min(max(y, 0.06), 0.94),
                    width: width,
                    height: height,
                    rotation: next() * .pi,
                    opacity: lerp(0.45, 0.92, shade),
                    shade: shade
                )
            )
        }
        return grains
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}

#Preview {
    HStack(spacing: 16) {
        ForEach([0.0, 0.35, 0.7, 1.0], id: \.self) { position in
            GrindSample(position: position)
        }
    }
    .padding(26)
    .background(Palette.paper)
}
