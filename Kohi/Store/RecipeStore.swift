import Foundation
import Observation
import os
import Supabase

/// The recipes you saved, in `recipes.json` beside the archive.
///
/// The bundled reference recipes are not in here: they are read-only and come
/// from `ReferenceBase`. This store holds only what you wrote, which is also
/// exactly what needs syncing.
@Observable
final class RecipeStore {
    private(set) var recipes: [Recipe] = []

    @ObservationIgnored weak var sink: (any ArchiveChangeSink)?
    @ObservationIgnored private let files: JSONFileStore<Recipe>
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(files: JSONFileStore<Recipe> = JSONFileStore(filename: "recipes.json")) {
        self.files = files
        recipes = files.load().sorted { $0.createdAt > $1.createdAt }
    }

    var isEmpty: Bool { recipes.isEmpty }

    func recipe(id: UUID) -> Recipe? {
        recipes.first { $0.id == id }
    }

    /// Yours plus the reference base, for the picker in the brew sheet.
    func all(for method: BrewMethod? = nil) -> [Recipe] {
        let pool = recipes + ReferenceBase.recipes
        guard let method else { return pool }
        return pool.filter { $0.method == method }
    }

    @discardableResult
    func add(_ recipe: Recipe) -> Recipe {
        recipes.insert(recipe, at: 0)
        sink?.changed(.recipe, id: recipe.id)
        scheduleSave()
        return recipe
    }

    /// Once per install: yours and the express recipes move to Auto unless
    /// you picked a mode. References already advance on their own.
    func moveToAutoAdvanceIfNeeded(defaults: UserDefaults = .standard) {
        let key = "kohi.recipes.autoAdvanceDefault"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        for recipe in recipes
        where (recipe.source == .mine || recipe.source == .express)
            && !recipe.advanceModeChosen
            && recipe.advanceMode != .auto
        {
            var moved = recipe
            moved.advanceMode = .auto
            moved.autoAdvance = true
            update(moved)
        }
    }

    func update(_ recipe: Recipe) {
        guard let index = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        var updated = recipe
        updated.updatedAt = .now
        recipes[index] = updated
        sink?.changed(.recipe, id: recipe.id)
        scheduleSave()
    }

    func delete(_ recipe: Recipe) {
        recipes.removeAll { $0.id == recipe.id }
        sink?.deleted(.recipe, id: recipe.id)
        scheduleSave()
    }

    /// Saves a brew as a recipe, named after the coffee it worked on. The
    /// recipe keeps the link to that card so its provenance stays readable,
    /// but it applies to anything.
    @discardableResult
    func save(brew: Brew, from card: CoffeeCard, name: String? = nil) -> Recipe {
        var recipe = RecipeRules.recipe(from: brew, card: card, source: .mine, name: name)
        recipe.name = name ?? defaultName(for: brew, card: card)
        return add(recipe)
    }

    /// "Ethiopia Chelbesa · V60", disambiguated when it already exists.
    private func defaultName(for brew: Brew, card: CoffeeCard) -> String {
        let coffee = card.name.isEmpty ? "Recipe" : card.name
        let method = brew.method?.label ?? ""
        let base = method.isEmpty ? coffee : "\(coffee) · \(method)"
        guard recipes.contains(where: { $0.name == base }) else { return base }
        var index = 2
        while recipes.contains(where: { $0.name == "\(base) (\(index))" }) { index += 1 }
        return "\(base) (\(index))"
    }

    /// Last write wins per record, by `updatedAt`.
    func merge(_ incoming: [Recipe]) {
        guard !incoming.isEmpty else { return }
        var byID = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for recipe in incoming {
            if let local = byID[recipe.id], local.updatedAt > recipe.updatedAt { continue }
            byID[recipe.id] = recipe
        }
        recipes = Array(byID.values).sorted { $0.createdAt > $1.createdAt }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = recipes
        let files = files
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                do { try files.save(snapshot) } catch {
                    Log.app.error("recipe save failed: \(error)")
                }
            }.value
        }
    }

    func flush() {
        saveTask?.cancel()
        try? files.save(recipes)
    }
}

extension RecipeStore: RemoteSyncStore {
    var syncKinds: [EntityKind] { [.recipe] }

    func syncableIDs(_ kind: EntityKind) -> [UUID] {
        kind == .recipe ? recipes.map(\.id) : []
    }

    func pushRecords(
        _ kind: EntityKind,
        ids: Set<UUID>,
        deleted: Set<UUID>,
        client: SupabaseClient,
        userID: UUID
    ) async throws {
        guard kind == .recipe else { return }

        let rows = recipes
            .filter { ids.contains($0.id) }
            .map { RecipeRow(recipe: $0, userID: userID) }
        if !rows.isEmpty {
            try await client.from(kind.table).upsert(rows).execute()
        }

        for id in deleted {
            try await client.from(kind.table).delete().eq("id", value: id).execute()
        }
    }

    func pullRecords(
        _ kind: EntityKind,
        since: Date?,
        client: SupabaseClient,
        userID: UUID
    ) async throws {
        guard kind == .recipe else { return }
        var query = client.from(kind.table).select().eq("user_id", value: userID)
        if let since {
            query = query.gt("updated_at", value: since.ISO8601Format())
        }
        let rows: [RecipeRow] = try await query.execute().value
        merge(rows.map { $0.toRecipe() })
    }
}
