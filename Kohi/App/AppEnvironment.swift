import SwiftUI

/// The observable objects every screen reads through `@Environment(Type.self)`.
///
/// That property wrapper force-unwraps. On iOS 18 a sheet or fullScreenCover is
/// hosted in a new controller that does not always copy those values from the
/// presenter — a fatal error the moment the presented view is laid out. Capture
/// this bundle from the presenter and pass it onto the presented content.
struct AppEnvironment {
    var store: CardStore
    var roasters: RoasterStore
    var setup: SetupStore
    var recipes: RecipeStore
    var account: AccountStore
    var setupFlow: SetupFlowController
    var sync: SyncCoordinator
    var flags: AIFlags
    var lotFlags: LotFlags
    var aiEvents: AIEventLog
    var feedback: AIFeedbackStore
}

private struct AppEnvironmentKey: EnvironmentKey {
    static var defaultValue: AppEnvironment? { nil }
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment? {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}

extension View {
    /// Writes the bundle and every typed Observable the rest of the app reads.
    func appEnvironment(_ env: AppEnvironment) -> some View {
        self
            .environment(\.appEnvironment, env)
            .environment(env.store)
            .environment(env.roasters)
            .environment(env.setup)
            .environment(env.recipes)
            .environment(env.account)
            .environment(env.setupFlow)
            .environment(env.sync)
            .environment(env.flags)
            .environment(env.lotFlags)
            .environment(env.aiEvents)
            .environment(env.feedback)
            .environment(IntentRouter.shared)
    }

    /// Same write, for sheet closures that captured the presenter's optional.
    @ViewBuilder
    func appEnvironment(_ env: AppEnvironment?) -> some View {
        if let env {
            appEnvironment(env)
        } else {
            self
        }
    }
}
