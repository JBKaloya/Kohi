// Draws the sample coffee cards bundled with the app so the grid has real
// objects to lay out during development. Run once with:
//   swift Tools/GenerateSampleCards.swift
// Output lands in Kohi/Resources/SampleCards.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Content

struct CardSpec {
    let slug: String
    let country: String
    let score: String
    let notes: [String]
    let farmer: String
    let region: String
    let altitude: String
    let variety: String
    let process: String
    let blurb: String
    /// Card width in pixels. Height falls out of the content.
    let width: CGFloat
    /// Reference width the type is sized against. Smaller values mean larger type
    /// relative to the card, which makes the finished card taller.
    let nominal: CGFloat
    let paper: (CGFloat, CGFloat, CGFloat)
}

let specs: [CardSpec] = [
    CardSpec(
        slug: "kenya-tekangu",
        country: "KE", score: "Q 87",
        notes: ["Floral", "Red Currant", "Vanilla"],
        farmer: "Tekangu Cooperative",
        region: "Nyeri, Kenya",
        altitude: "1800m",
        variety: "AA Tekangu Ngunguru #101",
        process: "Washed",
        blurb: "Kenya Tekangu comes from the high slopes of Mount Kenya, where smallholder farmers carefully hand-pick and process their coffee through the Tekangu Cooperative. Dried slowly under the Kenyan sun and produced with a strong focus on quality and transparency, this lot offers everything we love about Kenyan coffee: vibrant fruit notes, floral sweetness, and a beautifully clean finish.",
        width: 1200, nominal: 632, paper: (0.949, 0.933, 0.898)
    ),
    CardSpec(
        slug: "ethiopia-chelbesa",
        country: "ET", score: "Q 88",
        notes: ["Blueberry", "Jasmine", "Cane Sugar"],
        farmer: "Chelbesa Washing Station",
        region: "Gedeb, Gedeo",
        altitude: "2050m",
        variety: "Heirloom Landrace",
        process: "Natural",
        blurb: "Grown at the very top of the Gedeo zone, this lot is dried on raised beds for eighteen days and turned by hand through the warmest hours. The altitude slows the cherry down and the long drying builds a syrupy body that carries the fruit without ever tipping into ferment.",
        width: 1120, nominal: 600, paper: (0.957, 0.945, 0.914)
    ),
    CardSpec(
        slug: "colombia-el-paraiso",
        country: "CO", score: "Q 89",
        notes: ["Lychee", "Rose", "Passionfruit"],
        farmer: "Diego Samuel Bermúdez",
        region: "Piendamó, Cauca",
        altitude: "1930m",
        variety: "Castillo",
        process: "Double Anaerobic",
        blurb: "Diego Samuel runs one of the most precise fermentation programmes in Colombia. Cherry is sealed in stainless tanks and held under controlled temperature for a first anaerobic stage, then depulped and returned for a second. The result is unmistakable and divides rooms.",
        width: 1280, nominal: 691, paper: (0.945, 0.929, 0.894)
    ),
    CardSpec(
        slug: "guatemala-el-injerto",
        country: "GT", score: "Q 86",
        notes: ["Toffee", "Orange", "Cocoa"],
        farmer: "Aguirre Family",
        region: "La Libertad, Huehuetenango",
        altitude: "1650m",
        variety: "Pacamara",
        process: "Washed",
        blurb: "Four generations of the Aguirre family have farmed this land. The Pacamara trees sit on the cooler eastern slopes, picked in three passes and fermented in tile tanks before a slow patio dry. Classic Huehuetenango structure with a long, sweet finish.",
        width: 1200, nominal: 659, paper: (0.953, 0.937, 0.902)
    ),
    CardSpec(
        slug: "panama-hartmann",
        country: "PA", score: "Q 91",
        notes: ["Peach", "Bergamot", "Honeysuckle"],
        farmer: "Ratibor Hartmann",
        region: "Santa Clara, Volcán",
        altitude: "1500m",
        variety: "Geisha",
        process: "Honey",
        blurb: "The Hartmann farm sits against the Volcán Barú reserve, and the shade trees that border the plot are old enough that the cherry ripens weeks behind the surrounding farms. Left with most of its mucilage through the dry, this Geisha is delicate and unusually long.",
        width: 1760, nominal: 1185, paper: (0.960, 0.949, 0.921)
    ),
    CardSpec(
        slug: "brazil-fazenda-sertao",
        country: "BR", score: "Q 84",
        notes: ["Hazelnut", "Milk Chocolate", "Almond"],
        farmer: "Guimarães Family",
        region: "Carmo de Minas, Minas Gerais",
        altitude: "1150m",
        variety: "Yellow Bourbon",
        process: "Pulped Natural",
        blurb: "Sertão has been in the Guimarães family since 1918. The Yellow Bourbon is pulped and dried with the mucilage intact, which is what gives this lot the density it carries through milk. Our house espresso base for seven years running.",
        width: 1100, nominal: 616, paper: (0.941, 0.925, 0.886)
    ),
]

// MARK: - Drawing helpers

let inkColor = CGColor(srgbRed: 0.129, green: 0.118, blue: 0.106, alpha: 1)
let mutedColor = CGColor(srgbRed: 0.129, green: 0.118, blue: 0.106, alpha: 0.72)
let ruleColor = CGColor(srgbRed: 0.129, green: 0.118, blue: 0.106, alpha: 0.34)

func font(_ name: String, _ size: CGFloat) -> CTFont {
    CTFontCreateWithName(name as CFString, size, nil)
}

// CoreText's attribute names are not the strings you would guess
// (kCTFontAttributeName is "NSFont"), so always go through the constants.
let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
let kernKey = NSAttributedString.Key(kCTKernAttributeName as String)
let paragraphKey = NSAttributedString.Key(kCTParagraphStyleAttributeName as String)

enum Align { case left, right }

@discardableResult
func drawText(
    _ string: String,
    font ctFont: CTFont,
    color: CGColor,
    x: CGFloat,
    y: CGFloat,
    align: Align = .left,
    tracking: CGFloat = 0,
    in ctx: CGContext
) -> CGFloat {
    var attrs: [NSAttributedString.Key: Any] = [fontKey: ctFont, colorKey: color]
    if tracking != 0 { attrs[kernKey] = tracking }
    let attributed = NSAttributedString(string: string, attributes: attrs)
    let line = CTLineCreateWithAttributedString(attributed)
    let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    let originX = align == .left ? x : x - width
    ctx.textPosition = CGPoint(x: originX, y: y)
    CTLineDraw(line, ctx)
    return width
}

func paragraphString(
    _ string: String,
    font ctFont: CTFont,
    color: CGColor,
    lineSpacing: CGFloat
) -> NSAttributedString {
    var spacing = lineSpacing
    let style = withUnsafePointer(to: &spacing) { pointer in
        CTParagraphStyleCreate(
            [
                CTParagraphStyleSetting(
                    spec: .lineSpacingAdjustment,
                    valueSize: MemoryLayout<CGFloat>.size,
                    value: UnsafeRawPointer(pointer)
                )
            ],
            1
        )
    }
    return NSAttributedString(
        string: string,
        attributes: [fontKey: ctFont, colorKey: color, paragraphKey: style]
    )
}

func paragraphHeight(_ attributed: NSAttributedString, width: CGFloat) -> CGFloat {
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    var fitRange = CFRange()
    let size = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter,
        CFRangeMake(0, 0),
        nil,
        CGSize(width: width, height: .greatestFiniteMagnitude),
        &fitRange
    )
    return ceil(size.height)
}

/// Draws a wrapped paragraph. `rect` is in the top-left origin space the rest of
/// the layout uses; this temporarily returns the context to CoreText's bottom-up
/// orientation so the glyphs come out the right way round.
func drawParagraph(
    _ attributed: NSAttributedString,
    rect: CGRect,
    canvasHeight: CGFloat,
    in ctx: CGContext
) {
    ctx.saveGState()
    ctx.textMatrix = .identity
    ctx.translateBy(x: 0, y: canvasHeight)
    ctx.scaleBy(x: 1, y: -1)
    let flipped = CGRect(
        x: rect.minX,
        y: canvasHeight - rect.maxY,
        width: rect.width,
        height: rect.height
    )
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let frame = CTFramesetterCreateFrame(
        framesetter, CFRangeMake(0, 0), CGPath(rect: flipped, transform: nil), nil
    )
    CTFrameDraw(frame, ctx)
    ctx.restoreGState()
}

func rule(y: CGFloat, from x0: CGFloat, to x1: CGFloat, in ctx: CGContext, alpha: CGFloat = 1) {
    ctx.saveGState()
    ctx.setStrokeColor(ruleColor.copy(alpha: ruleColor.alpha * alpha) ?? ruleColor)
    ctx.setLineWidth(1.2)
    ctx.move(to: CGPoint(x: x0, y: y))
    ctx.addLine(to: CGPoint(x: x1, y: y))
    ctx.strokePath()
    ctx.restoreGState()
}

/// A few thousand faint specks so the paper doesn't read as a flat fill.
func speckle(in ctx: CGContext, size: CGSize, seed: UInt64) {
    var rng = SystemRandomNumberGenerator()
    _ = seed
    ctx.saveGState()
    for _ in 0..<2600 {
        let x = CGFloat.random(in: 0..<size.width, using: &rng)
        let y = CGFloat.random(in: 0..<size.height, using: &rng)
        let r = CGFloat.random(in: 0.4...1.5, using: &rng)
        let a = CGFloat.random(in: 0.015...0.055, using: &rng)
        ctx.setFillColor(CGColor(srgbRed: 0.35, green: 0.30, blue: 0.24, alpha: a))
        ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
    }
    ctx.restoreGState()
}

// MARK: - Card renderer

func render(_ spec: CardSpec) -> CGImage? {
    let W = spec.width
    let scale = W / spec.nominal
    let margin = W * 0.085
    let contentWidth = W - margin * 2

    // Vertical layout is deterministic apart from the blurb, so measure that
    // first and let the card height fall out of the content.
    let blurbFont = font("HelveticaNeue", 17 * scale)
    let blurbText = paragraphString(
        spec.blurb, font: blurbFont, color: mutedColor, lineSpacing: 5 * scale
    )
    let blurbHeight = paragraphHeight(blurbText, width: contentWidth)

    let headerBottom = margin + 30 * scale + 62 * scale + 40 * scale
    let notesHeight = 48 * scale + CGFloat(spec.notes.count) * 48 * scale
    let rowsHeight = 18 * scale + 5 * 32 * scale
    let blurbTop = headerBottom + notesHeight + rowsHeight + 44 * scale
    let H = (blurbTop + blurbHeight + margin * 0.9).rounded()
    let size = CGSize(width: W, height: H)

    guard let ctx = CGContext(
        data: nil,
        width: Int(W),
        height: Int(H),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setFillColor(CGColor(srgbRed: spec.paper.0, green: spec.paper.1, blue: spec.paper.2, alpha: 1))
    ctx.fill(CGRect(origin: .zero, size: size))
    speckle(in: ctx, size: size, seed: 1)

    // Flip into a top-left origin so the layout below reads downward.
    ctx.translateBy(x: 0, y: H)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

    let right = W - margin
    var y = margin + 30 * scale

    // Header: mark on the left, country and score discs on the right.
    ctx.saveGState()
    ctx.setFillColor(inkColor)
    let markW = 46 * scale
    let barH = 5 * scale
    for i in 0..<3 {
        let w = markW * [1.0, 0.72, 0.86][i]
        ctx.fill(CGRect(x: margin, y: y - 26 * scale + CGFloat(i) * (barH * 2.4), width: w, height: barH))
    }
    ctx.restoreGState()

    let discR = 34 * scale
    let discFont = font("HelveticaNeue-Medium", 21 * scale)
    var discX = right
    for text in [spec.score, spec.country] {
        let textW = drawTextMeasure(text, font: discFont, tracking: 0.5 * scale)
        let discW = max(discR * 2, textW + 34 * scale)
        let rect = CGRect(x: discX - discW, y: y - 34 * scale, width: discW, height: discR * 2)
        ctx.saveGState()
        ctx.setStrokeColor(inkColor)
        ctx.setLineWidth(1.6 * scale)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: discR, cornerHeight: discR, transform: nil))
        ctx.strokePath()
        ctx.restoreGState()
        drawText(
            text, font: discFont, color: inkColor,
            x: rect.midX + textW / 2, y: rect.midY + 7 * scale,
            align: .right, tracking: 0.5 * scale, in: ctx
        )
        discX = rect.minX - 16 * scale
    }

    y += 62 * scale
    rule(y: y, from: margin, to: right, in: ctx)
    y += 40 * scale

    // Tasting notes: label, then one note per ruled line.
    let labelFont = font("HelveticaNeue", 20 * scale)
    let noteFont = font("HelveticaNeue-Medium", 25 * scale)
    drawText("Notes:", font: labelFont, color: mutedColor, x: margin, y: y, in: ctx)
    y += 14 * scale
    rule(y: y, from: margin, to: right, in: ctx, alpha: 0.7)
    y += 34 * scale

    for note in spec.notes {
        drawText(note, font: noteFont, color: inkColor, x: margin, y: y, in: ctx)
        y += 14 * scale
        rule(y: y, from: margin, to: right, in: ctx, alpha: 0.7)
        y += 34 * scale
    }

    y += 18 * scale

    // Label column on the left, values set flush right.
    let rows = [
        ("Farmer:", spec.farmer),
        ("Region:", spec.region),
        ("Altitude:", spec.altitude),
        ("Variety:", spec.variety),
        ("Process:", spec.process),
    ]
    let valueFont = font("HelveticaNeue", 20 * scale)
    for (label, value) in rows {
        drawText(label, font: labelFont, color: mutedColor, x: margin, y: y, in: ctx)
        drawText(value, font: valueFont, color: inkColor, x: right, y: y, align: .right, in: ctx)
        y += 32 * scale
    }

    drawParagraph(
        blurbText,
        rect: CGRect(x: margin, y: blurbTop, width: contentWidth, height: blurbHeight + 4 * scale),
        canvasHeight: H,
        in: ctx
    )

    return ctx.makeImage()
}

func drawTextMeasure(_ string: String, font ctFont: CTFont, tracking: CGFloat) -> CGFloat {
    var attrs: [NSAttributedString.Key: Any] = [fontKey: ctFont]
    if tracking != 0 { attrs[kernKey] = tracking }
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attrs))
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

// MARK: - Write

let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Kohi/Resources/SampleCards")
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for spec in specs {
    guard let image = render(spec) else {
        print("failed to render \(spec.slug)")
        continue
    }
    let url = outputDirectory.appendingPathComponent("\(spec.slug).png")
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { continue }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("wrote \(url.lastPathComponent) \(image.width)x\(image.height)")
}
