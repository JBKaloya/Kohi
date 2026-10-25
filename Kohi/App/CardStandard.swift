import Foundation

/// One version for everything that changes the picture of a Kohi card. Raising any part
/// changes every tile token, and the archive is drawn again once.
nonisolated enum CardStandard {
    static let version = 3

    /// Parts that change the image. Part of every tile token.
    static let signature = [
        version,
        KohiCardContent.designVersion,
        CardArt.version,
        InkStamp.pipelineVersion,
        MarkShape.version,
        OriginStickerImage.catalogueVersion,
    ].map(String.init).joined(separator: ".")

    /// Written once the whole archive is at the standard.
    static let defaultsKey = "display.standard"
    static let signatureKey = "display.standardSignature"
    /// Written once the default face moved to Kohi cards.
    static let lookMigrationKey = "display.standardLook"

    static func isCurrent(_ defaults: UserDefaults) -> Bool {
        defaults.integer(forKey: defaultsKey) >= version
            && defaults.string(forKey: signatureKey) == signature
    }

    static func markCurrent(_ defaults: UserDefaults) {
        defaults.set(version, forKey: defaultsKey)
        defaults.set(signature, forKey: signatureKey)
    }

    /// The new card is the default face, once. Choices made per coffee stay: they were explicit.
    @MainActor
    static func migrateLook(_ defaults: UserDefaults) {
        guard defaults.integer(forKey: lookMigrationKey) < version else { return }
        defaults.set(CardLook.kohi.rawValue, forKey: CardLookStore.globalKey)
        defaults.set(version, forKey: lookMigrationKey)
    }
}

/// Measures again and redraws every tile at the standard, one card at a time, in the
/// background. A card is done when its stamp file is current and its tile for the current
/// token exists, so an interrupted pass picks up where it stopped.
@MainActor
final class CardRegeneration {
    static let shared = CardRegeneration()

    private(set) var running = false
    private var task: Task<Void, Never>?

    /// `visible` first, then the rest newest first.
    static func order(_ cards: [CoffeeCard], visible: Int = 12) -> [CoffeeCard] {
        let head = Array(cards.prefix(visible))
        let tail = cards.dropFirst(visible).sorted { $0.createdAt > $1.createdAt }
        return head + tail
    }

    static func isDone(_ card: CoffeeCard, composer: CardComposer = .shared) -> Bool {
        if ImageStore.shared.exists(card.id, kind: .flat) {
            guard let file = CardFiles.loadStampFile(card.id),
                  file.pipelineVersion == InkStamp.pipelineVersion,
                  file.scanRevision == CardFiles.scanRevision(card.id)
            else { return false }
        }
        return CardFiles.hasKohi(id: card.id, token: composer.token(for: card))
    }

    func startIfNeeded(
        cards: [CoffeeCard],
        library: StampLibrary,
        defaults: UserDefaults = .standard,
        composer: CardComposer = .shared
    ) {
        guard !running, !CardStandard.isCurrent(defaults) else { return }
        running = true
        let work = Self.order(cards)
        task = Task(priority: .utility) {
            await self.run(work, library: library, defaults: defaults, composer: composer)
            self.running = false
        }
    }

    /// The pass itself. Returns how many cards it touched.
    @discardableResult
    func run(
        _ cards: [CoffeeCard],
        library: StampLibrary,
        defaults: UserDefaults = .standard,
        composer: CardComposer = .shared,
        limit: Int? = nil
    ) async -> Int {
        var touched = 0
        for card in cards {
            if Task.isCancelled { return touched }
            if let limit, touched >= limit { return touched }
            if Self.isDone(card, composer: composer) { continue }
            await InkStampPipeline.backfill(cardID: card.id, library: library, roasterName: card.roaster)
            _ = await composer.tile(for: card)
            touched += 1
        }
        if cards.allSatisfy({ Self.isDone($0, composer: composer) }) {
            CardStandard.markCurrent(defaults)
        }
        return touched
    }

    func cancel() {
        task?.cancel()
        task = nil
        running = false
    }
}
