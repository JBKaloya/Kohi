import SwiftUI

/// A label facing a value, with the rules between them drawn by the list that
/// holds it. The tombstone grammar from `CaptionBlock`, available to the
/// sheets that need to read like it.
struct CatalogueRow: View {
    let label: String
    let value: String
    var labelWidth: CGFloat = 78

    init(_ label: String, value: String, labelWidth: CGFloat = 78) {
        self.label = label
        self.value = value
        self.labelWidth = labelWidth
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(label)
                .catalogueLabel()
                .frame(width: labelWidth, alignment: .leading)
            Text(value)
                .font(Typography.value)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 11)
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
