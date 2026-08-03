import Foundation

/// One scanned coffee card. A value type on purpose: the whole archive is an
/// array of these, which is what makes grid insert, move and delete animations
/// fall out of SwiftUI for free.
nonisolated struct CoffeeCard: Identifiable, Codable, Hashable, Sendable {
    let id: UUID

    var name: String
    var roaster: String
    var place: Place?
    var country: String
    var region: String
    var producer: String
    /// Free text. Cards write "1800m", "1650–1900 masl", "1.8k" — a failed parse
    /// would be worse than the words the roaster actually printed.
    var altitude: String
    var variety: String
    /// Free text with quick picks, so an unfamiliar process is never unrepresentable.
    var process: String
    var tastingNotes: [String]
    var brewMethod: BrewMethod?
    var personalNotes: String

    /// When the coffee was had. Defaults to the scan date, editable afterwards.
    var date: Date
    var createdAt: Date
    var updatedAt: Date

    /// Width over height of the flat scan. Stored so the grid can lay out and
    /// animate a tile before its image has been decoded.
    var aspectRatio: Double
    /// Whether a cut-out mask was produced and is worth compositing.
    var hasMask: Bool
    /// Whether the scan look was applied to `flat.heic`. The original capture is
    /// kept untouched, so this is what a reprocess would need to know.
    var enhanced: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        roaster: String = "",
        place: Place? = nil,
        country: String = "",
        region: String = "",
        producer: String = "",
        altitude: String = "",
        variety: String = "",
        process: String = "",
        tastingNotes: [String] = [],
        brewMethod: BrewMethod? = nil,
        personalNotes: String = "",
        date: Date = .now,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        aspectRatio: Double = 0.75,
        hasMask: Bool = false,
        enhanced: Bool = false
    ) {
        self.id = id
        self.name = name
        self.roaster = roaster
        self.place = place
        self.country = country
        self.region = region
        self.producer = producer
        self.altitude = altitude
        self.variety = variety
        self.process = process
        self.tastingNotes = tastingNotes
        self.brewMethod = brewMethod
        self.personalNotes = personalNotes
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.aspectRatio = aspectRatio
        self.hasMask = hasMask
        self.enhanced = enhanced
    }

    /// What the grid and detail view show when the lot has no name yet.
    var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled lot" : name
    }

    /// The origin line, e.g. "Nyeri, Kenya".
    var originLine: String {
        [region, country]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

// Decoding tolerates every field being absent. This is what keeps the promise
// that adding a field to an experiment never invalidates the existing archive.
nonisolated extension CoffeeCard {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        roaster = try c.decodeIfPresent(String.self, forKey: .roaster) ?? ""
        place = try c.decodeIfPresent(Place.self, forKey: .place)
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? ""
        region = try c.decodeIfPresent(String.self, forKey: .region) ?? ""
        producer = try c.decodeIfPresent(String.self, forKey: .producer) ?? ""
        altitude = try c.decodeIfPresent(String.self, forKey: .altitude) ?? ""
        variety = try c.decodeIfPresent(String.self, forKey: .variety) ?? ""
        process = try c.decodeIfPresent(String.self, forKey: .process) ?? ""
        tastingNotes = try c.decodeIfPresent([String].self, forKey: .tastingNotes) ?? []
        brewMethod = try c.decodeIfPresent(BrewMethod.self, forKey: .brewMethod)
        personalNotes = try c.decodeIfPresent(String.self, forKey: .personalNotes) ?? ""
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .now
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
        aspectRatio = try c.decodeIfPresent(Double.self, forKey: .aspectRatio) ?? 0.75
        hasMask = try c.decodeIfPresent(Bool.self, forKey: .hasMask) ?? false
        enhanced = try c.decodeIfPresent(Bool.self, forKey: .enhanced) ?? false
    }
}
