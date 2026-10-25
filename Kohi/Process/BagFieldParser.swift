import Foundation

/// Reads what the packaging says beyond the origin story: roast date and level,
/// lot, harvest, cupping score, price, bag weight, decaf.
///
/// Runs after the label pass in `FieldParser`, on the same normalised lines.
/// Kept apart because these values are typed — dates, numbers, enums — where
/// the label table only moves strings around. Same failure mode as everywhere
/// else: an empty field beats a wrong one.
nonisolated enum BagFieldParser {
    static func parse(_ texts: [String], into fields: inout ParsedFields) {
        for (index, line) in texts.enumerated() {
            let next = index + 1 < texts.count ? texts[index + 1] : nil

            if fields.roastedOn == nil {
                fields.roastedOn = roastDate(in: line, next: next)
            }
            if fields.cuppingScore == nil {
                fields.cuppingScore = cuppingScore(in: line)
            }
            if fields.agtron == nil {
                fields.agtron = agtron(in: line)
            }
            if fields.price == nil, let (amount, currency) = price(in: line) {
                fields.price = amount
                fields.currency = currency
            }
            if fields.bagWeightG == nil {
                fields.bagWeightG = bagWeight(in: line)
            }
            if fields.roastLevel == nil {
                fields.roastLevel = roastLevel(in: line)
            }
            if fields.isDecaf == nil, mentionsDecaf(line) {
                fields.isDecaf = true
            }
            if fields.decafMethod == nil, let method = DecafMethod.matching(line) {
                fields.decafMethod = method
                fields.isDecaf = true
            }
        }
    }

    // MARK: - Roast date

    /// Labels that introduce a roast date, in the four languages the scanner
    /// reads. `焙煎日` is one of them: `FieldParser` treats it as bag chrome when
    /// it lands in a *value*, which is right there and wrong here.
    private static let roastDateLabels = [
        "roasted on", "roast date", "roasted date", "date roasted", "roasted",
        "date de torréfaction", "torréfié le", "torrefie le", "torréfaction",
        "焙煎日", "焙煎年月日", "ロースト日",
        "烘焙日期", "烘焙日", "烘焙时间",
    ]

    /// Best-before labels. A date next to one of these is not a roast date, and
    /// on many bags the two sit one line apart.
    private static let expiryLabels = [
        "best before", "best by", "use by", "expiry", "expires",
        "à consommer", "a consommer", "date limite",
        "賞味期限", "消費期限", "保质期", "保存期限",
    ]

    private static func roastDate(in line: String, next: String?) -> Date? {
        let lowered = line.lowercased()
        guard !expiryLabels.contains(where: { lowered.contains($0) }) else { return nil }
        guard let label = roastDateLabels.first(where: { lowered.contains($0) }) else { return nil }

        // Whatever follows the label on the same line, else the line below.
        if let range = lowered.range(of: label) {
            let tail = String(line[range.upperBound...])
            if let date = date(in: tail) { return date }
        }
        if let next, !isLabelled(next) { return date(in: next) }
        return nil
    }

    private static func isLabelled(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return expiryLabels.contains { lowered.contains($0) }
    }

    /// A roast date is in the past and not ancient. A future date is a
    /// best-before that slipped through; a very old one is a misparse.
    private static func isPlausibleRoastDate(_ date: Date, now: Date) -> Bool {
        let calendar = Calendar.current
        guard let floor = calendar.date(byAdding: .year, value: -5, to: now),
              let ceiling = calendar.date(byAdding: .day, value: 2, to: now)
        else { return false }
        return date >= floor && date <= ceiling
    }

    /// Numeric, ISO, CJK and spelled-out dates. Ambiguous day/month pairs are
    /// read day-first: Kohi is written for European packaging, and a wrong
    /// guess here is visible in the form.
    static func date(in text: String, now: Date = .now) -> Date? {
        let candidates: [(pattern: String, order: [Component])] = [
            // 2026年3月12日
            (#"(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日"#, [.year, .month, .day]),
            // 2026-03-12, 2026/03/12, 2026.03.12
            (#"(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})"#, [.year, .month, .day]),
            // 12/03/2026, 12.03.2026, 12-03-2026
            (#"(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})"#, [.day, .month, .year]),
            // 12/03/26
            (#"(\d{1,2})[-/.](\d{1,2})[-/.](\d{2})\b"#, [.day, .month, .shortYear]),
        ]

        for candidate in candidates {
            guard let groups = capture(candidate.pattern, in: text, count: 3) else { continue }
            var parts: [Component: Int] = [:]
            for (component, value) in zip(candidate.order, groups) {
                guard let number = Int(value) else { continue }
                parts[component] = number
            }
            if let date = assemble(parts, now: now) { return date }
        }

        return spelledOutDate(in: text, now: now)
    }

    private enum Component { case year, month, day, shortYear }

    private static func assemble(_ parts: [Component: Int], now: Date) -> Date? {
        var year = parts[.year]
        if let short = parts[.shortYear] { year = 2000 + short }
        guard let year, var month = parts[.month], var day = parts[.day] else { return nil }

        // Day-first is the default, but "03/25/2026" can only be month-first.
        if month > 12, day <= 12 {
            swap(&month, &day)
        }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = Calendar.current.date(from: components) else { return nil }
        return isPlausibleRoastDate(date, now: now) ? date : nil
    }

    private static let monthNames: [String: Int] = [
        "january": 1, "février": 2, "february": 2, "janvier": 1,
        "march": 3, "mars": 3, "april": 4, "avril": 4,
        "may": 5, "mai": 5, "june": 6, "juin": 6,
        "july": 7, "juillet": 7, "august": 8, "août": 8, "aout": 8,
        "september": 9, "septembre": 9, "october": 10, "octobre": 10,
        "november": 11, "novembre": 11, "december": 12, "décembre": 12, "decembre": 12,
        "jan": 1, "feb": 2, "fév": 2, "mar": 3, "apr": 4, "avr": 4, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12, "déc": 12,
    ]

    /// "12 March 2026", "March 12, 2026", "12 mars 2026".
    private static func spelledOutDate(in text: String, now: Date) -> Date? {
        let lowered = text.lowercased()
        guard let entry = monthNames.first(where: { name, _ in
            lowered.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\b"#,
                          options: .regularExpression) != nil
        }) else { return nil }

        let numbers = capture(#"(\d{1,4})"#, in: lowered, count: 1, all: true) ?? []
        let values = numbers.compactMap(Int.init)
        guard let day = values.first(where: { (1...31).contains($0) }),
              let year = values.first(where: { $0 >= 1000 })
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = entry.value
        components.day = day
        guard let date = Calendar.current.date(from: components) else { return nil }
        return isPlausibleRoastDate(date, now: now) ? date : nil
    }

    // MARK: - Cupping score

    private static let scoreLabels = [
        "cupping score", "cup score", "sca score", "score", "sca", "q score",
        "note de dégustation", "score de dégustation", "得点", "评分", "評分",
    ]

    /// 55 to 100, as printed. Below 55 nobody prints a score; a bare number
    /// with a percent sign is moisture, not a cup.
    private static func cuppingScore(in line: String) -> Double? {
        let lowered = line.lowercased()
        guard scoreLabels.contains(where: { lowered.contains($0) }) else { return nil }
        guard !line.contains("%") else { return nil }
        guard let match = capture(#"(\d{2,3}([.,]\d{1,2})?)"#, in: line, count: 1)?.first else {
            return nil
        }
        guard let value = Double(match.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return (55...100).contains(value) ? value : nil
    }

    private static func agtron(in line: String) -> Int? {
        let lowered = line.lowercased()
        guard lowered.contains("agtron") else { return nil }
        guard let match = capture(#"(\d{2,3})"#, in: line, count: 1)?.first,
              let value = Int(match)
        else { return nil }
        return (0...120).contains(value) ? value : nil
    }

    // MARK: - Price

    private static let currencySymbols: [(token: String, code: String)] = [
        ("€", "EUR"), ("eur", "EUR"), ("$", "USD"), ("usd", "USD"),
        ("£", "GBP"), ("gbp", "GBP"), ("¥", "JPY"), ("jpy", "JPY"), ("円", "JPY"),
        ("chf", "CHF"), ("sek", "SEK"), ("nok", "NOK"), ("dkk", "DKK"),
    ]

    /// "14 €", "€14.00", "¥1,500", "14,50 EUR". Requires a currency marker:
    /// a bare number on a bag is a weight far more often than a price. Also
    /// how a café menu is read: the same rule holds on a chalkboard.
    static func price(in line: String) -> (Double, String)? {
        let lowered = line.lowercased()
        guard let currency = currencySymbols.first(where: { lowered.contains($0.token) }) else {
            return nil
        }
        // Avoid reading a price out of a weight or a percentage.
        guard !lowered.contains("%") else { return nil }

        let pattern = #"(\d{1,6}(?:[ ,.]\d{3})*(?:[.,]\d{1,2})?)"#
        guard let match = capture(pattern, in: line, count: 1)?.first else { return nil }

        // Thousands separators out, decimal comma to a point.
        var cleaned = match.replacingOccurrences(of: " ", with: "")
        if let lastComma = cleaned.lastIndex(of: ","),
           cleaned.distance(from: lastComma, to: cleaned.endIndex) <= 3,
           !cleaned.contains(".") {
            cleaned.replaceSubrange(lastComma...lastComma, with: ".")
            cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        } else {
            cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        }

        guard let value = Double(cleaned), value > 0, value < 100_000 else { return nil }
        return (value, currency.code)
    }

    // MARK: - Bag weight

    private static let ounceInGrams = 28.349523125

    /// Labels that make a mass unambiguous.
    private static let weightLabels = [
        "net wt", "net weight", "weight", "poids net", "poids", "contenu",
        "内容量", "净含量", "凈含量", "重量",
    ]

    /// Recipe vocabulary. "お湯 250g" is a brewing card's water, not a bag.
    private static let recipeWords = [
        "ml", "water", "eau", "湯", "水", "dose", "beans", "bean", "豆",
        "yield", "out", "ratio", "brew", "抽出", "grind",
    ]

    /// "250g", "1 kg", "12 oz", "内容量 250g".
    private static func bagWeight(in line: String) -> Double? {
        let lowered = line.lowercased()
        let labelled = weightLabels.contains { lowered.contains($0) }

        // Without a weight label, a mass has to stand nearly alone on its line
        // and share it with nothing that belongs to a recipe.
        if !labelled {
            guard !recipeWords.contains(where: { lowered.contains($0) }) else { return nil }
            guard lowered.split(separator: " ").count <= 3 else { return nil }
        }

        if let match = capture(#"(\d{1,4}(?:[.,]\d{1,2})?)\s*(kg|kilo|kilogram)s?\b"#,
                               in: lowered, count: 1)?.first,
           let value = Double(match.replacingOccurrences(of: ",", with: ".")) {
            let grams = value * 1000
            return (50...5000).contains(grams) ? grams : nil
        }
        if let match = capture(#"(\d{1,4}(?:[.,]\d{1,2})?)\s*(oz|ounces?)\b"#,
                               in: lowered, count: 1)?.first,
           let value = Double(match.replacingOccurrences(of: ",", with: ".")) {
            let grams = value * ounceInGrams
            return (50...5000).contains(grams) ? grams : nil
        }
        if let match = capture(#"(\d{2,4})\s*(g|gr|grams?|グラム|克)\b"#,
                               in: lowered, count: 1)?.first,
           let value = Double(match) {
            return (50...5000).contains(value) ? value : nil
        }
        return nil
    }

    // MARK: - Roast level

    /// Only explicit levels. "Omni" and "espresso roast" say what the roast is
    /// *for*, not how dark it is; mapping them to a notch would be inventing.
    private static let roastLevelTokens: [(token: String, level: RoastLevel)] = [
        ("super-light", .superLight), ("super light", .superLight),
        ("extra-light", .superLight), ("extra light", .superLight),
        ("ultra-light", .superLight), ("ultra light", .superLight),
        ("medium-light", .mediumLight), ("medium light", .mediumLight),
        ("light-medium", .mediumLight), ("moyen clair", .mediumLight),
        ("medium-dark", .mediumDark), ("medium dark", .mediumDark),
        ("moyen foncé", .mediumDark), ("中深煎り", .mediumDark), ("中深焙", .mediumDark),
        ("light roast", .light), ("torréfaction claire", .light),
        ("浅煎り", .light), ("浅焙", .light), ("淺焙", .light),
        ("dark roast", .dark), ("torréfaction foncée", .dark),
        ("深煎り", .dark), ("深焙", .dark),
        ("medium roast", .medium), ("torréfaction moyenne", .medium),
        ("中煎り", .medium), ("中焙", .medium),
    ]

    private static func roastLevel(in line: String) -> RoastLevel? {
        let lowered = line.lowercased()
        // Longest token first, so "medium-dark" is not read as "medium".
        for entry in roastLevelTokens.sorted(by: { $0.token.count > $1.token.count })
        where lowered.contains(entry.token) {
            return entry.level
        }

        // A bare "LIGHT" / "MEDIUM" heading, which is how many cards print it.
        let bare = lowered.trimmingCharacters(in: CharacterSet(charactersIn: " •·-—:"))
        switch bare {
        case "super-light", "super light", "extra light", "ultra light": return .superLight
        case "light": return .light
        case "medium-light", "medium light": return .mediumLight
        case "medium": return .medium
        case "medium-dark", "medium dark": return .mediumDark
        case "dark": return .dark
        default: return nil
        }
    }

    // MARK: - Decaf

    private static let decafTokens = [
        "decaf", "decaffeinated", "décaféiné", "decafeine", "sans caféine",
        "swiss water", "sugarcane ea", "ethyl acetate", "co2 decaf", "descafeinado",
        "デカフェ", "カフェインレス", "低咖啡因", "無咖啡因", "无咖啡因",
    ]

    private static func mentionsDecaf(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return decafTokens.contains { lowered.contains($0) }
    }

    // MARK: - Regex

    /// First match's capture groups, or every first group when `all` is set.
    private static func capture(
        _ pattern: String,
        in text: String,
        count: Int,
        all: Bool = false
    ) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return nil }
        let range = NSRange(text.startIndex..., in: text)

        if all {
            let matches = regex.matches(in: text, range: range)
            let values = matches.compactMap { match -> String? in
                guard let sub = Range(match.range(at: 1), in: text) else { return nil }
                return String(text[sub])
            }
            return values.isEmpty ? nil : values
        }

        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        var groups: [String] = []
        for index in 1...max(count, 1) where index < match.numberOfRanges {
            guard let sub = Range(match.range(at: index), in: text) else { continue }
            groups.append(String(text[sub]))
        }
        return groups.isEmpty ? nil : groups
    }
}
