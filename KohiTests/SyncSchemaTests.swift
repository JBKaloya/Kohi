import Foundation
import Testing
@testable import Kohi

struct SyncSchemaTests {
    @Test func aMissingTableIsNamed() {
        let message = "Could not find the table 'public.roasters' in the schema cache"
        #expect(SyncSchema.missingRelation(in: message) == "roasters")
    }

    @Test func aMissingColumnNamesTheTable() {
        let message = "Could not find the 'product_url' column of 'coffee_cards' in the schema cache"
        #expect(SyncSchema.missingRelation(in: message) == "coffee_cards")
    }

    @Test func anOrdinaryErrorIsNotASchemaGap() {
        #expect(SyncSchema.missingRelation(in: "network connection lost") == nil)
    }

    @Test func theAccountLineNamesWhatIsMissing() {
        let line = SyncSchema.message(missing: ["roasters", "equipment"])
        #expect(line.contains("roasters"))
        #expect(line.contains("equipment"))
        #expect(line.contains("migrations") || line.contains("Backend"))
    }
}
