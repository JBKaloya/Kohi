import SwiftUI

/// How the cup was: five dots, the seven-axis radar, the flavour wheel.
///
/// One section for a coffee made at home and one drunk out, so both read and
/// score the same. What to change next time is a different question and lives
/// elsewhere: after a brew, in its own step.
struct SensoryEvaluationSection: View {
    @Binding var rating: Int?
    @Binding var taste: TasteProfile
    @Binding var flavors: [FlavorTag]
    var previousTaste: TasteProfile?
    var previousCaption: String?
    var declared: [FlavorTag] = []
    var recent: [FlavorTag] = []
    var enabled = true
    var onChange: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            RatingPicker(rating: $rating, enabled: enabled, onChange: onChange)
            TasteBlock(
                taste: $taste,
                previous: previousTaste,
                previousCaption: previousCaption,
                enabled: enabled,
                onChange: onChange
            )
            FlavorsBlock(selection: $flavors, declared: declared, recent: recent)
        }
    }
}

/// The values that section edits, with the rules shared by both sides.
nonisolated enum SensoryScored {
    /// The last shape before this one, from the newest scored entry.
    static func previous(_ tastes: [TasteProfile]) -> TasteProfile? {
        tastes.first { !$0.isEmpty }
    }

    /// The flavours most recently picked, each once, at most eight.
    static func recent(_ logged: [[FlavorTag]]) -> [FlavorTag] {
        var seen = Set<String>()
        var tags: [FlavorTag] = []
        for tag in logged.joined() where seen.insert(tag.id).inserted {
            tags.append(tag)
        }
        return Array(tags.prefix(8))
    }
}
