import Foundation

/// Spelling pass for a brew narration. On-device, free, and the whole feature
/// when the model is off: coffee words the recogniser heard as English get
/// their catalogue names back, using the kit and the recipe as a dictionary.
nonisolated enum SpokenLexicon {
    static func terms(
        brew: Brew,
        recipe: Recipe?,
        equipment: [Equipment],
        filters: [FilterStock]
    ) -> [String] {
        var terms: [String] = Self.coffeeWords
        if let method = brew.method {
            terms.append(method.label)
            terms.append(contentsOf: method.aliases)
        }
        if let name = brew.recipeName, !name.isEmpty { terms.append(name) }
        if let recipe {
            terms.append(recipe.name)
            terms.append(recipe.method.label)
        }
        for item in equipment {
            terms.append(item.displayName)
            if !item.brand.isEmpty { terms.append(item.brand) }
            if !item.model.isEmpty { terms.append(item.model) }
        }
        for stock in filters {
            terms.append(stock.displayName)
            if let model = stock.model {
                terms.append(model.shortName)
                if !model.brand.isEmpty { terms.append(model.brand) }
            }
        }
        var seen = Set<String>()
        return terms.filter { term in
            let key = term.lowercased()
            guard key.count >= 3, seen.insert(key).inserted else { return false }
            return true
        }
    }

    static func rewrite(_ text: String, terms: [String]) -> String {
        var result = text
        for (pattern, replacement) in Self.mistakes {
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        let sorted = terms.sorted { $0.count > $1.count }
        for term in sorted {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: term))\\b"
            result = result.replacingOccurrences(
                of: pattern,
                with: term,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    /// The words a brew note actually uses, even when the kit is empty.
    static let coffeeWords: [String] = [
        "V60", "AeroPress", "Chemex", "Moka", "Kalita", "Origami",
        "Hario", "Cafec", "Sibarist", "Comandante", "1Zpresso",
        "bloom", "pour", "rinse", "drawdown", "bypass", "pulse",
        "swirl", "WDT", "clicks", "portafilter",
    ]

    private static let mistakes: [(String, String)] = [
        (#"\bv[\s-]?60\b"#, "V60"),
        (#"\bvee\s*sixty\b"#, "V60"),
        (#"\baero\s*press\b"#, "AeroPress"),
        (#"\bmocha\s*pot\b"#, "Moka"),
        (#"\bmoka\s*pot\b"#, "Moka"),
        (#"\bfrench\s*press\b"#, "French press"),
        (#"\bcold\s*brew\b"#, "cold brew"),
    ]
}

nonisolated extension BrewMethod {
    var aliases: [String] {
        switch self {
        case .v60: ["v 60", "pour over"]
        case .espresso: ["shot"]
        case .aeropress: ["aero press"]
        case .frenchPress: ["french press", "plunger"]
        case .moka: ["moka pot", "mocha pot"]
        case .coldBrew: ["cold brew"]
        case .filter: ["batch", "drip", "pour over", "hand brew"]
        }
    }
}
