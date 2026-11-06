import Foundation

/// One scan button for whatever sits next to the cup: the café's card, a
/// menu, or the bag. The text decides which it was.
nonisolated enum TastingCapture {
    enum Reading: Equatable {
        /// One coffee: a café card, a bag, or a board with a single coffee.
        /// `extra` carries what only a menu line says (method, price), and
        /// anything read as a guess.
        case fields(ParsedFields, extra: [MenuField])
        /// Several coffees: ask which one is in the cup.
        case menu([MenuCandidate])
        /// Nothing that reads as a coffee.
        case nothing
    }

    static func sort(_ texts: [String], roasters: [String]) -> Reading {
        sort(
            texts.enumerated().map { index, text in
                TextExtractor.Line(text: text, y: Double(index) * 0.03, x: 0)
            },
            roasters: roasters
        )
    }

    static func sort(_ lines: [TextExtractor.Line], roasters: [String]) -> Reading {
        let texts = lines.map(\.text)
        let candidates = MenuParser.parse(texts.filter(isMenuLine), roasters: roasters)
        let entries = candidates.filter(isMenuEntry)

        if entries.count >= 2 {
            return .menu(entries.enumerated().map { index, candidate in
                var candidate = candidate
                candidate.id = index
                return candidate
            })
        }

        var parsed = FieldParser.parse(lines)
        var extra: [MenuField] = []
        let single = entries.first ?? (candidates.count == 1 ? candidates.first : nil)

        let menuName = single?.field(.name).map { ($0, cleanName($0.value)) }
        extra = single?.fields.filter { $0.kind == .method || $0.kind == .price } ?? []

        if parsed.name == nil, let (field, cleaned) = menuName, field.confidence == .read, !cleaned.isEmpty {
            parsed.name = cleaned
        }
        if parsed.name == nil, let country = parsed.country {
            parsed.name = originLedName(country: country, in: texts)
        }
        if parsed.name == nil, let (_, cleaned) = menuName, !cleaned.isEmpty {
            extra.append(MenuField(kind: .name, value: cleaned, confidence: .uncertain))
        }

        guard parsed.name != nil || parsed.roaster != nil || parsed.country != nil
                || extra.contains(where: { $0.kind == .name }) else {
            return .nothing
        }
        return .fields(parsed, extra: extra)
    }

    // MARK: - Menu or card

    /// A labelled field ("Process: Washed") or a sentence belongs to a card,
    /// never to a menu entry.
    private static func isMenuLine(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let words = trimmed.split(separator: " ").filter { $0.contains(where: \.isLetter) }
        if words.count > 6 { return false }
        if let colon = trimmed.firstIndex(of: ":") {
            let label = trimmed[..<colon].trimmingCharacters(in: .whitespaces)
            if !label.isEmpty, label.split(separator: " ").count <= 3 { return false }
        }
        return true
    }

    /// What a café writes for each coffee on a board: a price, or a name
    /// that starts from an origin ("Kenya Kiambu AA").
    private static func isMenuEntry(_ candidate: MenuCandidate) -> Bool {
        if candidate.field(.price)?.confidence == .read { return true }
        guard let name = candidate.field(.name), name.confidence == .read,
              let country = candidate.field(.country)?.value else { return false }
        let folded = MenuParser.fold(name.value)
        return folded.hasPrefix(MenuParser.fold(country)) && folded != MenuParser.fold(country)
    }

    // MARK: - Names

    /// "Ethiopia Chelchele — V60" → "Ethiopia Chelchele".
    static func cleanName(_ value: String) -> String {
        let separators = CharacterSet(charactersIn: "—–|·•")
        let first = value
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { segment in
                segment.contains(where: \.isLetter) && MenuParser.methodWord(alone: segment) == nil
            } ?? ""
        return first.trimmingCharacters(in: CharacterSet(charactersIn: " -:").union(.whitespaces))
    }

    /// Cards often name the coffee only inside a sentence: "Kenya Tekangu
    /// comes from…". The origin and the capitalised words after it.
    static func originLedName(country: String, in texts: [String]) -> String? {
        let countryWords = country.split(separator: " ").count
        for text in texts {
            let words = text.split(separator: " ").map(String.init)
            guard words.count > countryWords else { continue }
            let head = words.prefix(countryWords).joined(separator: " ")
            guard MenuParser.fold(head) == MenuParser.fold(country) else { continue }
            let rest = words.dropFirst(countryWords).prefix(2).prefix { word in
                guard let first = word.first, first.isUppercase else { return false }
                return word.count >= 3 && word.allSatisfy { $0.isLetter || $0 == "-" }
            }
            guard !rest.isEmpty else { continue }
            return ([country] + rest).joined(separator: " ")
        }
        return nil
    }
}
