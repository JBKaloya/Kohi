import Foundation

/// Whether a scan is a coffee the archive already has.
///
/// Nothing here merges cards. A hit is a question, and the person answers it.
nonisolated enum CardMatch {
    enum Confidence: Sendable {
        case strong
        case probable
    }

    struct Hit: Sendable {
        let card: CoffeeCard
        let confidence: Confidence
    }

    /// The closest card, if the roaster and the name agree. Nil when either
    /// side is blank: an empty name must not match every untitled card.
    static func find(
        roaster: String,
        name: String,
        origin: ParsedFields? = nil,
        in cards: [CoffeeCard]
    ) -> Hit? {
        let roasterKey = Roaster.fold(roaster)
        let nameKey = SeedPlace.fold(name)
        guard !roasterKey.isEmpty, !nameKey.isEmpty else { return nil }

        struct Candidate {
            let card: CoffeeCard
            let confidence: Confidence
            let support: Int
        }

        let candidates: [Candidate] = cards.compactMap { card in
            let cardRoaster = Roaster.fold(card.roaster)
            guard cardRoaster == roasterKey else { return nil }
            let cardName = SeedPlace.fold(card.name)
            guard !cardName.isEmpty else { return nil }

            let confidence: Confidence
            if cardName == nameKey {
                confidence = .strong
            } else if probable(cardName, nameKey) {
                confidence = .probable
            } else {
                return nil
            }
            return Candidate(card: card, confidence: confidence, support: support(origin, card))
        }

        guard let best = candidates.max(by: { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence == .probable
            }
            if lhs.support != rhs.support { return lhs.support < rhs.support }
            return lhs.card.createdAt < rhs.card.createdAt
        }) else { return nil }

        return Hit(card: best.card, confidence: best.confidence)
    }

    /// One folded name contains the other, and the shorter one is long enough
    /// that "AA" does not match every lot from the same roaster.
    private static func probable(_ lhs: String, _ rhs: String) -> Bool {
        let shorter = min(lhs.count, rhs.count)
        guard shorter >= 4 else { return false }
        return lhs.contains(rhs) || rhs.contains(lhs)
    }

    /// Origin, process, producer, lot, harvest. Only counted when both sides
    /// actually say something, and only used to break a tie.
    private static func support(_ parsed: ParsedFields?, _ card: CoffeeCard) -> Int {
        guard let parsed else { return 0 }
        var score = 0
        if agrees(parsed.country, card.country) || agrees(parsed.region, card.region) {
            score += 1
        }
        if agrees(parsed.process, card.process) { score += 1 }
        if agrees(parsed.producer, card.producer) { score += 1 }
        if agrees(parsed.lot, card.lot) { score += 1 }
        if agrees(parsed.harvest, card.harvest) { score += 1 }
        return score
    }

    private static func agrees(_ parsed: String?, _ card: String?) -> Bool {
        guard let parsed, let card else { return false }
        let left = SeedPlace.fold(parsed)
        let right = SeedPlace.fold(card)
        return !left.isEmpty && left == right
    }
}
