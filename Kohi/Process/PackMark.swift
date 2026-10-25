import CoreGraphics
import Foundation

/// A symbol isolated by the ink hue, not by a darkness threshold.
/// The darkness chain stays for black type; this one is for a coloured mark
/// that is too small for that chain's area floor.
nonisolated enum PackMark {
    /// Bbox share of the pack. The clover sits near 1%; a bag face sits past 18%.
    static let areaFloor = 0.008
    static let areaCeiling = 0.18

    static func extract(_ image: CGImage) -> InkStampPipeline.Drawing? {
        guard let analysis = PackInkReader.buffer(image, maxSide: 96),
              let ink = PackInkReader.read(analysis),
              ink.isPrintedMark else { return nil }

        let width = analysis.width
        let height = analysis.height
        let count = width * height
        var mask = [Bool](repeating: false, count: count)
        for index in 0..<count {
            let pixel = hsv(analysis.rgba, index: index)
            guard pixel.s > 0.32, (0.12...0.92).contains(pixel.v) else { continue }
            let distance = hueDistance(pixel.h, ink.hue)
            if distance <= (1.5 / 24) {
                mask[index] = true
            }
        }

        guard let component = largestComponent(mask, width: width, height: height) else { return nil }
        let boxArea = component.width * component.height
        let packArea = count
        guard packArea > 0, boxArea > 0 else { return nil }
        let areaRatio = Double(boxArea) / Double(packArea)
        let coverage = Double(component.pixels) / Double(boxArea)
        let aspect = Double(component.width) / Double(component.height)
        guard (areaFloor...areaCeiling).contains(areaRatio) else { return nil }
        guard (0.18...1).contains(coverage) else { return nil }
        guard (0.35...2.8).contains(aspect) else { return nil }
        // A component that spans the frame is the bag, whatever the hue said.
        if component.width > Int(Double(width) * 0.85), component.height > Int(Double(height) * 0.85) {
            return nil
        }

        guard let rendered = render(
            image: image,
            analysis: analysis,
            component: component,
            hue: ink.hue
        ) else { return nil }

        let rect = CGRect(
            x: Double(component.minX) / Double(width),
            y: Double(component.minY) / Double(height),
            width: Double(component.width) / Double(width),
            height: Double(component.height) / Double(height)
        )
        return InkStampPipeline.Drawing(
            image: rendered,
            rect: rect,
            metrics: InkStamp.Metrics(coverage: coverage, areaRatio: areaRatio, components: 1),
            placement: .sticker,
            fromChroma: true
        )
    }

    /// The word rule still applies. The area floor does not: that floor was
    /// built for a darkness drawing, and it rejects a clover.
    static func accepted(_ metrics: InkStamp.Metrics, words: [String]) -> Bool {
        guard (0.18...1).contains(metrics.coverage) else { return false }
        guard (areaFloor...areaCeiling).contains(metrics.areaRatio) else { return false }
        guard metrics.components > 0, metrics.components < 20 else { return false }
        guard !words.contains(where: { $0.count >= 3 }) else { return false }
        return true
    }

    // MARK: - Components

    private struct Component {
        var minX: Int
        var minY: Int
        var width: Int
        var height: Int
        var pixels: Int
    }

    /// Four-connected. No erosion: a one-pixel eat is what thins an outline
    /// down until the fill test fails.
    private static func largestComponent(_ mask: [Bool], width: Int, height: Int) -> Component? {
        let count = width * height
        var seen = [Bool](repeating: false, count: count)
        var best: Component?
        var stack: [Int] = []
        stack.reserveCapacity(256)

        for start in 0..<count where mask[start] && !seen[start] {
            seen[start] = true
            stack.append(start)
            var pixels = 0
            var minX = width
            var minY = height
            var maxX = 0
            var maxY = 0
            var cursor = 0
            while cursor < stack.count {
                let index = stack[cursor]
                cursor += 1
                pixels += 1
                let x = index % width
                let y = index / width
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                for neighbor in [index - 1, index + 1, index - width, index + width] {
                    guard neighbor >= 0, neighbor < count, mask[neighbor], !seen[neighbor] else { continue }
                    if neighbor == index - 1, x == 0 { continue }
                    if neighbor == index + 1, x == width - 1 { continue }
                    seen[neighbor] = true
                    stack.append(neighbor)
                }
            }
            stack.removeAll(keepingCapacity: true)
            guard pixels >= 8 else { continue }
            let component = Component(
                minX: minX,
                minY: minY,
                width: maxX - minX + 1,
                height: maxY - minY + 1,
                pixels: pixels
            )
            if component.pixels > (best?.pixels ?? 0) {
                best = component
            }
        }
        return best
    }

    /// Cuts the mark from the original at its own resolution and paints the
    /// ink pixels black. Contours stay; nothing is eaten back.
    private static func render(
        image: CGImage,
        analysis: PackInkReader.Buffer,
        component: Component,
        hue: Double
    ) -> CGImage? {
        let scaleX = Double(image.width) / Double(analysis.width)
        let scaleY = Double(image.height) / Double(analysis.height)
        let crop = CGRect(
            x: Double(component.minX) * scaleX,
            y: Double(component.minY) * scaleY,
            width: Double(component.width) * scaleX,
            height: Double(component.height) * scaleY
        ).integral
        guard crop.width >= 2, crop.height >= 2 else { return nil }
        let width = Int(crop.width)
        let height = Int(crop.height)
        guard let cropped = image.cropping(to: crop) else { return nil }

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
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        for index in 0..<(width * height) {
            let pixel = hsv(rgba, index: index)
            let base = index * 4
            let matches = pixel.s > 0.32 && (0.12...0.92).contains(pixel.v) && hueDistance(pixel.h, hue) <= (1.5 / 24)
            if matches {
                rgba[base] = 26
                rgba[base + 1] = 24
                rgba[base + 2] = 21
                rgba[base + 3] = 255
            } else {
                rgba[base] = 0
                rgba[base + 1] = 0
                rgba[base + 2] = 0
                rgba[base + 3] = 0
            }
        }
        return ctx.makeImage()
    }

    private static func hsv(_ rgba: [UInt8], index: Int) -> (h: Double, s: Double, v: Double) {
        let base = index * 4
        let alpha = max(1, Int(rgba[base + 3]))
        return PackInkReader.hsv(
            r: Double(rgba[base]) / Double(alpha),
            g: Double(rgba[base + 1]) / Double(alpha),
            b: Double(rgba[base + 2]) / Double(alpha)
        )
    }

    private static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let delta = abs(a - b)
        return min(delta, 1 - delta)
    }
}
