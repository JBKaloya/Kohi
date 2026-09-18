import SwiftUI

/// A label facing a value, with the rules between them drawn by the list that
/// holds it. The tombstone grammar from `CaptionBlock`, available to the
/// sheets that need to read like it.
struct CatalogueRow: View {
    /// Wide enough for `Copy.forYourGrinder` and `Copy.totalBrewTime`
    /// at catalogue tracking, so those labels never wrap to two lines.
    static let labelColumn: CGFloat = 120

    let label: String
    let value: String
    var labelWidth: CGFloat = CatalogueRow.labelColumn

    init(_ label: String, value: String, labelWidth: CGFloat = CatalogueRow.labelColumn) {
        self.label = label
        self.value = value
        self.labelWidth = labelWidth
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(label)
                .catalogueLabel()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: labelWidth, alignment: .leading)
            Text(value)
                .font(Typography.value)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 11)
    }
}

/// Compact vs linear selection. One voice: ink is the choice, hairline and
/// muted ink are the rest. Compact controls invert (fill ink, paper text);
/// rows and rails raise ink and mute what is not chosen. No checkmark.
enum CatalogueChoice {
    static func ink(_ on: Bool) -> Color { on ? Palette.ink : Palette.inkMuted }
    static func rule(_ on: Bool) -> Color { on ? Palette.ink : Palette.hairline }
}

/// Trailing meta on a tappable row (provenance, kind). Selected, it inverts
/// like a `TagChip`; idle, it is a catalogue label.
struct CatalogueMark: View {
    let text: String
    var isSelected: Bool = false

    var body: some View {
        Text(text)
            .font(Typography.label)
            .tracking(Typography.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(isSelected ? Palette.paper : Palette.inkMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, isSelected ? 8 : 0)
            .padding(.vertical, isSelected ? 4 : 0)
            .background {
                Capsule().fill(isSelected ? Palette.ink : Color.clear)
            }
            .animation(Motion.quick, value: isSelected)
    }
}

/// Rows with hairlines between them, never around them.
struct CatalogueRows<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                }
                content(item)
            }
        }
    }
}
