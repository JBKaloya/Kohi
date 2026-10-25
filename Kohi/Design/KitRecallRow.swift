import SwiftUI

/// Read-only kit line on Today's settings. CHANGE reveals the other
/// brewers and grinders for the current method.
struct KitRecallRow: View {
    var brewer: Equipment?
    var grinder: Equipment?
    var expanded: Bool
    var onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(line)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Button(Copy.change, action: onChange)
                    .catalogueLabel()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(line)
        .accessibilityAddTraits(expanded ? .isSelected : [])
    }

    private var line: String {
        let parts = [brewer?.displayName, grinder?.displayName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        if parts.isEmpty { return "with your kit" }
        return "with " + parts.joined(separator: " · ")
    }
}