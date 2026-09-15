import Foundation
import Observation

/// Local switches for lot 2 surfaces. They hide UI; they never fork the
/// model or the migration — two write paths would be two truths.
///
/// On by default, except `flavorOrigin`: the origin classes on the wheel
/// are still to verify. First launch seeds that one off; the rest stay on.
@Observable
@MainActor
final class LotFlags {
    enum Feature: String, CaseIterable, Identifiable, Sendable {
        case taste7
        case flavorWheel
        case brewCompare
        case cardProfile
        case flavorOrigin

        var id: String { rawValue }

        var label: String {
            switch self {
            case .taste7: "Seven-axis taste"
            case .flavorWheel: "Flavor wheel"
            case .brewCompare: "Brew compare"
            case .cardProfile: "Card profile"
            case .flavorOrigin: "Aroma origin in diagnosis"
            }
        }

        /// What is lost when it is off — shown next to the switch.
        var fallback: String {
            switch self {
            case .taste7: "Taste stays folded away."
            case .flavorWheel: "Flavours stay as free text."
            case .brewCompare: "Compare with… is hidden."
            case .cardProfile: "The profile section is hidden."
            case .flavorOrigin: "Diagnosis ignores origin classes until they are verified."
            }
        }

        /// Off until the wheel's origin classes have been checked.
        var defaultsOnInDebug: Bool {
            self != .flavorOrigin
        }
    }

    private let defaults: UserDefaults
    private var disabled: Set<Feature>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.disabledKey) ?? []
        var set = Set(stored.compactMap(Feature.init(rawValue:)))
        // First launch: seed the release-off / origin-off defaults once.
        if defaults.object(forKey: Self.seededKey) == nil {
            if !Feature.flavorOrigin.defaultsOnInDebug {
                set.insert(.flavorOrigin)
            }
            defaults.set(true, forKey: Self.seededKey)
            defaults.set(set.map(\.rawValue), forKey: Self.disabledKey)
        }
        disabled = set
    }

    func isOn(_ feature: Feature) -> Bool {
        if let override = environmentOverride(feature) { return override }
        return !disabled.contains(feature)
    }

    func setOn(_ feature: Feature, _ on: Bool) {
        if on {
            disabled.remove(feature)
        } else {
            disabled.insert(feature)
        }
        defaults.set(disabled.map(\.rawValue), forKey: Self.disabledKey)
    }

    /// KOHI_TASTE7=0 / KOHI_TASTE7=1, matching DebugHooks.
    private func environmentOverride(_ feature: Feature) -> Bool? {
        let key = "KOHI_" + feature.rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1_$2", options: .regularExpression)
            .uppercased()
        guard let raw = ProcessInfo.processInfo.environment[key] else { return nil }
        return raw != "0"
    }

    private static let disabledKey = "lot2.disabled"
    private static let seededKey = "lot2.seeded"
}
