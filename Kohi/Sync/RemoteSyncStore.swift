import Foundation
import Supabase

/// A store of flat records that the coordinator can push and pull generically.
///
/// Each store owns its own row DTOs, so the data path stays typed end to end;
/// the coordinator only owns the bookkeeping — which ids are dirty, which were
/// deleted, and where the last pull stopped. Cards do not conform: brews,
/// images and posters make their push a special case, and pretending otherwise
/// would cost more than it saves.
@MainActor protocol RemoteSyncStore: SyncableStore {
    /// Upserts the given records and deletes the tombstoned ones. Called only
    /// when at least one of the two sets is non-empty. Throwing leaves the
    /// outbox untouched, so the work is retried on the next sync.
    func pushRecords(
        _ kind: EntityKind,
        ids: Set<UUID>,
        deleted: Set<UUID>,
        client: SupabaseClient,
        userID: UUID
    ) async throws

    /// Merges everything of that kind changed since `since` into the local
    /// cache.
    func pullRecords(
        _ kind: EntityKind,
        since: Date?,
        client: SupabaseClient,
        userID: UUID
    ) async throws
}
