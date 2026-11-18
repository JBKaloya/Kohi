import SnapshotTesting
import SwiftUI
import Testing
import UIKit
@testable import Kohi

/// For next time: Done leads once a brew is saved, Brew again leads from a
/// past brew, and Brew again opens the new brew rather than the same page.
@Suite(.serialized)
@MainActor
struct BrewAgainTests {
    @Observable
    final class Holder {
        var session: BrewSession
        init(_ session: BrewSession) { self.session = session }
    }

    private struct Swap: View {
        let holder: Holder
        let setup: SetupStore

        var body: some View {
            BrewFlowHost(
                session: holder.session,
                onDismiss: {},
                onAgain: { seed in
                    holder.session = BrewSession(
                        card: holder.session.card,
                        existing: seed.again(),
                        start: .dial,
                        setup: setup
                    )
                }
            )
        }
    }

    private func pastBrew(setup: SetupStore) -> BrewSession {
        var brew = Brew(method: .v60, dose: 15, water: 275, temperature: 99, rating: 4)
        brew.acidity = 1
        let session = BrewSession(card: BrewJourneySupport.card(), existing: brew, mode: .edit, start: .after, setup: setup)
        session.opensRead = true
        return session
    }

    @Test func brewAgainOpensHowMuchNotTheSamePage() throws {
        let setup = BrewJourneySupport.setup()
        let holder = Holder(pastBrew(setup: setup))
        let first = holder.session
        let host = UIHostingController(
            rootView: BrewJourneySupport.wrap(Swap(holder: holder, setup: setup), setup: setup)
                .environment(\.kohiHapticsEnabled, false)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        settle()

        holder.session = BrewSession(card: first.card, existing: first.brew.again(), start: .dial, setup: setup)
        settle()

        #expect(holder.session.step == .dial)
        #expect(holder.session !== first)
        assertSnapshot(
            of: host,
            as: .image(precision: 1, perceptualPrecision: 0.98, size: CGSize(width: 393, height: 852), traits: SnapshotSupport.traits),
            named: "after-swap",
            record: .missing
        )
        window.isHidden = true
    }

    @Test func afterSavingDoneLeads() throws {
        let read = try source("Recipes/BrewReadView.swift")
        let body = read.components(separatedBy: "if endsTheBrew || onAgain == nil").dropFirst().first ?? ""
        let done = body.range(of: "primary(Copy.done")
        let again = body.range(of: "primary(Copy.brewAgain")
        #expect(done != nil && again != nil)
        if let done, let again { #expect(done.lowerBound < again.lowerBound) }
        let host = try source("Recipes/BrewFlowHost.swift")
        let save = host.components(separatedBy: "private func save()").dropFirst().first ?? ""
        #expect(save.contains("endsTheBrew = true"))
        #expect(host.contains(".id(session.id)"))
    }

    @Test func afterSavingTheButtonsRead() {
        let setup = BrewJourneySupport.setup()
        let session = pastBrew(setup: setup)
        SnapshotSupport.image(
            of: BrewJourneySupport.wrap(
                BrewReadView(session: session, onAgain: {}, onDone: {}, endsTheBrew: true),
                setup: setup
            ),
            height: 2200,
            named: "ends-the-brew"
        )
    }

    private func source(_ file: String) throws -> String {
        try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: file))
    }

    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    }
}
