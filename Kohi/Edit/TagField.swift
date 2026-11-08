import SwiftUI

/// Wrapping row layout for tags and quick picks.
struct FlowLayout: Layout {
    var spacing: CGFloat = 7
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let layout = arrange(subviews, width: bounds.width)
        for (index, origin) in layout.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }

        return (origins, CGSize(width: maxX, height: y + rowHeight))
    }
}

/// Options to pick from, on one line that scrolls sideways. Wrapping is kept
/// for what you own (your notes, your flavours); a row of choices never
/// spills onto a second line.
struct ChipRail<Content: View>: View {
    var spacing: CGFloat = 7
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                content
            }
        }
        .scrollClipDisabled()
    }
}

/// A tag, either sitting in a list or offered as a quick pick.
struct TagChip: View {
    let text: String
    var isSelected: Bool = false
    var showsRemove: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(text)
                    .font(Typography.tag)
                    .lineLimit(1)
                if showsRemove {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                }
            }
            .foregroundStyle(isSelected ? Palette.paper : Palette.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(isSelected ? Palette.ink : Color.clear)
                    .overlay(Capsule().stroke(Palette.hairline, lineWidth: isSelected ? 0 : 1))
            }
        }
        .buttonStyle(.plain)
        .touchTarget()
        .animation(Motion.quick, value: isSelected)
    }
}

/// Free tags with an inline field to add more. Used for tasting notes.
struct TagField: View {
    @Binding var tags: [String]
    var placeholder: String = Placeholders.text(.cardTastingNotes)

    @State private var entry = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !tags.isEmpty {
                FlowLayout {
                    ForEach(tags, id: \.self) { tag in
                        TagChip(text: tag, showsRemove: true) {
                            withAnimation(Motion.quick) {
                                tags.removeAll { $0 == tag }
                            }
                        }
                    }
                }
            }

            TextField(placeholder, text: $entry)
                .font(Typography.value)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(commit)
            DictationField(text: $entry, vocabulary: { CoffeeLexicon.flavors() })
                .onChange(of: entry) { _, value in
                    if value.contains("\n") { commit() }
                }
        }
    }

    private func commit() {
        let value = entry.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !tags.contains(value) else {
            entry = ""
            return
        }
        withAnimation(Motion.snappy) { tags.append(value) }
        entry = ""
    }
}
