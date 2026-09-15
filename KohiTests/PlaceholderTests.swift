import Foundation
import Testing
@testable import Kohi

struct PlaceholderTests {
    @Test func everyFieldHasAnExample() {
        for field in Placeholders.Field.allCases {
            let value = Placeholders.text(field)
            #expect(!value.isEmpty, "\(field.rawValue) is empty")
        }
    }

    /// A placeholder is an example, never a prompt and never the field's own name.
    @Test func noPlaceholderIsAPromptOrALabel() {
        let forbidden = ["Enter", "Your", "Name"]
        for field in Placeholders.Field.allCases {
            let value = Placeholders.text(field)
            for word in forbidden {
                #expect(
                    !value.localizedCaseInsensitiveContains(word),
                    "\(field.rawValue) contains “\(word)”"
                )
            }
            #expect(
                value.caseInsensitiveCompare(Placeholders.label(field)) != .orderedSame,
                "\(field.rawValue) repeats its label"
            )
        }
    }
}
