import CoreGraphics
import Foundation

/// The ground of a Kohi card: the field, the symbol, print grain, a whisper of vignette.
/// CoreGraphics only, safe off the main thread, no Metal: ImageRenderer and snapshots stay plain.
nonisolated enum CardBackdrop {
    enum TextTone: String, Sendable {
        /// The top of the field reads light: ink text.
        case ink
        /// The top of the field reads dark: paper text.
        case paper
    }

    struct Rendered: @unchecked Sendable {
        var image: CGImage
        var textTone: TextTone
        /// Present only when the emboss edges were asked for separately.
        var edges: SymbolLayer.EmbossEdges?
    }

    static let fieldWidth = 96
    static let fieldHeight = 120

    /// Tile canvas: 360 pt at @3x.
    static let tilePixels = CGSize(width: 1080, height: 1350)

    static func render(
        _ art: CardArt,
        mark: MarkSource?,
        treatment: SymbolTreatment,
        size: CGSize,
        separateEmbossEdges: Bool = false
    ) -> Rendered? {
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        guard width > 0, height > 0,
              let (field, tone) = lowField(art),
              let ctx = MarkMask.rgba(width: width, height: height)
        else { return nil }
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let W = Double(width), H = Double(height)

        ctx.interpolationQuality = .high
        ctx.draw(field, in: full)

        var edges: SymbolLayer.EmbossEdges?
        if let mark, treatment != .none {
            edges = SymbolLayer.draw(
                in: ctx, art: art, mark: mark, treatment: treatment,
                width: width, height: height, lightGround: tone == .ink,
                separateEdges: separateEmbossEdges
            )
        }

        if let grain = GrainTexture.tile {
            ctx.saveGState()
            ctx.setBlendMode(.overlay)
            ctx.setAlpha(art.process.grainOverlay)
            let side = Double(GrainTexture.size) * W / 720
            ctx.draw(grain, in: CGRect(x: 0, y: 0, width: side, height: side), byTiling: true)
            ctx.restoreGState()
        }

        vignette(ctx, width: W, height: H)

        guard let image = ctx.makeImage() else { return nil }
        return Rendered(image: image, textTone: tone, edges: edges)
    }

    /// The field alone, scaled to `size`. What a tile shows while it waits.
    static func field(_ art: CardArt, size: CGSize) -> CGImage? {
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        guard width > 0, height > 0,
              let (low, _) = lowField(art),
              let ctx = MarkMask.rgba(width: width, height: height)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(low, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    static func textTone(_ art: CardArt) -> TextTone {
        lowField(art)?.1 ?? .ink
    }

    /// 96 × 120 evaluations: a gradient has no detail, low definition is the right one.
    static func lowField(_ art: CardArt) -> (CGImage, TextTone)? {
        let w = fieldWidth, h = fieldHeight
        guard let ctx = MarkMask.rgba(width: w, height: h), let base = ctx.data else { return nil }
        let row = ctx.bytesPerRow
        let bytes = base.bindMemory(to: UInt8.self, capacity: row * h)
        var lumTop = 0.0
        var countTop = 0
        for y in 0..<h {
            for x in 0..<w {
                let (r, g, b) = art.rgb(u: (Double(x) + 0.5) / Double(w), v: (Double(y) + 0.5) / Double(h))
                let p = y * row + x * 4
                bytes[p] = UInt8((r * 255).rounded())
                bytes[p + 1] = UInt8((g * 255).rounded())
                bytes[p + 2] = UInt8((b * 255).rounded())
                bytes[p + 3] = 255
                if Double(y) < Double(h) * 0.36, Double(x) < Double(w) * 0.75 {
                    lumTop += OKLab.luminance(r, g, b)
                    countTop += 1
                }
            }
        }
        guard let image = ctx.makeImage() else { return nil }
        let tone: TextTone = countTop > 0 && lumTop / Double(countTop) > 0.42 ? .ink : .paper
        return (image, tone)
    }

    /// Multiply, clear to 35 % of the width, rgba(60, 40, 25, 0.22) at the edge.
    private static func vignette(_ ctx: CGContext, width W: Double, height H: Double) {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let colors = [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
            CGColor(srgbRed: 60 / 255, green: 40 / 255, blue: 25 / 255, alpha: 0.22),
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.setBlendMode(.multiply)
        ctx.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: W * 0.5, y: H - H * 0.45),
            startRadius: W * 0.35,
            endCenter: CGPoint(x: W * 0.5, y: H - H * 0.5),
            endRadius: W * 0.95,
            options: [.drawsAfterEndLocation]
        )
        ctx.restoreGState()
    }
}
