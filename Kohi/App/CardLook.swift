import Foundation
import Observation

/// Global mosaic face, plus a per-coffee choice that wins, plus the card layout.
/// Stored in UserDefaults. It is not a field of the coffee.
@MainActor
@Observable
final class CardLookStore {
    static let globalKey = "display.cards"
    static let overridesKey = "display.cardLooks"

    private let defaults: UserDefaults
    var global: CardLook {
        didSet { defaults.set(global.rawValue, forKey: Self.globalKey) }
    }

    var layout: CardLayout {
        didSet { defaults.set(layout.rawValue, forKey: CardLayout.defaultsKey) }
    }

    private(set) var overrides: [UUID: CardLook]
    private(set) var layoutOverrides: [UUID: CardLayout]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        CardStandard.migrateLook(defaults)
        global = CardLook(rawValue: defaults.string(forKey: Self.globalKey) ?? "") ?? .kohi
        layout = CardLayout.stored(defaults)
        overrides = Self.loadOverrides(defaults)
        var layouts: [UUID: CardLayout] = [:]
        for (key, value) in CardLayout.storedOverrides(defaults) {
            guard let id = UUID(uuidString: key), let choice = CardLayout(rawValue: value) else { continue }
            layouts[id] = choice
        }
        layoutOverrides = layouts
    }

    func layout(for cardID: UUID) -> CardLayout {
        layoutOverrides[cardID] ?? layout
    }

    /// The global layout is not written per coffee: a coffee that matches it follows later changes.
    func setLayout(_ choice: CardLayout, for cardID: UUID) {
        var next = layoutOverrides
        next[cardID] = choice == layout ? nil : choice
        layoutOverrides = next
        let raw = Dictionary(uniqueKeysWithValues: next.map { ($0.key.uuidString, $0.value.rawValue) })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: CardLayout.overridesKey)
        }
    }

    /// No flat scan: always the Kohi card, so the mosaic has no hole.
    /// Otherwise the coffee's own choice, then the global setting.
    func resolved(cardID: UUID, hasScan: Bool) -> CardLook {
        if !hasScan { return .kohi }
        if let choice = overrides[cardID] { return choice }
        return global
    }

    func resolved(_ card: CoffeeCard) -> CardLook {
        resolved(cardID: card.id, hasScan: ImageStore.shared.exists(card.id, kind: .flat))
    }

    /// Menu and flip write the same key.
    func setOverride(_ look: CardLook, for cardID: UUID) {
        var next = overrides
        next[cardID] = look
        overrides = next
        saveOverrides()
    }

    private func saveOverrides() {
        let raw = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.uuidString, $0.value.rawValue) })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Self.overridesKey)
        }
    }

    private static func loadOverrides(_ defaults: UserDefaults) -> [UUID: CardLook] {
        guard let data = defaults.data(forKey: Self.overridesKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        var map: [UUID: CardLook] = [:]
        for (key, value) in decoded {
            guard let id = UUID(uuidString: key), let look = CardLook(rawValue: value) else { continue }
            map[id] = look
        }
        return map
    }
}

enum CardLook: String, Codable, Sendable {
    case scan
    case kohi
}
