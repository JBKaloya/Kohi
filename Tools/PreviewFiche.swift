// Preview of the colored fiche, before it exists in the app.
//   swift Tools/PreviewFiche.swift <folder of png/jpg/heic> [output folder]
// Writes one fiche per image, plus planche.png (scan, extracted mark, fiche).
// Identical files are drawn once. Names below are the sample archive; any
// other file is titled from its filename and has no country badge.

import AppKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CryptoKit
import Foundation
import ImageIO
import Vision

// MARK: - Inputs

struct Job {
    var url: URL
    var name: String
    var country: String
    var score: Double?
    var notes: [String]
    /// True when the title was read off the scan for this preview, not stored.
    var titleIsGuessed: Bool
}

struct KnownCard {
    var name: String
    var country: String
    var score: Double?
    var notes: [String]
}

/// Sample illustrations. The score is the number painted on the drawing.
let known: [String: KnownCard] = [
    "kenya-tekangu": KnownCard(name: "Kenya Tekangu", country: "Kenya", score: 87, notes: ["Floral", "Red Currant", "Vanilla"]),
    "ethiopia-chelbesa": KnownCard(name: "Chelbesa", country: "Ethiopia", score: 88, notes: ["Blueberry", "Jasmine", "Cane Sugar"]),
    "colombia-el-paraiso": KnownCard(name: "El Paraíso Lychee", country: "Colombia", score: 89, notes: ["Lychee", "Rose", "Passionfruit"]),
    "guatemala-el-injerto": KnownCard(name: "El Injerto Pacamara", country: "Guatemala", score: 86, notes: ["Toffee", "Orange", "Cocoa"]),
    "panama-hartmann": KnownCard(name: "Hartmann Geisha", country: "Panama", score: 91, notes: ["Peach", "Bergamot", "Honeysuckle"]),
    "brazil-fazenda-sertao": KnownCard(name: "Fazenda Sertão", country: "Brazil", score: 84, notes: ["Hazelnut", "Milk Chocolate", "Almond"]),
]

let origin: [String: String] = [
    "Ethiopia": "ET", "Kenya": "KE", "Rwanda": "RW", "Burundi": "BI",
    "Tanzania": "TZ", "Uganda": "UG", "Colombia": "CO", "Brazil": "BR",
    "Peru": "PE", "Bolivia": "BO", "Ecuador": "EC", "Guatemala": "GT",
    "Honduras": "HN", "El Salvador": "SV", "Nicaragua": "NI", "Costa Rica": "CR",
    "Panama": "PA", "Mexico": "MX", "Jamaica": "JM", "Indonesia": "ID",
    "Sumatra": "ID", "Java": "ID", "Sulawesi": "ID", "Papua New Guinea": "PG",
    "India": "IN", "Vietnam": "VN", "Thailand": "TH", "China": "CN",
    "Yemen": "YE", "Hawaii": "US",
]

let paper = (r: 0.980, g: 0.973, b: 0.957)
let ink = CGColor(srgbRed: 0.16, green: 0.145, blue: 0.125, alpha: 1)
let nameGray = CGColor(srgbRed: 0.45, green: 0.44, blue: 0.42, alpha: 1)
let hairline = CGColor(srgbRed: 0.16, green: 0.145, blue: 0.125, alpha: 0.28)

struct PackTint {
    var r, g, b: CGFloat
    var isPaper: Bool
    var color: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}

struct Mark {
    var image: CGImage?
    var note: String
}

// MARK: - Main

let args = Array(CommandLine.arguments.dropFirst())
guard let sourceArg = args.first else {
    fputs("usage: swift Tools/PreviewFiche.swift <images folder> [output folder]\n", stderr)
    exit(1)
}
let source = URL(fileURLWithPath: sourceArg)
let output = URL(fileURLWithPath: args.dropFirst().first ?? "fiche-preview")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let jobs = uniqueJobs(in: source)
guard !jobs.isEmpty else {
    fputs("no images in \(source.path)\n", stderr)
    exit(1)
}

var rows: [(job: Job, scan: CGImage, mark: Mark, fiche: CGImage)] = []
for var job in jobs {
    guard let scan = loadImage(job.url) else {
        fputs("skip \(job.url.lastPathComponent)\n", stderr)
        continue
    }
    let working = downsample(scan, maxPixel: 1024) ?? scan
    if job.name.isEmpty {
        job.name = guessTitle(working) ?? ""
        job.titleIsGuessed = !job.name.isEmpty
    }
    if job.country.isEmpty {
        job.country = guessCountry(working)
    }
    let tint = packTint(working)
    let mark = extractMark(working)
    let fiche = renderFiche(job: job, tint: tint, mark: mark.image, width: 640)
    let slug = job.url.deletingPathExtension().lastPathComponent
    writePNG(fiche, output.appending(path: "\(slug).png"))
    if let stamp = mark.image {
        writePNG(stamp, output.appending(path: "\(slug)-marque.png"))
    }
    print("\(slug): \(mark.note) — fond \(tint.isPaper ? "papier" : String(format: "#%02X%02X%02X", Int(tint.r * 255), Int(tint.g * 255), Int(tint.b * 255)))")
    rows.append((job, working, mark, fiche))
}

let planche = renderPlanche(rows)
writePNG(planche, output.appending(path: "planche.png"))
print("\(rows.count) fiches → \(output.path)")

// MARK: - Jobs

func uniqueJobs(in folder: URL) -> [Job] {
    let allowed: Set<String> = ["png", "jpg", "jpeg", "heic", "heif"]
    let urls = (try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil
    )) ?? []
    var seen = Set<String>()
    var jobs: [Job] = []
    for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        guard allowed.contains(url.pathExtension.lowercased()) else { continue }
        guard let data = try? Data(contentsOf: url) else { continue }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard seen.insert(digest).inserted else { continue }
        let key = url.deletingPathExtension().lastPathComponent
        let meta = known[key]
        jobs.append(Job(
            url: url,
            name: meta?.name ?? "",
            country: meta?.country ?? "",
            score: meta?.score,
            notes: meta?.notes ?? [],
            titleIsGuessed: false
        ))
    }
    return jobs
}

func loadImage(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func writePNG(_ image: CGImage, _ url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - Color

func packTint(_ image: CGImage) -> PackTint {
    let fallback = PackTint(r: paper.r, g: paper.g, b: paper.b, isPaper: true)
    guard let small = downsample(image, maxPixel: 48),
          let pixels = rgba(small) else { return fallback }
    let count = small.width * small.height
    var buckets = [(n: Int, s: Double)](repeating: (0, 0), count: 24)
    var saturated = 0
    for i in 0..<count {
        let r = Double(pixels[i * 4]) / 255
        let g = Double(pixels[i * 4 + 1]) / 255
        let b = Double(pixels[i * 4 + 2]) / 255
        let (h, s, v) = hsv(r, g, b)
        if s < 0.18 || v > 0.92 || v < 0.12 { continue }
        saturated += 1
        let bin = min(23, Int(h * 24))
        buckets[bin].n += 1
        buckets[bin].s += s
    }
    guard saturated * 8 > count,
          let best = buckets.enumerated().max(by: { $0.element.n < $1.element.n }),
          best.element.n > 0 else { return fallback }
    let sat = min(0.72, max(0.48, best.element.s / Double(best.element.n)))
    let hue = (Double(best.offset) + 0.5) / 24
    let (r, g, b) = rgb(h: hue, s: sat, v: 0.34)
    return PackTint(r: r, g: g, b: b, isPaper: false)
}

func hsv(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
    let maxV = max(r, g, b)
    let minV = min(r, g, b)
    let d = maxV - minV
    let s = maxV == 0 ? 0 : d / maxV
    var h = 0.0
    if d > 0 {
        if maxV == r { h = (g - b) / d + (g < b ? 6 : 0) }
        else if maxV == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h /= 6
    }
    return (h, s, maxV)
}

func rgb(h: Double, s: Double, v: Double) -> (CGFloat, CGFloat, CGFloat) {
    let i = Int(h * 6)
    let f = h * 6 - Double(i)
    let p = v * (1 - s)
    let q = v * (1 - f * s)
    let t = v * (1 - (1 - f) * s)
    let (r, g, b): (Double, Double, Double)
    switch i % 6 {
    case 0: (r, g, b) = (v, t, p)
    case 1: (r, g, b) = (q, v, p)
    case 2: (r, g, b) = (p, v, t)
    case 3: (r, g, b) = (p, q, v)
    case 4: (r, g, b) = (t, p, v)
    default: (r, g, b) = (v, p, q)
    }
    return (CGFloat(r), CGFloat(g), CGFloat(b))
}

// MARK: - Mark

func extractMark(_ image: CGImage) -> Mark {
    let boxes = textBoxes(image)
    guard let prepared = prepare(image, boxes: boxes) else {
        return Mark(image: nil, note: "rien à détourer")
    }
    let inked = prefersEdgeWork(prepared) ? edgeInk(prepared) : thresholdInk(prepared)
    guard let inked, let drawing = measured(inked, pack: prepared) else {
        return Mark(image: nil, note: "pas de symbole")
    }
    let lines = recognize(drawing).joined(separator: " ")
    let words = lines.unicodeScalars
        .split { !CharacterSet.letters.contains($0) }
        .map { String($0) }
    if words.contains(where: { $0.count >= 3 }) {
        return Mark(image: nil, note: "refusé, le dessin contient encore du texte")
    }
    return Mark(image: drawing, note: "symbole gardé")
}

func textBoxes(_ image: CGImage) -> [CGRect] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast
    request.usesLanguageCorrection = false
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([request])
    return (request.results ?? []).map(\.boundingBox)
}

func recognize(_ image: CGImage) -> [String] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast
    request.usesLanguageCorrection = false
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
}

func prepare(_ image: CGImage, boxes: [CGRect]) -> CGImage? {
    let width = image.width
    let height = image.height
    guard let ctx = context(width: width, height: height) else { return nil }
    let full = CGRect(x: 0, y: 0, width: width, height: height)
    ctx.setFillColor(CGColor(srgbRed: paper.r, green: paper.g, blue: paper.b, alpha: 1))
    ctx.fill(full)
    ctx.draw(image, in: full)
    ctx.setFillColor(CGColor(srgbRed: paper.r, green: paper.g, blue: paper.b, alpha: 1))
    for box in boxes {
        let dx = box.width * 0.04
        let dy = box.height * 0.04
        let grown = box.insetBy(dx: -dx, dy: -dy)
        ctx.fill(CGRect(
            x: grown.origin.x * CGFloat(width),
            y: grown.origin.y * CGFloat(height),
            width: grown.width * CGFloat(width),
            height: grown.height * CGFloat(height)
        ))
    }
    return ctx.makeImage()
}

func prefersEdgeWork(_ image: CGImage) -> Bool {
    guard let small = downsample(image, maxPixel: 96), let values = luminances(small) else { return false }
    let block = 8
    var variances: [Double] = []
    var y = 0
    while y + block <= small.height {
        var x = 0
        while x + block <= small.width {
            var sample: [Double] = []
            for dy in 0..<block {
                for dx in 0..<block {
                    sample.append(values[(y + dy) * small.width + (x + dx)])
                }
            }
            variances.append(variance(sample))
            x += block
        }
        y += block
    }
    guard !variances.isEmpty else { return false }
    variances.sort()
    return variances[variances.count / 2] > 0.004
}

func thresholdInk(_ image: CGImage) -> CGImage? {
    let input = CIImage(cgImage: image)
    let noir = CIFilter.photoEffectNoir()
    noir.inputImage = input
    guard let grey = noir.outputImage?.cropped(to: input.extent),
          let greyImage = CIContext().createCGImage(grey, from: input.extent) else { return nil }
    guard let values = luminances(greyImage) else { return nil }
    let limit = otsu(values)
    var mask = values.map { $0 <= limit }
    mask = erode(mask, width: greyImage.width, height: greyImage.height)
    mask = dilate(mask, width: greyImage.width, height: greyImage.height)
    return raster(mask, width: greyImage.width, height: greyImage.height)
}

func edgeInk(_ image: CGImage) -> CGImage? {
    let input = CIImage(cgImage: image)
    let edges = CIFilter.edgeWork()
    edges.inputImage = input
    edges.radius = 3
    guard let worked = edges.outputImage?.cropped(to: input.extent),
          let rendered = CIContext().createCGImage(worked, from: input.extent),
          let values = luminances(rendered) else { return nil }
    var mask = values.map { $0 > 0.45 }
    mask = erode(mask, width: rendered.width, height: rendered.height)
    mask = dilate(mask, width: rendered.width, height: rendered.height)
    return raster(mask, width: rendered.width, height: rendered.height)
}

func measured(_ image: CGImage, pack: CGImage) -> CGImage? {
    let width = image.width
    let height = image.height
    guard let pixels = rgba(image) else { return nil }
    let total = width * height
    let dust = Int(Double(total) * 0.002)
    var seen = [Bool](repeating: false, count: total)
    var kept = [Bool](repeating: false, count: total)
    var componentCount = 0
    var minX = width, minY = height, maxX = 0, maxY = 0
    var inkCount = 0
    func isInk(_ i: Int) -> Bool { pixels[i * 4 + 3] > 32 }

    for y in 0..<height {
        for x in 0..<width {
            let start = y * width + x
            guard !seen[start], isInk(start) else { continue }
            var stack = [start]
            var members: [Int] = []
            seen[start] = true
            while let current = stack.popLast() {
                members.append(current)
                let cx = current % width
                let cy = current / width
                for (nx, ny) in [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)] {
                    guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                    let next = ny * width + nx
                    guard !seen[next], isInk(next) else { continue }
                    seen[next] = true
                    stack.append(next)
                }
            }
            guard members.count >= max(dust, 1) else { continue }
            componentCount += 1
            for member in members {
                kept[member] = true
                inkCount += 1
                let mx = member % width
                let my = member / width
                minX = min(minX, mx)
                minY = min(minY, my)
                maxX = max(maxX, mx)
                maxY = max(maxY, my)
            }
        }
    }
    guard componentCount > 0, inkCount > 0, maxX >= minX, maxY >= minY else { return nil }
    let cropW = maxX - minX + 1
    let cropH = maxY - minY + 1
    let coverage = Double(inkCount) / Double(cropW * cropH)
    let areaRatio = Double(cropW * cropH) / Double(max(pack.width * pack.height, 1))
    guard (0.03...0.45).contains(coverage),
          (0.06...0.60).contains(areaRatio),
          componentCount > 0, componentCount < 400 else { return nil }

    var cleaned = pixels
    for i in 0..<total where isInk(i) && !kept[i] {
        cleaned[i * 4] = 0
        cleaned[i * 4 + 1] = 0
        cleaned[i * 4 + 2] = 0
        cleaned[i * 4 + 3] = 0
    }
    guard let full = imageFromRGBA(cleaned, width: width, height: height) else { return nil }
    return full.cropping(to: CGRect(x: minX, y: minY, width: cropW, height: cropH))
}

func erode(_ ink: [Bool], width: Int, height: Int) -> [Bool] {
    var out = [Bool](repeating: false, count: ink.count)
    guard width > 2, height > 2 else { return ink }
    for y in 1..<(height - 1) {
        for x in 1..<(width - 1) {
            var keep = true
            for dy in -1...1 where keep {
                for dx in -1...1 where keep {
                    if !ink[(y + dy) * width + (x + dx)] { keep = false }
                }
            }
            out[y * width + x] = keep
        }
    }
    return out
}

func dilate(_ ink: [Bool], width: Int, height: Int) -> [Bool] {
    var out = ink
    guard width > 2, height > 2 else { return ink }
    for y in 1..<(height - 1) {
        for x in 1..<(width - 1) {
            let index = y * width + x
            if ink[index] { continue }
            var hit = false
            for dy in -1...1 where !hit {
                for dx in -1...1 where !hit {
                    if ink[(y + dy) * width + (x + dx)] { hit = true }
                }
            }
            out[index] = hit
        }
    }
    return out
}

func raster(_ ink: [Bool], width: Int, height: Int) -> CGImage? {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for index in ink.indices where ink[index] {
        let pixel = index * 4
        pixels[pixel] = 26
        pixels[pixel + 1] = 24
        pixels[pixel + 2] = 21
        pixels[pixel + 3] = 255
    }
    return imageFromRGBA(pixels, width: width, height: height)
}

func otsu(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0.5 }
    var histogram = [Int](repeating: 0, count: 256)
    for value in values {
        histogram[min(255, max(0, Int((value * 255).rounded())))] += 1
    }
    let total = values.count
    var sum = 0.0
    for index in 0..<256 { sum += Double(index * histogram[index]) }
    var sumBackground = 0.0
    var weightBackground = 0
    var best = 0.0
    var threshold = 128
    for index in 0..<256 {
        weightBackground += histogram[index]
        if weightBackground == 0 { continue }
        let weightForeground = total - weightBackground
        if weightForeground == 0 { break }
        sumBackground += Double(index * histogram[index])
        let meanBackground = sumBackground / Double(weightBackground)
        let meanForeground = (sum - sumBackground) / Double(weightForeground)
        let variance = Double(weightBackground * weightForeground) * pow(meanBackground - meanForeground, 2)
        if variance > best {
            best = variance
            threshold = index
        }
    }
    return Double(threshold) / 255
}

func luminances(_ image: CGImage) -> [Double]? {
    guard let pixels = rgba(image) else { return nil }
    var values: [Double] = []
    values.reserveCapacity(image.width * image.height)
    for i in 0..<(image.width * image.height) {
        let r = Double(pixels[i * 4])
        let g = Double(pixels[i * 4 + 1])
        let b = Double(pixels[i * 4 + 2])
        values.append((0.2126 * r + 0.7152 * g + 0.0722 * b) / 255)
    }
    return values
}

func variance(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let mean = values.reduce(0, +) / Double(values.count)
    let sum = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
    return sum / Double(values.count)
}

// MARK: - Fiche

func renderFiche(job: Job, tint: PackTint, mark: CGImage?, width: CGFloat) -> CGImage {
    let height = width / (4.0 / 5.0)
    let ctx = context(width: Int(width), height: Int(height))!
    let full = CGRect(x: 0, y: 0, width: width, height: height)
    let paperColor = CGColor(srgbRed: paper.r, green: paper.g, blue: paper.b, alpha: 1)
    ctx.setFillColor(paperColor)
    ctx.fill(full)

    let margin = width * 0.07
    let badge = width * 0.105
    let headerTop = height - margin - badge
    if let mark, let painted = fittedMark(mark, side: Int(badge * 1.35), tint: tint.isPaper ? ink : tint.color) {
        let side = badge * 1.35
        ctx.draw(painted, in: CGRect(x: margin, y: headerTop - (side - badge) / 2, width: side, height: side))
    }

    let badges = badgeTexts(job)
    var x = width - margin - badge
    for text in badges.reversed() {
        drawBadge(text, in: CGRect(x: x, y: headerTop, width: badge, height: badge), ctx: ctx)
        x -= badge + badge * 0.18
    }

    let ruleY = headerTop - margin * 0.85
    ctx.setStrokeColor(hairline)
    ctx.setLineWidth(1)
    ctx.move(to: CGPoint(x: margin, y: ruleY))
    ctx.addLine(to: CGPoint(x: width - margin, y: ruleY))
    ctx.strokePath()

    let titleColor = tint.isPaper ? ink : tint.color
    let notesTop = drawNotes(job.notes, margin: margin, width: width, ctx: ctx)
    let titleRect = CGRect(
        x: margin,
        y: notesTop + 12,
        width: width - margin * 2,
        height: max(40, ruleY - notesTop - 28)
    )
    drawTitle(job.name, in: titleRect, color: titleColor, ctx: ctx)
    return ctx.makeImage()!
}

func drawNotes(_ notes: [String], margin: CGFloat, width: CGFloat, ctx: CGContext) -> CGFloat {
    guard !notes.isEmpty else { return margin }
    let contentWidth = width - margin * 2
    var y = margin
    let rowH: CGFloat = 28
    let shown = Array(notes.prefix(3).reversed())
    for note in shown {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 16, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: note, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink,
        ]))
        ctx.textPosition = CGPoint(x: margin, y: y + 8)
        CTLineDraw(line, ctx)
        y += rowH
        ctx.setStrokeColor(hairline)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: margin, y: y))
        ctx.addLine(to: CGPoint(x: margin + contentWidth, y: y))
        ctx.strokePath()
    }
    let label = CTFontCreateWithName("Helvetica" as CFString, 13, nil)
    let labelLine = CTLineCreateWithAttributedString(NSAttributedString(string: "Notes:", attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): label,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): nameGray,
    ]))
    y += 6
    ctx.textPosition = CGPoint(x: margin, y: y)
    CTLineDraw(labelLine, ctx)
    y += 22
    ctx.setStrokeColor(hairline)
    ctx.move(to: CGPoint(x: margin, y: y))
    ctx.addLine(to: CGPoint(x: margin + contentWidth, y: y))
    ctx.strokePath()
    return y + 8
}

func badgeTexts(_ job: Job) -> [String] {
    var marks: [String] = []
    if let code = origin[job.country] { marks.append(code) }
    if let score = job.score, score > 0, score <= 100 {
        marks.append("Q\(Int(score.rounded()))")
    }
    return marks
}

func guessCountry(_ image: CGImage) -> String {
    let text = recognize(image).joined(separator: " ")
    for name in origin.keys.sorted(by: { $0.count > $1.count }) where text.localizedCaseInsensitiveContains(name) {
        return name
    }
    return ""
}

func guessTitle(_ image: CGImage) -> String? {
    let skip: Set<String> = ["notes", "farmer", "region", "altitude", "variety", "process", "producer", "origin"]
    let lines = recognize(image)
    for line in lines {
        let words = line.split(separator: " ").map(String.init)
        guard (1...5).contains(words.count) else { continue }
        guard words.allSatisfy({ $0.count <= 16 }) else { continue }
        let letters = line.filter(\.isLetter)
        guard letters.count >= 4 else { continue }
        if words.contains(where: { skip.contains($0.lowercased().trimmingCharacters(in: .punctuationCharacters)) }) {
            continue
        }
        return line.trimmingCharacters(in: .whitespaces)
    }
    return nil
}

func drawBadge(_ text: String, in rect: CGRect, ctx: CGContext) {
    ctx.saveGState()
    ctx.setFillColor(CGColor(srgbRed: paper.r, green: paper.g, blue: paper.b, alpha: 1))
    ctx.addEllipse(in: rect)
    ctx.fillPath()
    ctx.setStrokeColor(hairline)
    ctx.setLineWidth(1.5)
    ctx.addEllipse(in: rect)
    ctx.strokePath()
    let font = CTFontCreateWithName("Helvetica" as CFString, rect.height * 0.32, nil)
    let color = ink
    let line = CTLineCreateWithAttributedString(NSAttributedString(
        string: text,
        attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
    ))
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
    ctx.textPosition = CGPoint(
        x: rect.midX - lineWidth / 2,
        y: rect.midY - (ascent - descent) / 2
    )
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

func drawTitle(_ text: String, in rect: CGRect, color: CGColor, ctx: CGContext) {
    guard !text.isEmpty else { return }
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    paragraph.lineBreakMode = .byWordWrapping
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, min(54, max(28, rect.width * 0.105)), nil)
    let attr = NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
    ])
    let framesetter = CTFramesetterCreateWithAttributedString(attr)
    let path = CGPath(rect: rect, transform: nil)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attr.length), path, nil)
    ctx.saveGState()
    ctx.clip(to: rect)
    CTFrameDraw(frame, ctx)
    ctx.restoreGState()
}

func fittedMark(_ stamp: CGImage, side: Int, tint: CGColor) -> CGImage? {
    guard let ctx = context(width: side, height: side) else { return nil }
    ctx.clear(CGRect(x: 0, y: 0, width: side, height: side))
    let scale = min(CGFloat(side) / CGFloat(stamp.width), CGFloat(side) / CGFloat(stamp.height))
    let dw = CGFloat(stamp.width) * scale
    let dh = CGFloat(stamp.height) * scale
    let dest = CGRect(x: (CGFloat(side) - dw) / 2, y: (CGFloat(side) - dh) / 2, width: dw, height: dh)
    ctx.draw(stamp, in: dest)
    ctx.setBlendMode(.sourceIn)
    ctx.setFillColor(tint)
    ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
    return ctx.makeImage()
}

func renderPlanche(_ rows: [(job: Job, scan: CGImage, mark: Mark, fiche: CGImage)]) -> CGImage {
    let rowH: CGFloat = 340
    let width: CGFloat = 980
    let height = rowH * CGFloat(rows.count) + 24
    let ctx = context(width: Int(width), height: Int(height))!
    ctx.setFillColor(CGColor(srgbRed: 0.97, green: 0.965, blue: 0.95, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for (index, row) in rows.enumerated() {
        let top = height - 12 - CGFloat(index + 1) * rowH
        drawFitted(row.scan, in: CGRect(x: 16, y: top + 36, width: 220, height: 280), ctx: ctx)
        if let stamp = row.mark.image {
            drawFitted(stamp, in: CGRect(x: 252, y: top + 70, width: 200, height: 220), ctx: ctx)
        }
        drawFitted(row.fiche, in: CGRect(x: 480, y: top + 16, width: 230, height: 288), ctx: ctx)
        let guessed = row.job.titleIsGuessed ? "titre lu sur le scan — " : ""
        let caption = "\(guessed)\(row.job.name) — \(row.mark.note)"
        let font = CTFontCreateWithName("Helvetica" as CFString, 13, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: caption, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink,
        ]))
        ctx.textPosition = CGPoint(x: 16, y: top + 12)
        CTLineDraw(line, ctx)
    }
    return ctx.makeImage()!
}

func drawFitted(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
    let scale = min(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
    let w = CGFloat(image.width) * scale
    let h = CGFloat(image.height) * scale
    let dest = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: dest)
}

// MARK: - Pixels

func downsample(_ image: CGImage, maxPixel: Int) -> CGImage? {
    let maxSide = max(image.width, image.height)
    if maxSide <= maxPixel { return image }
    let scale = CGFloat(maxPixel) / CGFloat(maxSide)
    let w = max(1, Int((CGFloat(image.width) * scale).rounded()))
    let h = max(1, Int((CGFloat(image.height) * scale).rounded()))
    guard let ctx = context(width: w, height: h) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()
}

func context(width: Int, height: Int) -> CGContext? {
    let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    ctx?.translateBy(x: 0, y: 0)
    return ctx
}

func rgba(_ image: CGImage) -> [UInt8]? {
    let width = image.width
    let height = image.height
    let row = width * 4
    var pixels = [UInt8](repeating: 0, count: height * row)
    guard let ctx = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: row,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return pixels
}

func imageFromRGBA(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
    let row = width * 4
    guard let ctx = context(width: width, height: height), let base = ctx.data else { return nil }
    let bytes = base.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * height)
    for y in 0..<height {
        let src = y * row
        let dst = y * ctx.bytesPerRow
        for x in 0..<row {
            bytes[dst + x] = pixels[src + x]
        }
    }
    return ctx.makeImage()
}
