import Foundation

/// A card read again with all its sides. The first scan sees one photo; a
/// heading on the back, a value the front prints blurred, or a layout the
/// device read wrong ("175C" as the process) only come right when the vision
/// model sees the card and its pages together.
///
/// Nothing is written on its own: each field the pages read differently
/// becomes a proposal the person takes or leaves.
nonisolated enum PageReread {
    struct Proposal: Identifiable, Equatable, Sendable {
        /// The `FieldValues` key: "process", "notes"…
        let key: String
        /// What the card holds now, nil when the field is empty.
        let current: String?
        /// What the pages say.
        let proposed: String
        var id: String { key }
    }

    /// The fields a person reads on the card, in the order the card shows
    /// them. Bag facts (price, weight, dates) stay with the scan.
    static let keys = ["name", "roaster", "country", "region", "producer", "altitude", "variety", "process", "notes", "harvest", "lot"]

    /// The photos read with the card: its pages and bag sides, oldest first,
    /// as many as fit beside the card in one call.
    static func pages(of card: CoffeeCard) -> [UUID] {
        Array(card.attachments.reversed()
            .filter { $0.role == .page || $0.role == .bag }
            .map(\.id)
            .prefix(CardVision.mostPhotos - 1))
    }

    /// Each field the reading fills differently from the card. An empty
    /// reading never proposes to clear a field, and the same value written
    /// another way ("WASHED", "Washed") is not a difference.
    static func proposals(card: CoffeeCard, reading: ParsedFields) -> [Proposal] {
        let now = FieldValues.of(card)
        let read = FieldValues.of(reading)
        return keys.compactMap { key in
            guard let proposed = read[key] else { return nil }
            let current = now[key]
            if let current, same(current, proposed, notes: key == "notes") { return nil }
            return Proposal(
                key: key,
                current: current.map { shown($0, key: key) },
                proposed: shown(proposed, key: key)
            )
        }
    }

    /// The card with the proposals taken.
    static func apply(_ proposals: [Proposal], from reading: ParsedFields, to card: CoffeeCard) -> CoffeeCard {
        var card = card
        for proposal in proposals {
            switch proposal.key {
            case "name": card.name = reading.name ?? card.name
            case "roaster": card.roaster = reading.roaster ?? card.roaster
            case "country": card.country = reading.country ?? card.country
            case "region": card.region = reading.region ?? card.region
            case "producer": card.producer = reading.producer ?? card.producer
            case "altitude": card.altitude = reading.altitude ?? card.altitude
            case "variety": card.variety = reading.variety ?? card.variety
            case "process": card.process = reading.process ?? card.process
            case "notes": if !reading.tastingNotes.isEmpty { card.tastingNotes = reading.tastingNotes }
            case "harvest": card.harvest = reading.harvest ?? card.harvest
            case "lot": card.lot = reading.lot ?? card.lot
            default: break
            }
        }
        return card
    }

    /// Case, accents and spacing aside; notes as a set, in any order.
    static func same(_ a: String, _ b: String, notes: Bool = false) -> Bool {
        if notes {
            return Set(a.split(separator: "|").map { folded(String($0)) })
                == Set(b.split(separator: "|").map { folded(String($0)) })
        }
        return folded(a) == folded(b)
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func shown(_ value: String, key: String) -> String {
        key == "notes" ? value.replacingOccurrences(of: "|", with: ", ") : value
    }
}
