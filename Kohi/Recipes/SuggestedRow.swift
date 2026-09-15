import SwiftUI

/// One coffee, one suggested recipe. Title is the coffee, not the recipe.
struct SuggestedRow: View {
    let suggestion: RecipeSuggestion
    var title: String
    var compactLine: String
    var scaledFrom: String = ""
    var onOpen: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(title)
                            .font(Typography.value)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(suggestion.provenance.listLabel)
                            .catalogueLabel()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Text(compactLine)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if !scaledFrom.isEmpty {
                        Text(scaledFrom)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
