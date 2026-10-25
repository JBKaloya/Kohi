import CoreGraphics
import CoreImage
import Foundation
import Vision

/// A pack symbol as closed polygons. Drawn even-odd: holes are contours too.
/// Sharp at any size, which a few hundred pixels of bitmap are not.
nonisolated struct MarkShape: Codable, Equatable, Sendable {
    static let version = 1

    var version: Int
    /// Width / height of the crop.
    var aspect: Double
    /// Closed polygons, 0…1, origin at the top left.
    var contours: [[SIMD2<Float>]]

    var pointCount: Int { contours.reduce(0) { $0 + $1.count } }

    /// Corners softened by a quadratic through the segment midpoints. `rect` is in a
    /// y-down space (a flipped context, or SwiftUI).
    func path(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        func point(_ p: SIMD2<Float>) -> CGPoint {
            CGPoint(x: rect.minX + CGFloat(p.x) * rect.width, y: rect.minY + CGFloat(p.y) * rect.height)
        }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        for contour in contours where contour.count >= 3 {
            let points = contour.map(point)
            path.move(to: mid(points[points.count - 1], points[0]))
            for i in points.indices {
                let next = points[(i + 1) % points.count]
                path.addQuadCurve(to: mid(points[i], next), control: points[i])
            }
            path.closeSubpath()
        }
        return path
    }
}

/// The cut-out made soft: upsampled, blurred, soft threshold. Ink colour, continuous alpha.
nonisolated enum MarkMask {
    static let ink = (26.0, 24.0, 21.0)

    static func antialiased(_ binary: CGImage) -> CGImage? {
        let long = max(binary.width, binary.height)
        guard long > 0 else { return nil }
        let scale = min(4, max(2, Int((512.0 / Double(long)).rounded(.up))))
        let width = binary.width * scale
        let height = binary.height * scale
        guard let up = rgba(width: width, height: height) else { return nil }
        up.interpolationQuality = .high
        up.draw(binary, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let upscaled = up.makeImage() else { return nil }

        let input = CIImage(cgImage: upscaled)
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: 1.5).cropped(to: input.extent)
        guard let soft = ImagePipeline.context.createCGImage(blurred, from: input.extent) else { return nil }

        let coverage = alpha(of: soft)
        guard coverage.count == width * height else { return nil }
        guard let out = rgba(width: width, height: height), let base = out.data else { return nil }
        let row = out.bytesPerRow
        let bytes = base.bindMemory(to: UInt8.self, capacity: row * height)
        for y in 0..<height {
            for x in 0..<width {
                let f = Double(coverage[y * width + x]) / 255
                let a = min(1, max(0, (f - 0.35) / 0.30))
                guard a > 0 else { continue }
                let p = y * row + x * 4
                bytes[p] = UInt8((ink.0 * a).rounded())
                bytes[p + 1] = UInt8((ink.1 * a).rounded())
                bytes[p + 2] = UInt8((ink.2 * a).rounded())
                bytes[p + 3] = UInt8((a * 255).rounded())
            }
        }
        return out.makeImage()
    }

    /// Alpha bytes, top row first.
    static func alpha(of image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        guard let ctx = rgba(width: width, height: height), let base = ctx.data else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let row = ctx.bytesPerRow
        let bytes = base.bindMemory(to: UInt8.self, capacity: row * height)
        var out = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                out[y * width + x] = bytes[y * row + x * 4 + 3]
            }
        }
        return out
    }

    static func rgba(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}

nonisolated enum MarkVectorizer {
    static let maxPoints = 4000

    /// Nil when Vision finds nothing worth keeping, or a shape too heavy to draw.
    static func vectorize(_ mask: CGImage) -> MarkShape? {
        guard mask.width > 0, mask.height > 0, let onWhite = onWhite(mask) else { return nil }
        let aspect = Double(mask.width) / Double(mask.height)
        for epsilon: Float in [0.0008, 0.002, 0.004] {
            guard let contours = contours(onWhite, epsilon: epsilon) else { return nil }
            guard !contours.isEmpty else { return nil }
            let count = contours.reduce(0) { $0 + $1.count }
            if count <= maxPoints {
                return MarkShape(version: MarkShape.version, aspect: aspect, contours: contours)
            }
        }
        return nil
    }

    private static func contours(_ image: CGImage, epsilon: Float) -> [[SIMD2<Float>]]? {
        let request = VNDetectContoursRequest()
        request.detectsDarkOnLight = true
        request.contrastAdjustment = 1.0
        request.maximumImageDimension = min(2048, max(image.width, image.height))
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return [] }
        var out: [[SIMD2<Float>]] = []
        for index in 0..<observation.contourCount {
            guard let contour = try? observation.contour(at: index),
                  let simple = try? contour.polygonApproximation(epsilon: epsilon)
            else { continue }
            let points = simple.normalizedPoints
            guard points.count >= 4 else { continue }
            var minX = Float.greatestFiniteMagnitude, minY = Float.greatestFiniteMagnitude
            var maxX = -Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
            for p in points {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            guard (maxX - minX) * (maxY - minY) >= 0.0004 else { continue }
            out.append(points.map { SIMD2<Float>($0.x, 1 - $0.y) })
        }
        return out
    }

    /// Vision wants a dark drawing on a light ground.
    private static func onWhite(_ mask: CGImage) -> CGImage? {
        guard let ctx = MarkMask.rgba(width: mask.width, height: mask.height) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: mask.width, height: mask.height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(mask, in: rect)
        return ctx.makeImage()
    }
}
