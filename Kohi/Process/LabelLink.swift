import Foundation
import os

/// Fetches metadata from a URL found on a coffee label (QR code or Data Matrix).
/// Extracts og:title, og:description, and JSON-LD Product schema to pre-fill
/// card fields silently.
nonisolated enum LabelLink {
    struct Metadata: Sendable {
        var name: String?
        var roaster: String?
        var country: String?
        var region: String?
        var producer: String?
        var altitude: String?
        var variety: String?
        var process: String?
        var tastingNotes: [String] = []
    }

    /// Hosts whose pages describe an account, not a coffee. Scraping them
    /// turns follower counts into tasting notes, so the code is kept for the
    /// record and the page is left alone.
    private static let socialHosts = [
        "instagram.com", "facebook.com", "fb.com", "tiktok.com", "twitter.com",
        "x.com", "youtube.com", "youtu.be", "linktr.ee", "linkedin.com",
        "pinterest.com", "threads.net", "line.me", "weibo.com", "t.me",
        "wa.me", "whatsapp.com",
    ]

    /// Fetches the page at `urlString` and scrapes metadata. Times out after 8s.
    static func fetch(_ urlString: String) async -> Metadata? {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        if let host = url.host()?.lowercased(),
           socialHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            Log.app.notice("label link points at a social profile, not scraping it")
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X)",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8) else {
                return nil
            }
            return parse(html)
        } catch {
            Log.app.notice("label link fetch failed: \(error)")
            return nil
        }
    }

    // MARK: - HTML scraping

    private static func parse(_ html: String) -> Metadata {
        var meta = Metadata()

        // og:title → coffee name
        meta.name = ogContent(html, property: "og:title").flatMap(plausibleName)

        // og:description → may contain tasting notes
        if let desc = ogContent(html, property: "og:description") {
            let candidates = desc
                .split(whereSeparator: { ",;·".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.split(separator: " ").count <= 3 && !$0.isEmpty }
                .filter(plausibleNote)
            if candidates.count >= 2 && candidates.count <= 8 {
                meta.tastingNotes = candidates
            }
        }

        // JSON-LD Product
        if let jsonLD = extractJSONLD(html) {
            if meta.name == nil, let name = jsonLD["name"] as? String {
                meta.name = name
            }
            if let brand = jsonLD["brand"] as? [String: Any],
               let brandName = brand["name"] as? String {
                meta.roaster = brandName
            } else if let brand = jsonLD["brand"] as? String {
                meta.roaster = brand
            }
            if let desc = jsonLD["description"] as? String {
                parseDescription(desc, into: &meta)
            }
            for key in ["additionalProperty", "additionalProperties"] {
                if let props = jsonLD[key] as? [[String: Any]] {
                    for prop in props {
                        guard let name = prop["name"] as? String,
                              let value = prop["value"] as? String else { continue }
                        mapProperty(name: name, value: value, into: &meta)
                    }
                }
            }
        }

        // <title> as last resort
        if meta.name == nil, let title = extractTag(html, tag: "title") {
            let cleaned = title
                .replacingOccurrences(of: " – ", with: "|")
                .replacingOccurrences(of: " - ", with: "|")
                .replacingOccurrences(of: " | ", with: "|")
                .split(separator: "|")
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespaces)
            if let cleaned, !cleaned.isEmpty { meta.name = cleaned }
        }

        return meta
    }

    // MARK: - Scrape plausibility

    /// Words that reveal a scraped fragment came from a profile page or a
    /// storefront chrome, not a coffee description.
    private static let scrapeNoise = [
        "follower", "following", "abonnés", "abonnements", "suivis", "posts",
        "likes", "photos and videos", "sign up", "log in", "shop", "cart",
    ]

    private static func plausibleNote(_ note: String) -> Bool {
        let lowered = note.lowercased()
        guard note.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        guard !note.contains("@"), !lowered.contains("www."), !lowered.contains("http") else { return false }
        return !scrapeNoise.contains(where: { lowered.contains($0) })
    }

    private static func plausibleName(_ name: String) -> String? {
        let lowered = name.lowercased()
        guard !scrapeNoise.contains(where: { lowered.contains($0) }) else { return nil }
        return name
    }

    private static func parseDescription(_ desc: String, into meta: inout Metadata) {
        let lines = desc.components(separatedBy: .newlines)
        for line in lines {
            let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
            if lower.hasPrefix("country") || lower.hasPrefix("origin") {
                meta.country = meta.country ?? extractValue(line)
            } else if lower.hasPrefix("region") {
                meta.region = meta.region ?? extractValue(line)
            } else if lower.hasPrefix("producer") || lower.hasPrefix("farm") {
                meta.producer = meta.producer ?? extractValue(line)
            } else if lower.hasPrefix("altitude") || lower.hasPrefix("elevation") {
                meta.altitude = meta.altitude ?? extractValue(line)
            } else if lower.hasPrefix("variety") || lower.hasPrefix("varietal") {
                meta.variety = meta.variety ?? extractValue(line)
            } else if lower.hasPrefix("process") {
                meta.process = meta.process ?? extractValue(line)
            }
        }
    }

    private static func mapProperty(name: String, value: String, into meta: inout Metadata) {
        let key = name.lowercased()
        if key.contains("country") || key.contains("origin") {
            meta.country = meta.country ?? value
        } else if key.contains("region") {
            meta.region = meta.region ?? value
        } else if key.contains("producer") || key.contains("farm") {
            meta.producer = meta.producer ?? value
        } else if key.contains("altitude") || key.contains("elevation") {
            meta.altitude = meta.altitude ?? value
        } else if key.contains("variety") || key.contains("varietal") {
            meta.variety = meta.variety ?? value
        } else if key.contains("process") {
            meta.process = meta.process ?? value
        }
    }

    private static func extractValue(_ line: String) -> String? {
        let trimmed = line
            .trimmingCharacters(in: .whitespaces)
        guard let colonIndex = trimmed.firstIndex(of: ":") else { return nil }
        let value = trimmed[trimmed.index(after: colonIndex)...]
            .trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    // MARK: - Regex helpers

    private static func ogContent(_ html: String, property: String) -> String? {
        let pattern = "<meta[^>]+property=[\"']\(property)[\"'][^>]+content=[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            // Try reversed attribute order
            let alt = "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+property=[\"']\(property)[\"']"
            guard let regex2 = try? NSRegularExpression(pattern: alt, options: .caseInsensitive),
                  let match2 = regex2.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range2 = Range(match2.range(at: 1), in: html) else {
                return nil
            }
            return String(html[range2])
        }
        return String(html[range])
    }

    private static func extractTag(_ html: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>([^<]+)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractJSONLD(_ html: String) -> [String: Any]? {
        let pattern = "<script[^>]+type=[\"']application/ld\\+json[\"'][^>]*>([\\s\\S]*?)</script>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)

        for match in matches {
            guard let jsonRange = Range(match.range(at: 1), in: html) else { continue }
            let jsonString = String(html[jsonRange])
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }

            if let dict = json as? [String: Any] {
                if isProduct(dict) { return dict }
            } else if let array = json as? [[String: Any]] {
                if let product = array.first(where: isProduct) { return product }
            }
        }
        return nil
    }

    private static func isProduct(_ dict: [String: Any]) -> Bool {
        guard let type = dict["@type"] as? String else { return false }
        return type.lowercased().contains("product")
    }
}
