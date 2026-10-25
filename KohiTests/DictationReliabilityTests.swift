import AVFoundation
import Foundation
import Testing
@testable import Kohi

struct DictationReliabilityTests {
    @Test func aFinalFragmentAccumulatesInsteadOfReplacing() {
        let first = DictationTranscript.join("", "bloom sixty grams")
        let next = DictationTranscript.join(first, "pour to three hundred")
        #expect(first == "bloom sixty grams")
        #expect(next == "bloom sixty grams pour to three hundred")
    }

    @Test func emptySidesDoNotLeaveAStraySpace() {
        #expect(DictationTranscript.join("settled", "") == "settled")
        #expect(DictationTranscript.join("", "live") == "live")
        #expect(DictationTranscript.join("  ", "  ") == "")
    }

    @Test func speechLocalesAlwaysOfferEnglishAndFrench() {
        let ids = SpeechLocales.candidates.map {
            $0.language.languageCode?.identifier ?? $0.identifier
        }
        #expect(ids.contains("en"))
        #expect(ids.contains("fr"))
        #expect(SpeechLocales.score(text: "put some water in the moka", segments: [])
            > SpeechLocales.score(text: "hi", segments: []))
    }

    @Test func appendAndReplaceAreExplicit() {
        #expect(DictationTranscript.apply("swirl", to: "bloom", mode: .replace) == "swirl")
        #expect(DictationTranscript.apply("swirl", to: "bloom", mode: .append) == "bloom swirl")
        #expect(DictationTranscript.apply("swirl", to: "", mode: .append) == "swirl")
    }

    @Test func noSpeechIsARetry() {
        for code in [203, 1110, 216] {
            let error = NSError(domain: "kAFAssistantErrorDomain", code: code)
            #expect(DictationFailure.classify(error) == .retry)
        }
    }

    @Test func anUnknownDomainGivesUp() {
        let error = NSError(domain: "KohiTests", code: 1)
        #expect(DictationFailure.classify(error) == .giveUp)
    }

    @Test func aDeviceRouteRebuildsTheTap() {
        #expect(DictationRouteChange.shouldRebuild(.newDeviceAvailable))
        #expect(DictationRouteChange.shouldRebuild(.oldDeviceUnavailable))
        #expect(!DictationRouteChange.shouldRebuild(.unknown))
        #expect(!DictationRouteChange.shouldRebuild(.categoryChange))
    }

    @Test func theMicLockRejectsASecondOwnerUntilRelease() {
        DictationMic.resetForTests()
        let first = NSObject()
        let second = NSObject()
        #expect(DictationMic.acquire(first))
        #expect(!DictationMic.acquire(second))
        DictationMic.release(first)
        #expect(DictationMic.acquire(second))
        DictationMic.resetForTests()
    }

    @Test func aStaleOwnerClearsOnForeground() {
        DictationMic.resetForTests()
        let first = NSObject()
        #expect(DictationMic.acquire(first))
        DictationMic.clearStaleOwner()
        #expect(DictationMic.acquire(NSObject()))
        DictationMic.resetForTests()
    }

    @MainActor
    @Test func deinitReleasesTheMic() {
        DictationMic.resetForTests()
        do {
            let dictation = Dictation()
            #expect(DictationMic.acquire(dictation))
            #expect(DictationMic.isHeld)
        }
        DictationMic.reapIfAbandoned()
        #expect(!DictationMic.isHeld)
        DictationMic.resetForTests()
    }
}

struct VoiceNoteCoverageTests {
    @Test func aShortGapIsCovered() {
        #expect(VoiceNoteCoverage.uncoveredRange(coveredThrough: 58, duration: 60) == nil)
    }

    @Test func aLongFileYieldsTheRemainder() {
        let rest = VoiceNoteCoverage.uncoveredRange(coveredThrough: 50, duration: 90)
        #expect(rest == 50...90)
        let next = VoiceNoteCoverage.coveredThrough(origin: rest!.lowerBound, relativeEnd: 40)
        #expect(next == 90)
        #expect(VoiceNoteCoverage.uncoveredRange(coveredThrough: next, duration: 90) == nil)
    }

    @Test func threePassesReachALongFixture() {
        var covered: TimeInterval = 0
        let duration: TimeInterval = 150
        var passes = 0
        while passes < VoiceNoteCoverage.maxPasses {
            passes += 1
            let relative = min(55, duration - covered)
            covered = VoiceNoteCoverage.coveredThrough(origin: covered, relativeEnd: relative)
            if VoiceNoteCoverage.uncoveredRange(coveredThrough: covered, duration: duration) == nil {
                break
            }
        }
        #expect(passes == 3)
        #expect(covered == 150)
    }

    @Test func liveDictationAndBrewNotesShareValidSessionPlans() {
        let plans = [
            DictationSessionPlan(category: .playAndRecord, mode: .measurement, options: .duckOthers),
            DictationSessionPlan(category: .record, mode: .measurement, options: []),
            DictationSessionPlan(category: .record, mode: .default, options: []),
        ]
        #expect(DictationSession.plans == plans)
        #expect(BrewVoiceNote.sessionPlans == DictationSession.plans)
        #expect(plans.allSatisfy { $0.mode != .spokenAudio })
        #expect(plans.allSatisfy { plan in
            plan.category != .record || !plan.options.contains(.duckOthers)
        })
    }

    @Test func pendingRoundTrips() throws {
        try FileManager.default.createDirectory(
            at: BrewVoiceNote.directory,
            withIntermediateDirectories: true
        )
        let brewID = UUID()
        let pending = BrewVoiceNote.Pending(
            brewID: brewID,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            path: "/tmp/kohi-test.m4a"
        )
        let data = try JSONEncoder().encode(pending)
        try data.write(to: BrewVoiceNote.pendingURL, options: .atomic)
        let loaded = BrewVoiceNote.pending()
        #expect(loaded?.brewID == brewID)
        #expect(loaded?.path == pending.path)
        BrewVoiceNote.discardPending()
        #expect(BrewVoiceNote.pending() == nil)
    }
}

struct DictationPlistTests {
    @Test func theAppDeclaresBackgroundAudio() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plist = try String(
            contentsOf: root.appending(path: "Kohi/Info.plist"),
            encoding: .utf8
        )
        #expect(plist.contains("UIBackgroundModes"))
        #expect(plist.contains("<string>audio</string>"))
        #expect(!plist.contains("Recording stops the moment you tap again"))
        #expect(plist.contains("even if the screen locks"))
    }

    @Test func noViewHidesAMicBehindSupport() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Kohi")
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        )
        var scanned = 0
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            scanned += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(
                !text.contains("if Dictation.isSupported"),
                "\(url.lastPathComponent) hides a mic"
            )
            #expect(
                !text.contains("Dictation.isSupported ?"),
                "\(url.lastPathComponent) hides a mic"
            )
            #expect(
                !text.contains("guard Dictation.isSupported"),
                "\(url.lastPathComponent) hides a mic"
            )
            #expect(
                !text.contains("if showsFilter"),
                "\(url.lastPathComponent) hides a filter row"
            )
            #expect(
                !text.contains("if family.takesPaper"),
                "\(url.lastPathComponent) hides a filter row"
            )
        }
        #expect(scanned > 20)
    }
}
