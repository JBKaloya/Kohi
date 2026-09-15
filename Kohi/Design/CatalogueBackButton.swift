import SwiftUI

/// Explicit back control for zoom transitions, where the edge swipe is easy
/// to miss. Catalogue label, 44 pt target, no container.
struct CatalogueBackButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .catalogueLabel()
            }
            .foregroundStyle(Palette.inkMuted)
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
