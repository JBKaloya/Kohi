import Foundation

/// DTO matching the `public.tastings` table (snake_case).
///
/// The coffee, the place and the sensory blocks are jsonb: each is read and
/// written whole. `legacy` keeps what the card-era tasting carried and the new
/// one no longer writes — the original context and the three correction axes —
/// so nothing an older build recorded is lost in transit.
struct TastingRow: Codable, Sendable, Equatable {
    let id: UUID
    let user_id: UUID

    var card_id: UUID?
    var tasted_at: Date
    var coffee: TastedCoffee
    var place: Place?
    var place_ref: String?
    var place_map_id: String?
    var method: String?
    var brewer: String?
    var is_batch: Bool
    var method_note: String?
    var price_amount: Decimal?
    var price_currency: String?
    var rating: Int?
    var taste: TasteProfile
    var flavors: [FlavorTag]
    var legacy: Legacy?
    var note: String?
    var photos: [String]
    var created_at: Date
    var updated_at: Date
    var deleted_at: Date?

    struct Legacy: Codable, Sendable, Equatable {
        var context: Tasting.Context?
        var acidity: Int
        var bitterness: Int
        var body: Int
    }

    init(tasting: Tasting, userID: UUID) {
        id = tasting.id
        user_id = userID
        card_id = tasting.cardID
        tasted_at = tasting.date
        coffee = tasting.coffee
        place = tasting.place
        place_ref = tasting.placeID
        place_map_id = tasting.place?.mapItemID
        method = tasting.method?.rawValue
        brewer = tasting.brewer?.rawValue
        is_batch = tasting.isBatch
        method_note = tasting.methodNote
        price_amount = tasting.price?.amount
        price_currency = tasting.price?.currency
        rating = tasting.rating
        taste = tasting.taste
        flavors = tasting.flavors
        let hasAxes = tasting.acidity != 0 || tasting.bitterness != 0 || tasting.body != 0
        let isHome = tasting.place == nil
        legacy = hasAxes || isHome
            ? Legacy(
                context: isHome ? tasting.context : nil,
                acidity: tasting.acidity,
                bitterness: tasting.bitterness,
                body: tasting.body
            )
            : nil
        note = tasting.note
        photos = tasting.photos
        created_at = tasting.createdAt
        updated_at = tasting.updatedAt
        deleted_at = tasting.deletedAt
    }

    func toTasting() -> Tasting {
        let context: Tasting.Context
        if let place {
            context = .out(place: place, placeID: place_ref)
        } else {
            context = legacy?.context ?? .home(brewID: nil)
        }
        let price = price_amount.flatMap { amount in
            price_currency.map { CupPrice(amount: amount, currency: $0) }
        }
        return Tasting(
            id: id,
            date: tasted_at,
            context: context,
            cardID: card_id,
            coffee: coffee,
            method: method.flatMap(BrewMethod.init(rawValue:)),
            brewer: brewer.flatMap(BrewerType.init(rawValue:)),
            isBatch: is_batch,
            methodNote: method_note,
            price: price,
            photos: photos,
            rating: rating,
            taste: taste,
            flavors: flavors,
            acidity: legacy?.acidity ?? 0,
            bitterness: legacy?.bitterness ?? 0,
            body: legacy?.body ?? 0,
            note: note,
            createdAt: created_at,
            updatedAt: updated_at,
            deletedAt: deleted_at
        )
    }
}

extension TastingRow {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        user_id = try c.decode(UUID.self, forKey: .user_id)
        card_id = try c.decodeIfPresent(UUID.self, forKey: .card_id)
        tasted_at = try c.decode(Date.self, forKey: .tasted_at)
        coffee = try c.decodeIfPresent(TastedCoffee.self, forKey: .coffee) ?? TastedCoffee()
        place = try? c.decodeIfPresent(Place.self, forKey: .place)
        place_ref = try c.decodeIfPresent(String.self, forKey: .place_ref)
        place_map_id = try c.decodeIfPresent(String.self, forKey: .place_map_id)
        method = try c.decodeIfPresent(String.self, forKey: .method)
        brewer = try c.decodeIfPresent(String.self, forKey: .brewer)
        is_batch = try c.decodeIfPresent(Bool.self, forKey: .is_batch) ?? false
        method_note = try c.decodeIfPresent(String.self, forKey: .method_note)
        price_amount = try c.decodeIfPresent(Decimal.self, forKey: .price_amount)
        price_currency = try c.decodeIfPresent(String.self, forKey: .price_currency)?
            .trimmingCharacters(in: .whitespaces)
        rating = try c.decodeIfPresent(Int.self, forKey: .rating)
        taste = try c.decodeIfPresent(TasteProfile.self, forKey: .taste) ?? TasteProfile()
        flavors = try c.decodeIfPresent([FlavorTag].self, forKey: .flavors) ?? []
        legacy = try? c.decodeIfPresent(Legacy.self, forKey: .legacy)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        photos = try c.decodeIfPresent([String].self, forKey: .photos) ?? []
        created_at = try c.decodeIfPresent(Date.self, forKey: .created_at) ?? tasted_at
        updated_at = try c.decodeIfPresent(Date.self, forKey: .updated_at) ?? created_at
        deleted_at = try c.decodeIfPresent(Date.self, forKey: .deleted_at)
    }
}
