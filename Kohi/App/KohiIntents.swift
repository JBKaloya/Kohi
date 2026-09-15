import AppIntents
import SwiftUI

/// Two ways in that skip the app: "Log a brew" and "Start a V60".
///
/// Both open the app on the right sheet rather than writing anything in the
/// background. A brew logged without you seeing it is a brew you cannot trust,
/// and the whole archive is only worth keeping if every row was looked at.
struct LogABrewIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a brew"
    static let description = IntentDescription(
        "Opens Kohi on a new brew for your most recent coffee."
    )
    static let openAppWhenRun = true

    @Parameter(title: "Coffee")
    var coffee: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.request(.logBrew(coffee: coffee, method: nil))
        return .result()
    }
}

struct StartABrewIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a brew"
    static let description = IntentDescription(
        "Opens Kohi on a new brew with the method already chosen, and the guided timer ready."
    )
    static let openAppWhenRun = true

    @Parameter(title: "Method")
    var method: BrewMethodAppEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.request(.logBrew(coffee: nil, method: method.method))
        return .result()
    }
}

/// The methods, as something Shortcuts can offer in a menu.
struct BrewMethodAppEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Brew method")
    static let defaultQuery = BrewMethodQuery()

    var id: String
    var method: BrewMethod { BrewMethod(rawValue: id) ?? .v60 }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(method.label)")
    }
}

struct BrewMethodQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BrewMethodAppEntity] {
        identifiers.compactMap { BrewMethod(rawValue: $0) }.map { BrewMethodAppEntity(id: $0.rawValue) }
    }

    func suggestedEntities() async throws -> [BrewMethodAppEntity] {
        BrewMethod.allCases.map { BrewMethodAppEntity(id: $0.rawValue) }
    }
}

struct KohiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogABrewIntent(),
            phrases: [
                "Log a brew in \(.applicationName)",
                "Log a coffee in \(.applicationName)",
            ],
            shortTitle: "Log a brew",
            systemImageName: "drop"
        )
        AppShortcut(
            intent: StartABrewIntent(),
            phrases: [
                "Start a brew in \(.applicationName)",
                "Start a \(\.$method) in \(.applicationName)",
            ],
            shortTitle: "Start a brew",
            systemImageName: "timer"
        )
    }
}

/// Where an intent's request waits until the UI is up and can act on it.
///
/// A singleton because an intent runs before any view exists; the root view
/// reads it and clears it, so a request is honoured exactly once.
@Observable
@MainActor
final class IntentRouter {
    static let shared = IntentRouter()

    enum Request: Equatable {
        case logBrew(coffee: String?, method: BrewMethod?)
    }

    private(set) var pending: Request?

    func request(_ request: Request) {
        pending = request
    }

    func take() -> Request? {
        defer { pending = nil }
        return pending
    }
}
