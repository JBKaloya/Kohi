import Foundation

/// A roaster, shared by everyone rather than retyped on every card.
///
/// Reference data: read from a public table, cached locally, and never pushed
/// through the outbox except when this device is the one creating the entry.
/// The card keeps its free-text `roaster` as the authority for display, so an
/// unmatched card reads exactly the same as a matched one.
nonisolated struct Roaster: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var country: String
    var city: String
    var website: String?
    var instagram: String?
    /// Who first created the entry. Nil for seeded rows.
    var createdBy: UUID?
    var updatedAt: Date
    /// Slug in the bundled seed. Stays on the device: the shared table has no
    /// column for it, and a pull must not wipe it. See `RoasterStore.merge`.
    var seedID: String?
    /// A person corrected this row. Their copy wins, and the provenance tag
    /// switches to "from you".
    var editedByUser: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        country: String = "",
        city: String = "",
        website: String? = nil,
        instagram: String? = nil,
        createdBy: UUID? = nil,
        updatedAt: Date = .now,
        seedID: String? = nil,
        editedByUser: Bool = false
    ) {
        self.id = id
        self.name = name
        self.country = country
        self.city = city
        self.website = website
        self.instagram = instagram
        self.createdBy = createdBy
        self.updatedAt = updatedAt
        self.seedID = seedID
        self.editedByUser = editedByUser
    }

    /// Host of `website`, without `www`. Instagram links are not a domain:
    /// several roasters have nothing else, and instagram.com would collapse
    /// them into one.
    var websiteDomain: String? {
        Self.domain(of: website)
    }

    static func domain(of website: String?) -> String? {
        guard let website, let host = URL(string: website)?.host?.lowercased() else { return nil }
        if host.contains("instagram.com") { return nil }
        let stripped = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return stripped.isEmpty ? nil : stripped
    }

    /// "Belleville Brûlerie · Paris, France".
    var summary: String {
        let location = [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
        return location.isEmpty ? name : "\(name) · \(location)"
    }

    /// The key two entries have to share to be the same roaster: name folded to
    /// letters and digits, plus country. Accents, punctuation, casing and the
    /// word "roasters" are all noise — "Belleville Brûlerie" and
    /// "belleville brulerie" are one roastery, and "Kaffe" in Norway is not
    /// "Kaffe" in Sweden.
    var dedupeKey: String {
        "\(Self.fold(name))|\(Self.fold(country))"
    }

    static func fold(_ value: String) -> String {
        let stripped = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: " ")

        let noise: Set<String> = [
            "roasters", "roaster", "roastery", "roasting", "coffee", "coffees",
            "cafe", "cafes", "brulerie", "torrefaction", "torrefacteur", "torrefacteurs",
            "the", "co", "company", "and",
        ]
        let words = stripped
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty && !noise.contains($0) }

        // Everything was noise ("Coffee Company"): keep it rather than fold the
        // entry down to an empty key that would match every other empty one.
        return words.isEmpty ? stripped.replacingOccurrences(of: " ", with: "") : words.joined()
    }
}

nonisolated extension Roaster {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? ""
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        website = try c.decodeIfPresent(String.self, forKey: .website)
        instagram = try c.decodeIfPresent(String.self, forKey: .instagram)
        createdBy = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
        seedID = try c.decodeIfPresent(String.self, forKey: .seedID)
        editedByUser = try c.decodeIfPresent(Bool.self, forKey: .editedByUser) ?? false
    }
}
