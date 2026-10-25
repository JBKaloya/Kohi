import CoreGraphics
import Foundation

/// Colour read off a pack. A small saturated mark and a bag that is itself
/// the colour are different answers; both are kept.
nonisolated struct PackInk: Equatable, Sendable {
    /// 0...1 around the wheel.
    var hue: Double
    /// Share of the image that belongs to this colour.
    var share: Double
    /// Share of the chromatic pixels that landed in the winning bins.
    var concentration: Double
    /// True when the colour is a printed mark. False when it is the bag.
    var isPrintedMark: Bool
    var red: Double
    var green: Double
    var blue: Double

    /// Below this, saturated pixels are JPEG noise, not ink.
    static let shareFloor = 0.005
    /// The winning hue has to own the chromatic pixels, not split them.
    static let concentrationFloor = 0.34
    /// Above this, the colour is the bag face rather than a mark printed on it.
    static let bagShare = 0.18
}

/// Reads brand ink from a pack photo. The title uses this; the symbol uses
/// `isPrintedMark` to refuse a bag that is simply blue.
nonisolated enum PackInkReader {
    struct Buffer: Sendable {
        var width: Int
        var height: Int
        var rgba: [UInt8]
    }

    static func read(_ image: CGImage) -> PackInk? {
        guard let buffer = buffer(image, maxSide: 64) else { return nil }
        return read(buffer)
    }

    static func buffer(_ image: CGImage, maxSide: Int) -> Buffer? {
        let longest = max(image.width, image.height)
        let scale = longest > maxSide ? Double(maxSide) / Double(longest) : 1
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Buffer(width: width, height: height, rgba: rgba)
    }

    static func read(_ buffer: Buffer) -> PackInk? {
        let bins = 24
        var histogram = [Int](repeating: 0, count: bins)
        let count = buffer.width * buffer.height
        guard count > 0 else { return nil }

        for index in 0..<count {
            let pixel = pixel(buffer.rgba, index: index)
            guard pixel.s > 0.32, (0.12...0.92).contains(pixel.v) else { continue }
            histogram[bin(pixel.h, bins: bins)] += 1
        }

        guard let primary = cluster(histogram, total: count) else { return nil }

        // A bag-sized colour can hide a smaller mark in another hue.
        // The mark, when it clears the floor, is the ink a title should take.
        // Saturation above 0.32 can under-count a bag that is only moderately
        // saturated, so a looser pass at the same hue can still call it the bag.
        if primary.share >= PackInk.bagShare || looseShare(buffer, around: primary.bin) >= PackInk.bagShare {
            var rest = histogram
            for offset in -1...1 {
                rest[wrap(primary.bin + offset, bins)] = 0
            }
            if let secondary = cluster(rest, total: count),
               secondary.share >= PackInk.shareFloor,
               secondary.concentration >= 0.40 {
                return ink(bin: secondary.bin, bins: bins, share: secondary.share, concentration: secondary.concentration, printed: true)
            }
            return ink(bin: primary.bin, bins: bins, share: primary.share, concentration: primary.concentration, printed: false)
        }

        let printed = looseShare(buffer, around: primary.bin) < PackInk.bagShare
        return ink(
            bin: primary.bin,
            bins: bins,
            share: primary.share,
            concentration: primary.concentration,
            printed: printed
        )
    }

    /// Share of the image near this hue, at a lower saturation than the ink pass.
    /// A coloured bag clears this; a small logo does not.
    private static func looseShare(_ buffer: Buffer, around bin: Int) -> Double {
        let bins = 24
        let count = buffer.width * buffer.height
        guard count > 0 else { return 0 }
        var owned = 0
        for index in 0..<count {
            let pixel = pixel(buffer.rgba, index: index)
            guard pixel.s > 0.15, (0.12...0.92).contains(pixel.v) else { continue }
            let distance = abs(self.bin(pixel.h, bins: bins) - bin)
            let wrapped = min(distance, bins - distance)
            if wrapped <= 1 { owned += 1 }
        }
        return Double(owned) / Double(count)
    }

    /// Dark enough to be a title on paper, still the measured hue.
    static func display(hue: Double) -> (Double, Double, Double) {
        rgb(h: hue, s: 0.62, v: 0.36)
    }

    static func hsv(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let maxV = max(r, g, b)
        let minV = min(r, g, b)
        let delta = maxV - minV
        let saturation = maxV == 0 ? 0 : delta / maxV
        var hue = 0.0
        if delta > 0.0001 {
            if maxV == r {
                hue = (g - b) / delta
            } else if maxV == g {
                hue = 2 + (b - r) / delta
            } else {
                hue = 4 + (r - g) / delta
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, saturation, maxV)
    }

    // MARK: - Histogram

    private struct Cluster {
        var bin: Int
        var share: Double
        var concentration: Double
    }

    private static func cluster(_ histogram: [Int], total: Int) -> Cluster? {
        let chromatic = histogram.reduce(0, +)
        guard chromatic > 0, let peak = histogram.max(), peak > 0,
              let bin = histogram.firstIndex(of: peak) else { return nil }
        var owned = 0
        for offset in -1...1 {
            owned += histogram[wrap(bin + offset, histogram.count)]
        }
        let share = Double(owned) / Double(total)
        let concentration = Double(owned) / Double(chromatic)
        guard share >= PackInk.shareFloor, concentration >= PackInk.concentrationFloor else { return nil }
        return Cluster(bin: bin, share: share, concentration: concentration)
    }

    private static func ink(bin: Int, bins: Int, share: Double, concentration: Double, printed: Bool) -> PackInk {
        let hue = (Double(bin) + 0.5) / Double(bins)
        let color = display(hue: hue)
        return PackInk(
            hue: hue,
            share: share,
            concentration: concentration,
            isPrintedMark: printed,
            red: color.0,
            green: color.1,
            blue: color.2
        )
    }

    private static func pixel(_ rgba: [UInt8], index: Int) -> (h: Double, s: Double, v: Double) {
        let base = index * 4
        let alpha = max(1, Int(rgba[base + 3]))
        let r = Double(rgba[base]) / Double(alpha)
        let g = Double(rgba[base + 1]) / Double(alpha)
        let b = Double(rgba[base + 2]) / Double(alpha)
        return hsv(r: r, g: g, b: b)
    }

    private static func bin(_ hue: Double, bins: Int) -> Int {
        let raw = Int(hue * Double(bins))
        return min(bins - 1, max(0, raw))
    }

    private static func wrap(_ value: Int, _ count: Int) -> Int {
        ((value % count) + count) % count
    }

    private static func rgb(h: Double, s: Double, v: Double) -> (Double, Double, Double) {
        let sector = h * 6
        let index = Int(sector) % 6
        let fraction = sector - Double(Int(sector))
        let p = v * (1 - s)
        let q = v * (1 - fraction * s)
        let t = v * (1 - (1 - fraction) * s)
        switch index {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}
