import Foundation

/// What to offer under the coffee name while it is being typed.
///
/// Every row says where it comes from — your Coffee Collection, a coffee you
/// tasted before, a roaster you know — and whether it matched exactly or only
/// approximately. Nothing here deduplicates: typing a name never links or
/// merges anything on its own, and free text always saves.
nonisolated enum CoffeeSuggestions {
    enum Source: Hashable, Sendable {
        /// A card on your shelf. Picking it links the tasting and copies the
        /// card into the snapshot, once.
        case collection(cardID: UUID)
        case tastedBefore
        case roaster
    }

    enum Match: Hashable, Sendable {
        case exact
        case approximate
    }

    struct Suggestion: Identifiable, Hashable, Sendable {
        let title: String
        let subtitle: String
        let source: Source
        let match: Match
        let coffee: TastedCoffee

        var id: String {
            switch source {
            case .collection(let cardID): "card:\(cardID)"
            case .tastedBefore: "tasted:\(SeedPlace.fold(title))|\(SeedPlace.fold(subtitle))"
            case .roaster: "roaster:\(SeedPlace.fold(title))"
            }
        }

        var label: String {
            let where_: String = switch source {
            case .collection: Copy.inCoffeeCollection
            case .tastedBefore: Copy.tastedBefore
            case .roaster: "Roaster"
            }
            return match == .exact ? where_ : "\(where_) · close match"
        }
    }

    static let limit = 6

    static func suggest(
        _ query: String,
        cards: [CoffeeCard],
        tastings: [Tasting],
        roasters: [String]
    ) -> [Suggestion] {
        let needle = SeedPlace.fold(query)
        guard needle.count >= 2 else { return [] }
        var result: [Suggestion] = []

        for card in cards {
            let name = SeedPlace.fold(card.displayName)
            guard let match = match(needle, in: [name, SeedPlace.fold(card.roaster), SeedPlace.fold(card.country)])
            else { continue }
            result.append(Suggestion(
                title: card.displayName,
                subtitle: [card.roaster, card.originLine].filter { !$0.isEmpty }.joined(separator: " · "),
                source: .collection(cardID: card.id),
                match: name == needle ? .exact : match,
                coffee: TastedCoffee(card: card)
            ))
        }

        var seenTasted = Set<String>()
        for tasting in tastings.sorted(by: { $0.date > $1.date }) where !tasting.isDeleted {
            let coffee = tasting.coffee
            let name = SeedPlace.fold(coffee.name)
            guard !name.isEmpty, seenTasted.insert(name + "|" + SeedPlace.fold(coffee.roaster)).inserted else { continue }
            guard let match = match(needle, in: [name, SeedPlace.fold(coffee.roaster)]) else { continue }
            if result.contains(where: { SeedPlace.fold($0.title) == name && SeedPlace.fold($0.coffee.roaster) == SeedPlace.fold(coffee.roaster) }) {
                continue
            }
            var snapshot = coffee
            snapshot.referenceID = nil
            result.append(Suggestion(
                title: coffee.name,
                subtitle: [coffee.roaster, coffee.originLine].filter { !$0.isEmpty }.joined(separator: " · "),
                source: .tastedBefore,
                match: name == needle ? .exact : match,
                coffee: snapshot
            ))
        }

        var seenRoasters = Set<String>()
        for roaster in roasters {
            let key = SeedPlace.fold(roaster)
            guard !key.isEmpty, seenRoasters.insert(key).inserted else { continue }
            guard let match = match(needle, in: [key]) else { continue }
            result.append(Suggestion(
                title: roaster,
                subtitle: "",
                source: .roaster,
                match: key == needle ? .exact : match,
                coffee: TastedCoffee(roaster: roaster)
            ))
        }

        return Array(result.sorted { lhs, rhs in
            if lhs.match != rhs.match { return lhs.match == .exact }
            return rank(lhs.source) < rank(rhs.source)
        }.prefix(limit))
    }

    /// Origins and processes the parser knows, for the detail fields.
    static func origins(_ query: String) -> [String] {
        lexicon(FieldParser.originNames, query)
    }

    static func processes(_ query: String) -> [String] {
        lexicon(FieldParser.processNames, query)
    }

    static func varieties(_ query: String) -> [String] {
        lexicon(FieldParser.varietyNames, query)
    }

    private static func lexicon(_ words: [String], _ query: String) -> [String] {
        let needle = SeedPlace.fold(query)
        guard !needle.isEmpty else { return [] }
        return words
            .filter { SeedPlace.fold($0).hasPrefix(needle) && SeedPlace.fold($0) != needle }
            .prefix(4)
            .map { $0 }
    }

    /// Exact on a field, approximate on a prefix of a word or a substring of
    /// at least three letters.
    private static func match(_ needle: String, in fields: [String]) -> Match? {
        let fields = fields.filter { !$0.isEmpty }
        if fields.contains(needle) { return .exact }
        if fields.contains(where: { field in
            field.hasPrefix(needle) || (needle.count >= 3 && field.contains(needle))
        }) {
            return .approximate
        }
        return nil
    }

    private static func rank(_ source: Source) -> Int {
        switch source {
        case .collection: 0
        case .tastedBefore: 1
        case .roaster: 2
        }
    }
}
