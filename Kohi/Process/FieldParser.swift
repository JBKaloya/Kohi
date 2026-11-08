import CoreGraphics
import Foundation

/// Best-effort metadata read off a card. Every field is optional and every field
/// is wrong sometimes; the edit sheet is the real answer.
nonisolated struct ParsedFields: Equatable, Sendable {
    var name: String?
    var roaster: String?
    var country: String?
    var region: String?
    var producer: String?
    var altitude: String?
    var variety: String?
    var process: String?
    var tastingNotes: [String] = []
    var labelCode: String?

    // On the bag. Read by `BagFieldParser`, which runs after the label pass.
    var roastLevel: RoastLevel?
    var agtron: Int?
    var roastedOn: Date?
    var harvest: String?
    var cuppingScore: Double?
    var price: Double?
    var currency: String?
    var bagWeightG: Double?
    var lot: String?
    /// Only ever set to `true`: nothing on a bag says "this is not decaf".
    var isDecaf: Bool?
    var decafMethod: DecafMethod?
    /// Product page from a QR http(s). Distinct from the raw `labelCode`.
    var productURL: String?

    /// Brew recipe printed on the card, when one was recognised.
    var recipe: Brew?
    /// Language the card was written in when it was not English ("ja", "zh").
    /// Drives translation and the vision fallback.
    var sourceLanguage: String?
    /// Original text per field, kept when a translation replaced the value.
    var originalFields: [String: String] = [:]
    /// Lines OCR found before any parsing. Tells a photo that is not a card
    /// apart from a card this parser could not make sense of.
    var linesRead = 0
    /// What the vision model filled, when it ran. Carried to the edit sheet
    /// so the save can say whether those values were kept.
    var modelFill: ModelFill?

    var isEmpty: Bool {
        name == nil && roaster == nil && country == nil && region == nil
            && producer == nil && altitude == nil && variety == nil
            && process == nil             && tastingNotes.isEmpty && labelCode == nil && productURL == nil
            && recipe == nil && !hasBagFields
    }

    var hasBagFields: Bool {
        roastLevel != nil || agtron != nil || roastedOn != nil || harvest != nil
            || cuppingScore != nil || price != nil || bagWeightG != nil
            || lot != nil || isDecaf != nil || decafMethod != nil || productURL != nil
    }

    /// How many fields the local read managed to fill.
    var filledCount: Int {
        let strings = [name, roaster, country, region, producer, altitude, variety, process]
        return strings.compactMap(\.self).count
            + (tastingNotes.isEmpty ? 0 : 1)
            + (recipe == nil ? 0 : 1)
    }

    /// Whether the local read is weak enough to be worth a second opinion from
    /// the vision model: handwriting, foreign scripts, and free-form layouts
    /// all land here.
    var wantsVisionAssist: Bool {
        guard linesRead > 0 else { return false }
        // Which fields are empty matters more than how many filled.
        // Three weak fields with no name and no notes used to look "enough".
        if name == nil, tastingNotes.isEmpty { return true }
        if sourceLanguage != nil { return filledCount < 5 }
        if linesRead < 4 { return true }
        return filledCount < 3
    }

    /// Merges metadata fetched from a label link, filling only nil fields.
    mutating func mergeLinked(_ linked: LabelLink.Metadata) {
        name = name ?? linked.name
        roaster = roaster ?? linked.roaster
        country = country ?? linked.country
        region = region ?? linked.region
        producer = producer ?? linked.producer
        altitude = altitude ?? linked.altitude
        variety = variety ?? linked.variety
        process = process ?? linked.process
        if tastingNotes.isEmpty { tastingNotes = linked.tastingNotes }
    }

    /// Fills empty fields from another parse (the vision fallback). Never
    /// replaces something the local read or the user already produced.
    mutating func fillMissing(from other: ParsedFields) {
        name = name ?? other.name
        roaster = roaster ?? other.roaster
        country = country ?? other.country
        region = region ?? other.region
        producer = producer ?? other.producer
        altitude = altitude ?? other.altitude
        variety = variety ?? other.variety
        process = process ?? other.process
        if tastingNotes.isEmpty { tastingNotes = other.tastingNotes }
        recipe = recipe ?? other.recipe
        sourceLanguage = sourceLanguage ?? other.sourceLanguage
        originalFields.merge(other.originalFields) { current, _ in current }
        fillMissingBagFields(from: other)
    }

    /// Same rule for the bag fields: fill the holes, touch nothing else.
    mutating func fillMissingBagFields(from other: ParsedFields) {
        roastLevel = roastLevel ?? other.roastLevel
        agtron = agtron ?? other.agtron
        roastedOn = roastedOn ?? other.roastedOn
        harvest = harvest ?? other.harvest
        cuppingScore = cuppingScore ?? other.cuppingScore
        price = price ?? other.price
        currency = currency ?? other.currency
        bagWeightG = bagWeightG ?? other.bagWeightG
        lot = lot ?? other.lot
        isDecaf = isDecaf ?? other.isDecaf
        decafMethod = decafMethod ?? other.decafMethod
        productURL = productURL ?? other.productURL
    }
}

/// Layered heuristics over the OCR lines. Layer one is label matching
/// ("Altitude: 1800m") in English, French, Japanese, and Chinese. Layer two
/// reads the parenthesised-token layout some roasters use. Layer three
/// classifies leftover unlabeled lines by lexicon. The failure mode stays the
/// same on every layer: an empty field, not a wrong one.
nonisolated enum FieldParser {
    // MARK: - Vocabulary

    // Computed rather than stored: a key path table is not `Sendable`, and
    // rebuilding this handful of strings costs nothing next to the OCR.
    private static var fieldLabels: [(keys: [String], name: String, field: WritableKeyPath<ParsedFields, String?>)] {[
        // "lot" used to sit here, so "Lot: 24-118" became the coffee's name.
        // It has its own field now.
        (["coffee", "name", "nom", "名称", "品名", "商品名"], "name", \.name),
        (["roaster", "roasted by", "roastery", "torréfacteur",
          "ロースター", "焙煎所", "焙煎者", "烘焙商", "烘焙者"], "roaster", \.roaster),
        (["farmer", "producer", "grower", "farm", "cooperative", "co-op", "washing station",
          "producteur", "productrice", "ferme", "coopérative", "station de lavage",
          "生産者", "農園", "生产者", "农园", "庄园", "莊園"], "producer", \.producer),
        (["region", "origin", "terroir", "région", "origine",
          "産地", "地域", "产区", "产地", "產地"], "region", \.region),
        (["country", "pays", "生産国", "生豆生産国", "国家", "产国", "國家"], "country", \.country),
        (["altitude", "elevation", "height", "masl", "標高", "海拔", "海拔高度"], "altitude", \.altitude),
        (["variety", "varietal", "varieties", "cultivar", "variété", "variétés",
          "品種", "品种", "豆种", "豆種"], "variety", \.variety),
        (["process", "processing", "preparation", "procédé", "méthode", "traitement",
          "精製", "精製方法", "処理", "処理法", "生産処理", "处理", "处理法", "處理"], "process", \.process),
        (["lot", "lot no", "lot number", "batch", "batch no", "roast #", "lot n°",
          "ロット", "批次"], "lot", \.lot),
        (["harvest", "harvested", "crop", "récolte", "収穫", "収穫年", "収穫期",
          "采收", "採收", "产季"], "harvest", \.harvest),
    ]}

    private static let noteLabels = [
        "tasting notes", "flavour notes", "flavor notes", "cupping notes",
        "notes de dégustation", "notes aromatiques", "notes", "note",
        "flavour", "flavor", "flavors", "flavours", "we taste", "taste",
        "reminds us of", "arômes", "aromas",
        "風味", "风味", "フレーバー", "カッピングノート", "香味",
    ]

    /// Coffee-growing origins. Doubles as the whitelist for the country field:
    /// a labelled country the list does not know is far more likely to be an
    /// OCR misread than a new origin, and an empty field beats a wrong one.
    private static let countries = [
        "Ethiopia", "Kenya", "Rwanda", "Burundi", "Tanzania", "Uganda", "Congo",
        "Colombia", "Brazil", "Peru", "Bolivia", "Ecuador", "Guatemala", "Honduras",
        "El Salvador", "Nicaragua", "Costa Rica", "Panama", "Mexico", "Jamaica",
        "Indonesia", "Sumatra", "Java", "Sulawesi", "Papua New Guinea", "Timor",
        "India", "Vietnam", "Thailand", "China", "Yemen", "Myanmar", "Laos",
        "Taiwan", "Philippines", "Malawi", "Zambia", "Nepal", "Zimbabwe",
        "Cameroon", "Madagascar", "Haiti", "Dominican Republic", "Cuba",
        "Venezuela", "Sri Lanka", "Hawaii",
    ]

    /// Localised country spellings mapped to the English name the archive uses.
    /// Doubles as translation for the country field, no session required.
    private static let countryAliases: [String: String] = [
        // Chinese, simplified and traditional
        "埃塞俄比亚": "Ethiopia", "衣索比亞": "Ethiopia",
        "肯尼亚": "Kenya", "肯亞": "Kenya",
        "哥伦比亚": "Colombia", "哥倫比亞": "Colombia",
        "巴西": "Brazil",
        "厄瓜多尔": "Ecuador", "厄瓜多爾": "Ecuador",
        "秘鲁": "Peru", "祕魯": "Peru",
        "危地马拉": "Guatemala", "瓜地馬拉": "Guatemala",
        "巴拿马": "Panama", "巴拿馬": "Panama",
        "玻利维亚": "Bolivia", "玻利維亞": "Bolivia",
        "卢旺达": "Rwanda", "盧安達": "Rwanda",
        "洪都拉斯": "Honduras", "宏都拉斯": "Honduras",
        "哥斯达黎加": "Costa Rica", "哥斯大黎加": "Costa Rica",
        "印度尼西亚": "Indonesia", "印尼": "Indonesia",
        "也门": "Yemen", "葉門": "Yemen",
        "台湾": "Taiwan", "台灣": "Taiwan", "臺灣": "Taiwan",
        "中国": "China", "中國": "China",
        // Japanese
        "エチオピア": "Ethiopia", "ケニア": "Kenya", "コロンビア": "Colombia",
        "ブラジル": "Brazil", "エクアドル": "Ecuador", "ペルー": "Peru",
        "グアテマラ": "Guatemala", "パナマ": "Panama", "ボリビア": "Bolivia",
        "ルワンダ": "Rwanda", "ホンジュラス": "Honduras", "コスタリカ": "Costa Rica",
        "インドネシア": "Indonesia", "イエメン": "Yemen", "エルサルバドル": "El Salvador",
        // French
        "éthiopie": "Ethiopia", "colombie": "Colombia", "brésil": "Brazil",
        "pérou": "Peru", "bolivie": "Bolivia", "équateur": "Ecuador",
    ]

    /// Words that make an unlabeled token a process description.
    private static let processLexicon = [
        "washed", "natural", "honey", "anaerobic", "fermentation", "fermented",
        "maceration", "wet hulled", "semi-washed", "pulped natural", "lavé",
        "水洗", "日晒", "日曬", "蜜处理", "蜜處理", "厌氧", "厭氧",
        "ウォッシュド", "ウォッシュト", "ナチュラル", "ハニー", "アナエロビック", "嫌気性",
    ]

    /// Process spellings that translate straight to the English the app uses.
    private static let processAliases: [(match: String, value: String)] = [
        ("水洗", "Washed"), ("日晒", "Natural"), ("日曬", "Natural"),
        ("蜜处理", "Honey"), ("蜜處理", "Honey"), ("厌氧", "Anaerobic"), ("厭氧", "Anaerobic"),
        ("ウォッシュド", "Washed"), ("ウォッシュト", "Washed"), ("ナチュラル", "Natural"),
        ("ハニー", "Honey"), ("アナエロビック", "Anaerobic"), ("嫌気性発酵", "Anaerobic"),
        ("lavé", "Washed"),
    ]

    /// Words that make an unlabeled token a variety.
    private static let varietyLexicon = [
        "gesha", "geisha", "typica", "bourbon", "caturra", "catuai", "catuaí",
        "sl-28", "sl28", "sl 28", "sl-34", "sl34", "sl 34", "heirloom", "pacamara",
        "pacas", "maragogype", "castillo", "batian", "ruiru", "mundo novo",
        "sidra", "wush wush", "74110", "74158", "chiroso", "tabi", "laurina",
        "catucai", "catucaí", "villa sarchi", "sl-14", "sl14",
        "铁皮卡", "鐵皮卡", "瑰夏", "ティピカ", "ゲイシャ", "ブルボン", "カトゥーラ",
    ]

    private static let varietyAliases: [(match: String, value: String)] = [
        ("铁皮卡", "Typica"), ("鐵皮卡", "Typica"), ("瑰夏", "Gesha"),
        ("ティピカ", "Typica"), ("ゲイシャ", "Gesha"), ("ブルボン", "Bourbon"),
        ("カトゥーラ", "Caturra"),
    ]

    /// The lexicons in the English the archive uses, for suggestions and for
    /// reading a café menu. Not for parsing: that keeps the localised forms.
    static var originNames: [String] { countries }
    static let processNames = [
        "Washed", "Natural", "Honey", "Anaerobic", "Semi-washed", "Wet hulled",
        "Pulped natural", "Carbonic maceration",
    ]
    static var varietyNames: [String] {
        var seen = Set<String>()
        return varietyLexicon
            .filter { $0.unicodeScalars.allSatisfy(\.isASCII) }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .filter { seen.insert($0.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")).inserted }
    }

    /// Tokens that mark the producer on unlabeled cards.
    private static let producerHints = [
        "finca", "hacienda", "estate", "farm", "station", "coop", "cooperative", "fazenda",
    ]

    // MARK: - Parse

    static func parse(_ lines: [TextExtractor.Line]) -> ParsedFields {
        var fields = ParsedFields()
        let texts = lines.map { normalize($0.text) }

        fields.sourceLanguage = detectLanguage(texts)

        var consumed = parseTokenLayout(texts, into: &fields)

        var index = 0
        while index < texts.count {
            defer { index += 1 }
            guard !consumed.contains(index) else { continue }

            // A line can carry several fields split by pipes.
            for segment in segments(of: texts[index]) {
                for piece in LabelValueParser.segments(in: segment) {
                if let (field, name, inlineValue) = match(piece, in: fieldLabels) {
                    let value = inlineValue
                        ?? (piece == texts[index] ? nextValue(after: index, in: texts, skipping: consumed) : nil)
                    if let value = sanitized(value, forField: name), fields[keyPath: field] == nil {
                        fields[keyPath: field] = value
                        consumed.insert(index)
                    }
                    continue
                }

                if let inline = matchNotes(piece) {
                    let collected = inline.isEmpty
                        ? collectNotes(after: index, in: texts, skipping: consumed)
                        : split(inline)
                    let cleaned = cleanNotes(collected)
                    if fields.tastingNotes.isEmpty, !cleaned.isEmpty {
                        fields.tastingNotes = cleaned
                        consumed.insert(index)
                    }
                }
                }
            }
        }

        classifyLeftovers(texts, skipping: consumed, into: &fields)
        resolveOrigin(&fields, lines: texts)
        applyKnownTranslations(&fields)

        BagFieldParser.parse(texts, into: &fields)
        fields.recipe = RecipeParser.parse(texts)
        if fields.roaster == nil, let seed = RoasterLineMatch.match(lines: texts) {
            fields.roaster = seed.name
        }
        inferTitle(from: lines, texts: texts, into: &fields)
        return fields
    }

    /// The coffee's name is usually the largest line, not a labelled field.
    /// A line only wins when it is clearly taller than the rest, and it never
    /// steals the roaster, a country, or a one-word process.
    private static func inferTitle(
        from lines: [TextExtractor.Line],
        texts: [String],
        into fields: inout ParsedFields
    ) {
        guard fields.name == nil else { return }
        let heights = lines.map(\.bounds.height).filter { $0 > 0.001 }
        guard heights.count >= 2 else { return }
        let sorted = heights.sorted()
        let median = sorted[sorted.count / 2]
        guard median > 0 else { return }
        let roasterFold = fields.roaster.map(Roaster.fold) ?? ""

        var eligible: [(text: String, height: CGFloat)] = []
        for (index, line) in lines.enumerated() {
            let height = line.bounds.height
            guard height > 0.001 else { continue }
            let text = index < texts.count ? texts[index] : normalize(line.text)
            let words = text.split(separator: " ")
            guard (1...5).contains(words.count) else { continue }
            guard text.count <= 32 else { continue }
            guard text.filter(\.isLetter).count >= 3 else { continue }
            if isWeightOrPrice(text) { continue }
            if text.filter({ $0 == "," }).count >= 2 { continue }
            if isLabel(text) { continue }
            if fields.tastingNotes.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) { continue }
            if countries.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) { continue }
            if words.count == 1, processLexicon.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
                continue
            }
            let folded = Roaster.fold(text)
            if roasterFold.count >= 4, folded.contains(roasterFold) {
                continue
            }
            eligible.append((text, height))
        }
        guard let best = eligible.max(by: { $0.height < $1.height }) else { return }
        if let second = eligible.filter({ $0.text != best.text }).map(\.height).max() {
            // Two lines of similar size: don't guess which is the name.
            guard best.height >= second * 1.35 else { return }
        } else {
            // A weight can be the tallest line and still not be the name.
            // Compare with the lines that are actually smaller.
            let shorter = heights.filter { $0 < best.height * 0.98 }
            guard !shorter.isEmpty else { return }
            let baseline = shorter.sorted()[shorter.count / 2]
            guard best.height >= baseline * 1.35 else { return }
        }
        fields.name = best.text
    }

    /// "250g" and "€18" are the biggest type on some bags, and they are not the coffee.
    private static func isWeightOrPrice(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "").lowercased()
        if compact.range(of: #"^\d+([.,]\d+)?(g|kg|oz|ml|cl|l)$"#, options: .regularExpression) != nil {
            return true
        }
        if compact.contains("€") || compact.contains("$") || compact.contains("£") { return true }
        let digits = compact.filter(\.isNumber).count
        return digits > 0 && digits == compact.filter { $0.isNumber || $0 == "." || $0 == "," }.count
    }

    // MARK: - Normalisation

    /// Full-width punctuation folded to ASCII and letter-spaced headings
    /// ("C O U N T R Y") collapsed, so one matching pass covers every card.
    private static func normalize(_ text: String) -> String {
        var line = text
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "｜", with: "|")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .trimmingCharacters(in: .whitespaces)

        let parts = line.split(separator: " ")
        if parts.count >= 4, parts.allSatisfy({ $0.count == 1 && $0.first!.isLetter }) {
            line = parts.joined()
        }
        return line
    }

    /// "VARIETAL: SL-28 | PROCESS: WASHED" and "Espèce Arabica — Variété
    /// Bourbon Rouge" both carry two fields on one line.
    private static func segments(of line: String) -> [String] {
        line.split(separator: "|")
            .flatMap { $0.components(separatedBy: " — ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Kana means Japanese, han alone means Chinese. A single kana is not
    /// enough: OCR sprinkles them into Chinese text as misreads.
    private static func detectLanguage(_ texts: [String]) -> String? {
        var kana = 0
        var han = 0
        for text in texts {
            for scalar in text.unicodeScalars {
                switch scalar.value {
                case 0x3040...0x30FF: kana += 1
                case 0x4E00...0x9FFF: han += 1
                default: break
                }
            }
        }
        if kana >= 3 { return "ja" }
        return han >= 2 ? "zh" : nil
    }

    // MARK: - Label matching

    private static func match(
        _ line: String,
        in table: [(keys: [String], name: String, field: WritableKeyPath<ParsedFields, String?>)]
    ) -> (WritableKeyPath<ParsedFields, String?>, String, String?)? {
        for entry in table {
            for key in entry.keys.sorted(by: { $0.count > $1.count }) {
                guard let remainder = remainder(of: line, afterLabel: key) else { continue }
                return (entry.field, entry.name, remainder.isEmpty ? nil : remainder)
            }
        }
        return nil
    }

    private static func matchNotes(_ line: String) -> String? {
        for key in noteLabels.sorted(by: { $0.count > $1.count }) {
            if let remainder = remainder(of: line, afterLabel: key) { return remainder }
        }
        return nil
    }

    /// Returns what follows a label, or nil if the line does not start with it.
    /// The label has to be followed by a separator (or end the line) so a line
    /// of prose beginning with "Process" does not swallow the paragraph, and
    /// "note" does not eat "notes".
    private static func remainder(of line: String, afterLabel label: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let lowered = trimmed.lowercased()
        guard lowered.hasPrefix(label) else { return nil }

        let boundary = trimmed.index(trimmed.startIndex, offsetBy: label.count)
        if boundary < trimmed.endIndex {
            let next = trimmed[boundary]
            guard ": ：\t-–—".contains(next) else { return nil }
        }

        let rest = String(trimmed[boundary...])
            .trimmingCharacters(in: CharacterSet(charactersIn: " :：–—-\t"))
        if rest.isEmpty { return "" }
        // A label followed by a lot of words is prose, not a value.
        guard rest.split(separator: " ").count <= 8 else { return nil }
        return rest
    }

    /// Bag chrome that sits next to the real labels on Japanese packaging and
    /// gets read as a value when the columns interleave.
    private static let chromeValues = [
        "保存方法", "原材料名", "内容量", "賞味期限", "販売者", "製造者", "要冷蔵",
        "名称", "品名", "焙煎日", "挽き方",
    ]

    /// Words that start a sentence, not a value. "Coffee roasted in Paris"
    /// matches the coffee label, and the rest of it is prose.
    private static let proseStarters = [
        "roasted", "from", "made", "grown", "in", "by", "with", "and", "for",
        "the", "of", "to", "is", "are", "this", "we", "our", "produced", "torréfié",
    ]

    /// Rejects values that are clearly not the field they landed in: bag
    /// weights posing as names, mangled labels read as values, prose, and the
    /// mixed-script soup OCR returns when it half-reads a CJK line.
    private static func sanitized(_ value: String?, forField field: String) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first.isLetter || first.isNumber else { return nil }
        guard !chromeValues.contains(trimmed), !resemblesLabel(trimmed) else { return nil }
        guard !isMixedScript(trimmed), !isPackagingTerm(trimmed) else { return nil }

        let words = trimmed.split(separator: " ")
        if let opener = words.first?.lowercased(), proseStarters.contains(opener) {
            return nil
        }

        switch field {
        case "name", "roaster":
            guard words.count <= 5 else { return nil }
            if trimmed.range(
                of: #"^\d+([.,]\d+)?\s*(g|kg|ml|oz)\.?$"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil {
                return nil
            }
        case "country":
            // Closed vocabulary, so anything unrecognised is a misread.
            guard knownCountry(trimmed) != nil else { return nil }
        default:
            break
        }

        return trimmed.isEmpty ? nil : trimmed
    }

    /// Japanese and Chinese packaging labels all end the same way — 原材料名
    /// (ingredients), 内容量 (net weight), 保存方法 (storage), 焙煎日 (roast date).
    /// OCR misreads the stems, so the ending is the reliable tell.
    private static func isPackagingTerm(_ value: String) -> Bool {
        guard isCJK(value), value.count <= 5, let last = value.last else { return false }
        return "名量法日者限".contains(last)
    }

    private static func knownCountry(_ value: String) -> String? {
        if let match = countries.first(where: { value.localizedCaseInsensitiveContains($0) }) {
            return match
        }
        if let alias = countryAliases.first(where: { value.contains($0.key) }) {
            return alias.value
        }
        return nil
    }

    /// Latin letters mixed into a CJK value means OCR read half the glyphs as
    /// letters. "仅R会失 卡" is not a variety.
    private static func isMixedScript(_ value: String) -> Bool {
        var han = false
        var latin = false
        for scalar in value.unicodeScalars {
            if (0x3040...0x30FF).contains(scalar.value) || (0x4E00...0x9FFF).contains(scalar.value) {
                han = true
            } else if let character = Character(scalar).asciiValue,
                      (65...90).contains(character) || (97...122).contains(character) {
                latin = true
            }
        }
        return han && latin
    }

    private static func isLabel(_ line: String) -> Bool {
        match(line, in: fieldLabels) != nil || matchNotes(line) != nil || resemblesLabel(line)
    }

    /// OCR turns "ELEVATION" into "eievation" and "VARIETY" into "VARIET T".
    /// Both are labels, not values, so a one-character miss against the
    /// vocabulary is enough to disqualify them.
    private static func resemblesLabel(_ value: String) -> Bool {
        let candidate = folded(value)
        guard candidate.count >= 4 else { return false }
        let keys = fieldLabels.flatMap(\.keys) + noteLabels
        for key in keys {
            let target = folded(key)
            guard abs(target.count - candidate.count) <= 1 else { continue }
            if isWithinOneEdit(candidate, target) { return true }
        }
        return false
    }

    /// Drops spacing and punctuation and folds the glyph pairs OCR confuses.
    private static func folded(_ text: String) -> String {
        var result = ""
        for character in text.lowercased() {
            guard character.isLetter || character.isNumber else { continue }
            switch character {
            case "i", "l", "1", "j": result.append("i")
            case "o", "0": result.append("o")
            case "s", "5": result.append("s")
            default: result.append(character)
            }
        }
        return result
    }

    private static func isWithinOneEdit(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let first = Array(a)
        let second = Array(b)
        if first.count == second.count {
            var differences = 0
            for index in first.indices where first[index] != second[index] {
                differences += 1
                if differences > 1 { return false }
            }
            return true
        }
        // One insertion: walk both, allowing a single skip in the longer one.
        let (shorter, longer) = first.count < second.count ? (first, second) : (second, first)
        var shortIndex = 0
        var skipped = false
        for character in longer {
            if shortIndex < shorter.count, shorter[shortIndex] == character {
                shortIndex += 1
            } else if skipped {
                return false
            } else {
                skipped = true
            }
        }
        return true
    }

    private static func nextValue(after index: Int, in texts: [String], skipping consumed: Set<Int>) -> String? {
        let next = index + 1
        guard next < texts.count, !consumed.contains(next), !isLabel(texts[next]) else { return nil }
        let value = texts[next].trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, value.split(separator: " ").count <= 8 else { return nil }
        return value
    }

    private static func collectNotes(after index: Int, in texts: [String], skipping consumed: Set<Int>) -> [String] {
        var notes: [String] = []
        var cursor = index + 1
        while cursor < texts.count, notes.count < 6 {
            defer { cursor += 1 }
            guard !consumed.contains(cursor) else { break }
            let line = texts[cursor]
            guard !isLabel(line) else { break }
            let candidate = line.trimmingCharacters(in: .whitespaces)
            // Notes are short. A long line is the roaster's blurb.
            guard !candidate.isEmpty, candidate.split(separator: " ").count <= 6 else { break }
            let parts = split(candidate).filter(isPlausibleNote)
            guard !parts.isEmpty else { break }
            notes.append(contentsOf: parts)
        }
        return notes
    }

    private static func split(_ value: String) -> [String] {
        value
            .split(whereSeparator: { ",;/|•·、".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The most notes a single card prints. More than this and the photo is a
    /// menu listing several coffees, where the notes belong to whichever entry
    /// came first.
    private static let noteLimit = 6

    private static func cleanNotes(_ notes: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for note in notes where isPlausibleNote(note) {
            let key = note.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(note)
            if result.count == noteLimit { break }
        }
        return result
    }

    /// Bag chrome that sits below the notes list and would ride along
    /// otherwise ("WHOLE BEAN COFFEE", "NET WT 12 OZ", the roaster's URL), plus
    /// the shapes OCR garbage takes: consonant runs, stray single letters,
    /// sentences of CJK prose.
    private static func isPlausibleNote(_ note: String) -> Bool {
        // Two glyphs is a whole note in Chinese (白花); in English it is noise.
        guard note.count >= (isCJK(note) ? 2 : 3) else { return false }
        guard note.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        guard !note.contains(where: { "。、；:".contains($0) }) else { return false }

        let lowered = note.lowercased()
        let noise = ["coffee", "beans", "net wt", "www.", "http", "@", "organic"]
        guard !noise.contains(where: { lowered.contains($0) }) else { return false }

        // Tasting notes in Chinese or Japanese are two to four glyphs; a long
        // one is the roaster's story.
        if isCJK(note) { return note.count <= 6 }

        // Latin notes: every word real, none a lone initial or a consonant run.
        let words = lowered.split(separator: " ")
        guard let last = words.last, !proseStarters.contains(String(last)) else { return false }
        return words.allSatisfy { word in
            word.count >= 2 && word.contains(where: { "aeiouyàâéèêëîïôöùûü".contains($0) })
        }
    }

    private static func isCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
        }
    }

    // MARK: - Parenthesised token layout

    /// Some roasters print cards as bare tokens: "( Caranavi ) ( Gesha )
    /// ( 1600m ) ( Double Fermentation )", with tasting notes following a
    /// roast-level heading. No labels anywhere, so each token is classified
    /// by what it looks like.
    private static func parseTokenLayout(_ texts: [String], into fields: inout ParsedFields) -> Set<Int> {
        var tokensByLine: [(index: Int, tokens: [String])] = []
        for (index, line) in texts.enumerated() {
            let tokens = parenthesisedTokens(in: line)
            if !tokens.isEmpty { tokensByLine.append((index, tokens)) }
        }

        // One or two parenthesised groups are decoration — a logo, a city.
        // The token layout uses them for everything.
        let total = tokensByLine.reduce(0) { $0 + $1.tokens.count }
        guard total >= 3 else { return [] }

        var consumed: Set<Int> = []
        var sawRoastHeading = false
        var notes: [String] = []
        var unclassified: [String] = []

        for (index, line) in texts.enumerated() {
            if isRoastHeading(line) {
                sawRoastHeading = true
                consumed.insert(index)
                continue
            }
            guard let entry = tokensByLine.first(where: { $0.index == index }) else { continue }
            consumed.insert(index)

            for token in entry.tokens {
                // "Caturra, Colombia" carries two facts in one token.
                for part in split(token) {
                    classifyToken(
                        part, into: &fields,
                        sawRoastHeading: sawRoastHeading,
                        notes: &notes, unclassified: &unclassified
                    )
                }
            }
        }

        if fields.tastingNotes.isEmpty { fields.tastingNotes = cleanNotes(notes) }

        // What is left on these cards is, in printing order, the region and
        // the farm. Only trust that when the leftovers are few.
        if unclassified.count <= 3 {
            var leftovers = unclassified
            if fields.region == nil, !leftovers.isEmpty {
                fields.region = leftovers.removeFirst()
            }
            if fields.producer == nil, !leftovers.isEmpty {
                fields.producer = leftovers.removeFirst()
            }
        }

        return consumed
    }

    private static func parenthesisedTokens(in line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var depth = 0
        for character in line {
            switch character {
            case "(":
                depth += 1
                current = ""
            case ")":
                if depth > 0 {
                    let token = current.trimmingCharacters(in: .whitespaces)
                    if token.count > 1 { tokens.append(token) }
                    depth = 0
                }
            default:
                if depth > 0 { current.append(character) }
            }
        }
        return tokens
    }

    private static func isRoastHeading(_ line: String) -> Bool {
        let cleaned = line
            .trimmingCharacters(in: CharacterSet(charactersIn: " •·-"))
            .lowercased()
        let words = cleaned.split(whereSeparator: { " -/".contains($0) }).map(String.init)
        guard !words.isEmpty, words.count <= 3 else { return false }
        let levels = ["light", "medium", "dark"]
        return words.allSatisfy { levels.contains($0) || $0 == "roast" }
            && words.contains(where: { levels.contains($0) })
    }

    private static func classifyToken(
        _ token: String,
        into fields: inout ParsedFields,
        sawRoastHeading: Bool,
        notes: inout [String],
        unclassified: inout [String]
    ) {
        let lowered = token.lowercased()

        if isAltitude(token) {
            fields.altitude = fields.altitude ?? token
            return
        }
        if processLexicon.contains(where: { lowered.contains($0) }) {
            fields.process = fields.process ?? token
            return
        }
        if varietyLexicon.contains(where: { lowered.contains($0) }) {
            if let variety = fields.variety, !variety.localizedCaseInsensitiveContains(token) {
                fields.variety = "\(variety), \(token)"
            } else if fields.variety == nil {
                fields.variety = token
            }
            return
        }
        if countries.contains(where: { lowered == $0.lowercased() }) || countryAliases[token] != nil {
            fields.country = fields.country ?? (countryAliases[token] ?? token)
            return
        }
        if producerHints.contains(where: { lowered.contains($0) }) {
            fields.producer = fields.producer ?? token
            return
        }
        if sawRoastHeading {
            notes.append(token)
            return
        }
        unclassified.append(token)
    }

    private static func isAltitude(_ text: String) -> Bool {
        text.range(
            of: #"^\d[\d,.\s]{2,}\s*(-|–|~|〜)?\s*[\d,.\s]*\s*(m|masl|meters|metres|mètres|米)\.?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    // MARK: - Leftover classification

    /// Lines no label claimed still carry facts: a bare "Washed", an altitude,
    /// or a "TANGERINE | BLACKCURRANT | VANILLA" note row.
    private static func classifyLeftovers(
        _ texts: [String], skipping consumed: Set<Int>, into fields: inout ParsedFields
    ) {
        for (index, line) in texts.enumerated() {
            guard !consumed.contains(index) else { continue }
            let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: " •·"))
            guard !trimmed.isEmpty else { continue }
            let lowered = trimmed.lowercased()

            if fields.altitude == nil, isAltitude(trimmed) {
                fields.altitude = trimmed
                continue
            }
            if fields.process == nil,
               trimmed.split(separator: " ").count <= 3,
               processLexicon.contains(where: { lowered.contains($0) }) {
                fields.process = trimmed
                continue
            }
            if fields.variety == nil,
               trimmed.split(separator: " ").count <= 3,
               varietyLexicon.contains(where: { lowered.contains($0) }) {
                fields.variety = trimmed
                continue
            }
            if fields.tastingNotes.isEmpty, let notes = unlabeledNotes(trimmed) {
                fields.tastingNotes = cleanNotes(notes)
            }
        }
    }

    /// A separator-joined row of short food words with no digits reads as
    /// tasting notes even without a heading. Commas alone do not qualify:
    /// French prose is full of them.
    private static func unlabeledNotes(_ line: String) -> [String]? {
        guard line.contains(where: { "|/•·、".contains($0) }) else { return nil }
        guard line.rangeOfCharacter(from: .decimalDigits) == nil else { return nil }
        let parts = split(line)
        guard parts.count >= 2, parts.count <= 6 else { return nil }
        guard parts.allSatisfy({ part in
            let words = part.split(separator: " ")
            return words.count <= 3 && part.count <= 24 && !part.contains(":") && isPlausibleNote(part)
        }) else { return nil }
        return parts
    }

    // MARK: - Origin

    /// Cards very often print "Nyeri, Kenya" against a single Region label, and
    /// otherwise mention the country somewhere loose in the text.
    private static func resolveOrigin(_ fields: inout ParsedFields, lines: [String]) {
        if let region = fields.region {
            for country in countries where region.localizedCaseInsensitiveContains(country) {
                fields.country = fields.country ?? country
                let trimmed = region
                    .replacingOccurrences(of: country, with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,–-"))
                fields.region = trimmed.isEmpty ? nil : trimmed
                break
            }
        }

        // "産地: エチオピア" lands in region because the label means origin;
        // when the value is just a country name, move it where it belongs.
        if let region = fields.region {
            for (alias, name) in countryAliases where region.contains(alias) {
                if fields.country == nil {
                    fields.country = name
                    fields.originalFields["country"] = alias
                }
                let trimmed = region
                    .replacingOccurrences(of: alias, with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,、–-"))
                fields.region = trimmed.isEmpty ? nil : trimmed
                break
            }
        }

        guard fields.country == nil else { return }
        for line in lines {
            for country in countries where line.localizedCaseInsensitiveContains(country) {
                fields.country = country
                return
            }
            for (alias, name) in countryAliases where line.contains(alias) {
                fields.country = name
                fields.originalFields["country"] = alias
                return
            }
        }
    }

    // MARK: - Known translations

    /// Values with a fixed vocabulary translate through tables, keeping the
    /// original on record. Free text waits for the translation session or the
    /// vision model.
    private static func applyKnownTranslations(_ fields: inout ParsedFields) {
        if let country = fields.country, let english = countryAliases[country] {
            fields.originalFields["country"] = country
            fields.country = english
        }
        if let process = fields.process {
            for (match, value) in processAliases where process.contains(match) {
                fields.originalFields["process"] = process
                fields.process = value
                break
            }
        }
        if let variety = fields.variety {
            for (match, value) in varietyAliases where variety.contains(match) {
                fields.originalFields["variety"] = variety
                fields.variety = value
                break
            }
        }
    }
}
