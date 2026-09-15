import Foundation
import Observation
import Supabase
import os

/// Two switches in series, and a feature runs only when both are closed: yours
/// in the account sheet, and the server's in `ai_flags`.
///
/// The server one exists so a feature that starts misbehaving — or costing too
/// much — can be turned off for a build that is already on a phone, without
/// shipping anything. The local one exists so the whole experimental layer can
/// be refused outright.
@Observable
@MainActor
final class AIFlags {
    /// The master switch. On by default when the key has never been set, so
    /// suggested correction and the other experimental features are available
    /// without a hunt through Profile. You can still turn the layer off.
    var isExperimentalEnabled: Bool {
        didSet {
            guard oldValue != isExperimentalEnabled else { return }
            defaults.set(isExperimentalEnabled, forKey: Self.enabledKey)
        }
    }

    /// Per-feature switches, only consulted when the master is on.
    private(set) var disabledByYou: Set<AIFeature> {
        didSet {
            defaults.set(disabledByYou.map(\.rawValue), forKey: Self.disabledKey)
        }
    }

    /// What the server last said. Empty means "no opinion", which reads as
    /// enabled: a flags table that fails to load must not silently kill every
    /// feature.
    private(set) var disabledByServer: Set<AIFeature> = []
    private(set) var refreshedAt: Date?

    private let defaults: UserDefaults
    private static let enabledKey = "ai.experimental.enabled"
    private static let disabledKey = "ai.experimental.disabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.enabledKey) == nil {
            isExperimentalEnabled = true
            defaults.set(true, forKey: Self.enabledKey)
        } else {
            isExperimentalEnabled = defaults.bool(forKey: Self.enabledKey)
        }
        let stored = defaults.stringArray(forKey: Self.disabledKey) ?? []
        disabledByYou = Set(stored.compactMap(AIFeature.init(rawValue:)))
    }

    /// The only question the rest of the app asks.
    func isOn(_ feature: AIFeature) -> Bool {
        if feature.isExperimental, !isExperimentalEnabled { return false }
        return !disabledByYou.contains(feature) && !disabledByServer.contains(feature)
    }

    func setOn(_ feature: AIFeature, _ on: Bool) {
        if on {
            disabledByYou.remove(feature)
        } else {
            disabledByYou.insert(feature)
        }
    }

    /// Why a feature is off, for the row that shows it. Nil when it is on.
    func reason(_ feature: AIFeature) -> String? {
        if feature.isExperimental, !isExperimentalEnabled { return "Experimental AI is off" }
        if disabledByServer.contains(feature) { return "Paused" }
        if disabledByYou.contains(feature) { return "Off" }
        return nil
    }

    // MARK: - Server flags

    struct Row: Decodable, Sendable {
        let feature: String
        let enabled: Bool
    }

    /// Pulled at launch and after a sync. A failure leaves the last known set
    /// in place rather than clearing it — the previous answer is better than
    /// no answer.
    func refresh(client: SupabaseClient?) async {
        guard let client else { return }
        do {
            let rows: [Row] = try await client
                .from("ai_flags")
                .select("feature, enabled")
                .execute()
                .value
            disabledByServer = Set(
                rows.filter { !$0.enabled }.compactMap { AIFeature(rawValue: $0.feature) }
            )
            refreshedAt = .now
        } catch {
            Log.app.notice("ai flags: keeping the previous set (\(error))")
        }
    }
}
