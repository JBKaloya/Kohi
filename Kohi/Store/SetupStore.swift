import Foundation
import Observation
import os
import Supabase

/// The cupboard and the tap: equipment, water profiles, and the defaults that
/// let the brew sheet arrive already filled in.
///
/// Kept in its own file rather than in the archive, because it describes the
/// person, not the collection — and because losing a card is a different order
/// of problem from losing a grinder entry.
@Observable
final class SetupStore {
    private(set) var equipment: [Equipment] = []
    private(set) var waterProfiles: [WaterProfile] = []
    private(set) var calibrations: [GrindCalibration] = []

    @ObservationIgnored weak var sink: (any ArchiveChangeSink)?
    @ObservationIgnored private let files: JSONDocumentStore<Snapshot>
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private static let preferredMethodKey = "setup.preferredMethod"

    nonisolated struct Snapshot: Codable, Sendable {
        var equipment: [Equipment] = []
        var waterProfiles: [WaterProfile] = []
        var calibrations: [GrindCalibration] = []
    }

    init(files: JSONDocumentStore<Snapshot> = JSONDocumentStore(filename: "setup.json")) {
        self.files = files
        if let snapshot = files.load() {
            equipment = snapshot.equipment
            waterProfiles = snapshot.waterProfiles
            calibrations = snapshot.calibrations
        }
    }

    var isEmpty: Bool {
        equipment.isEmpty && waterProfiles.isEmpty && calibrations.isEmpty
    }

    var kitIsEmpty: Bool { equipment.isEmpty }

    /// First method marked as a default, which is the order onboarding recorded.
    var preferredRecipeMethod: BrewMethod? {
        if let stored = UserDefaults.standard.string(forKey: Self.preferredMethodKey),
           let method = BrewMethod(rawValue: stored) {
            return method
        }
        return equipment.flatMap(\.isDefaultFor).first
    }

    func setPreferredRecipeMethod(_ method: BrewMethod) {
        UserDefaults.standard.set(method.rawValue, forKey: Self.preferredMethodKey)
    }

    // MARK: - Reading

    func equipment(_ kind: EquipmentKind) -> [Equipment] {
        equipment
            .filter { $0.kind == kind }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    func equipment(id: UUID) -> Equipment? {
        equipment.first { $0.id == id }
    }

    func waterProfile(id: UUID) -> WaterProfile? {
        waterProfiles.first { $0.id == id }
    }

    var grinders: [Equipment] { equipment(.grinder) }

    /// The equipment set as default for a method, one per kind. What the brew
    /// sheet starts from.
    func defaults(for method: BrewMethod) -> [Equipment] {
        var byKind: [EquipmentKind: Equipment] = [:]
        for item in equipment where item.isDefaultFor.contains(method) {
            // First one wins per kind: two defaults for the same kind and
            // method is a state the toggle below prevents.
            if byKind[item.kind] == nil { byKind[item.kind] = item }
        }
        return EquipmentKind.allCases.compactMap { byKind[$0] }
    }

    var defaultWaterProfile: WaterProfile? {
        waterProfiles.first { $0.isDefault } ?? waterProfiles.first
    }

    /// The grinder to read a reference recipe's grind in. The one set as
    /// default for the method, else the only grinder, else nothing.
    func preferredGrinder(for method: BrewMethod?) -> Equipment? {
        if let method,
           let byMethod = grinders.first(where: { $0.isDefaultFor.contains(method) }) {
            return byMethod
        }
        return grinders.count == 1 ? grinders.first : nil
    }

    // MARK: - Writing

    func add(_ item: Equipment) {
        equipment.append(item)
        sink?.changed(.equipment, id: item.id)
        scheduleSave()
    }

    func update(_ item: Equipment) {
        guard let index = equipment.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.updatedAt = .now
        equipment[index] = updated
        sink?.changed(.equipment, id: item.id)
        scheduleSave()
    }

    func delete(_ item: Equipment) {
        equipment.removeAll { $0.id == item.id }
        sink?.deleted(.equipment, id: item.id)
        scheduleSave()
    }

    /// Makes an item the default for a method, clearing whatever else of the
    /// same kind held that role. One grinder per method, or the brew sheet has
    /// nothing to pick from.
    func setDefault(_ item: Equipment, for method: BrewMethod, on: Bool) {
        for index in equipment.indices {
            let candidate = equipment[index]
            if candidate.id == item.id {
                var updated = candidate
                if on {
                    if !updated.isDefaultFor.contains(method) { updated.isDefaultFor.append(method) }
                } else {
                    updated.isDefaultFor.removeAll { $0 == method }
                }
                updated.updatedAt = .now
                equipment[index] = updated
                sink?.changed(.equipment, id: updated.id)
            } else if on, candidate.kind == item.kind,
                      candidate.isDefaultFor.contains(method) {
                var updated = candidate
                updated.isDefaultFor.removeAll { $0 == method }
                updated.updatedAt = .now
                equipment[index] = updated
                sink?.changed(.equipment, id: updated.id)
            }
        }
        scheduleSave()
    }

    func setRange(_ range: GrindRange, on item: Equipment) {
        guard var updated = equipment(id: item.id) else { return }
        updated.ranges.removeAll { $0.method == range.method }
        updated.ranges.append(range)
        updated.ranges.sort { $0.method.rawValue < $1.method.rawValue }
        update(updated)
    }

    func clearRange(_ method: BrewMethod, on item: Equipment) {
        guard var updated = equipment(id: item.id) else { return }
        updated.ranges.removeAll { $0.method == method }
        update(updated)
    }

    func add(_ profile: WaterProfile) {
        var stored = profile
        // The first profile is the default: having water on file but no default
        // would leave the brew sheet with nothing to pre-fill.
        if waterProfiles.isEmpty { stored.isDefault = true }
        waterProfiles.append(stored)
        sink?.changed(.waterProfile, id: stored.id)
        scheduleSave()
    }

    func update(_ profile: WaterProfile) {
        guard let index = waterProfiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = profile
        updated.updatedAt = .now
        waterProfiles[index] = updated
        sink?.changed(.waterProfile, id: profile.id)
        scheduleSave()
    }

    func delete(_ profile: WaterProfile) {
        waterProfiles.removeAll { $0.id == profile.id }
        // Never leave the set without a default.
        if !waterProfiles.contains(where: \.isDefault), var first = waterProfiles.first {
            first.isDefault = true
            waterProfiles[0] = first
            sink?.changed(.waterProfile, id: first.id)
        }
        sink?.deleted(.waterProfile, id: profile.id)
        scheduleSave()
    }

    func makeDefault(_ profile: WaterProfile) {
        for index in waterProfiles.indices {
            let shouldBeDefault = waterProfiles[index].id == profile.id
            guard waterProfiles[index].isDefault != shouldBeDefault else { continue }
            waterProfiles[index].isDefault = shouldBeDefault
            waterProfiles[index].updatedAt = .now
            sink?.changed(.waterProfile, id: waterProfiles[index].id)
        }
        scheduleSave()
    }

    // MARK: - Calibrations

    func calibration(grinderID: UUID, method: BrewMethod) -> GrindCalibration? {
        calibrations.first { $0.grinderID == grinderID && $0.method == method }
    }

    func calibrations(grinderID: UUID) -> [GrindCalibration] {
        calibrations
            .filter { $0.grinderID == grinderID }
            .sorted { $0.method.rawValue < $1.method.rawValue }
    }

    /// One calibration per grinder and method: a second one for the same pair
    /// replaces the first rather than sitting beside it, because the question
    /// it answers has one answer.
    func record(_ calibration: GrindCalibration) {
        if let index = calibrations.firstIndex(where: {
            $0.grinderID == calibration.grinderID && $0.method == calibration.method
        }) {
            let existing = calibrations[index]
            var updated = calibration
            updated.updatedAt = .now
            calibrations[index] = updated
            sink?.changed(.grindCalibration, id: updated.id)
            // The replaced record leaves a tombstone unless it is the same row.
            if existing.id != updated.id {
                sink?.deleted(.grindCalibration, id: existing.id)
            }
        } else {
            calibrations.append(calibration)
            sink?.changed(.grindCalibration, id: calibration.id)
        }
        scheduleSave()
    }

    func delete(_ calibration: GrindCalibration) {
        calibrations.removeAll { $0.id == calibration.id }
        sink?.deleted(.grindCalibration, id: calibration.id)
        scheduleSave()
    }

    func resetKit() {
        let items = equipment
        let waters = waterProfiles
        let cals = calibrations
        for item in items { delete(item) }
        for profile in waters { delete(profile) }
        for calibration in cals { delete(calibration) }
        UserDefaults.standard.removeObject(forKey: Self.preferredMethodKey)
    }

    // MARK: - Merge

    /// Last write wins per record, by `updatedAt`. Setup is single-user data,
    /// so the only real conflict is two devices edited offline.
    func merge(equipment incoming: [Equipment]) {
        guard !incoming.isEmpty else { return }
        var byID = Dictionary(equipment.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in incoming {
            if let local = byID[item.id], local.updatedAt > item.updatedAt { continue }
            byID[item.id] = item
        }
        equipment = Array(byID.values).sorted { $0.createdAt < $1.createdAt }
        scheduleSave()
    }

    func merge(waterProfiles incoming: [WaterProfile]) {
        guard !incoming.isEmpty else { return }
        var byID = Dictionary(
            waterProfiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        for profile in incoming {
            if let local = byID[profile.id], local.updatedAt > profile.updatedAt { continue }
            byID[profile.id] = profile
        }
        waterProfiles = Array(byID.values).sorted { $0.createdAt < $1.createdAt }
        scheduleSave()
    }

    func merge(calibrations incoming: [GrindCalibration]) {
        guard !incoming.isEmpty else { return }
        var byID = Dictionary(
            calibrations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        for calibration in incoming {
            if let local = byID[calibration.id], local.updatedAt > calibration.updatedAt {
                continue
            }
            byID[calibration.id] = calibration
        }
        calibrations = Array(byID.values).sorted { $0.createdAt < $1.createdAt }
        scheduleSave()
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = snapshot()
        let files = files
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                do { try files.save(snapshot) } catch {
                    Log.app.error("setup save failed: \(error)")
                }
            }.value
        }
    }

    func flush() {
        saveTask?.cancel()
        try? files.save(snapshot())
    }

    private func snapshot() -> Snapshot {
        Snapshot(
            equipment: equipment,
            waterProfiles: waterProfiles,
            calibrations: calibrations
        )
    }
}

extension SetupStore: RemoteSyncStore {
    var syncKinds: [EntityKind] { [.equipment, .waterProfile, .grindCalibration] }

    func syncableIDs(_ kind: EntityKind) -> [UUID] {
        switch kind {
        case .equipment: equipment.map(\.id)
        case .waterProfile: waterProfiles.map(\.id)
        case .grindCalibration: calibrations.map(\.id)
        default: []
        }
    }

    func pushRecords(
        _ kind: EntityKind,
        ids: Set<UUID>,
        deleted: Set<UUID>,
        client: SupabaseClient,
        userID: UUID
    ) async throws {
        switch kind {
        case .equipment:
            let rows = equipment
                .filter { ids.contains($0.id) }
                .map { EquipmentRow(equipment: $0, userID: userID) }
            if !rows.isEmpty {
                try await client.from(kind.table).upsert(rows).execute()
            }
        case .waterProfile:
            let rows = waterProfiles
                .filter { ids.contains($0.id) }
                .map { WaterProfileRow(profile: $0, userID: userID) }
            if !rows.isEmpty {
                try await client.from(kind.table).upsert(rows).execute()
            }
        case .grindCalibration:
            let rows = calibrations
                .filter { ids.contains($0.id) }
                .map { GrindCalibrationRow(calibration: $0, userID: userID) }
            if !rows.isEmpty {
                try await client.from(kind.table).upsert(rows).execute()
            }
        default:
            return
        }

        for id in deleted {
            try await client.from(kind.table)
                .delete()
                .eq("id", value: id)
                .execute()
        }
    }

    func pullRecords(
        _ kind: EntityKind,
        since: Date?,
        client: SupabaseClient,
        userID: UUID
    ) async throws {
        var query = client.from(kind.table).select().eq("user_id", value: userID)
        if let since {
            query = query.gt("updated_at", value: since.ISO8601Format())
        }
        switch kind {
        case .equipment:
            let rows: [EquipmentRow] = try await query.execute().value
            merge(equipment: rows.map { $0.toEquipment() })
        case .waterProfile:
            let rows: [WaterProfileRow] = try await query.execute().value
            merge(waterProfiles: rows.map { $0.toWaterProfile() })
        case .grindCalibration:
            let rows: [GrindCalibrationRow] = try await query.execute().value
            merge(calibrations: rows.map { $0.toCalibration() })
        default:
            return
        }
    }
}
