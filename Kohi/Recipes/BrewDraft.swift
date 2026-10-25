import Foundation

/// A brew journey closed before Save. Resume is offered the next time the
/// archive opens, the same way an unfinished voice note is recovered.
@MainActor
enum BrewDraft {
    static let resumeNotification = Notification.Name("kohi.resumeBrewDraft")

    private static let key = "brew.draft"

    struct Payload: Codable, Sendable {
        var cardID: UUID
        var brew: Brew
        var recipeID: UUID?
        var size: RecipeSize
        var step: String
        var fromCard: Bool
        var logged: Bool
    }

    static func save(_ session: BrewSession) {
        let payload = Payload(
            cardID: session.card.id,
            brew: session.brew,
            recipeID: session.recipe?.id,
            size: session.size,
            step: String(describing: session.step),
            fromCard: session.fromCard,
            logged: session.logged
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> Payload? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func requestResume() {
        NotificationCenter.default.post(name: resumeNotification, object: nil)
    }

    static func session(
        from payload: Payload,
        store: CardStore,
        recipes: RecipeStore,
        setup: SetupStore
    ) -> BrewSession? {
        guard let card = store.card(id: payload.cardID) else { return nil }
        let recipe = payload.recipeID.flatMap { id in recipes.recipes.first { $0.id == id } }
        let step: BrewSession.Step = switch payload.step {
        case "start": .start
        case "previous": .previous
        case "kit": .dial
        case "dial": .dial
        case "pour": .dial
        case "after": .after
        default: .scope
        }
        let session = BrewSession(
            card: card,
            recipe: recipe,
            existing: payload.brew,
            start: step,
            fromCard: payload.fromCard,
            setup: setup
        )
        session.brew = payload.brew
        session.size = payload.size
        session.logged = payload.logged
        return session
    }
}
