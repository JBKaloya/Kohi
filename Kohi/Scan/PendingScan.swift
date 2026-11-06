import Foundation

/// A scan that has been filed and read, and not yet named.
///
/// The local OCR pass happens here, before any sheet, so a coffee the archive
/// already has can be recognised without opening the edit form. Barcodes, the
/// label link and the vision fallback still run later, from these lines.
struct PendingScan: Identifiable, Sendable {
    let scan: ScanResult
    let card: CoffeeCard
    let lines: [TextExtractor.Line]
    let parsed: ParsedFields

    var id: UUID { card.id }
}

/// A café card scanned after *A cup at…*. It becomes a tasting, never a card.
struct CupScan: Identifiable {
    let id = UUID()
    let place: PlaceSuggestion
    let scan: ScanResult
}

/// A pending scan that looks like a card already on the shelf.
struct DuplicateOffer: Identifiable {
    let pending: PendingScan
    let match: CardMatch.Hit

    var id: UUID { pending.card.id }
}
