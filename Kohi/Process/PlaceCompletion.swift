import Foundation

/// Spellings offered while a roaster's city or country is typed.
///
/// The archive keeps country names in English. A French keyboard still finds
/// them: "Danemark" is Denmark. Cities stay in whatever spelling the index
/// already uses, so "Copenhagen" offers "Copenhague" when that is the row
/// everyone else filed.
nonisolated enum PlaceCompletion {
    struct CityOffer: Equatable, Sendable {
        var title: String
        /// Set when one country accounts for more of these rows than the rest
        /// put together. A tie stays blank: guessing would file the roastery
        /// in the wrong country, and the country is half of the dedupe key.
        var country: String?
    }

    /// The English name when `typed` is one the archive already uses, or the
    /// only country the prefix can mean. Anything ambiguous is returned as typed.
    static func canonicalCountry(_ typed: String, known: [String] = []) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let exact = exactCountry(trimmed) { return exact }
        let matches = countries(matching: trimmed, known: known, limit: 2)
        return matches.count == 1 ? matches[0] : trimmed
    }

    /// Prefix matches, countries already in the index first. Two letters is
    /// the shortest query that is not half the globe. The spelling already in
    /// the field is left out: a chip that repeats it is noise.
    static func countries(matching query: String, known: [String] = [], limit: Int = 4) -> [String] {
        let folded = fold(query)
        guard folded.count >= 2 else { return [] }
        let indexed = Set(known.map { fold(exactCountry($0) ?? $0) })
        let ranked = catalog.compactMap { entry -> RankedCountry? in
            guard entry.folds.contains(where: { $0.hasPrefix(folded) }) else { return nil }
            if fold(entry.canonical) == folded { return nil }
            return RankedCountry(
                name: entry.canonical,
                indexed: indexed.contains(fold(entry.canonical))
            )
        }
        return ranked
            .sorted { lhs, rhs in
                if lhs.indexed != rhs.indexed { return lhs.indexed }
                if lhs.name.count != rhs.name.count { return lhs.name.count < rhs.name.count }
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
            .prefix(limit)
            .map(\.name)
    }

    /// Cities from `roasters`. An empty query lists the chosen country's
    /// cities; a query searches every city, narrowed when the country already
    /// resolves. The chip is the index spelling, not a translation of whatever
    /// was typed.
    static func cities(
        matching query: String,
        in roasters: [Roaster],
        country: String,
        limit: Int = 6
    ) -> [CityOffer] {
        let folded = fold(query)
        let known = roasters.map(\.country)
        let filter = countryFilter(country, known: known)
        if folded.isEmpty {
            guard filter != nil else { return [] }
        } else if folded.count < 2, filter == nil {
            return []
        }

        let filtered = buckets(in: roasters).filter { bucket in
            guard let filter else { return true }
            return bucket.byCountry[filter] != nil
        }

        if folded.isEmpty, let filter {
            return filtered
                .sorted { lhs, rhs in
                    let left = lhs.byCountry[filter] ?? 0
                    let right = rhs.byCountry[filter] ?? 0
                    if left != right { return left > right }
                    return lhs.title.localizedCompare(rhs.title) == .orderedAscending
                }
                .prefix(limit)
                .map(offer)
        }

        let scored = filtered.compactMap { bucket -> (Bucket, Int)? in
            guard let score = score(folded, bucket) else { return nil }
            return (bucket, score)
        }
        guard let best = scored.map(\.1).min() else { return [] }
        // The field already holds the index spelling. A joined label that
        // merely contains it ("Aarhus / Copenhague") is not a completion.
        if best == 0, scored.contains(where: { $0.1 == 0 && fold($0.0.title) == folded }) {
            return []
        }
        return scored
            .filter { $0.1 == best && fold($0.0.title) != folded }
            .sorted { lhs, rhs in
                if lhs.0.total != rhs.0.total { return lhs.0.total > rhs.0.total }
                return lhs.0.title.localizedCompare(rhs.0.title) == .orderedAscending
            }
            .prefix(limit)
            .map { offer($0.0) }
    }

    // MARK: - Country catalog

    private struct RankedCountry {
        var name: String
        var indexed: Bool
    }

    private struct CountryEntry {
        var canonical: String
        var folds: Set<String>
    }

    /// Regions Apple exposes that are not a place a roastery can be.
    private static let excludedCodes: Set<String> = ["EU", "EZ", "UN", "QO"]

    /// Short forms and exonyms the locale tables do not already carry.
    private static let extras: [String: [String]] = [
        "GB": ["UK", "Angleterre", "England", "Britain", "Grande-Bretagne", "Great Britain"],
        "US": ["USA", "US", "America"],
        "AE": ["UAE"],
        "NL": ["Holland", "Hollande"],
        "DE": ["Deutschland"],
        "KR": ["Korea", "Corée", "Coree"],
        "CZ": ["Czech Republic", "République tchèque"],
    ]

    private static let catalog: [CountryEntry] = {
        let english = Locale(identifier: "en")
        let french = Locale(identifier: "fr")
        var foldsByName: [String: Set<String>] = [:]
        for region in Locale.Region.isoRegions {
            let code = region.identifier.uppercased()
            guard code.count == 2, code.allSatisfy(\.isLetter), !excludedCodes.contains(code) else { continue }
            guard let name = english.localizedString(forRegionCode: code), !name.isEmpty else { continue }
            var folds: Set<String> = [fold(name)]
            if let frenchName = french.localizedString(forRegionCode: code) {
                folds.insert(fold(frenchName))
            }
            for extra in extras[code] ?? [] {
                folds.insert(fold(extra))
            }
            foldsByName[name, default: []].formUnion(folds)
        }
        return foldsByName.map { CountryEntry(canonical: $0.key, folds: $0.value) }
    }()

    private static func exactCountry(_ typed: String) -> String? {
        let folded = fold(typed)
        guard !folded.isEmpty else { return nil }
        return catalog.first { $0.folds.contains(folded) }?.canonical
    }

    /// The country to narrow a city list with. A partial query counts only
    /// when it can mean one country — "Den" is Denmark, "Un" is not.
    private static func countryFilter(_ typed: String, known: [String]) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let exact = exactCountry(trimmed) { return exact }
        let matches = countries(matching: trimmed, known: known, limit: 2)
        return matches.count == 1 ? matches[0] : nil
    }

    // MARK: - Cities

    private struct Bucket {
        var title: String
        var total: Int
        var byCountry: [String: Int]
        var primary: Set<String>
        var all: Set<String>
    }

    /// English and French names for the cities the seed already spells in French.
    private static let cityGroups: [[String]] = [
        ["Copenhague", "Copenhagen", "København"],
        ["Londres", "London"],
        ["Barcelone", "Barcelona"],
        ["Vienne", "Vienna", "Wien"],
        ["Hambourg", "Hamburg"],
        ["Munich", "München"],
        ["Athènes", "Athens"],
        ["Bergame", "Bergamo"],
        ["Varsovie", "Warsaw", "Warszawa"],
        ["Lisbonne", "Lisbon", "Lisboa"],
        ["Édimbourg", "Edinburgh"],
        ["Cornouailles", "Cornwall"],
        ["Anvers", "Antwerp", "Antwerpen"],
        ["Bruxelles", "Brussels", "Brussel"],
        ["Göteborg", "Gothenburg"],
        ["Zurich", "Zürich"],
        ["Prague", "Praha"],
        ["Florence", "Firenze"],
        ["Séoul", "Seoul"],
    ]

    private static let cityAliasIndex: [String: Set<String>] = {
        var index: [String: Set<String>] = [:]
        for group in cityGroups {
            let folds = Set(group.map(fold))
            for item in folds {
                index[item] = folds
            }
        }
        return index
    }()

    private static func buckets(in roasters: [Roaster]) -> [Bucket] {
        struct Accum {
            var spellings: [String: Int] = [:]
            var byCountry: [String: Int] = [:]
            var primary: Set<String> = []
            var all: Set<String> = []
        }
        var grouped: [String: Accum] = [:]
        for roaster in roasters {
            let city = roaster.city.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !city.isEmpty else { continue }
            let rawCountry = roaster.country.trimmingCharacters(in: .whitespacesAndNewlines)
            let countryName = rawCountry.isEmpty ? "" : (exactCountry(rawCountry) ?? rawCountry)
            let folded = fold(city)
            let key = cityAliasIndex[folded]?.sorted().joined(separator: "|") ?? folded
            var entry = grouped[key] ?? Accum()
            entry.spellings[city, default: 0] += 1
            if !countryName.isEmpty {
                entry.byCountry[countryName, default: 0] += 1
            }
            let names = folds(for: city)
            entry.primary.formUnion(names.primary)
            entry.all.formUnion(names.all)
            grouped[key] = entry
        }
        return grouped.values.map { entry in
            let title = entry.spellings.max { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value < rhs.value }
                return lhs.key.localizedCompare(rhs.key) == .orderedDescending
            }?.key ?? ""
            return Bucket(
                title: title,
                total: entry.spellings.values.reduce(0, +),
                byCountry: entry.byCountry,
                primary: entry.primary,
                all: entry.all
            )
        }
    }

    private static func folds(for title: String) -> (primary: Set<String>, all: Set<String>) {
        let primary = aliasSet(fold(title))
        var all = primary
        for part in title.split(separator: "/") {
            let piece = fold(String(part))
            guard !piece.isEmpty else { continue }
            all.formUnion(aliasSet(piece))
        }
        return (primary, all)
    }

    private static func aliasSet(_ folded: String) -> Set<String> {
        var set: Set<String> = [folded]
        if let group = cityAliasIndex[folded] {
            set.formUnion(group)
        }
        return set
    }

    /// 0 is the city's own name or an alias of it. 1 is a half of a joined
    /// label ("Aarhus / Copenhague"). 2 is a prefix. 3 is a shared stem long
    /// enough to be the same word misspelled, not a different city.
    private static func score(_ query: String, _ bucket: Bucket) -> Int? {
        if bucket.primary.contains(query) { return 0 }
        if bucket.all.contains(query) { return 1 }
        if bucket.all.contains(where: { $0.hasPrefix(query) }) { return 2 }
        let shared = bucket.all.map { sharedPrefix($0, query) }.max() ?? 0
        if query.count >= 5, shared >= 5 { return 3 }
        return nil
    }

    private static func sharedPrefix(_ lhs: String, _ rhs: String) -> Int {
        zip(lhs, rhs).prefix { $0.0 == $0.1 }.count
    }

    private static func offer(_ bucket: Bucket) -> CityOffer {
        let ranked = bucket.byCountry.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key.localizedCompare(rhs.key) == .orderedAscending
        }
        let rest = ranked.dropFirst().reduce(0) { $0 + $1.value }
        let country = ranked.first.flatMap { $0.value > rest ? $0.key : nil }
        return CityOffer(title: bucket.title, country: country)
    }

    private static func fold(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
