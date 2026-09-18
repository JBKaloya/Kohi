import SwiftUI

/// A recipe in Mine or Reference: name, compact parameters, provenance as the
/// trailing mark so the chosen row can invert it.
struct RecipeRowView: View {
    let recipe: Recipe
    var provenance: String = ""
    var attribution: String = ""
    var scaledFrom: String = ""
    var isSelected: Bool = false
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
                            CatalogueMark(text: provenance, isSelected: isSelected)
                                .multilineTextAlignment(.trailing)
                        }
                        if !attribution.isEmpty {
                            Text(attribution)
                                .font(Typography.tag)
                                .foregroundStyle(Palette.inkMuted)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(1)
                        }
                    }
                    .frame(width: 110, alignment: .trailing)
                }
                Rectangle().fill(CatalogueChoice.rule(isSelected)).frame(height: 1)
            }
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(Motion.quick, value: isSelected)
    }
}
