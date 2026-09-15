import SwiftUI

/// A recipe in Mine or Reference: name, compact parameters, provenance in 86 pt.
struct RecipeRowView: View {
    let recipe: Recipe
    var provenance: String = ""
    var attribution: String = ""
    var scaledFrom: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.name)
                            .font(Typography.value)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)

                        Text(recipe.compactLine)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if !scaledFrom.isEmpty {
                            Text(scaledFrom)
                                .font(Typography.tag)
                                .foregroundStyle(Palette.inkMuted)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 4) {
                        if !provenance.isEmpty {
                            Text(provenance)
                                .catalogueLabel()
                                .multilineTextAlignment(.trailing)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        if !attribution.isEmpty {
                            Text(attribution)
                                .font(Typography.tag)
                                .foregroundStyle(Palette.inkMuted)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(1)
                        }
                    }
                    .frame(width: 86, alignment: .trailing)
                }
                Rectangle().fill(Palette.hairline).frame(height: 1)
            }
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
