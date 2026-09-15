import Foundation

/// Reads a brewing recipe off a card, when one is printed: dose, water, time,
/// temperature, grind. Cards write these bilingually (KOFFEE MAMEYA prints
/// 豆量 over "Beans") or in Chinese alone, so every label carries its aliases.
/// Returns nil unless at least two quantities were found — one number alone is
/// as likely a bag weight as a recipe.
nonisolated enum RecipeParser {
    private enum Slot {
        case dose, water, time, temperature, grind, ratio
    }

    private static let labels: [(keys: [String], slot: Slot)] = [
        (["dose", "coffee weight", "beans", "bean", "café", "coffee",
          "豆量", "粉量", "粉重", "使用豆量", "粉重量"], .dose),
        (["total water", "hot water", "water", "eau",
          "お湯の量", "湯量", "注水量", "水量"], .water),
        (["total brew time", "brew time", "brewing time", "time", "temps",
          "抽出時間", "萃取时间", "萃取時間", "时间", "時間"], .time),
        (["temperature", "temp", "température",
          "お湯の温度", "水温", "湯温", "温度", "水溫"], .temperature),
        (["grind size", "grind", "mouture",
          "挽き目", "研磨度", "粒度", "刻度"], .grind),
        (["brew ratio", "ratio", "比例", "粉水比"], .ratio),
    ]

    /// How the card names the method, mapped to the app's vocabulary.
    private static let methodHints: [(match: String, method: BrewMethod)] = [
        ("aeropress", .aeropress),
        ("french press", .frenchPress),
        ("cold brew", .coldBrew),
        ("espresso", .espresso),
        ("v60", .v60),
        ("moka", .moka),
        ("pour over", .filter),
        ("drip", .filter),
        ("filter", .filter),
        ("手冲", .filter), ("手沖", .filter), ("滴滤", .filter), ("滴濾", .filter),
        ("ドリップ", .filter), ("エスプレッソ", .espresso),
    ]

    static func parse(_ texts: [String]) -> Brew? {
        var dose: Double?
        var water: Double?
        var seconds: Int?
        var temperature: Double?
        var grind: String?
        var ratio: Double?

        for (index, line) in texts.enumerated() {
            for entry in labels {
                // Handwritten recipes scatter: the number the label points at
                // may be one or two OCR lines away, behind a stray annotation.
                // Each candidate gets a chance; range checks pick the real one.
                for raw in values(for: entry.keys, line: line, index: index, texts: texts) {
                    switch entry.slot {
                    case .dose:
                        if dose == nil, let n = number(in: raw), (4...100).contains(n) { dose = n }
                    case .water:
                        if water == nil, let n = number(in: raw), (50...2000).contains(n) { water = n }
                    case .time:
                        if seconds == nil { seconds = parseTime(raw) }
                    case .temperature:
                        if temperature == nil, let n = number(in: raw), (60...100).contains(n) { temperature = n }
                    case .grind:
                        if grind == nil, let setting = grindSetting(raw) { grind = setting }
                    case .ratio:
                        if ratio == nil { ratio = parseRatio(raw) }
                    }
                }
            }
        }

        if water == nil, let dose, let ratio { water = (dose * ratio).rounded() }

        let quantities: [Double?] = [dose, water, seconds.map(Double.init), temperature]
        guard quantities.compactMap(\.self).count >= 2 else { return nil }

        return Brew(
            method: detectMethod(texts),
            dose: dose,
            water: water,
            seconds: seconds,
            grind: GrindSetting(raw: grind ?? ""),
            temperature: temperature
        )
    }

    // MARK: - Label and value plumbing

    /// Candidate values for a label: what follows it on the same line, then up
    /// to three of the next OCR lines (handwritten values drift), stopping at
    /// the next label.
    private static func values(for keys: [String], line: String, index: Int, texts: [String]) -> [String] {
        for key in keys.sorted(by: { $0.count > $1.count }) {
            guard let rest = remainder(of: line, afterLabel: key) else { continue }
            var candidates: [String] = []
            if !rest.isEmpty { candidates.append(rest) }
            for ahead in 1...3 {
                guard index + ahead < texts.count else { break }
                let candidate = texts[index + ahead].trimmingCharacters(in: .whitespaces)
                guard !candidate.isEmpty, !isAnyLabel(candidate) else { break }
                guard candidate.split(separator: " ").count <= 4 else { break }
                candidates.append(candidate)
            }
            return candidates
        }
        return []
    }

    private static func isAnyLabel(_ line: String) -> Bool {
        for entry in labels {
            for key in entry.keys where remainder(of: line, afterLabel: key) != nil {
                return true
            }
        }
        return false
    }

    private static func remainder(of line: String, afterLabel label: String) -> String? {
        let trimmed = line
            .replacingOccurrences(of: "：", with: ":")
            .trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix(label) else { return nil }

        let boundary = trimmed.index(trimmed.startIndex, offsetBy: label.count)
        if boundary < trimmed.endIndex {
            let next = trimmed[boundary]
            guard ": \t-–—".contains(next) else { return nil }
        }
        return String(trimmed[boundary...])
            .trimmingCharacters(in: CharacterSet(charactersIn: " :–—-\t"))
    }

    // MARK: - Value parsing

    /// A grind is a word or a dial setting ("Medium fine", "EK#14"). Anything
    /// with a slash, a step marker, or CJK is the pour schedule that follows
    /// the recipe, not the setting.
    private static func grindSetting(_ raw: String) -> String? {
        guard !raw.isEmpty, raw.split(separator: " ").count <= 3 else { return nil }
        guard !raw.contains(where: { "/\\、。".contains($0) }) else { return nil }
        guard !raw.unicodeScalars.contains(where: {
            (0x2460...0x24FF).contains($0.value)      // ①②③ step markers
                || (0x3040...0x30FF).contains($0.value)
                || (0x4E00...0x9FFF).contains($0.value)
        }) else { return nil }
        guard number(in: raw) == nil || raw.contains("#") else { return nil }
        return raw
    }

    private static func number(in text: String) -> Double? {
        guard let range = text.range(of: #"\d+([.,]\d+)?"#, options: .regularExpression) else {
            return nil
        }
        return Double(text[range].replacingOccurrences(of: ",", with: "."))
    }

    /// "2:30", "140 sec", "140秒", "2 min", or a bare number: over 20 reads as
    /// seconds, 20 or under as minutes — nobody brews for 14 seconds or 140 minutes.
    private static func parseTime(_ text: String) -> Int? {
        let lowered = text.lowercased()
        if let range = lowered.range(of: #"(\d+)\s*[::]\s*(\d{2})"#, options: .regularExpression) {
            let parts = lowered[range].split(whereSeparator: { ":：".contains($0) })
            if parts.count == 2, let m = Int(parts[0].trimmingCharacters(in: .whitespaces)),
               let s = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                return m * 60 + s
            }
        }
        guard let n = number(in: lowered) else { return nil }
        if lowered.contains("min") || lowered.contains("分") { return Int(n * 60) }
        if lowered.contains("sec") || lowered.contains("秒") || lowered.hasSuffix("s") { return Int(n) }
        return n > 20 ? Int(n) : Int(n * 60)
    }

    /// "1:15" or "1/15" — the coffee side is always 1 on cards.
    private static func parseRatio(_ text: String) -> Double? {
        guard let range = text.range(of: #"1\s*[::/]\s*(\d+([.,]\d+)?)"#, options: .regularExpression) else {
            return nil
        }
        let match = text[range]
        guard let divider = match.rangeOfCharacter(from: CharacterSet(charactersIn: ":：/")) else {
            return nil
        }
        return Double(match[divider.upperBound...]
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: "."))
    }

    private static func detectMethod(_ texts: [String]) -> BrewMethod? {
        var found: Set<BrewMethod> = []
        for line in texts {
            let lowered = line.lowercased()
            for hint in methodHints where lowered.contains(hint.match) {
                found.insert(hint.method)
            }
        }
        // "Espresso / Filter" on a card describes the roast, not this recipe.
        return found.count == 1 ? found.first : nil
    }
}
