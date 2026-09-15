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

    var place_name: String?
    var place_address: String?
    var place_latitude: Double?
    var place_longitude: Double?

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
        self.place_name = card.place?.name
        self.place_address = card.place?.address
        self.place_latitude = card.place?.latitude
        self.place_longitude = card.place?.longitude
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
