import SwiftUI

/// The Kohi field as the paper, the scan cropped to 4:5 laid on it, the name
/// under it in the card's own tone. The grid's face when it shows scans.
struct HybridCardFace: View {
    let card: CoffeeCard
    let width: CGFloat

    var body: some View {
        let field = CardComposer.shared.placeholderField(for: card)
        let inset = width * 0.78
        ZStack(alignment: .top) {
            if let field {
                Image(decorative: field.image, scale: 1)
                    .resizable()
                    .interpolation(.high)
            } else {
                Palette.paperShade
            }
            VStack(spacing: width * 0.04) {
                CardImageView(card: card, targetWidth: inset, aspect: 4.0 / 5.0, fills: true)
                    .frame(width: inset)
                    .clipShape(RoundedRectangle(cornerRadius: width * 0.025, style: .continuous))
                Text(card.name)
                    .font(.system(size: max(9, width * 0.06), weight: .medium))
                    .foregroundStyle(field?.tone == .paper ? Palette.paper : Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, width * 0.08)
            }
            .padding(.top, width * 0.08)
        }
        .frame(width: width, height: width / CardTileLayout.aspectRatio)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.05, style: .continuous))
    }
}
