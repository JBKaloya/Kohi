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
    @Environment(SetupStore.self) private var setup
    @State private var reading = false

    var body: some View {
        journey
            .onAppear {
                if session.opensRead { reading = true }
            }
    }

    @ViewBuilder
    private var journey: some View {
        if reading {
            BrewReadView(
                session: session,
                previous: session.card.brews.first { $0.id != session.brew.id },
                onAgain: { onAgain?(session.brew) },
                onDone: onDismiss
            )
        } else {
            switch session.step {
            case .start:
                BrewStartView(
                    session: session,
                    onBack: dismiss,
                    onClose: dismiss
                )
            case .previous:
                BrewPreviousView(
                    session: session,
                    onBack: back,
                    onClose: dismiss
                )
            case .scope:
                BrewScopeView(
                    session: session,
                    onBack: back,
                    onClose: dismiss,
                    onNext: { session.goToDial() }
                )
            case .kit:
                BrewKitView(
                    session: session,
                    onBack: back,
                    onClose: dismiss,
                    onNext: { session.goToDial() }
                )
            case .dial:
                BrewDialView(
                    session: session,
                    onBack: back,
                    onClose: dismiss,
                    onBrewNow: { session.brewNow(in: setup) },
                    onAlreadyBrewed: { session.alreadyBrewed(in: setup) }
                )
            case .pour:
                GuidedBrewView(
                    card: session.card,
                    recipe: session.timerRecipe(in: setup),
                    brew: session.brew,
                    voiceNote: session.voiceNote,
                    equipment: setup.equipment,
                    onFinish: {
                        var brew = $0
                        if brew.actualSource == .none { brew.actualSource = .timer }
                        brew.refreshPourRates()
                        session.poured(brew)
                    },
                    onCancel: { session.step = .dial },
                    journeyStep: session.progressIndex,
                    journeyTotal: session.progressTotal
                )
            case .after:
                AfterBrewSheet(
                    session: session,
                    onSave: save,
                    onDelete: onDelete,
                    onBrewFromCompare: onAgain,
                    onBack: { session.step = .dial }
                )
            }
        }
    }

    private func back() {
        if !session.retreat() { dismiss() }
    }

    private func dismiss() {
        BrewDraft.save(session)
        onDismiss()
    }

    private func save() {
        session.finish(store: store, events: events)
        BrewDraft.clear()
        reading = true
    }
}
