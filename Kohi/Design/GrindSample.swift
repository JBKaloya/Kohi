import CoreGraphics
import Foundation
import SwiftUI

/// A little sachet of grounds. Fine is powder; coarse is chips you can count.
/// Driven by a µm band (annexe G1), with a 1 mm hairline so the pile has a scale.
struct GrindPreview: View {
    var microns: ClosedRange<Double>
    var position: Double
    var isSet = true
    /// Measured particle diameters in µm. Unused in 1.0 — section 9 phase B.
    var measured: [Double]? = nil

    var body: some View {
        let primary = Palette.primary
        let ink = Palette.ink
        let muted = Palette.inkMuted
        let dim = isSet ? 1.0 : 0.4
        let band = microns
        let t = position
        let sample = measured

        Canvas { context, size in
            let grains = GrindSampleField.particles(position: t, microns: band, measured: sample)
            for grain in grains {
                var copy = context
                let frame = grain.frame(in: size)
                copy.translateBy(x: frame.midX, y: frame.midY)
                copy.rotate(by: .radians(grain.rotation))
                copy.translateBy(x: -frame.midX, y: -frame.midY)
                copy.opacity = grain.opacity * dim
                copy.fill(Path(ellipseIn: frame), with: .color(Self.ink(grain.shade, primary, ink, muted)))
            }

            let millimetre = 6.4
            var tick = context
            tick.opacity = 0.55
            tick.stroke(
                Path { path in
                    let y = size.height - 4
                    path.move(to: CGPoint(x: 4, y: y))
                    path.addLine(to: CGPoint(x: 4 + millimetre, y: y))
                },
                with: .color(ink),
                lineWidth: 1
            )
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

/// Kept so existing call sites and the rail preview still compile.
typealias GrindSample = GrindPreview

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
        particles(position: position, microns: 400...700, measured: nil)
    }

    static func particles(
        position: Double,
        microns: ClosedRange<Double>,
        measured: [Double]? = nil
    ) -> [Grain] {
        let t = clamp(position)
        let mid = microns.lowerBound + (microns.upperBound - microns.lowerBound) * t
        let sizeT = clamp((mid - 180) / (1_300 - 180))
        let count = measured?.count ?? count(at: sizeT)
        let minSize = lerp(0.7, 3.2, sizeT)
        let maxSize = lerp(1.5, 8.0, sizeT)
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

        for index in 0..<count {
            let u = next()
            let v = next()
            let x = 0.5 + (u - 0.5) * lerp(0.92, 0.78, sizeT)
            let y = 0.5 + (v - 0.5) * lerp(0.92, 0.78, sizeT)
            let measuredSize = measured.flatMap { values -> Double? in
                guard index < values.count, values[index] > 0 else { return nil }
                return minSize + min(max((values[index] - microns.lowerBound)
                    / max(microns.upperBound - microns.lowerBound, 1), 0), 1)
                    * (maxSize - minSize)
            }
            let size = measuredSize ?? (minSize + next() * (maxSize - minSize))
            let stretch = lerp(1.0, 1.55, sizeT)
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
            GrindPreview(microns: 400...700, position: position)
        }
    }
    .padding(26)
    .background(Palette.paper)
}