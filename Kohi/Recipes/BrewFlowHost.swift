import SwiftUI

/// Sole presenter of the brew journey. GuidedBrewView and AfterBrewSheet
/// are only constructed here.
struct BrewFlowHost: View {
    @Bindable var session: BrewSession
    var onDismiss: () -> Void
    var onAgain: ((Brew) -> Void)?
    var onDelete: (() -> Void)?

    @Environment(CardStore.self) private var store
    @Environment(AIEventLog.self) private var events

    var body: some View {
        Group {
            switch session.step {
            case .scope:
                BrewScopeView(
                    session: session,
                    onClose: onDismiss,
                    onNext: { session.goToKit() }
                )
            case .kit:
                BrewKitView(
                    session: session,
                    onBack: { session.step = .scope },
                    onClose: onDismiss,
                    onBrewNow: { session.brewNow() },
                    onAlreadyBrewed: { session.alreadyBrewed() }
                )
            case .pour:
                GuidedBrewView(
                    card: session.card,
                    recipe: session.timerRecipe,
                    brew: session.brew,
                    onFinish: { session.poured($0) },
                    onCancel: { session.step = .kit }
                )
            case .after:
                AfterBrewSheet(
                    session: session,
                    onSave: save,
                    onDelete: onDelete,
                    onAgain: onAgain,
                    onBack: { session.step = .kit }
                )
            }
        }
    }

    private func save() {
        session.finish(store: store, events: events)
        onDismiss()
    }
}
