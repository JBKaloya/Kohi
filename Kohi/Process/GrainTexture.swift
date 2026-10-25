import CoreGraphics
import Foundation

/// Print grain, 256 × 256, made once from a fixed seed. Near-gaussian noise around
/// mid grey, plus a sprinkle of airbrush spatter.
nonisolated enum GrainTexture {
    static let seed: UInt32 = 20261025
    static let size = 256

    static let tile: CGImage? = make()

    private static func make() -> CGImage? {
        var rnd = Mulberry32(seed: seed)
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<(size * size) {
            let g = (rnd.unit() + rnd.unit() + rnd.unit() - 1.5) * 1.15
            let sparkle: Double = rnd.unit() < 0.012 ? (rnd.unit() < 0.5 ? -70 : 70) : 0
            let v = UInt8(min(255, max(0, (128 + g * 52 + sparkle).rounded())))
            bytes[i * 4] = v
            bytes[i * 4 + 1] = v
            bytes[i * 4 + 2] = v
        }
        guard let ctx = MarkMask.rgba(width: size, height: size), let base = ctx.data else { return nil }
        let row = ctx.bytesPerRow
        let out = base.bindMemory(to: UInt8.self, capacity: row * size)
        for y in 0..<size {
            for x in 0..<(size * 4) {
                out[y * row + x] = bytes[y * size * 4 + x]
            }
        }
        return ctx.makeImage()
    }
}
