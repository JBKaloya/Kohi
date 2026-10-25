import CoreGraphics
import Foundation
import Testing
@testable import Kohi

struct PackInkTests {
    @Test func paperHasNoInk() {
        let image = Self.image(side: 64) { _, _ in (250, 248, 242) }
        #expect(PackInkReader.read(image) == nil)
        #expect(PackMark.extract(image) == nil)
    }

    @Test func aSmallBlueMarkIsInkAndASymbol() {
        // 12×12 on 96×96 is about 1.6% of the frame: under the old area floor, above the new one.
        let image = Self.image(side: 96) { x, y in
            if (20..<32).contains(x), (20..<32).contains(y) { return (20, 40, 200) }
            return (250, 248, 242)
        }
        let ink = PackInkReader.read(image)
        #expect(ink != nil)
        #expect(ink?.isPrintedMark == true)
        #expect((ink?.share ?? 0) >= PackInk.shareFloor)
        #expect((ink?.share ?? 1) < PackInk.bagShare)

        let mark = PackMark.extract(image)
        #expect(mark != nil)
        #expect(mark?.fromChroma == true)
        #expect((mark?.metrics.areaRatio ?? 1) < 0.06)
        if let mark {
            #expect(PackMark.accepted(mark.metrics, words: []))
            #expect(!InkStampGates.accepted(mark.metrics, words: []))
            #expect(Self.opaqueCount(mark.image) > 20)
        }
    }

    @Test func aBagThatIsItselfBlueIsInkButNotASymbol() {
        let image = Self.image(side: 96) { x, y in
            if x > 4, y > 4 { return (20, 50, 190) }
            return (250, 248, 242)
        }
        let ink = PackInkReader.read(image)
        #expect(ink != nil)
        #expect(ink?.isPrintedMark == false)
        #expect(PackMark.extract(image) == nil)
    }

    @Test func scatteredNoiseDoesNotInventAHue() {
        var noise = 0
        let image = Self.image(side: 64) { x, y in
            noise = (noise * 17 + x * 13 + y * 7) % 255
            let jitter = UInt8(240 + noise % 15)
            return (jitter, jitter, UInt8(230 + noise % 10))
        }
        #expect(PackInkReader.read(image) == nil)
    }

    @Test func aRealCloverScanClearsTheSymbolGate() async throws {
        for name in [
            "43f1b7ff-92c1-4a7d-8300-db9117ea60db",
            "cbe9215b-1103-4408-ac36-39d15255a1ff",
        ] {
            let url = URL(fileURLWithPath: "/tmp/kohi-remote/\(name).heic")
            guard FileManager.default.fileExists(atPath: url.path),
                  let image = ImageCodec.decode(url) else { continue }
            let drawing = try #require(InkStampPipeline.draw(scan: image))
            #expect(drawing.fromChroma)
            let lines = await TextExtractor.read(image: drawing.image)
            let words = lines.flatMap { InkStampGates.words(in: $0.text) }
            #expect(PackMark.accepted(drawing.metrics, words: words), "\(name) words=\(words)")
        }
    }

    @Test func kloverMatchesTheSeedAndAShortNameDoesNotWin() {
        let seed = RoasterLineMatch.match(lines: ["KLOVER COFFEE PARIS", "Ethiopia"])
        #expect(seed?.slug == "klover")
        #expect(RoasterLineMatch.match(name: "Klover")?.name == "Klover")
    }

    private static func image(side: Int, pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
        var rgba = [UInt8](repeating: 255, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let color = pixel(x, y)
                let index = (y * side + x) * 4
                rgba[index] = color.0
                rgba[index + 1] = color.1
                rgba[index + 2] = color.2
                rgba[index + 3] = 255
            }
        }
        let ctx = CGContext(
            data: &rgba,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }

    private static func opaqueCount(_ image: CGImage) -> Int {
        guard let buffer = PackInkReader.buffer(image, maxSide: 256) else { return 0 }
        var count = 0
        for index in 0..<(buffer.width * buffer.height) {
            if buffer.rgba[index * 4 + 3] > 200 { count += 1 }
        }
        return count
    }
}

/// Runs the real reader on a folder of scans when one is present.
/// The folder is `KOHI_BENCH_SCANS`, or `/tmp/kohi-remote`. Absent, the test
/// does nothing: the thresholds live in `PackInkTests`.
struct PackBenchTests {
    @Test func reportScansWhenAFolderIsPresent() async {
        guard let folder = Self.folder() else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { ["heic", "jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        guard !files.isEmpty else { return }

        var named = 0
        var roasted = 0
        var inked = 0
        var marked = 0
        var report: [String] = []
        for url in files {
            guard let image = ImageCodec.decode(url) else { continue }
            let lines = await TextExtractor.readFromURL(url)
            let parsed = FieldParser.parse(lines)
            if parsed.name != nil { named += 1 }
            if parsed.roaster != nil { roasted += 1 }
            let ink = PackInkReader.read(image)
            if ink != nil { inked += 1 }
            let symbol = PackMark.extract(image) != nil
            if symbol { marked += 1 }
            let hue = ink.map { String(format: "%.0f", $0.hue * 360) } ?? "-"
            let share = ink.map { String(format: "%.1f%%", $0.share * 100) } ?? "-"
            let kind = ink.map { $0.isPrintedMark ? "mark" : "bag" } ?? "-"
            let line = "BENCH \(url.deletingPathExtension().lastPathComponent.prefix(8)) name=\(parsed.name ?? "-") roaster=\(parsed.roaster ?? "-") notes=\(parsed.tastingNotes.count) hue=\(hue) share=\(share) \(kind) symbol=\(symbol)"
            report.append(line)
            print(line)
        }
        let totals = "BENCH totals \(files.count) named=\(named) roaster=\(roasted) ink=\(inked) symbol=\(marked)"
        report.append(totals)
        print(totals)
        try? report.joined(separator: "\n").write(toFile: "/tmp/kohi-bench.txt", atomically: true, encoding: .utf8)
        #expect(files.count > 0)
    }

    private static func folder() -> URL? {
        if let raw = ProcessInfo.processInfo.environment["KOHI_BENCH_SCANS"], !raw.isEmpty {
            let url = URL(fileURLWithPath: raw)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        let fallback = URL(fileURLWithPath: "/tmp/kohi-remote")
        guard FileManager.default.fileExists(atPath: fallback.path) else { return nil }
        return fallback
    }
}
