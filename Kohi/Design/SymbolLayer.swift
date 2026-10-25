import CoreGraphics
import Foundation

/// How the pack symbol sits in the card's ground.
nonisolated enum SymbolTreatment: String, Codable, CaseIterable, Sendable {
    case none
    /// Blind emboss: light on the top-left edge, shadow on the bottom-right.
    case emboss
    /// Screen print: a misregistered second pass, a speckled transfer.
    case ink
    /// Dots whose radius follows the mark.
    case halftone
    /// The mark small and repeated, for marks that would blur when enlarged.
    case pattern
}

/// The symbol to draw: the vector shape when there is one, otherwise the soft bitmap.
nonisolated enum MarkSource: @unchecked Sendable {
    case shape(MarkShape)
    case bitmap(CGImage)

    var aspect: Double {
        switch self {
        case .shape(let shape): shape.aspect
        case .bitmap(let image): Double(image.width) / Double(max(image.height, 1))
        }
    }
}

/// Rasterises the symbol at the destination size, then applies the treatment.
/// Contexts here are CoreGraphics native (y up); placement is computed y-down, as in the lab.
nonisolated enum SymbolLayer {
    struct EmbossEdges: @unchecked Sendable {
        /// Already tinted, full opacity. Screen at 0.55.
        var highlight: CGImage
        /// Already tinted, full opacity. Multiply at 0.50.
        var shadow: CGImage
        /// Offset in pixels used to cut the edges.
        var offset: Double
    }

    static func offset(width: Double) -> Double { max(2, 0.0055 * width) }

    /// Draws `treatment` into `ctx`, a W × H pixel context. `lightGround` is the text tone:
    /// true when the field reads as light (ink text). When `separateEdges` is true the emboss
    /// edges are not drawn and come back so the fiche can move them with the tilt.
    @discardableResult
    static func draw(
        in ctx: CGContext,
        art: CardArt,
        mark: MarkSource,
        treatment: SymbolTreatment,
        width: Int,
        height: Int,
        lightGround: Bool,
        separateEdges: Bool = false
    ) -> EmbossEdges? {
        let W = Double(width), H = Double(height)
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let o = offset(width: W)
        switch treatment {
        case .none:
            return nil
        case .pattern:
            guard let m = patternMask(mark, width: width, height: height) else { return nil }
            ctx.saveGState()
            ctx.setBlendMode(lightGround ? .multiply : .screen)
            ctx.setAlpha(lightGround ? 0.20 : 0.17)
            if let tint = tinted(m, lightGround ? rgb(0x3A2A20) : rgb(0xFFF6E6)) { ctx.draw(tint, in: full) }
            ctx.restoreGState()
            return nil
        case .emboss:
            guard let m = placedMask(mark, art: art, width: width, height: height),
                  let edges = embossEdges(m, width: width, height: height, offset: o)
            else { return nil }
            ctx.saveGState()
            ctx.setBlendMode(.screen)
            ctx.setAlpha(0.07)
            if let face = tinted(m, (1, 1, 1)) { ctx.draw(face, in: full) }
            if !separateEdges {
                ctx.setAlpha(0.55)
                ctx.draw(edges.highlight, in: full)
                ctx.setBlendMode(.multiply)
                ctx.setAlpha(0.50)
                ctx.draw(edges.shadow, in: full)
            }
            ctx.restoreGState()
            return separateEdges ? edges : nil
        case .ink:
            guard let m = placedMask(mark, art: art, width: width, height: height) else { return nil }
            let notes = art.noteBlobs
            let first = notes.first?.lab ?? art.blobs[0].lab
            let deep = OKLab.byte(OKLab.toSRGB([0.30, first.y * 0.6, first.z * 0.6]))
            let secondLab = art.ink ?? (notes.count > 1 ? notes[1].lab : art.blobs[1].lab)
            let second = OKLab.byte(OKLab.toSRGB(secondLab))
            guard let pass = speckled(tinted(m, deep), width: width, height: height),
                  let misregistered = tinted(m, second)
            else { return nil }
            ctx.saveGState()
            ctx.setBlendMode(.multiply)
            ctx.setAlpha(0.28)
            ctx.draw(misregistered, in: full.offsetBy(dx: o * 1.4, dy: o))
            ctx.setAlpha(0.62)
            ctx.draw(pass, in: full)
            ctx.restoreGState()
            return nil
        case .halftone:
            guard let m = placedMask(mark, art: art, width: width, height: height) else { return nil }
            let cell = max(5, W * 0.016)
            let cols = Int((W / cell).rounded(.up)) + 2
            let rows = Int((H / cell).rounded(.up)) + 2
            guard let small = MarkMask.rgba(width: cols, height: rows) else { return nil }
            small.interpolationQuality = .medium
            small.draw(m, in: CGRect(x: 0, y: 0, width: cols, height: rows))
            guard let smallImage = small.makeImage() else { return nil }
            let alpha = MarkMask.alpha(of: smallImage)
            let dots = CGMutablePath()
            for y in 0..<rows {
                for x in 0..<cols {
                    let a = Double(alpha[y * cols + x]) / 255
                    guard a >= 0.04 else { continue }
                    let r = cell * 0.52 * a.squareRoot()
                    let cx = (Double(x) + 0.5) * W / Double(cols)
                    let cy = H - (Double(y) + 0.5) * H / Double(rows)
                    dots.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                }
            }
            let notes = art.noteBlobs
            let first = notes.first?.lab ?? art.blobs[0].lab
            let fill = lightGround
                ? OKLab.byte(OKLab.toSRGB([0.32, first.y * 0.5, first.z * 0.5]))
                : rgb(0xFFF3DF)
            ctx.saveGState()
            ctx.setBlendMode(lightGround ? .multiply : .screen)
            ctx.setAlpha(lightGround ? 0.75 : 0.70)
            ctx.setFillColor(CGColor(srgbRed: fill.0, green: fill.1, blue: fill.2, alpha: 1))
            ctx.addPath(dots)
            ctx.fillPath()
            ctx.restoreGState()
            return nil
        }
    }

    // MARK: - Masks

    /// The symbol alone, black with alpha, placed and rotated in a W × H layer.
    static func placedMask(_ mark: MarkSource, art: CardArt, width: Int, height: Int) -> CGImage? {
        let r = art.symbolDraws
        guard r.count >= 4, let ctx = MarkMask.rgba(width: width, height: height) else { return nil }
        let W = Double(width), H = Double(height)
        let asp = mark.aspect
        var w = W * (1.0 + r[0] * 0.35)
        if w / asp > H * 1.05 { w = H * 1.05 * asp }
        let h = w / asp
        let cx = W * (0.56 + r[1] * 0.18), cy = H * (0.30 + r[2] * 0.14), rot = (r[3] - 0.5) * 0.45
        ctx.translateBy(x: 0, y: H)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: cx, y: cy)
        ctx.rotate(by: rot)
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        fill(mark, in: rect, ctx: ctx)
        return ctx.makeImage()
    }

    /// The symbol at 15 % of the width, staggered rows, turned −0.21 rad.
    static func patternMask(_ mark: MarkSource, width: Int, height: Int) -> CGImage? {
        let W = Double(width), H = Double(height)
        let asp = mark.aspect
        let s = W * 0.15, gap = s * 1.55
        let w = asp >= 1 ? s : s * asp
        let h = asp >= 1 ? s / asp : s
        guard let stamp = rasterized(mark, width: Int(w.rounded(.up)), height: Int(h.rounded(.up))),
              let ctx = MarkMask.rgba(width: width, height: height)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: H)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: W / 2, y: H / 2)
        ctx.rotate(by: -0.21)
        ctx.translateBy(x: -W, y: -H)
        var row = 0
        var yy = 0.0
        while yy < H * 2 {
            var xx = Double(row % 2) * gap / 2
            while xx < W * 2 {
                ctx.saveGState()
                ctx.translateBy(x: xx, y: yy)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(stamp, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
                ctx.restoreGState()
                xx += gap
            }
            row += 1
            yy += gap * 0.9
        }
        return ctx.makeImage()
    }

    /// The symbol filling a `width` × `height` image, upright.
    static func rasterized(_ mark: MarkSource, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, let ctx = MarkMask.rgba(width: width, height: height) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        fill(mark, in: CGRect(x: 0, y: 0, width: width, height: height), ctx: ctx)
        return ctx.makeImage()
    }

    /// `ctx` is y-down here. A bitmap is flipped back locally so it lands upright.
    private static func fill(_ mark: MarkSource, in rect: CGRect, ctx: CGContext) {
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        switch mark {
        case .shape(let shape):
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            ctx.addPath(shape.path(in: rect))
            ctx.fillPath(using: .evenOdd)
        case .bitmap(let image):
            ctx.saveGState()
            ctx.translateBy(x: 0, y: rect.minY + rect.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: rect)
            ctx.restoreGState()
        }
    }

    private static func embossEdges(_ m: CGImage, width: Int, height: Int, offset o: Double) -> EmbossEdges? {
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let shifted = full.offsetBy(dx: o, dy: -o)
        guard let hl = MarkMask.rgba(width: width, height: height),
              let sh = MarkMask.rgba(width: width, height: height)
        else { return nil }
        hl.draw(m, in: full)
        hl.setBlendMode(.destinationOut)
        hl.draw(m, in: shifted)
        sh.draw(m, in: shifted)
        sh.setBlendMode(.destinationOut)
        sh.draw(m, in: full)
        guard let hlImage = hl.makeImage(), let shImage = sh.makeImage(),
              let highlight = tinted(hlImage, rgb(0xFFFAF0)),
              let shadow = tinted(shImage, rgb(0x2A1C12))
        else { return nil }
        return EmbossEdges(highlight: highlight, shadow: shadow, offset: o)
    }

    /// Half the ink knocked out through the grain, as in the lab.
    private static func speckled(_ image: CGImage?, width: Int, height: Int) -> CGImage? {
        guard let image, let ctx = MarkMask.rgba(width: width, height: height) else { return nil }
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.draw(image, in: full)
        if let grain = GrainTexture.tile {
            ctx.setBlendMode(.destinationOut)
            ctx.setAlpha(0.5)
            ctx.draw(grain, in: CGRect(x: 0, y: 0, width: GrainTexture.size, height: GrainTexture.size), byTiling: true)
        }
        return ctx.makeImage()
    }

    /// The mask's alpha, filled with one colour.
    static func tinted(_ mask: CGImage, _ color: (Double, Double, Double)) -> CGImage? {
        guard let ctx = MarkMask.rgba(width: mask.width, height: mask.height) else { return nil }
        let full = CGRect(x: 0, y: 0, width: mask.width, height: mask.height)
        ctx.draw(mask, in: full)
        ctx.setBlendMode(.sourceIn)
        ctx.setFillColor(CGColor(srgbRed: color.0, green: color.1, blue: color.2, alpha: 1))
        ctx.fill(full)
        return ctx.makeImage()
    }

    static func rgb(_ hex: Int) -> (Double, Double, Double) {
        (Double((hex >> 16) & 255) / 255, Double((hex >> 8) & 255) / 255, Double(hex & 255) / 255)
    }
}
