import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import os

/// Turns a scan into an ink drawing, or into nothing. Nothing is a valid card.
nonisolated enum InkStampPipeline {
    struct Drawing: Sendable {
        var image: CGImage
        var rect: CGRect
        var metrics: InkStamp.Metrics
        var placement: InkStamp.Placement
        /// Cut by hue rather than by darkness. The area floor differs.
        var fromChroma: Bool = false
    }

    private static let signposter = OSSignposter(logger: Log.app)
    private static let maxPixel = 1024

    /// Steps (b)–(e). `textBoxes` and `barcodes` are normalized, origin bottom-left.
    /// `mask` is the pack cut-out when ingest kept one; nil means the scan is already the pack.
    static func draw(
        scan: CGImage,
        textBoxes: [CGRect] = [],
        barcodes: [CGRect] = [],
        manualRect: CGRect? = nil,
        mask: CGImage? = nil
    ) -> Drawing? {
        let state = signposter.beginInterval("ink")
        defer { signposter.endInterval("ink", state) }

        // A coloured mark is decided before the text is painted out. The
        // darkness chain still runs when this finds nothing.
        if manualRect == nil, let mark = PackMark.extract(scan) {
            return mark
        }

        guard let prepared = prepare(
            scan: scan, textBoxes: textBoxes, barcodes: barcodes, manualRect: manualRect, mask: mask
        ) else { return nil }

        let inked = prefersEdgeWork(prepared)
            ? edgeInk(prepared)
            : thresholdInk(prepared)
        guard let inked else { return nil }
        return measured(inked, pack: prepared)
    }

    /// Full chain including the word gate. Returns nil when the pack stays text.
    static func make(
        scan: CGImage,
        textBoxes: [CGRect],
        barcodes: [CGRect],
        manualRect: CGRect? = nil,
        mask: CGImage? = nil
    ) async -> InkStamp? {
        guard let drawing = draw(
            scan: scan, textBoxes: textBoxes, barcodes: barcodes, manualRect: manualRect, mask: mask
        ) else { return nil }

        let lines = await TextExtractor.read(image: drawing.image)
        let words = lines.flatMap { InkStampGates.words(in: $0.text) }
        let passes = drawing.fromChroma
            ? PackMark.accepted(drawing.metrics, words: words)
            : InkStampGates.accepted(drawing.metrics, words: words)
        guard passes else { return nil }

        return InkStamp(
            rect: drawing.rect,
            placement: drawing.placement,
            source: manualRect == nil ? .auto : .manual,
            version: InkStamp.pipelineVersion,
            metrics: drawing.metrics
        )
    }

    /// After a coffee is saved, when a tile appears with a stale measurement,
    /// or when Style asks again. One card at a time: the cost is the decode.
    static func backfill(
        cardID: UUID,
        library: StampLibrary,
        roasterName: String = "",
        manualRect: CGRect? = nil,
        force: Bool = false
    ) async {
        await StampLane.shared.acquire()
        await measure(
            cardID: cardID,
            library: library,
            roasterName: roasterName,
            manualRect: manualRect,
            force: force
        )
        await StampLane.shared.release()
    }

    private static func measure(
        cardID: UUID,
        library: StampLibrary,
        roasterName: String,
        manualRect: CGRect?,
        force: Bool
    ) async {
        guard ImageStore.shared.exists(cardID, kind: .flat) else { return }
        let revision = CardFiles.scanRevision(cardID)
        let existing = await library.file(for: cardID)
        if let existing, !force,
           existing.scanRevision == revision,
           existing.pipelineVersion == InkStamp.pipelineVersion,
           manualRect == nil {
            return
        }

        let flatURL = ImageStore.shared.url(for: cardID, kind: .flat)
        guard let scan = ImageCodec.downsample(flatURL, maxPixel: maxPixel) ?? ImageCodec.decode(flatURL) else {
            return
        }
        let ink = PackInkReader.read(scan)
        let mask = ImageStore.shared.exists(cardID, kind: .mask)
            ? ImageCodec.decode(ImageStore.shared.url(for: cardID, kind: .mask))
            : nil
        let boxes = await OCRSidecar.boxes(for: cardID)
        let keptStyle = existing?.style ?? .auto
        let region = force ? manualRect : (manualRect ?? existing?.manualRect)
        let seed = RoasterLineMatch.match(name: roasterName)

        var stamp: InkStamp?
        var vectorVersion: Int?
        if let seed, let logo = await RoasterMarkCache.fetchIfNeeded(seed: seed, force: force) {
            stamp = InkStamp(
                rect: CGRect(x: 0.06, y: 0.72, width: 0.22, height: 0.22),
                placement: .sticker,
                source: .library,
                version: InkStamp.pipelineVersion,
                metrics: InkStamp.Metrics(coverage: 0.4, areaRatio: 0.08, components: 1)
            )
            CardFiles.writeStamp(logo, id: cardID)
            CardFiles.removeStampShape(cardID)
        } else if let pixels = draw(
            scan: scan,
            textBoxes: boxes.text,
            barcodes: boxes.barcodes,
            manualRect: region,
            mask: mask
        ) {
            let lines = await TextExtractor.read(image: pixels.image)
            let words = lines.flatMap { InkStampGates.words(in: $0.text) }
            let passes = pixels.fromChroma
                ? PackMark.accepted(pixels.metrics, words: words)
                : InkStampGates.accepted(pixels.metrics, words: words)
            if passes {
                var metrics = pixels.metrics
                metrics.cropLongSide = max(pixels.image.width, pixels.image.height)
                stamp = InkStamp(
                    rect: pixels.rect,
                    placement: pixels.placement,
                    source: region == nil ? .auto : .manual,
                    version: InkStamp.pipelineVersion,
                    metrics: metrics
                )
                let soft = MarkMask.antialiased(pixels.image) ?? pixels.image
                CardFiles.writeStamp(soft, id: cardID)
                if let shape = MarkVectorizer.vectorize(soft) {
                    CardFiles.writeStampShape(shape, id: cardID)
                    vectorVersion = shape.version
                } else {
                    CardFiles.removeStampShape(cardID)
                }
            } else {
                CardFiles.removeStamp(cardID)
                CardFiles.removeStampShape(cardID)
            }
        } else {
            CardFiles.removeStamp(cardID)
            CardFiles.removeStampShape(cardID)
        }

        let file = StampFile(
            style: keptStyle,
            stamp: stamp,
            scanRevision: revision,
            pipelineVersion: InkStamp.pipelineVersion,
            manualRect: region,
            inkRed: ink?.red,
            inkGreen: ink?.green,
            inkBlue: ink?.blue,
            vectorVersion: vectorVersion
        )
        await library.replace(file, for: cardID)
    }

    // MARK: - Prepare

    private static func prepare(
        scan: CGImage,
        textBoxes: [CGRect],
        barcodes: [CGRect],
        manualRect: CGRect?,
        mask: CGImage?
    ) -> CGImage? {
        let source = ImagePipeline.downsample(scan, maxPixel: maxPixel) ?? scan
        let width = source.width
        let height = source.height
        guard let ctx = context(width: width, height: height) else { return nil }
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.setFillColor(paper)
        ctx.fill(full)

        if let mask {
            let lifted = masked(source, mask: mask) ?? source
            ctx.draw(lifted, in: full)
        } else {
            ctx.draw(source, in: full)
        }

        ctx.setFillColor(paper)
        if let manualRect {
            let keep = pixelRect(manualRect, width: width, height: height)
            let w = CGFloat(width)
            let h = CGFloat(height)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: keep.minY))
            ctx.fill(CGRect(x: 0, y: keep.maxY, width: w, height: h - keep.maxY))
            ctx.fill(CGRect(x: 0, y: keep.minY, width: keep.minX, height: keep.height))
            ctx.fill(CGRect(x: keep.maxX, y: keep.minY, width: w - keep.maxX, height: keep.height))
        }
        for box in (textBoxes + barcodes).map(dilated) {
            ctx.fill(pixelRect(box, width: width, height: height))
        }
        return ctx.makeImage()
    }

    /// High local variance means a photograph, which the threshold would turn into a slab.
    static func prefersEdgeWork(_ image: CGImage) -> Bool {
        guard let small = ImagePipeline.downsample(image, maxPixel: 96) else { return false }
        let values = luminances(small)
        let block = 8
        var variances: [Double] = []
        var y = 0
        while y + block <= small.height {
            var x = 0
            while x + block <= small.width {
                var sample: [Double] = []
                sample.reserveCapacity(block * block)
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

    // MARK: - Ink

    private static func thresholdInk(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let extent = input.extent
        let noir = CIFilter.photoEffectNoir()
        noir.inputImage = input
        guard let grey = noir.outputImage?.cropped(to: extent),
              let greyImage = ImagePipeline.context.createCGImage(grey, from: extent)
        else { return nil }
        let values = luminances(greyImage)
        let limit = otsu(values)
        var ink = values.map { $0 <= limit }
        ink = erode(ink, width: greyImage.width, height: greyImage.height)
        ink = dilate(ink, width: greyImage.width, height: greyImage.height)
        return raster(ink, width: greyImage.width, height: greyImage.height)
    }

    private static func edgeInk(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let extent = input.extent
        let edges = CIFilter.edgeWork()
        edges.inputImage = input
        edges.radius = 3
        guard let worked = edges.outputImage?.cropped(to: extent),
              let rendered = ImagePipeline.context.createCGImage(worked, from: extent)
        else { return nil }
        let values = luminances(rendered)
        var ink = values.map { $0 > 0.45 }
        ink = erode(ink, width: rendered.width, height: rendered.height)
        ink = dilate(ink, width: rendered.width, height: rendered.height)
        return raster(ink, width: rendered.width, height: rendered.height)
    }

    /// One-pixel opening: minimum, then maximum. Drops specks without moving the drawing.
    private static func erode(_ ink: [Bool], width: Int, height: Int) -> [Bool] {
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

    private static func dilate(_ ink: [Bool], width: Int, height: Int) -> [Bool] {
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

    private static func raster(_ ink: [Bool], width: Int, height: Int) -> CGImage? {
        guard let ctx = context(width: width, height: height), let base = ctx.data else { return nil }
        let row = ctx.bytesPerRow
        let bytes = base.bindMemory(to: UInt8.self, capacity: row * height)
        for index in ink.indices where ink[index] {
            let y = index / width
            let x = index % width
            let pixel = y * row + x * 4
            bytes[pixel] = 26
            bytes[pixel + 1] = 24
            bytes[pixel + 2] = 21
            bytes[pixel + 3] = 255
        }
        return ctx.makeImage()
    }

    private static func otsu(_ values: [Double]) -> Double {
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

    // MARK: - Measure

    private static func measured(_ image: CGImage, pack: CGImage) -> Drawing? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let total = width * height
        let dust = Int(Double(total) * 0.002)
        var seen = [Bool](repeating: false, count: total)
        var kept = [Bool](repeating: false, count: total)
        var componentCount = 0
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var inkCount = 0

        func index(_ x: Int, _ y: Int) -> Int { y * width + x }
        func isInk(_ i: Int) -> Bool { pixels[i * 4 + 3] > 32 }

        for y in 0..<height {
            for x in 0..<width {
                let start = index(x, y)
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
                        let next = index(nx, ny)
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

        let cropWidth = maxX - minX + 1
        let cropHeight = maxY - minY + 1
        let cropArea = cropWidth * cropHeight
        let packArea = max(pack.width * pack.height, 1)
        let metrics = InkStamp.Metrics(
            coverage: Double(inkCount) / Double(cropArea),
            areaRatio: Double(cropArea) / Double(packArea),
            components: componentCount
        )
        guard InkStampGates.accepted(metrics, words: []) else { return nil }

        // Clear dust that failed the component floor, then crop.
        for i in 0..<total where isInk(i) && !kept[i] {
            pixels[i * 4] = 0
            pixels[i * 4 + 1] = 0
            pixels[i * 4 + 2] = 0
            pixels[i * 4 + 3] = 0
        }
        guard let cleaned = ctx.makeImage(),
              let cropped = cleaned.cropping(to: CGRect(x: minX, y: minY, width: cropWidth, height: cropHeight)),
              let owned = copy(cropped)
        else { return nil }

        let rect = CGRect(
            x: Double(minX) / Double(width),
            y: Double(minY) / Double(height),
            width: Double(cropWidth) / Double(width),
            height: Double(cropHeight) / Double(height)
        )
        return Drawing(
            image: owned,
            rect: rect,
            metrics: metrics,
            placement: InkStampGates.placement(areaRatio: metrics.areaRatio, coverage: metrics.coverage)
        )
    }

    // MARK: - Pixels

    private static let paper = CGColor(red: 0.980, green: 0.973, blue: 0.957, alpha: 1)

    private static func copy(_ image: CGImage) -> CGImage? {
        guard let ctx = context(width: image.width, height: image.height) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func masked(_ image: CGImage, mask: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard let ctx = context(width: width, height: height) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.draw(image, in: rect)
        ctx.setBlendMode(.destinationIn)
        ctx.draw(mask, in: rect)
        guard let cut = ctx.makeImage(), let over = context(width: width, height: height) else { return nil }
        over.setFillColor(paper)
        over.fill(rect)
        over.draw(cut, in: rect)
        return over.makeImage()
    }

    /// Expands a normalized rect by 8% so anti-aliased glyph edges go with the text.
    private static func dilated(_ rect: CGRect) -> CGRect {
        let dx = rect.width * 0.04
        let dy = rect.height * 0.04
        return rect.insetBy(dx: -dx, dy: -dy)
    }

    /// Vision rects are bottom-left. CGContext in this file is bottom-left too.
    private static func pixelRect(_ normalized: CGRect, width: Int, height: Int) -> CGRect {
        CGRect(
            x: normalized.origin.x * CGFloat(width),
            y: normalized.origin.y * CGFloat(height),
            width: normalized.width * CGFloat(width),
            height: normalized.height * CGFloat(height)
        )
    }

    private static func luminances(_ image: CGImage) -> [Double] {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var values: [Double] = []
        values.reserveCapacity(width * height)
        for i in 0..<(width * height) {
            let r = Double(pixels[i * 4])
            let g = Double(pixels[i * 4 + 1])
            let b = Double(pixels[i * 4 + 2])
            values.append((0.2126 * r + 0.7152 * g + 0.0722 * b) / 255)
        }
        return values
    }

    private static func variance(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let sum = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return sum / Double(values.count)
    }
}

/// One measurement at a time. Decoding the flat scan is the cost, and a grid
/// of tiles would otherwise start a dozen of them together.
@MainActor
private final class StampLane {
    static let shared = StampLane()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
