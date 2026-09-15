import Foundation

/// One scanned coffee card. A value type on purpose: the whole archive is an
/// array of these, which is what makes grid insert, move and delete animations
/// fall out of SwiftUI for free.
nonisolated struct CoffeeCard: Identifiable, Codable, Hashable, Sendable {
    let id: UUID

    var name: String
    var roaster: String
    /// Set once the free-text roaster is matched to a `Roaster` entity. The
    /// text stays authoritative for display, so an unmatched card reads the same.
    var roasterId: UUID?
    var place: Place?
    /// Roastery, café, shop or online. Nil until someone says.
    var placeType: PlaceType?
    var country: String
    var region: String
    var producer: String
    /// Free text. Cards write "1800m", "1650–1900 masl", "1.8k" — a failed parse
    /// would be worse than the words the roaster actually printed.
    var altitude: String
    var variety: String
    /// Free text with quick picks, so an unfamiliar process is never unrepresentable.
    var process: String

    /// Any of the origin block is filled. Edit folds the block closed when
    /// this is false, so an empty form does not read as work to do.
    var hasOrigin: Bool {
        [country, region, producer, altitude, variety]
            .contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Country · region · producer, for a collapsed Origin header in edit.
    var originSummary: String? {
        let parts = [country, region, producer]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var tastingNotes: [String]
    /// Wheel ids recognised from the printed notes. Derived, never stored.
    var declaredFlavors: [FlavorTag] {
        FlavorMatcher.match(tastingNotes).tags.filter { !$0.isCustom }
    }
    var brewMethod: BrewMethod?
    var personalNotes: String

    /// Extraction log: every brew of this card, newest first.
    var brews: [Brew]

    /// The most recent brew by date, regardless of array order.
    var lastBrew: Brew? {
        brews.max { $0.date < $1.date }
    }

    /// Linked pages, recipes, or documents. Newest first.
    var attachments: [CardAttachment]

    var species: BeanSpecies
    var isDecaf: Bool
    var decafMethod: DecafMethod?
    /// Product page, filled from a QR http(s) or pasted. Distinct from `labelCode`.
    var productURL: String?
    var farm: String?
    var washStation: String?

    // MARK: On the bag
    //
    // What the packaging says beyond the origin story. `roastedOn` and
    // `roastLevel` are the two that change how you brew; the rest is collection
    // keeping, and useful the day this data is shared.

    var roastLevel: RoastLevel?
    /// Agtron number when the roaster prints one. No conversion to `roastLevel`:
    /// the scales disagree between instruments.
    var agtron: Int?
    /// Roast date. Distinct from `date` (when the coffee was had) and
    /// `createdAt` (when the card was filed).
    var roastedOn: Date?
    /// Free text: "2025/26", "Nov 2025".
    var harvest: String?
    /// 0–100, as printed. Recorded, never computed.
    var cuppingScore: Double?
    var price: Double?
    /// ISO code, e.g. "EUR". Nil means unknown, not "local currency".
    var currency: String?
    var bagWeightG: Double?
    /// Lot or batch number as printed.
    var lot: String?

    /// Raw QR / barcode payload, stored for linking.
    var labelCode: String?

    /// The brew recipe printed on the card, when the scan recognised one.
    /// Not a logged brew: it seeds the brew sheet instead.
    var recipeSuggestion: Brew?

    /// Language the card was written in when fields were translated ("ja", "zh").
    var sourceLanguage: String?
    /// Original text per field name, kept when a translation replaced the value.
    var originalFields: [String: String]

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

    /// Lifecycle of the AI-generated poster image. The scan stays the archive;
    /// the poster is a square stamp-on-parchment variant for the grid.
    var poster: PosterState

    init(
        id: UUID = UUID(),
        name: String = "",
        roaster: String = "",
        roasterId: UUID? = nil,
        place: Place? = nil,
        placeType: PlaceType? = nil,
        country: String = "",
        region: String = "",
        producer: String = "",
        altitude: String = "",
        variety: String = "",
        process: String = "",
        tastingNotes: [String] = [],
        brewMethod: BrewMethod? = nil,
        personalNotes: String = "",
        brews: [Brew] = [],
        attachments: [CardAttachment] = [],
        species: BeanSpecies = .arabica,
        isDecaf: Bool = false,
        decafMethod: DecafMethod? = nil,
        productURL: String? = nil,
        farm: String? = nil,
        washStation: String? = nil,
        roastLevel: RoastLevel? = nil,
        agtron: Int? = nil,
        roastedOn: Date? = nil,
        harvest: String? = nil,
        cuppingScore: Double? = nil,
        price: Double? = nil,
        currency: String? = nil,
        bagWeightG: Double? = nil,
        lot: String? = nil,
        labelCode: String? = nil,
        recipeSuggestion: Brew? = nil,
        sourceLanguage: String? = nil,
        originalFields: [String: String] = [:],
        date: Date = .now,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        aspectRatio: Double = 0.75,
        hasMask: Bool = false,
        enhanced: Bool = false,
        poster: PosterState = .none
    ) {
        self.id = id
        self.name = name
        self.roaster = roaster
        self.roasterId = roasterId
        self.place = place
        self.placeType = placeType
        self.country = country
        self.region = region
        self.producer = producer
        self.altitude = altitude
        self.variety = variety
        self.process = process
        self.tastingNotes = tastingNotes
        self.brewMethod = brewMethod
        self.personalNotes = personalNotes
        self.brews = brews
        self.attachments = attachments
        self.species = species
        self.isDecaf = isDecaf
        self.decafMethod = decafMethod
        self.productURL = productURL
        self.farm = farm
        self.washStation = washStation
        self.roastLevel = roastLevel
        self.agtron = agtron
        self.roastedOn = roastedOn
        self.harvest = harvest
        self.cuppingScore = cuppingScore
        self.price = price
        self.currency = currency
        self.bagWeightG = bagWeightG
        self.lot = lot
        self.labelCode = labelCode
        self.recipeSuggestion = recipeSuggestion
        self.sourceLanguage = sourceLanguage
        self.originalFields = originalFields
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.aspectRatio = aspectRatio
        self.hasMask = hasMask
        self.enhanced = enhanced
        self.poster = poster
    }

    /// What the grid and detail view show. When no explicit name was parsed,
    /// builds a title from the most identifying fields so the card is never
    /// just "Untitled lot" if anything useful was extracted.
    ///
    /// Variety comes last: half of Ethiopia is "Heirloom", and that is the
    /// worst thing to title a shelf by.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }

        let candidates = [producer, farm ?? "", washStation ?? "", region, country, roaster, variety]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if candidates.count >= 2 {
            return candidates.prefix(2).joined(separator: ", ")
        }
        if let single = candidates.first { return single }
        return "Untitled lot"
    }

    /// The origin line, e.g. "Nyeri, Kenya".
    var originLine: String {
        [region, country]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Price per kilo, so bags of different sizes can be compared.
    var pricePerKilo: Double? {
        guard let price, let bagWeightG, bagWeightG > 0 else { return nil }
        return price / (bagWeightG / 1000)
    }

    /// "14 € · 250 g · 56 €/kg", dropping whatever is missing.
    var priceLine: String? {
        var parts: [String] = []
        if let price {
            parts.append(Self.money(price, currency: currency))
        }
        if let bagWeightG {
            parts.append(Self.grams(bagWeightG))
        }
        if let perKilo = pricePerKilo {
            parts.append(Self.money(perKilo, currency: currency) + "/kg")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Days since roast, for the freshness note on a suggested recipe.
    /// Counts calendar days so "roasted today" is 0, not a fraction.
    func daysOffRoast(asOf now: Date = .now) -> Int? {
        guard let roastedOn else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: roastedOn),
            to: calendar.startOfDay(for: now)
        ).day
    }

    static func money(_ value: Double, currency: String?) -> String {
        let amount = value == value.rounded()
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
        guard let currency, !currency.isEmpty else { return amount }
        return "\(amount) \(Self.symbol(for: currency))"
    }

    static func grams(_ value: Double) -> String {
        value == value.rounded()
            ? String(format: "%.0f g", value)
            : String(format: "%.1f g", value)
    }

    private static func symbol(for currency: String) -> String {
        switch currency.uppercased() {
        case "EUR": "€"
        case "USD": "$"
        case "GBP": "£"
        case "JPY": "¥"
        default: currency.uppercased()
        }
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
        roasterId = try c.decodeIfPresent(UUID.self, forKey: .roasterId)
        place = try c.decodeIfPresent(Place.self, forKey: .place)
        placeType = try c.decodeIfPresent(PlaceType.self, forKey: .placeType)
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? ""
        region = try c.decodeIfPresent(String.self, forKey: .region) ?? ""
        producer = try c.decodeIfPresent(String.self, forKey: .producer) ?? ""
        altitude = try c.decodeIfPresent(String.self, forKey: .altitude) ?? ""
        variety = try c.decodeIfPresent(String.self, forKey: .variety) ?? ""
        process = try c.decodeIfPresent(String.self, forKey: .process) ?? ""
        tastingNotes = try c.decodeIfPresent([String].self, forKey: .tastingNotes) ?? []
        brewMethod = try c.decodeIfPresent(BrewMethod.self, forKey: .brewMethod)
        personalNotes = try c.decodeIfPresent(String.self, forKey: .personalNotes) ?? ""
        brews = (try c.decodeIfPresent([Brew].self, forKey: .brews) ?? [])
            .sorted { $0.date > $1.date }
        attachments = try c.decodeIfPresent([CardAttachment].self, forKey: .attachments) ?? []
        species = try c.decodeIfPresent(BeanSpecies.self, forKey: .species) ?? .arabica
        isDecaf = try c.decodeIfPresent(Bool.self, forKey: .isDecaf) ?? false
        decafMethod = try c.decodeIfPresent(DecafMethod.self, forKey: .decafMethod)
        productURL = try c.decodeIfPresent(String.self, forKey: .productURL)
        farm = try c.decodeIfPresent(String.self, forKey: .farm)
        washStation = try c.decodeIfPresent(String.self, forKey: .washStation)
        roastLevel = try c.decodeIfPresent(RoastLevel.self, forKey: .roastLevel)
        agtron = try c.decodeIfPresent(Int.self, forKey: .agtron)
        roastedOn = try c.decodeIfPresent(Date.self, forKey: .roastedOn)
        harvest = try c.decodeIfPresent(String.self, forKey: .harvest)
        cuppingScore = try c.decodeIfPresent(Double.self, forKey: .cuppingScore)
        price = try c.decodeIfPresent(Double.self, forKey: .price)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        bagWeightG = try c.decodeIfPresent(Double.self, forKey: .bagWeightG)
        lot = try c.decodeIfPresent(String.self, forKey: .lot)
        labelCode = try c.decodeIfPresent(String.self, forKey: .labelCode)
        recipeSuggestion = try c.decodeIfPresent(Brew.self, forKey: .recipeSuggestion)
        sourceLanguage = try c.decodeIfPresent(String.self, forKey: .sourceLanguage)
        originalFields = try c.decodeIfPresent([String: String].self, forKey: .originalFields) ?? [:]
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .now
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
        aspectRatio = try c.decodeIfPresent(Double.self, forKey: .aspectRatio) ?? 0.75
        hasMask = try c.decodeIfPresent(Bool.self, forKey: .hasMask) ?? false
        enhanced = try c.decodeIfPresent(Bool.self, forKey: .enhanced) ?? false
        poster = try c.decodeIfPresent(PosterState.self, forKey: .poster) ?? .none
    }
}
