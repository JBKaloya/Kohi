import CryptoKit
import Foundation

/// What a Kohi card is allowed to show. Built only from stored fields.
/// Empty strings are absent lines. Nothing here is written back to the card.
nonisolated struct KohiCardContent: Equatable, Sendable {
    /// Bump when the gabarit changes so cached tiles are redrawn.
    static let designVersion = 3

    var roaster: String
    /// `displayName`: a card without a name still has a title.
    var title: String
    /// Detail titles longer than 22 characters drop a size.
    var titleUsesSmallSize: Bool
    /// "Nyeri, Kenya". Ink.
    var place: String
    /// Altitude, already display-formatted. Muted.
    var altitude: String
    var process: String
    var variety: String
    /// At most three. Pack notes first, then flavours from tastings and brews.
    var notes: [String]
    /// Title ink: the first note brought to L 0.36, so it reads on the label and rhymes with the ground.
    var titleRed: Double?
    var titleGreen: Double?
    var titleBlue: Double?
    /// `Stickers/origin-<iso>`, `Stickers/seal-<process>`, or nil.
    var sticker: String?
    var stickerOnRight: Bool
    /// Degrees.
    var stickerRotation: Double
    /// Detail footer, already uppercase. "ROASTED 25 SEP 2026 · FROM THE PACK".
    var footer: String

    var hasPlaceLine: Bool { !place.isEmpty || !altitude.isEmpty }
    var hasProcessLine: Bool { !process.isEmpty || !variety.isEmpty }

    static func make(_ card: CoffeeCard, ink: StampFile? = nil) -> KohiCardContent {
        make(card, art: CardArt.make(card, ink: ink))
    }

    static func make(_ card: CoffeeCard, art: CardArt) -> KohiCardContent {
        let roaster = card.roaster.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = card.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = [card.region, card.country]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let altitude = altitudeText(card.altitude)
        let process = card.process.trimmingCharacters(in: .whitespacesAndNewlines)
        let variety = card.variety.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = faceNotes(card)
        let footer = footer(roastedOn: card.roastedOn, createdAt: card.createdAt)
        let color = art.titleRGB

        return KohiCardContent(
            roaster: roaster,
            title: title,
            titleUsesSmallSize: title.count > 22,
            place: place,
            altitude: altitude,
            process: process,
            variety: variety,
            notes: notes,
            titleRed: color.0,
            titleGreen: color.1,
            titleBlue: color.2,
            sticker: OriginStickerImage.assetName(for: card),
            stickerOnRight: art.stickerOnRight,
            stickerRotation: art.stickerRotation,
            footer: footer
        )
    }

    /// Pack notes fill the face first. Flavours logged at home — a brew or a
    /// card-era home note — take the remaining slots, still capped at three.
    /// Coffee-shop tastings live in their own store and stay off the face.
    static func faceNotes(_ card: CoffeeCard) -> [String] {
        var notes: [String] = []
        var seen: Set<String> = []
        func append(_ raw: String) {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, notes.count < 3 else { return }
            let key = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            guard seen.insert(key).inserted else { return }
            notes.append(text)
        }
        for note in card.tastingNotes { append(note) }
        let home = card.tastings.filter { if case .home = $0.context { true } else { false } }
        let tags = home.flatMap(\.flavors) + card.brews.flatMap(\.flavors)
        for tag in tags { append(tag.displayName) }
        return notes
    }

    /// Stable id for the tile cache. `symbol` names what the ground shows of the pack
    /// symbol and the measurement it came from; empty when nothing is shown.
    func cacheToken(symbol: String, layout: CardLayout, density: CardDensity) -> String {
        let payload = [
            roaster, title, place, altitude, process, variety,
            notes.joined(separator: "\u{1f}"),
            String(format: "%.3f", titleRed ?? -1),
            String(format: "%.3f", titleGreen ?? -1),
            String(format: "%.3f", titleBlue ?? -1),
            sticker ?? "",
            stickerOnRight ? "r" : "l",
            String(format: "%.2f", stickerRotation),
            footer,
            symbol,
            layout.rawValue,
            density.rawValue,
            String(CardStandard.version),
        ].joined(separator: "\u{1e}")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// A bare number becomes "1 800 m". Anything else is the roaster's words.
    static func altitudeText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let compact = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
        guard compact.allSatisfy(\.isNumber), let value = Int(compact), value > 0 else {
            return trimmed
        }
        return grouped(value) + " m"
    }

    static func packDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date).uppercased()
    }

    private static func footer(roastedOn: Date?, createdAt: Date) -> String {
        if let roastedOn {
            return "\(Copy.roasted) \(packDay(roastedOn)) · \(Copy.fromThePack)"
        }
        return "\(Copy.added) \(packDay(createdAt)) · \(Copy.fromThePack)"
    }

    private static func grouped(_ value: Int) -> String {
        let digits = String(value)
        var parts: [String] = []
        var rest = digits[...]
        while rest.count > 3 {
            let split = rest.index(rest.endIndex, offsetBy: -3)
            parts.insert(String(rest[split...]), at: 0)
            rest = rest[..<split]
        }
        parts.insert(String(rest), at: 0)
        return parts.joined(separator: "\u{202F}")
    }
}

enum CardDensity: String, Codable, Sendable {
    case tile
    case detail
}

/// Label: a paper label on the ground. Full bleed: the text sits on the ground.
enum CardLayout: String, Codable, CaseIterable, Sendable {
    case label
    case fullBleed

    nonisolated static let defaultsKey = "display.cardLayout"

    nonisolated static let overridesKey = "display.cardLayouts"

    nonisolated static func stored(_ defaults: UserDefaults = .standard) -> CardLayout {
        CardLayout(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .label
    }

    /// The coffee's own layout when it has one, else the global one.
    nonisolated static func stored(for id: UUID, _ defaults: UserDefaults = .standard) -> CardLayout {
        if let raw = storedOverrides(defaults)[id.uuidString], let layout = CardLayout(rawValue: raw) {
            return layout
        }
        return stored(defaults)
    }

    nonisolated static func storedOverrides(_ defaults: UserDefaults) -> [String: String] {
        guard let data = defaults.data(forKey: overridesKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }
}
