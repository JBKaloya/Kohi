import Foundation

/// Every kind of record the archive can push to Supabase.
///
/// The outbox tracks dirty rows and tombstones per kind, so adding an entity is
/// a case here plus a row DTO — not a new sync path.
nonisolated enum EntityKind: String, Codable, CaseIterable, Sendable {
    case card
    case roaster
    case equipment
    case waterProfile
    case recipe
    case grindCalibration
    case filterStock
    case tasting

    /// The Supabase table this kind upserts into.
    var table: String {
        switch self {
        case .card: "coffee_cards"
        case .roaster: "roasters"
        case .equipment: "equipment"
        case .waterProfile: "water_profiles"
        case .recipe: "recipes"
        case .grindCalibration: "grind_calibrations"
        case .filterStock: "filter_stock"
        case .tasting: "tastings"
        }
    }

    /// Shown in the account sheet's pending counter.
    var label: String {
        switch self {
        case .card: "Cards"
        case .roaster: "Roasters"
        case .equipment: "Equipment"
        case .waterProfile: "Water"
        case .recipe: "Recipes"
        case .grindCalibration: "Calibrations"
        case .filterStock: "Filters"
        case .tasting: "Tastings"
        }
    }

    /// Readable by everyone, not scoped to one account. These tables are
    /// filtered by nothing on pull, and rows are never deleted from the client.
    var isShared: Bool {
        switch self {
        case .roaster: true
        case .card, .equipment, .waterProfile, .recipe, .grindCalibration, .filterStock, .tasting: false
        }
    }
}
