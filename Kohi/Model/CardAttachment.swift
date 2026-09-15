import Foundation

/// A document linked to a coffee card: another side of the label, a recipe
/// sheet, or any extra reference the user wants to keep with the card.
nonisolated struct CardAttachment: Identifiable, Codable, Hashable, Sendable {
    enum Role: String, Codable, Sendable, CaseIterable {
        /// Another face or page of the same card. OCR is merged into empty fields.
        case page
        /// A brew recipe card.
        case recipe
        /// The bag itself, front or back. Not the archive object — the card
        /// stays that — but it usually carries the roast date and the lot.
        case bag
        /// A till receipt, kept for the price.
        case receipt
        /// Anything else worth keeping alongside the card.
        case document

        var label: String {
            switch self {
            case .page: "Page"
            case .recipe: "Recipe"
            case .bag: "Bag"
            case .receipt: "Receipt"
            case .document: "Document"
            }
        }

        /// One glyph for the corner badge. "T" for the receipt — a ticket —
        /// because "R" is already the recipe's.
        var badge: String {
            switch self {
            case .page: "P"
            case .recipe: "R"
            case .bag: "B"
            case .receipt: "T"
            case .document: "D"
            }
        }

        /// Roles whose text is worth merging into still-empty card fields.
        var feedsFields: Bool {
            switch self {
            case .page, .bag, .receipt: true
            case .recipe, .document: false
            }
        }
    }

    let id: UUID
    var role: Role
    var caption: String
    var aspectRatio: Double
    var createdAt: Date

    init(
        id: UUID = UUID(),
        role: Role = .page,
        caption: String = "",
        aspectRatio: Double = 0.75,
        createdAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.caption = caption
        self.aspectRatio = aspectRatio
        self.createdAt = createdAt
    }
}

nonisolated extension CardAttachment {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try c.decodeIfPresent(Role.self, forKey: .role) ?? .page
        caption = try c.decodeIfPresent(String.self, forKey: .caption) ?? ""
        aspectRatio = try c.decodeIfPresent(Double.self, forKey: .aspectRatio) ?? 0.75
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }
}
