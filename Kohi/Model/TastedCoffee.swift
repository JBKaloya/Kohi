import Foundation

/// The coffee as it was served, kept on the tasting itself.
///
/// This is a snapshot, not a reference: the cup a café poured in March does
/// not change when the card on the shelf is edited in June. A tasting linked
/// to a card copies its fields once, then lives on its own.
nonisolated struct TastedCoffee: Codable, Hashable, Sendable {
    /// Free text, as the user wrote it or the menu printed it. Never normalized.
    var name: String
    /// The roaster, never the shop. A café roasting its own beans fills both.
    var roaster: String
    var roasterId: UUID?
    var country: String
    var region: String
    var farm: String
    var variety: String
    var process: String
    var tastingNotes: [String]
    /// Reserved for a shared coffee catalogue. Unused for now.
    var referenceID: String?

    init(
        name: String = "",
        roaster: String = "",
        roasterId: UUID? = nil,
        country: String = "",
        region: String = "",
        farm: String = "",
        variety: String = "",
        process: String = "",
        tastingNotes: [String] = [],
        referenceID: String? = nil
    ) {
        self.name = name
        self.roaster = roaster
        self.roasterId = roasterId
        self.country = country
        self.region = region
        self.farm = farm
        self.variety = variety
        self.process = process
        self.tastingNotes = tastingNotes
        self.referenceID = referenceID
    }

    /// Copies what the card knows, once. Later card edits never reach here.
    init(card: CoffeeCard) {
        self.init(
            name: card.displayName,
            roaster: card.roaster,
            roasterId: card.roasterId,
            country: card.country,
            region: card.region,
            farm: card.farm ?? card.producer,
            variety: card.variety,
            process: card.process,
            tastingNotes: card.tastingNotes
        )
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Nyeri, Kenya".
    var originLine: String {
        [region, country]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Wheel ids recognised from the declared notes. Derived, never stored.
    var declaredFlavors: [FlavorTag] {
        FlavorMatcher.match(tastingNotes).tags.filter { !$0.isCustom }
    }

    /// Anything beyond the name and the roaster.
    var hasMore: Bool {
        [country, region, farm, variety, process].contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            || !tastingNotes.isEmpty
    }
}

nonisolated extension TastedCoffee {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        roaster = try c.decodeIfPresent(String.self, forKey: .roaster) ?? ""
        roasterId = try c.decodeIfPresent(UUID.self, forKey: .roasterId)
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? ""
        region = try c.decodeIfPresent(String.self, forKey: .region) ?? ""
        farm = try c.decodeIfPresent(String.self, forKey: .farm) ?? ""
        variety = try c.decodeIfPresent(String.self, forKey: .variety) ?? ""
        process = try c.decodeIfPresent(String.self, forKey: .process) ?? ""
        tastingNotes = try c.decodeIfPresent([String].self, forKey: .tastingNotes) ?? []
        referenceID = try c.decodeIfPresent(String.self, forKey: .referenceID)
    }
}
