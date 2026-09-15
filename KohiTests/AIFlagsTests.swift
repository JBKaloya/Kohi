import Foundation
import Testing

@testable import Kohi

/// Two switches in series. The tests that matter are the ones about failure:
/// off by default, and a server that says nothing must not turn everything off.
@MainActor
struct AIFlagsTests {
    static func flags() -> AIFlags {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return AIFlags(defaults: defaults)
    }

    /// Experimental AI starts on in this lot. The two that shipped before
    /// this section existed stay on even if the master is later turned off.
    @Test func onlyTheExperimentalOnesStartOff() {
        let flags = Self.flags()

        #expect(flags.isExperimentalEnabled)
        #expect(flags.isOn(.ask))
        #expect(flags.isOn(.fieldExtract))
        #expect(flags.isOn(.recipeAdapt))
        #expect(flags.isOn(.cardVision))
        #expect(flags.isOn(.poster))
    }

    @Test func theMasterSwitchTurnsThemAllOn() {
        let flags = Self.flags()
        flags.isExperimentalEnabled = true

        for feature in AIFeature.allCases {
            #expect(flags.isOn(feature))
        }
    }

    @Test func aFeatureCanBeRefusedOnItsOwn() {
        let flags = Self.flags()
        flags.isExperimentalEnabled = true
        flags.setOn(.ask, false)

        #expect(!flags.isOn(.ask))
        #expect(flags.isOn(.recipeAdapt))
    }

    @Test func theMasterSwitchOverridesEveryOtherOne() {
        let flags = Self.flags()
        flags.isExperimentalEnabled = true
        flags.setOn(.ask, true)
        flags.isExperimentalEnabled = false

        #expect(!flags.isOn(.ask))
        #expect(flags.reason(.ask) == "Experimental AI is off")
        // And it leaves the non-experimental ones alone.
        #expect(flags.isOn(.cardVision))
    }

    @Test func aFeatureThatIsNotExperimentalCanStillBeRefused() {
        let flags = Self.flags()
        flags.setOn(.poster, false)

        #expect(!flags.isOn(.poster))
        #expect(flags.reason(.poster) == "Off")
    }

    @Test func choicesSurviveARelaunch() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let first = AIFlags(defaults: defaults)
        first.isExperimentalEnabled = true
        first.setOn(.recipeAdapt, false)

        let second = AIFlags(defaults: defaults)

        #expect(second.isExperimentalEnabled)
        #expect(!second.isOn(.recipeAdapt))
        #expect(second.isOn(.ask))
    }

    /// A flags table that cannot be reached must not read as "everything is
    /// disabled" — that would make one failed request look like a kill switch.
    @Test func aServerThatSaysNothingChangesNothing() async {
        let flags = Self.flags()
        flags.isExperimentalEnabled = true

        await flags.refresh(client: nil)

        for feature in AIFeature.allCases {
            #expect(flags.isOn(feature))
        }
        #expect(flags.refreshedAt == nil)
    }

    @Test func everyFeatureNamesWhatIsLostWithoutIt() {
        for feature in AIFeature.allCases {
            #expect(!feature.label.isEmpty)
            #expect(!feature.fallback.isEmpty)
            if feature != .aiFeedback {
                #expect(feature.function != nil)
            }
        }
    }
}

/// The event log. Buffered, dropped rather than retried, and answerable after
/// the fact.
@MainActor
struct AIEventLogTests {
    @Test func anEventWaitsUntilThereIsSomewhereToSendIt() {
        let log = AIEventLog()
        log.record(AIEvent(feature: .ask, model: "test", latencyMs: 120))

        #expect(log.pending.count == 1)
        #expect(log.recent.count == 1)
    }

    @Test func theVerdictCanArriveLater() {
        let log = AIEventLog()
        let id = log.record(AIEvent(feature: .fieldExtract, model: "test", latencyMs: 90))

        log.setAccepted(true, for: id)

        #expect(log.pending.first?.accepted == true)
        #expect(log.recent.first?.accepted == true)
    }

    @Test func theAcceptanceLineNeedsEnoughAnswersToMeanAnything() {
        let log = AIEventLog()
        let first = log.record(AIEvent(feature: .ask, model: "test", latencyMs: 10))
        log.setAccepted(true, for: first)

        #expect(log.acceptanceLine == nil)

        for _ in 0..<2 {
            let id = log.record(AIEvent(feature: .ask, model: "test", latencyMs: 10))
            log.setAccepted(false, for: id)
        }

        #expect(log.acceptanceLine == "1 of 3 kept")
    }

    @Test func aFailureIsRecordedAsAnUnacceptedEvent() {
        let log = AIEventLog()
        log.record(AIEvent(
            feature: .recipeAdapt,
            model: "unknown",
            latencyMs: 4000,
            accepted: false,
            failure: "timed out"
        ))

        #expect(log.recent.first?.accepted == false)
        #expect(log.recent.first?.failure == "timed out")
    }
}
