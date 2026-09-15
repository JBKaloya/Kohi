import Foundation

/// How a store tells the sync layer that something needs pushing. Kept
/// entity-agnostic so equipment, water profiles and recipes travel the same
/// path as cards.
@MainActor protocol ArchiveChangeSink: AnyObject {
    func changed(_ kind: EntityKind, id: UUID)
    func deleted(_ kind: EntityKind, id: UUID)
}

extension ArchiveChangeSink {
    func cardChanged(_ id: UUID) { changed(.card, id: id) }
    func cardDeleted(_ id: UUID) { deleted(.card, id: id) }
}

/// A local store the coordinator can re-push wholesale on Force Full Backup.
///
/// A store may own several kinds — Setup holds equipment, water profiles and
/// grind calibrations in one file — so everything here is keyed by kind rather
/// than assuming one collection per store.
@MainActor protocol SyncableStore: AnyObject {
    var syncKinds: [EntityKind] { get }
    /// Every id this store holds of that kind, for a full re-upload.
    func syncableIDs(_ kind: EntityKind) -> [UUID]
}
