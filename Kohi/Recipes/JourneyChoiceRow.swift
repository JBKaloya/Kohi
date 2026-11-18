import SwiftUI

/// One way into a brew: an icon in a ring, a title, and what it leads to.
struct JourneyChoiceRow: View {
    var systemName: String
    var title: String
    var detail: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Palette.hairline, lineWidth: 1)
                        .frame(width: 44, height: 44)
                    Image(systemName: systemName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.ink)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.value)
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
