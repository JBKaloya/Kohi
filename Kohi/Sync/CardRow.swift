import Foundation

/// DTO matching the `public.coffee_cards` table schema (snake_case).
/// Converts to/from the local `CoffeeCard` model without modifying it.
struct CardRow: Codable, Sendable {
    let id: UUID
    let user_id: UUID

    var name: String
    var roaster: String
    var country: String
    var region: String
    var producer: String
    var altitude: String
    var variety: String
    var process: String
    var tasting_notes: [String]
    var brew_method: String?
    var personal_notes: String

    var species: String
    var is_decaf: Bool
    var decaf_method: String?
    var product_url: String?
    var farm: String?
    var wash_station: String?
    var label_code: String?

    var roaster_id: UUID?
    var place_type: String?
    var roast_level: String?
    var agtron: Int?
    var roasted_on: Date?
    var harvest: String?
    var cupping_score: Double?
    var price: Double?
    var currency: String?
    var bag_weight_g: Double?
    var lot: String?

    var recipe_suggestion: Brew?
    var source_language: String?
    var original_fields: [String: String]

    var date: Date
    var created_at: Date
    var updated_at: Date

    var aspect_ratio: Double
    var has_mask: Bool
    var enhanced: Bool
    var poster: String

    var attachments: [CardAttachment]
    /// Times the coffee was drunk. Optional on decode so a server that has
    /// not migrated yet still loads — same reason as `place_ref`.
    var tastings: [Tasting]

    var place_name: String?
    var place_address: String?
    var place_latitude: Double?
    var place_longitude: Double?
    /// Bundled place slug. Optional so a server that has not migrated yet
    /// still decodes — see `init(from:)`.
    var place_ref: String?

    private enum CodingKeys: String, CodingKey {
        case id, user_id, name, roaster, country, region, producer, altitude, variety, process
        case tasting_notes, brew_method, personal_notes, species, is_decaf, decaf_method
        case product_url, farm, wash_station, label_code, roaster_id, place_type
        case roast_level, agtron, roasted_on, harvest, cupping_score, price, currency
        case bag_weight_g, lot, recipe_suggestion, source_language, original_fields
        case date, created_at, updated_at, aspect_ratio, has_mask, enhanced, poster
        case attachments, tastings, place_name, place_address, place_latitude, place_longitude, place_ref
    }

    init(card: CoffeeCard, userID: UUID) {
        self.id = card.id
        self.user_id = userID
        self.name = card.name
        self.roaster = card.roaster
        self.country = card.country
        self.region = card.region
        self.producer = card.producer
        self.altitude = card.altitude
        self.variety = card.variety
        self.process = card.process
        self.tasting_notes = card.tastingNotes
        self.brew_method = card.brewMethod?.rawValue
        self.personal_notes = card.personalNotes
        self.species = card.species.rawValue
        self.is_decaf = card.isDecaf
        self.decaf_method = card.decafMethod?.rawValue
        self.product_url = card.productURL
        self.farm = card.farm
        self.wash_station = card.washStation
        self.label_code = card.labelCode
        self.roaster_id = card.roasterId
        self.place_type = card.placeType?.rawValue
        self.roast_level = card.roastLevel?.rawValue
        self.agtron = card.agtron
        self.roasted_on = card.roastedOn
        self.harvest = card.harvest
        self.cupping_score = card.cuppingScore
        self.price = card.price
        self.currency = card.currency
        self.bag_weight_g = card.bagWeightG
        self.lot = card.lot
        self.recipe_suggestion = card.recipeSuggestion
        self.source_language = card.sourceLanguage
        self.original_fields = card.originalFields
        self.date = card.date
        self.created_at = card.createdAt
        self.updated_at = card.updatedAt
        self.aspect_ratio = card.aspectRatio
        self.has_mask = card.hasMask
        self.enhanced = card.enhanced
        self.poster = card.poster.rawValue
        self.attachments = card.attachments
        self.tastings = card.tastings
        self.place_name = card.place?.name
        self.place_address = card.place?.address
        self.place_latitude = card.place?.latitude
        self.place_longitude = card.place?.longitude
        self.place_ref = card.placeID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        user_id = try container.decode(UUID.self, forKey: .user_id)
        name = try container.decode(String.self, forKey: .name)
        roaster = try container.decode(String.self, forKey: .roaster)
        country = try container.decode(String.self, forKey: .country)
        region = try container.decode(String.self, forKey: .region)
        producer = try container.decode(String.self, forKey: .producer)
        altitude = try container.decode(String.self, forKey: .altitude)
        variety = try container.decode(String.self, forKey: .variety)
        process = try container.decode(String.self, forKey: .process)
        tasting_notes = try container.decode([String].self, forKey: .tasting_notes)
        brew_method = try container.decodeIfPresent(String.self, forKey: .brew_method)
        personal_notes = try container.decode(String.self, forKey: .personal_notes)
        species = try container.decode(String.self, forKey: .species)
        is_decaf = try container.decode(Bool.self, forKey: .is_decaf)
        decaf_method = try container.decodeIfPresent(String.self, forKey: .decaf_method)
        product_url = try container.decodeIfPresent(String.self, forKey: .product_url)
        farm = try container.decodeIfPresent(String.self, forKey: .farm)
        wash_station = try container.decodeIfPresent(String.self, forKey: .wash_station)
        label_code = try container.decodeIfPresent(String.self, forKey: .label_code)
        roaster_id = try container.decodeIfPresent(UUID.self, forKey: .roaster_id)
        place_type = try container.decodeIfPresent(String.self, forKey: .place_type)
        roast_level = try container.decodeIfPresent(String.self, forKey: .roast_level)
        agtron = try container.decodeIfPresent(Int.self, forKey: .agtron)
        roasted_on = try container.decodeIfPresent(Date.self, forKey: .roasted_on)
        harvest = try container.decodeIfPresent(String.self, forKey: .harvest)
        cupping_score = try container.decodeIfPresent(Double.self, forKey: .cupping_score)
        price = try container.decodeIfPresent(Double.self, forKey: .price)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        bag_weight_g = try container.decodeIfPresent(Double.self, forKey: .bag_weight_g)
        lot = try container.decodeIfPresent(String.self, forKey: .lot)
        recipe_suggestion = try container.decodeIfPresent(Brew.self, forKey: .recipe_suggestion)
        source_language = try container.decodeIfPresent(String.self, forKey: .source_language)
        original_fields = try container.decodeIfPresent([String: String].self, forKey: .original_fields) ?? [:]
        date = try container.decode(Date.self, forKey: .date)
        created_at = try container.decode(Date.self, forKey: .created_at)
        updated_at = try container.decode(Date.self, forKey: .updated_at)
        aspect_ratio = try container.decode(Double.self, forKey: .aspect_ratio)
        has_mask = try container.decode(Bool.self, forKey: .has_mask)
        enhanced = try container.decode(Bool.self, forKey: .enhanced)
        poster = try container.decode(String.self, forKey: .poster)
        attachments = try container.decode([CardAttachment].self, forKey: .attachments)
        tastings = (try? container.decodeIfPresent([Lossy<Tasting>].self, forKey: .tastings))?
            .compactMap(\.value) ?? []
        place_name = try container.decodeIfPresent(String.self, forKey: .place_name)
        place_address = try container.decodeIfPresent(String.self, forKey: .place_address)
        place_latitude = try container.decodeIfPresent(Double.self, forKey: .place_latitude)
        place_longitude = try container.decodeIfPresent(Double.self, forKey: .place_longitude)
        place_ref = try container.decodeIfPresent(String.self, forKey: .place_ref)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(user_id, forKey: .user_id)
        try container.encode(name, forKey: .name)
        try container.encode(roaster, forKey: .roaster)
        try container.encode(country, forKey: .country)
        try container.encode(region, forKey: .region)
        try container.encode(producer, forKey: .producer)
        try container.encode(altitude, forKey: .altitude)
        try container.encode(variety, forKey: .variety)
        try container.encode(process, forKey: .process)
        try container.encode(tasting_notes, forKey: .tasting_notes)
        try container.encodeIfPresent(brew_method, forKey: .brew_method)
        try container.encode(personal_notes, forKey: .personal_notes)
        try container.encode(species, forKey: .species)
        try container.encode(is_decaf, forKey: .is_decaf)
        try container.encodeIfPresent(decaf_method, forKey: .decaf_method)
        try container.encodeIfPresent(product_url, forKey: .product_url)
        try container.encodeIfPresent(farm, forKey: .farm)
        try container.encodeIfPresent(wash_station, forKey: .wash_station)
        try container.encodeIfPresent(label_code, forKey: .label_code)
        try container.encodeIfPresent(roaster_id, forKey: .roaster_id)
        try container.encodeIfPresent(place_type, forKey: .place_type)
        try container.encodeIfPresent(roast_level, forKey: .roast_level)
        try container.encodeIfPresent(agtron, forKey: .agtron)
        try container.encodeIfPresent(roasted_on, forKey: .roasted_on)
        try container.encodeIfPresent(harvest, forKey: .harvest)
        try container.encodeIfPresent(cupping_score, forKey: .cupping_score)
        try container.encodeIfPresent(price, forKey: .price)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encodeIfPresent(bag_weight_g, forKey: .bag_weight_g)
        try container.encodeIfPresent(lot, forKey: .lot)
        try container.encodeIfPresent(recipe_suggestion, forKey: .recipe_suggestion)
        try container.encodeIfPresent(source_language, forKey: .source_language)
        try container.encode(original_fields, forKey: .original_fields)
        try container.encode(date, forKey: .date)
        try container.encode(created_at, forKey: .created_at)
        try container.encode(updated_at, forKey: .updated_at)
        try container.encode(aspect_ratio, forKey: .aspect_ratio)
        try container.encode(has_mask, forKey: .has_mask)
        try container.encode(enhanced, forKey: .enhanced)
        try container.encode(poster, forKey: .poster)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(tastings, forKey: .tastings)
        try container.encodeIfPresent(place_name, forKey: .place_name)
        try container.encodeIfPresent(place_address, forKey: .place_address)
        try container.encodeIfPresent(place_latitude, forKey: .place_latitude)
        try container.encodeIfPresent(place_longitude, forKey: .place_longitude)
        try container.encodeIfPresent(place_ref, forKey: .place_ref)
    }

    func toCoffeeCard(brews: [Brew] = []) -> CoffeeCard {
        var place: Place?
        if let pName = place_name, !pName.isEmpty {
            place = Place(
                name: pName,
                address: place_address ?? "",
                latitude: place_latitude ?? 0,
                longitude: place_longitude ?? 0
            )
        }

        return CoffeeCard(
            id: id,
            name: name,
            roaster: roaster,
            roasterId: roaster_id,
            place: place,
            placeID: place_ref,
            placeType: place_type.flatMap { PlaceType(rawValue: $0) },
            country: country,
            region: region,
            producer: producer,
            altitude: altitude,
            variety: variety,
            process: process,
            tastingNotes: tasting_notes,
            brewMethod: brew_method.flatMap { BrewMethod(rawValue: $0) },
            personalNotes: personal_notes,
            brews: brews,
            tastings: tastings,
            attachments: attachments,
            species: BeanSpecies(rawValue: species) ?? .arabica,
            isDecaf: is_decaf,
            decafMethod: decaf_method.flatMap(DecafMethod.init(rawValue:)),
            productURL: product_url,
            farm: farm,
            washStation: wash_station,
            roastLevel: roast_level.flatMap { RoastLevel(rawValue: $0) },
            agtron: agtron,
            roastedOn: roasted_on,
            harvest: harvest,
            cuppingScore: cupping_score,
            price: price,
            currency: currency,
            bagWeightG: bag_weight_g,
            lot: lot,
            labelCode: label_code,
            recipeSuggestion: recipe_suggestion,
            sourceLanguage: source_language,
            originalFields: original_fields,
            date: date,
            createdAt: created_at,
            updatedAt: updated_at,
            aspectRatio: aspect_ratio,
            hasMask: has_mask,
            enhanced: enhanced,
            poster: PosterState(rawValue: poster) ?? .none
        )
    }
}

/// A `coffee_cards` row with its `brews(*)` join, decoded through `CardRow` so
/// the pull uses the same mapping as the push. Decoding the card separately is
/// how fields silently went missing before.
struct CardWithBrews: Decodable, Sendable {
    let row: CardRow
    let brews: [BrewRow]

    private enum Keys: String, CodingKey {
        case brews
    }

    init(from decoder: any Decoder) throws {
        row = try CardRow(from: decoder)
        let container = try decoder.container(keyedBy: Keys.self)
        brews = try container.decodeIfPresent([BrewRow].self, forKey: .brews) ?? []
    }
}
