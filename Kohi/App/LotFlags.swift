import Foundation
import Observation

/// Local switches for lot 2 surfaces. They hide UI; they never fork the
/// model or the migration — two write paths would be two truths.
///
/// On by default, except `flavorOrigin` (origin classes still to verify) and
/// `keepVoiceNote` (audio is deleted after transcription). First launch seeds
/// those off; the rest stay on.
@Observable
@MainActor
final class LotFlags {
    enum Feature: String, CaseIterable, Identifiable, Sendable {
        case brewCompare
        case cardProfile
        case flavorOrigin
        case keepVoiceNote

        var id: String { rawValue }

        var label: String {
            switch self {
            case .brewCompare: "Brew compare"
            case .cardProfile: "Card profile"
            case .flavorOrigin: "Aroma origin in diagnosis"
            case .keepVoiceNote: Copy.keepVoiceNotes
            }
        }

        /// What is lost when it is off — shown next to the switch.
        var fallback: String {
            switch self {
            case .brewCompare: "Compare with… is hidden."
            case .cardProfile: "The profile section is hidden."
            case .flavorOrigin: "Diagnosis ignores origin classes until they are verified."
            case .keepVoiceNote: "A brew note is transcribed then deleted."
            }
        }

        /// Off until the wheel's origin classes have been checked. Voice-note
        /// audio is deleted after transcription unless this is turned on.
        var defaultsOnInDebug: Bool {
            switch self {
            case .flavorOrigin, .keepVoiceNote: false
            default: true
            }
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
        // Existing installs already have `seededKey`. A feature that defaults
        // off has to be inserted once, or `isOn` would read it as on.
        if defaults.object(forKey: Self.voiceNoteSeededKey) == nil {
            set.insert(.keepVoiceNote)
            defaults.set(true, forKey: Self.voiceNoteSeededKey)
            defaults.set(set.map(\.rawValue), forKey: Self.disabledKey)
        }
        // Older builds seeded taste7 / flavorWheel (and sometimes compare /
        // profile) off. Taste and the wheel are no longer optional; this
        // one-shot also restores compare and profile.
        if defaults.object(forKey: Self.surfacesResetKey) == nil {
            let stored = defaults.stringArray(forKey: Self.disabledKey) ?? []
            let purged = stored.filter {
                !["taste7", "flavorWheel", "brewCompare", "cardProfile"].contains($0)
            }
            defaults.set(purged, forKey: Self.disabledKey)
            defaults.set(true, forKey: Self.surfacesResetKey)
            set = Set(purged.compactMap(Feature.init(rawValue:)))
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
    private static let voiceNoteSeededKey = "lot2.keepVoiceNote.seeded"
    private static let surfacesResetKey = "lot2.surfaces.reset"
}
