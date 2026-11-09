import Foundation

/// Turns "eighteen grams, two hundred fifty of water, two forty-five, four
/// stars" into a brew.
///
/// Deterministic and offline. It runs before any model is asked, and it is
/// what the app falls back to when the model is off, unavailable, or wrong —
/// which is the only reason dictation can be offered at all without a network.
///
/// The grammar it understands is small on purpose: numbers with units, times,
/// a rating, and a handful of verbs. Anything it cannot place stays in the
/// transcript and lands in Notes rather than being guessed at.
nonisolated enum SpokenBrewParser {
    /// What a phrase turned into, and which parts of it were understood.
    struct Result: Equatable, Sendable {
        var dose: Double?
        var water: Double?
        var beverage: Double?
        var seconds: Int?
        var temperature: Double?
        var grind: String?
        var method: BrewMethod?
        var rating: Int?
        var flavors: [String] = []
        var taste = TasteProfile()
        var agitation: Agitation?
        var waterProfileId: UUID?
        var waterName: String?
        var filterStockId: UUID?
        var filterName: String?
        /// Pour / bloom / rinse masses said during the brew.
        var spokenSteps: [SpokenStep] = []
        /// What was said, minus everything that was placed in a field. Empty
        /// when the whole phrase was understood.
        var leftover: String = ""

        var isEmpty: Bool {
            dose == nil && water == nil && beverage == nil && seconds == nil
                && temperature == nil && grind == nil && method == nil
                && rating == nil && flavors.isEmpty && taste.isEmpty && agitation == nil
                && waterProfileId == nil && filterStockId == nil
                && waterName == nil && filterName == nil && spokenSteps.isEmpty
        }

        /// How much of the phrase found a home, 0 to 1. Under a half, the
        /// caller should offer the model rather than the parse.
        var confidence: Double = 0
    }

    struct SpokenStep: Equatable, Sendable {
        var action: StepAction
        var mass: Double?
        var agitation: Agitation?
    }

    static func parse(
        _ transcript: String,
        waters: [WaterProfile] = [],
        filters: [FilterStock] = []
    ) -> Result {
        var result = Result()
        let text = normalize(transcript)
        var consumed: [Range<String.Index>] = []

        func take(_ range: Range<String.Index>?) {
            if let range { consumed.append(range) }
        }

        // Time first: "2:45" and "two forty-five" would otherwise be read as
        // two separate numbers.
        if let (seconds, range) = time(in: text) {
            result.seconds = seconds
            take(range)
        }

        let (steps, stepRanges) = spokenSteps(in: text, skipping: consumed)
        result.spokenSteps = steps
        consumed.append(contentsOf: stepRanges)

        if let (value, range) = quantity(in: text, units: ["g", "gram", "grams", "gramme", "grammes"],
                                         nouns: ["dose", "coffee", "in", "beans"]) {
            result.dose = value
            take(range)
        }

        if let (value, range) = quantity(in: text, units: ["g", "gram", "grams", "ml", "millilitres"],
                                         nouns: ["water", "eau"], skipping: consumed) {
            result.water = value
            take(range)
        }

        if let (value, range) = quantity(in: text, units: ["g", "gram", "grams"],
                                         nouns: ["out", "yield", "cup", "beverage"], skipping: consumed) {
            result.beverage = value
            take(range)
        }

        if let (value, range) = quantity(in: text, units: ["celsius", "degrees", "degree", "°c", "°"],
                                         nouns: ["temperature", "temp", "water at"],
                                         unitIsEnough: true, skipping: consumed) {
            if (60...100).contains(value) { result.temperature = value }
            take(range)
        }

        if let (setting, range) = grind(in: text, skipping: consumed) {
            result.grind = setting
            take(range)
        }

        if let (method, range) = method(in: text) {
            result.method = method
            take(range)
        }

        if let (rating, range) = rating(in: text) {
            result.rating = rating
            take(range)
        }

        let (taste, tasteRanges) = taste(in: text, skipping: consumed)
        result.taste = taste
        consumed.append(contentsOf: tasteRanges)

        if let (agitation, range) = agitation(in: text, skipping: consumed) {
            result.agitation = agitation
            take(range)
        }

        let (flavors, flavorRanges) = flavors(in: text, skipping: consumed)
        result.flavors = flavors
        consumed.append(contentsOf: flavorRanges)

        result.leftover = remainder(of: text, minus: consumed)
        if let hit = namedThing(in: result.leftover, waters: waters, filters: filters) {
            result.waterProfileId = hit.waterId
            result.waterName = hit.waterName
            result.filterStockId = hit.filterId
            result.filterName = hit.filterName
            if let range = text.range(of: hit.matched, options: [.caseInsensitive, .diacriticInsensitive]) {
                take(range)
            }
            result.leftover = remainder(of: text, minus: consumed)
        }
        result.confidence = coverage(of: text, consumed: consumed)
        return result
    }

    /// Applies a parse to a brew, filling only what is empty. Dictation
    /// corrects nothing you typed yourself.
    static func apply(
        _ result: Result,
        to brew: inout Brew,
        appendLeftover: Bool = true
    ) {
        if brew.dose == nil { brew.dose = result.dose }
        if brew.water == nil { brew.water = result.water }
        if brew.beverage == nil { brew.beverage = result.beverage }
        if brew.seconds == nil { brew.seconds = result.seconds }
        if brew.temperature == nil { brew.temperature = result.temperature }
        if brew.grind.isEmpty, let grind = result.grind {
            brew.grind = GrindSetting(raw: grind)
        }
        if brew.method == nil { brew.method = result.method }
        if brew.ratingHalves == nil { brew.ratingHalves = result.rating.map { $0 * 2 } }
        if brew.agitation == nil { brew.agitation = result.agitation }
        if brew.waterProfileID == nil { brew.waterProfileID = result.waterProfileId }
        if brew.filterStockId == nil { brew.filterStockId = result.filterStockId }
        for axis in TasteAxis.allCases where brew.taste[axis] == nil {
            brew.taste[axis] = result.taste[axis]
        }
        for flavor in result.flavors {
            let tag = FlavorMatcher.match(flavor).tags.first ?? FlavorTag(custom: flavor)
            if !brew.flavors.contains(where: { $0.id == tag.id }) { brew.flavors.append(tag) }
        }
        applySpokenSteps(result.spokenSteps, to: &brew)
        if appendLeftover {
            let leftover = result.leftover.trimmingCharacters(in: .whitespacesAndNewlines)
            if !leftover.isEmpty {
                brew.notes = brew.notes.isEmpty
                    ? leftover.capitalizedFirst
                    : brew.notes + "\n" + leftover.capitalizedFirst
            }
        }
        if brew.captureSource == nil { brew.captureSource = .dictated }
    }

    /// Timer keeps `at`. Narration overwrites mass and agitation on matching steps.
    static func applySpokenSteps(_ spoken: [SpokenStep], to brew: inout Brew) {
        guard !spoken.isEmpty else { return }
        if brew.actualSteps.isEmpty {
            brew.actualSteps = brew.plannedSteps.map { plan in
                var step = plan
                step.mass = plan.mass ?? plan.targetMass
                return step
            }
        }
        var used: Set<UUID> = []
        for phrase in spoken {
            let match = brew.actualSteps.firstIndex { step in
                !used.contains(step.id) && step.action == phrase.action
            } ?? brew.actualSteps.firstIndex { step in
                !used.contains(step.id)
            }
            guard let match else { continue }
            used.insert(brew.actualSteps[match].id)
            let keptAt = brew.actualSteps[match].at
            if let mass = phrase.mass {
                brew.actualSteps[match].mass = mass
                brew.actualSteps[match].skipped = false
            }
            if let agitation = phrase.agitation {
                brew.actualSteps[match].agitation = agitation
            }
            brew.actualSteps[match].at = keptAt
        }
        brew.refreshPourRates()
    }

    // MARK: - Pieces

    /// Lowercased, with spoken numbers turned into digits so a single numeric
    /// scanner handles both "18" and "eighteen".
    static func normalize(_ text: String) -> String {
        var result = text.lowercased()
        result = result.replacingOccurrences(of: "-", with: " ")
        result = spokenClock(result)

        // Ordered longest-first so "twenty five" beats "twenty" then "five".
        for (word, value) in Self.numberWords.sorted(by: { $0.key.count > $1.key.count }) {
            result = result.replacingOccurrences(
                of: "\\b\(word)\\b", with: value, options: .regularExpression
            )
        }
        // "two hundred and fifty" is now "2 100 and 50". The "and" is glue
        // between two halves of one number, not a word of its own.
        result = result.replacingOccurrences(
            of: #"(?<=\d)\s+and\s+(?=\d)"#, with: " ", options: .regularExpression
        )
        // "40 5": one number said in two words.
        result = foldTens(result)
        // "2 100 50": fold the multiplier and the remainder back into one.
        result = foldHundreds(result)
        return result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// English says a number and a time the same way: "two forty-five" is a
    /// brew time, "two fifty of water" is 250 g. Both are settled here, in
    /// words, before any digit substitution — otherwise the numeric scanner
    /// sees two quantities and fills two fields from one phrase.
    ///
    /// What tells them apart is the noun: a mass or a volume after the words
    /// forces the hundreds reading, and anything else reads as a clock.
    private static func spokenClock(_ text: String) -> String {
        let hundreds = clockPattern(followedBy: Self.quantityNouns)
        let result = replaceSpokenPairs(in: text, matching: hundreds) { head, rest in
            String(head * 100 + rest)
        }
        return replaceSpokenPairs(in: result, matching: clockPattern(followedBy: nil)) {
            String(format: "%d:%02d", $0, $1)
        }
    }

    /// `<one…nine> <twenty…fifty> [<one…nine>]`, optionally with a noun after
    /// it. Only the tens a minute can hold are accepted, so "sixty" is out.
    private static func clockPattern(followedBy nouns: [String]?) -> String {
        let units = Self.clockUnits.joined(separator: "|")
        let tens = Self.clockTens.joined(separator: "|")
        let head = #"\b(\#(units))\s+(\#(tens))(?:\s+(\#(units)))?\b"#
        guard let nouns else { return head }
        return head + #"(?=\s*(?:\#(nouns.map(escaped).joined(separator: "|")))\b)"#
    }

    private static func replaceSpokenPairs(
        in text: String,
        matching pattern: String,
        value: (Int, Int) -> String
    ) -> String {
        var result = text
        var search = result.startIndex..<result.endIndex
        while let match = result.range(of: pattern, options: .regularExpression, range: search) {
            let words = result[match].split(separator: " ").map(String.init)
            guard let head = Self.clockUnits.firstIndex(of: words[0]).map({ $0 + 1 }),
                  let tens = Self.clockTens.firstIndex(of: words[1]).map({ ($0 + 2) * 10 })
            else { break }
            let unit = words.count > 2
                ? (Self.clockUnits.firstIndex(of: words[2]).map { $0 + 1 } ?? 0)
                : 0

            let replacement = value(head, tens + unit)
            result.replaceSubrange(match, with: replacement)
            search = result.index(match.lowerBound, offsetBy: replacement.count)..<result.endIndex
        }
        return result
    }

    /// "twenty five" arrives as "20 5" once the words are digits. Adjacent
    /// tens and units are always one number when spoken, so they rejoin.
    private static func foldTens(_ text: String) -> String {
        var words = text.split(separator: " ").map(String.init)
        var index = 0
        while index + 1 < words.count {
            guard let tens = Int(words[index]), tens >= 20, tens <= 90, tens % 10 == 0,
                  let unit = Int(words[index + 1]), unit >= 1, unit <= 9
            else { index += 1; continue }

            words.replaceSubrange(index...(index + 1), with: [String(tens + unit)])
            index += 1
        }
        return words.joined(separator: " ")
    }

    private static func foldHundreds(_ text: String) -> String {
        var words = text.split(separator: " ").map(String.init)
        var index = 0
        while index < words.count {
            guard words[index] == "100", index > 0, let multiplier = Int(words[index - 1]),
                  multiplier < 10
            else { index += 1; continue }

            var total = multiplier * 100
            var consumedUpTo = index
            // Absorb the tens and units that follow: "2 100 50" → 250.
            while consumedUpTo + 1 < words.count, let next = Int(words[consumedUpTo + 1]),
                  next < 100, total % 100 + next < 100 {
                total += next
                consumedUpTo += 1
            }
            words.replaceSubrange((index - 1)...consumedUpTo, with: [String(total)])
            index = index - 1 + 1
        }
        return words.joined(separator: " ")
    }

    /// "2:45", "two forty-five", "165 seconds", "3 minutes".
    private static func time(in text: String) -> (Int, Range<String.Index>)? {
        if let match = text.range(of: #"\b(\d{1,2})[:.](\d{2})\b"#, options: .regularExpression) {
            let parts = text[match].split(whereSeparator: { $0 == ":" || $0 == "." })
            if let m = Int(parts[0]), let s = Int(parts[1]) {
                return (m * 60 + s, match)
            }
        }
        if let match = text.range(
            of: #"\b(\d+(?:\.\d+)?)\s*(seconds|second|secs|sec|s)\b"#,
            options: .regularExpression
        ), let value = firstNumber(in: String(text[match])) {
            return (Int(value), match)
        }
        if let match = text.range(
            of: #"\b(\d+(?:\.\d+)?)\s*(minutes|minute|mins|min)\b"#,
            options: .regularExpression
        ), let value = firstNumber(in: String(text[match])) {
            return (Int(value * 60), match)
        }
        return nil
    }

    private static func spokenSteps(
        in text: String,
        skipping consumed: [Range<String.Index>]
    ) -> ([SpokenStep], [Range<String.Index>]) {
        let verbs: [(StepAction, String)] = [
            (.preInfusion, "pre[- ]?infusion|preinfusion"),
            (.rinse, "rinse|rincer|rinsed|rincage"),
            (.bloom, "bloom|bloomed|fleur"),
            (.pour, "pour|poured|verse|verser|versee"),
            (.wait, "wait|waited|attendre"),
            (.steep, "steep|steeped|infuse"),
            (.press, "press|pressed|presser"),
            (.shot, "shot"),
            (.fill, "fill|filled|remplir"),
        ]
        var found: [(SpokenStep, Range<String.Index>)] = []
        for (action, verbs) in verbs {
            let pattern = #"\b(?:\#(verbs))(?:\s+(?:to|a|à))?(?:\s+(\d+(?:\.\d+)?))?(?:\s*(?:g|grams|grammes|gramme))?\b"#
            var search = text.startIndex..<text.endIndex
            while let match = text.range(of: pattern, options: .regularExpression, range: search) {
                if consumed.contains(where: { $0.overlaps(match) })
                    || found.contains(where: { $0.1.overlaps(match) })
                {
                    search = match.upperBound..<text.endIndex
                    continue
                }
                let mass = firstNumber(in: String(text[match]))
                let needsMass = action == .pour || action == .bloom || action == .rinse
                    || action == .shot || action == .fill
                if needsMass && mass == nil {
                    search = match.upperBound..<text.endIndex
                    continue
                }
                found.append((SpokenStep(action: action, mass: mass), match))
                search = match.upperBound..<text.endIndex
            }
        }
        found.sort { $0.1.lowerBound < $1.1.lowerBound }
        return (found.map(\.0), found.map(\.1))
    }

    /// A number attached to a unit or to a noun that names the field. Both
    /// orders are accepted, because people say "250 of water" and "water 250".
    private static func quantity(
        in text: String,
        units: [String],
        nouns: [String],
        /// True when the unit alone names the field — "94 degrees" can only be
        /// a temperature, while "18 grams" could be any of three things.
        unitIsEnough: Bool = false,
        skipping consumed: [Range<String.Index>] = []
    ) -> (Double, Range<String.Index>)? {
        let unitAlternatives = units.map(escaped).joined(separator: "|")
        let nounAlternatives = nouns.map(escaped).joined(separator: "|")

        var patterns = [
            // "250 g of water", "250 grams water", "18 in"
            #"\b(\d+(?:\.\d+)?)\s*(?:\#(unitAlternatives))?\b\s*(?:of\s+)?(?:\#(nounAlternatives))\b"#,
            // "water 250", "dose 18 g"
            #"\b(?:\#(nounAlternatives))\s+(?:of\s+)?(\d+(?:\.\d+)?)\s*(?:\#(unitAlternatives))?\b"#,
        ]
        if unitIsEnough {
            patterns.append(#"\b(\d+(?:\.\d+)?)\s*(?:\#(unitAlternatives))\b"#)
        }

        for pattern in patterns {
            var search = text.startIndex..<text.endIndex
            while let match = text.range(of: pattern, options: .regularExpression, range: search) {
                if consumed.contains(where: { $0.overlaps(match) }) {
                    search = match.upperBound..<text.endIndex
                    continue
                }
                if let value = firstNumber(in: String(text[match])) {
                    return (value, match)
                }
                search = match.upperBound..<text.endIndex
            }
        }
        return nil
    }

    /// "22 clicks", "grind 3.5", "medium fine".
    private static func grind(
        in text: String,
        skipping consumed: [Range<String.Index>]
    ) -> (String, Range<String.Index>)? {
        let numeric = [
            #"\b(\d+(?:\.\d+)?)\s*(clicks|click|notches|notch)\b"#,
            #"\bgrind\s+(?:at\s+)?(\d+(?:\.\d+)?)\s*(clicks|click)?\b"#,
        ]
        for pattern in numeric {
            if let match = text.range(of: pattern, options: .regularExpression),
               !consumed.contains(where: { $0.overlaps(match) }) {
                var setting = String(text[match])
                    .replacingOccurrences(of: "grind ", with: "")
                    .replacingOccurrences(of: "at ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !setting.contains(where: { $0.isLetter }) { setting += " clicks" }
                return (setting, match)
            }
        }
        for term in ["extra fine", "medium fine", "medium coarse", "extra coarse", "fine", "medium", "coarse"] {
            if let match = text.range(of: "\\b\(term)\\b", options: .regularExpression),
               !consumed.contains(where: { $0.overlaps(match) }) {
                return (term, match)
            }
        }
        return nil
    }

    private static func method(in text: String) -> (BrewMethod, Range<String.Index>)? {
        for method in BrewMethod.allCases {
            let spellings = [method.rawValue, method.label] + Self.methodAliases[method, default: []]
            for spelling in spellings {
                let needle = spelling.lowercased()
                if let match = text.range(of: "\\b\(escaped(needle))\\b", options: .regularExpression) {
                    return (method, match)
                }
            }
        }
        return nil
    }

    /// "four stars", "four out of five", "rated four".
    private static func rating(in text: String) -> (Int, Range<String.Index>)? {
        let patterns = [
            #"\b([1-5])\s*(stars|star)\b"#,
            #"\b([1-5])\s*out\s*of\s*5\b"#,
            #"\brated\s+([1-5])\b"#,
        ]
        for pattern in patterns {
            if let match = text.range(of: pattern, options: .regularExpression),
               let value = firstNumber(in: String(text[match])) {
                return (Int(value), match)
            }
        }
        return nil
    }

    private static func flavors(
        in text: String,
        skipping consumed: [Range<String.Index>]
    ) -> ([String], [Range<String.Index>]) {
        var found: [String] = []
        var ranges: [Range<String.Index>] = []
        var terms: [(label: String, needle: String)] = []
        for node in FlavorWheel.shared.nodes {
            terms.append((node.en, node.en.lowercased()))
            if !node.fr.isEmpty { terms.append((node.en, node.fr.lowercased())) }
            for synonym in node.synonyms {
                terms.append((node.en, synonym.lowercased()))
            }
        }
        terms.sort { $0.needle.count > $1.needle.count }
        for term in terms {
            if term.needle.count < 3 { continue }
            if let match = text.range(of: "\\b\(escaped(term.needle))\\b", options: .regularExpression),
               !consumed.contains(where: { $0.overlaps(match) }),
               !ranges.contains(where: { $0.overlaps(match) })
            {
                if !found.contains(term.label) { found.append(term.label) }
                ranges.append(match)
            }
        }
        return (found, ranges)
    }

    /// "acidity 7", "low sweetness", "long finish", "clean".
    private static func taste(
        in text: String,
        skipping consumed: [Range<String.Index>]
    ) -> (TasteProfile, [Range<String.Index>]) {
        var profile = TasteProfile()
        var ranges: [Range<String.Index>] = []

        func take(_ range: Range<String.Index>, axis: TasteAxis, value: Int) {
            guard !consumed.contains(where: { $0.overlaps(range) }) else { return }
            guard !ranges.contains(where: { $0.overlaps(range) }) else { return }
            if profile[axis] == nil { profile[axis] = value }
            ranges.append(range)
        }

        for axis in TasteAxis.allCases {
            let names = [axis.label, axis.rawValue] + Self.axisAliases[axis, default: []]
            for name in names {
                let numeric = #"\b\#(escaped(name.lowercased()))\s+(\d{1,2})\b"#
                if let match = text.range(of: numeric, options: .regularExpression),
                   let number = firstNumber(in: String(text[match])),
                   (0...10).contains(Int(number))
                {
                    take(match, axis: axis, value: Int(number))
                }
                for (word, score) in Self.qualitativeScores {
                    let before = #"\b\#(escaped(word))\s+\#(escaped(name.lowercased()))\b"#
                    let after = #"\b\#(escaped(name.lowercased()))\s+\#(escaped(word))\b"#
                    if let match = text.range(of: before, options: .regularExpression) {
                        take(match, axis: axis, value: score)
                    }
                    if let match = text.range(of: after, options: .regularExpression) {
                        take(match, axis: axis, value: score)
                    }
                }
            }
        }

        if let match = text.range(of: #"\b(long finish|long aftertaste|longue finale)\b"#, options: .regularExpression) {
            take(match, axis: .aftertaste, value: 8)
        }
        if let match = text.range(of: #"\b(clean|propre|nette?|clarity)\b"#, options: .regularExpression) {
            take(match, axis: .clarity, value: 8)
        }

        return (profile, ranges)
    }

    private static func agitation(
        in text: String,
        skipping consumed: [Range<String.Index>]
    ) -> (Agitation, Range<String.Index>)? {
        let terms: [(Agitation, [String])] = [
            (.swirl, ["swirl", "swirled", "swirling"]),
            (.stir, ["stir", "stirred", "stirring"]),
            (.wdt, ["wdt", "weiss distribution"]),
            (.pulse, ["pulse", "pulsed"]),
            (.none, ["no agitation", "without stirring"]),
        ]
        for (value, spellings) in terms {
            for spelling in spellings {
                if let match = text.range(of: "\\b\(escaped(spelling))\\b", options: .regularExpression),
                   !consumed.contains(where: { $0.overlaps(match) })
                {
                    return (value, match)
                }
            }
        }
        return nil
    }

    private static func namedThing(
        in leftover: String,
        waters: [WaterProfile],
        filters: [FilterStock]
    ) -> (
        matched: String,
        waterId: UUID?,
        waterName: String?,
        filterId: UUID?,
        filterName: String?
    )? {
        let hay = leftover.lowercased()
        guard hay.count >= 3 else { return nil }

        var waterTerms: [(String, WaterProfile)] = waters.flatMap { profile in
            [profile.displayName, profile.name]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.count >= 3 }
                .map { ($0, profile) }
        }
        for profile in waters where profile.source == .tap {
            waterTerms.append(contentsOf: [("tap", profile), ("robinet", profile)])
        }

        var filterTerms: [(String, FilterStock)] = filters.flatMap { stock in
            [stock.displayName, stock.customName, stock.model?.shortName, stock.model?.line, stock.model?.model]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .filter { $0.count >= 3 }
                .map { ($0, stock) }
        }
        for model in ReferenceBase.filters {
            if let owned = filters.first(where: { $0.modelId == model.id }) {
                filterTerms.append((model.shortName, owned))
            }
        }

        func best<T>(_ terms: [(String, T)]) -> (String, T)? {
            terms
                .map { ($0.0.lowercased(), $0.1) }
                .filter { $0.0.count >= 3 && hay.contains($0.0) }
                .max { $0.0.count < $1.0.count }
        }

        let water = best(waterTerms)
        let filter = best(filterTerms)
        var filterName: String?
        if filter == nil {
            filterName = ReferenceBase.filters
                .map(\.shortName)
                .filter { $0.count >= 3 && hay.contains($0.lowercased()) }
                .max { $0.count < $1.count }
        }
        guard water != nil || filter != nil || filterName != nil else { return nil }
        let matched = [water?.0, filter?.0, filterName?.lowercased()]
            .compactMap { $0 }
            .max { $0.count < $1.count } ?? leftover
        return (
            matched,
            water?.1.id,
            water?.1.displayName,
            filter?.1.id,
            filter?.1.displayName ?? filterName
        )
    }

    // MARK: - Text arithmetic

    private static func firstNumber(in text: String) -> Double? {
        guard let match = text.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression)
        else { return nil }
        return Double(text[match])
    }

    private static func remainder(of text: String, minus consumed: [Range<String.Index>]) -> String {
        var kept = ""
        var index = text.startIndex
        let sorted = consumed.sorted { $0.lowerBound < $1.lowerBound }
        for range in sorted where range.lowerBound >= index {
            kept += text[index..<range.lowerBound]
            index = range.upperBound
        }
        kept += text[index...]

        // What is left is only worth keeping if it says something: filler
        // words and stray punctuation are not notes.
        let words = kept
            .replacingOccurrences(of: #"[,.;]"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
            .filter { !Self.filler.contains($0) && $0.count > 1 }
        return words.joined(separator: " ")
    }

    private static func coverage(of text: String, consumed: [Range<String.Index>]) -> Double {
        guard !text.isEmpty else { return 0 }
        let merged = consumed.sorted { $0.lowerBound < $1.lowerBound }
        var covered = 0
        var index = text.startIndex
        for range in merged where range.lowerBound >= index {
            covered += text.distance(from: range.lowerBound, to: range.upperBound)
            index = range.upperBound
        }
        return Double(covered) / Double(text.count)
    }

    private static func escaped(_ text: String) -> String {
        NSRegularExpression.escapedPattern(for: text)
    }

    // MARK: - Vocabulary

    private static let clockUnits = [
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
    ]
    private static let clockTens = ["twenty", "thirty", "forty", "fifty"]

    /// Nouns and units that make "two fifty" a quantity rather than a clock.
    private static let quantityNouns = [
        "of", "g", "gram", "grams", "ml", "millilitre", "millilitres",
        "milliliter", "milliliters", "degree", "degrees", "celsius", "water",
        "in", "out",
    ]

    private static let numberWords: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
        "ten": "10", "eleven": "11", "twelve": "12", "thirteen": "13",
        "fourteen": "14", "fifteen": "15", "sixteen": "16", "seventeen": "17",
        "eighteen": "18", "nineteen": "19", "twenty": "20", "thirty": "30",
        "forty": "40", "fifty": "50", "sixty": "60", "seventy": "70",
        "eighty": "80", "ninety": "90", "hundred": "100",
    ]

    private static let methodAliases: [BrewMethod: [String]] = [
        .v60: ["v 60", "pour over", "pourover"],
        .espresso: ["shot", "double shot"],
        .aeropress: ["aero press"],
        .frenchPress: ["french press", "plunger", "cafetiere"],
        .moka: ["moka pot", "mocha pot"],
        .coldBrew: ["cold brew"],
        .filter: ["batch", "drip", "pour over", "hand brew"],
    ]

    private static let axisAliases: [TasteAxis: [String]] = [
        .acidity: ["acidité", "acidite", "sour"],
        .bitterness: ["amertume", "bitter"],
        .sweetness: ["sucrosité", "sweet"],
        .aroma: ["arôme", "arome", "smell"],
        .aftertaste: ["arrière-goût", "arriere-gout", "finish", "finale"],
        .body: ["corps", "mouthfeel"],
        .clarity: ["clarté", "clarte"],
    ]

    private static let qualitativeScores: [(String, Int)] = [
        ("low", 3), ("faible", 3), ("medium", 5), ("moyen", 5), ("moyenne", 5),
        ("high", 7), ("élevé", 7), ("eleve", 7), ("élevée", 7), ("forte", 7), ("fort", 7),
    ]

    /// Words that carry nothing once the fields are out.
    private static let filler: Set<String> = [
        "and", "with", "the", "a", "of", "at", "to", "for", "then", "it",
        "was", "is", "in", "on", "this", "that", "um", "uh", "okay", "so",
        "brew", "brewed", "made", "did", "i", "my",
    ]
}
