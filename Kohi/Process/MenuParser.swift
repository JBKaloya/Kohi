import Foundation

/// How sure a menu reader is about one value.
nonisolated enum MenuConfidence: String, Codable, Sendable {
    /// Printed on the menu, word for word.
    case read
    /// Inferred: a section header, a roaster found inside a longer line, a
    /// name taken from a line that also carried the origin. Shown to confirm,
    /// never pre-filled.
    case uncertain
}

/// One value read off a menu. A field that is not there is missing, not
/// empty: it simply has no `MenuField`.
nonisolated struct MenuField: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Codable, Sendable {
        case name
        case roaster
        case country
        case process
        case variety
        case notes
        case method
        case price

        var label: String {
            switch self {
            case .name: "Coffee"
            case .roaster: "Roaster"
            case .country: "Country"
            case .process: "Process"
            case .variety: "Variety"
            case .notes: "Notes"
            case .method: "Method"
            case .price: "Price"
            }
        }
    }

    var kind: Kind
    var value: String
    var confidence: MenuConfidence

    var id: String { "\(kind.rawValue):\(value)" }
}

/// One coffee on a menu, with whatever could be read about it.
nonisolated struct MenuCandidate: Identifiable, Hashable, Sendable {
    var id: Int
    var fields: [MenuField]

    func field(_ kind: MenuField.Kind) -> MenuField? {
        fields.first { $0.kind == kind }
    }

    var name: String { field(.name)?.value ?? "" }

    /// Under the name in the picker: what else was found, uncertain values
    /// marked with a question mark.
    var summary: String {
        fields
            .filter { $0.kind != .name }
            .map { $0.confidence == .read ? $0.value : "\($0.value)?" }
            .joined(separator: " · ")
    }

    var isEmpty: Bool { name.isEmpty }
}

/// Reads a photographed café menu into coffees to pick from. On device, from
/// the OCR lines alone, with the same lexicons as the bag parser.
///
/// The menu decides nothing. It offers candidates; picking one fills only
/// what was read, and lists what was inferred as suggestions to confirm.
nonisolated enum MenuParser {
    /// Lines that are furniture rather than coffee.
    private static let furniture: Set<String> = [
        "menu", "coffee", "coffees", "cafe", "cafes", "today", "aujourdhui",
        "single origin", "singleorigin", "origine", "origin", "boissons", "drinks",
        "carte", "nos cafes", "our coffees", "guest", "guest roaster", "en ce moment",
        "this week", "cette semaine", "hot", "chaud", "prix", "price",
    ]

    /// Words that start a "Notes:" line.
    private static let noteMarkers = ["notes", "notes de", "tasting notes", "aromes", "saveurs", "goût", "gout"]

    static func parse(_ lines: [String], roasters: [String] = []) -> [MenuCandidate] {
        var blocks: [Block] = []
        var current = Block()
        var sectionMethod: String?

        func close() {
            if !current.isEmpty { blocks.append(current) }
            current = Block()
            current.sectionMethod = sectionMethod
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.count >= 2 else { continue }
            let folded = fold(line)
            if furniture.contains(folded) { continue }

            // "FILTRE", "Espresso" alone: a section header for what follows.
            if let method = methodWord(alone: line) {
                close()
                sectionMethod = method
                current.sectionMethod = method
                continue
            }

            let reading = read(line, roasters: roasters)

            // A new title once this block already has one.
            if reading.title != nil, current.title != nil {
                close()
            }
            current.absorb(reading)
        }
        close()

        return blocks.enumerated().compactMap { index, block in
            let candidate = block.candidate(id: index)
            return candidate.isEmpty ? nil : candidate
        }
    }

    /// The model's answer, kept only where the menu supports it: a value that
    /// does not appear in the OCR text is downgraded to uncertain, so a name
    /// the model made up can never pre-fill.
    static func grounded(_ candidates: [MenuCandidate], in lines: [String]) -> [MenuCandidate] {
        let text = fold(lines.joined(separator: " "))
        return candidates.enumerated().map { index, candidate in
            var candidate = candidate
            candidate.id = index
            candidate.fields = candidate.fields.map { field in
                var field = field
                if field.kind == .price {
                    let digits = field.value.filter(\.isNumber)
                    if !digits.isEmpty, !text.filter(\.isNumber).contains(digits) {
                        field.confidence = .uncertain
                    }
                } else if !text.contains(fold(field.value)) {
                    field.confidence = .uncertain
                }
                return field
            }
            return candidate
        }
        .filter { !$0.isEmpty }
    }

    // MARK: - One line

    struct Reading {
        var title: MenuField?
        var fields: [MenuField] = []
    }

    static func read(_ line: String, roasters: [String]) -> Reading {
        var reading = Reading()
        var rest = line
        let folded = fold(line)

        if let (amount, currency) = BagFieldParser.price(in: line) {
            reading.fields.append(MenuField(kind: .price, value: CupPrice(amount: Decimal(amount), currency: currency).formatted, confidence: .read))
            rest = strippingPrice(rest)
        }

        if let marker = noteMarkers.first(where: { folded.hasPrefix($0) }) {
            let body = String(line.dropFirst(marker.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " :–—-").union(.whitespaces))
            if !body.isEmpty {
                reading.fields.append(MenuField(kind: .notes, value: body, confidence: .read))
            }
            return reading
        }

        var named: [String] = []
        if let country = FieldParser.originNames.first(where: { contains(word: $0, in: folded) }) {
            reading.fields.append(MenuField(kind: .country, value: country, confidence: .read))
            named.append(country)
        }
        if let process = FieldParser.processNames.first(where: { contains(word: $0, in: folded) }) {
            reading.fields.append(MenuField(kind: .process, value: process, confidence: .read))
            named.append(process)
        }
        if let variety = FieldParser.varietyNames.first(where: { $0.count >= 4 && contains(word: $0, in: folded) }) {
            reading.fields.append(MenuField(kind: .variety, value: variety, confidence: .read))
            named.append(variety)
        }
        if let method = methodWord(in: line) {
            reading.fields.append(MenuField(kind: .method, value: method, confidence: .read))
            named.append(method)
        }

        let roaster = roasterIn(line, known: roasters)
        if let roaster {
            reading.fields.append(roaster)
            named.append(roaster.value)
        }

        // Comma-separated words with nothing else on the line: notes.
        let commas = rest.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if commas.count >= 2, named.isEmpty, commas.allSatisfy({ $0.split(separator: " ").count <= 3 }) {
            reading.fields.append(MenuField(kind: .notes, value: commas.joined(separator: ", "), confidence: .read))
            return reading
        }

        let titleText = rest
            .trimmingCharacters(in: CharacterSet(charactersIn: " ·•–—-|:").union(.whitespaces))
        guard titleText.count >= 3, titleText.contains(where: \.isLetter) else { return reading }

        // Nothing left once the known words are out ("Kenya, Washed",
        // "Fève"): an attribute line, not a coffee.
        var residue = " \(fold(titleText)) "
        for word in named {
            residue = residue.replacingOccurrences(of: " \(fold(word)) ", with: " ")
        }
        guard residue.filter(\.isLetter).count >= 3 else { return reading }

        // Origin in the name is how cafés write it ("Ethiopia Guji"). Any
        // other known word on the line makes which part is the name a guess.
        let onlyOrigin = named.allSatisfy { word in
            reading.fields.contains { $0.kind == .country && $0.value == word }
        }
        reading.title = MenuField(kind: .name, value: titleText, confidence: onlyOrigin ? .read : .uncertain)
        return reading
    }

    // MARK: - Words

    /// Lowercased, accents off, punctuation as spaces, single-spaced.
    static func fold(_ text: String) -> String {
        let plain = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US_POSIX"))
            .lowercased()
        let spaced = plain.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(spaced).split(separator: " ").joined(separator: " ")
    }

    static func contains(word: String, in folded: String) -> Bool {
        let needle = fold(word)
        guard !needle.isEmpty else { return false }
        return " \(folded) ".contains(" \(needle) ")
    }

    private static let methodWords: [(words: [String], label: String)] = [
        (["espresso", "expresso", "ristretto"], "Espresso"),
        (["v60", "hario v60"], "V60"),
        (["kalita", "kalita wave"], "Kalita"),
        (["chemex"], "Chemex"),
        (["aeropress"], "AeroPress"),
        (["batch", "batch brew", "filtre", "filter", "drip"], "Batch"),
    ]

    static func methodWord(in line: String) -> String? {
        let folded = fold(line)
        return methodWords.first { $0.words.contains { contains(word: $0, in: folded) } }?.label
    }

    static func methodWord(alone line: String) -> String? {
        let folded = fold(line)
        return methodWords.first { $0.words.contains(folded) }?.label
    }

    /// A known roaster on the line: read when the line is the roaster, else
    /// uncertain.
    private static func roasterIn(_ line: String, known: [String]) -> MenuField? {
        let folded = fold(line)
        let names = known.filter { fold($0).count >= 3 }
        if let exact = names.first(where: { fold($0) == folded || folded.hasPrefix("par \(fold($0))") || folded.hasPrefix("by \(fold($0))") || folded.hasPrefix("roasted by \(fold($0))") || folded.hasPrefix("torrefie par \(fold($0))") }) {
            return MenuField(kind: .roaster, value: exact, confidence: .read)
        }
        if let inside = names.sorted(by: { $0.count > $1.count }).first(where: { contains(word: $0, in: folded) }) {
            return MenuField(kind: .roaster, value: inside, confidence: .uncertain)
        }
        return nil
    }

    private static func strippingPrice(_ line: String) -> String {
        line.replacingOccurrences(
            of: #"(€|\$|£|¥|円)?\s?\d{1,6}(?:[ ,.]\d{3})*(?:[.,]\d{1,2})?\s?(€|\$|£|¥|円|eur|usd|gbp|jpy|chf)?"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Block

    private struct Block {
        var title: MenuField?
        var fields: [MenuField] = []
        var sectionMethod: String?

        var isEmpty: Bool { title == nil && fields.isEmpty }

        mutating func absorb(_ reading: Reading) {
            if let title = reading.title, self.title == nil { self.title = title }
            for field in reading.fields where !fields.contains(where: { $0.kind == field.kind }) {
                fields.append(field)
            }
        }

        func candidate(id: Int) -> MenuCandidate {
            var all: [MenuField] = []
            if let title { all.append(title) }
            all += fields
            if let sectionMethod, !all.contains(where: { $0.kind == .method }) {
                all.append(MenuField(kind: .method, value: sectionMethod, confidence: .uncertain))
            }
            // Without a name there is nothing to pick; a block of origin
            // words alone names itself after them, as a guess.
            if title == nil, let country = fields.first(where: { $0.kind == .country }) {
                all.insert(MenuField(kind: .name, value: country.value, confidence: .uncertain), at: 0)
            }
            return MenuCandidate(id: id, fields: all)
        }
    }
}
