import Foundation
import Testing
@testable import Kohi

/// The four Ask examples from the test guide, and G7 for a sour V60.
struct AskCoverageTests {
    @Test func theBaseHasTheNineteenAnnexFEntries() {
        let f = ReferenceBase.knowledge.filter { $0.id.hasPrefix("f") }
        #expect(f.count == 19)
    }

    @Test func theFourAskExamplesHaveAMatchingEntry() {
        let examples: [(String, String)] = [
            ("How grind size changes extraction", "f6-cameron-espresso-2020"),
            ("What TDS and extraction yield mean", "g4-strength"),
            ("Which water hardness suits filter coffee", "f11-scaa-water-2009"),
            ("Why a coffee needs to rest after roasting", "g5-rest"),
        ]
        for (question, id) in examples {
            let entry = ReferenceBase.knowledge.first { $0.id == id }
            #expect(entry != nil, "missing \(id) for \(question)")
            #expect(entry?.body.isEmpty == false)
        }
    }

    @Test func aBusyModelIsNotADroppedConnection() {
        let quota = #"{"error":"model returned 429","model":"gemini-3.6-flash"}"#.data(using: .utf8)!
        #expect(Ask.classify(http: 429, body: Data()) == .busy)
        #expect(Ask.classify(http: 502, body: quota) == .busy)
        #expect(Ask.classify(http: 401, body: Data()) == .unauthorized)
        #expect(Ask.classify(http: 500, body: #"{"error":"function is not configured"}"#.data(using: .utf8)!) == .notConfigured)
        #expect(Ask.classify(http: 502, body: #"{"error":"model returned 404"}"#.data(using: .utf8)!) == .server)
        #expect(Ask.Failure.busy.message == "Ask hit today's limit. Try again later.")
        #expect(Ask.Failure.network.message.contains("connection"))
        #expect(Ask.Failure.server.message.contains("answer service"))
    }

    @Test func aSourV60CitesG7() {
        let g7 = ReferenceBase.knowledge.first { $0.id == "g7-diagnosis" }
        #expect(g7 != nil)
        #expect(g7?.body.localizedCaseInsensitiveContains("sour") == true)
        #expect(g7?.body.localizedCaseInsensitiveContains("finer") == true)
    }
}
