import CoreGraphics
import Foundation
import ImageIO
import os

/// One logo per roaster, fetched from the roaster's own site and kept.
/// A miss is remembered too, so a scan does not hit the network twice.
/// Tests leave this alone: the fetch is skipped when a test bundle is loaded.
nonisolated enum RoasterMarkCache {
    private static let log = Logger(subsystem: "studio.jbk.kohiapp", category: "mark")

    static var fetchingEnabled: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    static func cached(slug: String) -> CGImage? {
        let url = file(slug: slug, ext: "png")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return image
    }

    static func attempted(slug: String) -> Bool {
        if cached(slug: slug) != nil { return true }
        return FileManager.default.fileExists(atPath: file(slug: slug, ext: "miss").path)
    }

    static func store(_ image: CGImage, slug: String) {
        guard let data = ImageCodec.encodePNG(image) else { return }
        let url = file(slug: slug, ext: "png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.removeItem(at: file(slug: slug, ext: "miss"))
    }

    /// Downloads the site's icon once. Returns the cached image, or nil.
    static func fetchIfNeeded(seed: RoasterSeed, force: Bool) async -> CGImage? {
        if let cached = cached(slug: seed.slug) { return cached }
        guard fetchingEnabled, let website = seed.website, !website.isEmpty else { return nil }
        if attempted(slug: seed.slug), !force { return nil }
        guard let image = await fetchIcon(website: website) else {
            markMiss(slug: seed.slug)
            return nil
        }
        let fitted = ImagePipeline.downsample(image, maxPixel: 256) ?? image
        store(fitted, slug: seed.slug)
        return fitted
    }

    // MARK: - Disk

    private static func markMiss(slug: String) {
        let url = file(slug: slug, ext: "miss")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data().write(to: url)
    }

    private static func file(slug: String, ext: String) -> URL {
        directory().appendingPathComponent("\(slug).\(ext)")
    }

    private static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("RoasterMarks", isDirectory: true)
    }

    // MARK: - Fetch

    private static func fetchIcon(website: String) async -> CGImage? {
        guard let page = url(website) else { return nil }
        var request = URLRequest(url: page, timeoutInterval: 8)
        request.setValue("Kohi", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { return nil }
            let html = String(data: data, encoding: .utf8) ?? ""
            let candidates = iconURLs(in: html, base: page) + [page.appendingPathComponent("favicon.ico")]
            for candidate in candidates {
                if let image = await download(candidate), min(image.width, image.height) >= 32 {
                    return image
                }
            }
        } catch {
            log.debug("mark fetch failed: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    private static func download(_ url: URL) async -> CGImage? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Kohi", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
              data.count < 1_500_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return image
    }

    private static func url(_ website: String) -> URL? {
        if let url = URL(string: website), url.scheme != nil { return url }
        return URL(string: "https://\(website)")
    }

    /// apple-touch-icon first, then any rel=icon. Social images are photos, not marks.
    private static func iconURLs(in html: String, base: URL) -> [URL] {
        let patterns = [
            "apple-touch-icon[^>]*href\\s*=\\s*[\"']([^\"']+)",
            "href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*apple-touch-icon",
            "rel\\s*=\\s*[\"'][^\"']*icon[^\"']*[\"'][^>]*href\\s*=\\s*[\"']([^\"']+)",
            "href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*rel\\s*=\\s*[\"'][^\"']*icon",
        ]
        var found: [URL] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            for match in regex.matches(in: html, range: range) {
                guard match.numberOfRanges > 1, let slice = Range(match.range(at: 1), in: html) else { continue }
                let raw = String(html[slice])
                if let resolved = URL(string: raw, relativeTo: base)?.absoluteURL {
                    found.append(resolved)
                }
            }
        }
        var seen: Set<String> = []
        return found.filter { seen.insert($0.absoluteString).inserted }
    }
}
