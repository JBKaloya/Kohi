import SwiftUI

/// A hairline frame around labelled edit cells. Never used in reading views,
/// never nested, never more than six cells.
struct FieldGroup<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !title.isEmpty {
                Text(title).catalogueLabel()
            }
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(14)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Palette.hairline, lineWidth: 1)
            )
        }
    }
}
