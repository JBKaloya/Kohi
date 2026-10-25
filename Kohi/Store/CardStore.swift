import Foundation
import Observation
import os

/// The single source of truth for the archive. Views read `cards`; the scan flow
/// and the edit sheet write through the mutating methods.
@Observable
final class CardStore {
    private(set) var cards: [CoffeeCard] = []

    /// Set while a freshly scanned card is flying into the grid so the tile can
    /// hold its landing animation until the transition is over.
    var landingCardID: UUID?

    @ObservationIgnored weak var sink: (any ArchiveChangeSink)?
    /// Unlinked, never deleted, when a card goes.
    @ObservationIgnored weak var tastings: TastingStore?
    @ObservationIgnored private let files: CardFileStore
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Card id → wheel ids declared on the bag plus tasted on brews.
    /// Invalidated on write so search never runs `FlavorMatcher` per keystroke.
    @ObservationIgnored private var flavorIndex: [UUID: Set<String>] = [:]
    /// Card id → shelf title. Depends on neighbours, so the whole index is
    /// rebuilt rather than patched one key at a time.
    @ObservationIgnored private var titleIndex: [UUID: String] = [:]
    @ObservationIgnored private var titlesAreValid = false

    init(files: CardFileStore = CardFileStore()) {
        self.files = files
        let loaded = files.load()
        let relinked = loaded.map { card -> CoffeeCard in
            var card = card
            for index in card.brews.indices {
                card.brews[index].dropOrphanRecipeLink()
            }
            return card
        }
        cards = Self.sorted(relinked)
        if relinked != loaded {
            try? files.save(relinked)
        }
    }

    func card(id: UUID) -> CoffeeCard? {
        cards.first { $0.id == id }
    }

    func add(_ card: CoffeeCard) {
        cards = Self.sorted(cards + [card])
        flavorIndex.removeValue(forKey: card.id)
        invalidateTitles()
        ThumbnailCache.shared.warm(card)
        sink?.cardChanged(card.id)
        scheduleSave()
    }

    /// Adds many cards at once without warming every thumbnail up front, which
    /// is what the grid is for.
    func insert(_ newCards: [CoffeeCard]) {
        cards = Self.sorted(cards + newCards)
        invalidateTitles()
        for card in newCards {
            flavorIndex.removeValue(forKey: card.id)
            sink?.cardChanged(card.id)
        }
        scheduleSave()
    }

    /// Marks a card as just-arrived so its tile plays the landing animation, then
    /// clears the flag once the animation has had time to run.
    func markLanding(_ card: CoffeeCard) {
        landingCardID = card.id
        Task {
            try? await Task.sleep(for: Motion.Tile.landingWindow)
            if landingCardID == card.id { landingCardID = nil }
        }
    }

    func update(_ card: CoffeeCard) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        var updated = card
        updated.updatedAt = .now
        cards[index] = updated
        flavorIndex.removeValue(forKey: card.id)
        invalidateTitles()
        CardFiles.invalidateKohi(id: card.id)
        sink?.cardChanged(card.id)
        scheduleSave()
    }

    /// Moves every card linked to one roaster id onto another.
    func relinkRoaster(from old: UUID, to new: UUID) {
        for card in cards where card.roasterId == old {
            var moved = card
            moved.roasterId = new
            update(moved)
        }
    }

    func delete(_ card: CoffeeCard) {
        cards.removeAll { $0.id == card.id }
        flavorIndex.removeValue(forKey: card.id)
        invalidateTitles()
        ThumbnailCache.shared.invalidate(card.id)
        tastings?.unlinkCard(card.id)
        sink?.cardDeleted(card.id)
        let id = card.id
        Task.detached(priority: .utility) { ImageStore.shared.removeAll(for: id) }
        scheduleSave()
    }

    /// Newest scan first. The editable `date` field is for the cup, not the shelf
    /// order, so the grid stays in the order cards were collected.
    private static func sorted(_ cards: [CoffeeCard]) -> [CoffeeCard] {
        cards.sorted { $0.createdAt > $1.createdAt }
    }

    /// Coalesces a burst of edits into one write.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = cards
        let files = files
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                do { try files.save(snapshot) } catch { Log.app.error("save failed: \(error)") }
            }.value
            _ = self
        }
    }

    /// Declared tasting notes plus flavours logged on brews, as wheel ids.
    func flavorIDs(for card: CoffeeCard) -> Set<String> {
        if let cached = flavorIndex[card.id] { return cached }
        var ids = Set(card.declaredFlavors.map(\.id))
        for brew in card.brews {
            ids.formUnion(brew.flavors.map(\.id))
        }
        flavorIndex[card.id] = ids
        return ids
    }

    /// The name on the shelf, with a suffix only when two cards would otherwise
    /// read the same. Unique titles stay bare.
    func title(for card: CoffeeCard) -> String {
        if !titlesAreValid { rebuildTitles() }
        return titleIndex[card.id] ?? card.displayName
    }

    private func invalidateTitles() {
        titlesAreValid = false
        titleIndex.removeAll()
    }

    private func rebuildTitles() {
        titleIndex = CardTitles.index(for: cards)
        titlesAreValid = true
    }

    /// Writes immediately, for backgrounding.
    func flush() {
        saveTask?.cancel()
        let snapshot = cards
        try? files.save(snapshot)
    }
}

extension CardStore: SyncableStore {
    var syncKinds: [EntityKind] { [.card] }

    func syncableIDs(_ kind: EntityKind) -> [UUID] {
        kind == .card ? cards.map(\.id) : []
    }
}

/// Shelf titles that stay unique without inventing names.
///
/// `displayName` is pure and does not know its neighbours. This looks across
/// the archive and only adds a suffix when two cards would otherwise read the
/// same, using the first field that actually differs: roaster, roast date,
/// lot, then the scan date.
nonisolated enum CardTitles {
    static func index(for cards: [CoffeeCard]) -> [UUID: String] {
        var groups: [String: [CoffeeCard]] = [:]
        for card in cards {
            groups[card.displayName, default: []].append(card)
        }
        var titles: [UUID: String] = [:]
        for (base, group) in groups {
            if group.count == 1 {
                titles[group[0].id] = base
                continue
            }
            for card in group {
                titles[card.id] = disambiguated(card, among: group, base: base)
            }
        }
        return titles
    }

    static func title(for card: CoffeeCard, among cards: [CoffeeCard]) -> String {
        index(for: cards)[card.id] ?? card.displayName
    }

    private static func disambiguated(
        _ card: CoffeeCard,
        among group: [CoffeeCard],
        base: String
    ) -> String {
        let keys: [(CoffeeCard) -> String] = [
            { $0.roaster.trimmingCharacters(in: .whitespaces) },
            { $0.roastedOn.map(dateLabel) ?? "" },
            { ($0.lot ?? "").trimmingCharacters(in: .whitespaces) },
            { dateLabel($0.createdAt) },
        ]
        for key in keys {
            let values = group.map(key)
            let distinct = Set(values)
            guard distinct.count > 1 else { continue }
            let value = key(card)
            if !value.isEmpty { return "\(base) · \(value)" }
        }
        return base
    }

    private static func dateLabel(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
