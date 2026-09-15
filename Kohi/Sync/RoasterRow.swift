import Foundation

/// DTO matching the `public.roasters` table schema (snake_case).
struct RoasterRow: Codable, Sendable {
    let id: UUID
    var name: String
    var country: String
    var city: String
    var website: String?
    var instagram: String?
    var created_by: UUID?
    var updated_at: Date
    /// Generated column on the server; sent so the unique index catches a
    /// duplicate the client did not.
    var dedupe_key: String

    init(roaster: Roaster, userID: UUID?) {
        self.id = roaster.id
        self.name = roaster.name
        self.country = roaster.country
        self.city = roaster.city
        self.website = roaster.website
        self.instagram = roaster.instagram
        self.created_by = roaster.createdBy ?? userID
        self.updated_at = roaster.updatedAt
        self.dedupe_key = roaster.dedupeKey
    }

    func toRoaster() -> Roaster {
        Roaster(
            id: id,
            name: name,
            country: country,
            city: city,
            website: website,
            instagram: instagram,
            createdBy: created_by,
            updatedAt: updated_at
        )
    }
}
