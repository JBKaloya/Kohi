import Foundation

/// One coffee drunk in a coffee shop. A record of its own, synced on its own.
///
/// The coffee is a snapshot (`coffee`), the card is only a link (`cardID`).
/// What the cup was like — the score, the seven axes, the flavours — is scored
/// with the same vocabulary a brew uses.
///
/// `.home` and the three correction axes come from the time tastings lived on
/// the card. They still decode, so nothing written by an older build is lost,
/// but nothing new writes them.
nonisolated struct Tasting: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var date: Date
    var context: Context
    /// The card this coffee is on, when it is. Navigational only.
    var cardID: UUID?
    var coffee: TastedCoffee
    var method: BrewMethod?
    var brewer: BrewerType?
    var isBatch: Bool
    /// Free text for a method outside the list.
    var methodNote: String?
    var price: CupPrice?
    /// File names under `tastings/<id>/`.
    var photos: [String]
    /// Half points, 1...10, same scale as `Brew.ratingHalves`. Nil when the
    /// cup was not scored. The one to read and write.
    var ratingHalves: Int? {
        didSet { rating = HalfRating.whole(ratingHalves) }
    }
    /// Whole dots for builds before half points. Follows `ratingHalves`.
    private(set) var rating: Int?
    /// Seven axes, 0 to 10, the same profile a brew carries.
    var taste: TasteProfile
    var flavors: [FlavorTag]
    /// Legacy. Each axis is −1 (under), 0 (balanced), or +1 (over).
    var acidity: Int
    var bitterness: Int
    var body: Int
    var note: String?
    var createdAt: Date
    var updatedAt: Date
    /// Soft delete. A deleted tasting stays in the store so the legacy copy on
    /// its card is never imported again.
    var deletedAt: Date?

    enum Context: Codable, Hashable, Sendable {
        /// Legacy. Nil when the coffee was drunk at home without a logged brew.
        case home(brewID: UUID?)
        /// `placeID` is the seed slug. Nil for a Maps pin or a name typed by hand.
        case out(place: Place, placeID: String?)
    }

    init(
        id: UUID = UUID(),
        date: Date = .now,
        context: Context,
        cardID: UUID? = nil,
        coffee: TastedCoffee = TastedCoffee(),
        method: BrewMethod? = nil,
        brewer: BrewerType? = nil,
        isBatch: Bool = false,
        methodNote: String? = nil,
        price: CupPrice? = nil,
        photos: [String] = [],
        rating: Int? = nil,
        ratingHalves: Int? = nil,
        taste: TasteProfile = TasteProfile(),
        flavors: [FlavorTag] = [],
        acidity: Int = 0,
        bitterness: Int = 0,
        body: Int = 0,
        note: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.date = date
        self.context = context
        self.cardID = cardID
        self.coffee = coffee
        self.method = method
        self.brewer = brewer
        self.isBatch = isBatch
        self.methodNote = methodNote
        self.price = price
        self.photos = photos
        let halves = ratingHalves.flatMap { HalfRating.range.contains($0) ? $0 : nil }
            ?? HalfRating.resolve(halves: nil, whole: rating)
        self.ratingHalves = halves
        self.rating = HalfRating.whole(halves)
        self.taste = taste
        self.flavors = flavors
        self.acidity = acidity
        self.bitterness = bitterness
        self.body = body
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var place: Place? {
        if case .out(let place, _) = context { return place }
        return nil
    }

    var placeID: String? {
        if case .out(_, let placeID) = context { return placeID }
        return nil
    }

    var isDeleted: Bool { deletedAt != nil }

    /// Nothing worth showing beyond the date and the place.
    var isBlank: Bool {
        ratingHalves == nil && taste.isEmpty && flavors.isEmpty
            && acidity == 0 && bitterness == 0 && body == 0
            && (note ?? "").isEmpty
    }

    /// The coffee's name, or the card's when an old tasting carried none.
    func coffeeName(fallback: String = "A coffee") -> String {
        let name = coffee.trimmedName
        return name.isEmpty ? fallback : name
    }

    /// "Hand brew · V60", "Batch brew", "Espresso · Moka", or the free text.
    var methodLine: String? {
        if isBatch { return BrewerFamily.batch.label }
        if let brewer { return brewer.methodLine }
        if let method {
            return method == .filter ? method.family.label : DefaultSequence.type(for: method).methodLine
        }
        let note = methodNote?.trimmingCharacters(in: .whitespaces) ?? ""
        return note.isEmpty ? nil : note
    }
}

// A tasting filed before the taste blocks existed carries only a score and a
// note; one filed on a card carries no coffee. Decoding tolerates both.
nonisolated extension Tasting {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .now
        context = try c.decode(Context.self, forKey: .context)
        cardID = try c.decodeIfPresent(UUID.self, forKey: .cardID)
        coffee = try c.decodeIfPresent(TastedCoffee.self, forKey: .coffee) ?? TastedCoffee()
        method = try? c.decodeIfPresent(BrewMethod.self, forKey: .method)
        brewer = try? c.decodeIfPresent(BrewerType.self, forKey: .brewer)
        isBatch = try c.decodeIfPresent(Bool.self, forKey: .isBatch) ?? false
        methodNote = try c.decodeIfPresent(String.self, forKey: .methodNote)
        price = try c.decodeIfPresent(CupPrice.self, forKey: .price)
        photos = try c.decodeIfPresent([String].self, forKey: .photos) ?? []
        let halves = HalfRating.resolve(
            halves: try? c.decodeIfPresent(Int.self, forKey: .ratingHalves),
            whole: try c.decodeIfPresent(Int.self, forKey: .rating)
        )
        ratingHalves = halves
        rating = HalfRating.whole(halves)
        taste = try c.decodeIfPresent(TasteProfile.self, forKey: .taste) ?? TasteProfile()
        flavors = try c.decodeIfPresent([FlavorTag].self, forKey: .flavors) ?? []
        acidity = try c.decodeIfPresent(Int.self, forKey: .acidity) ?? 0
        bitterness = try c.decodeIfPresent(Int.self, forKey: .bitterness) ?? 0
        body = try c.decodeIfPresent(Int.self, forKey: .body) ?? 0
        note = try c.decodeIfPresent(String.self, forKey: .note)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? date
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}
