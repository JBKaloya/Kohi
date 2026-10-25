import SwiftUI

/// The Kohi card: a small landscape (the ground of the origin, the notes, the sky of the
/// altitude, the pack symbol in relief), a paper label, and the origin sticker on its corner.
/// Tile and fiche share one gabarit: every measure is a share of the card's width.
struct KohiCard: View {
    let content: KohiCardContent
    let density: CardDensity
    let width: CGFloat
    var layout: CardLayout = .label
    /// The rendered ground. Nil shows the paper until it arrives.
    var backdrop: CGImage?
    var textTone: CardBackdrop.TextTone = .ink
    /// Emboss edges drawn apart so the light can follow the tilt (fiche only).
    var edges: SymbolLayer.EmbossEdges?
    /// −1…1 on each axis.
    var tilt: CGSize = .zero

    private static let labelPaper = Color(red: 0xFB / 255, green: 0xF8 / 255, blue: 0xF2 / 255)

    private var height: CGFloat { width / CardTileLayout.aspectRatio }
    private var corner: CGFloat { width * 0.05 }
    private func w(_ share: CGFloat) -> CGFloat { width * share }

    var body: some View {
        ZStack {
            ground
            switch layout {
            case .label: labelLayout
            case .fullBleed: bleedLayout
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Ground

    @ViewBuilder
    private var ground: some View {
        if let backdrop {
            ZStack {
                Image(decorative: backdrop, scale: 1)
                    .resizable()
                    .interpolation(.high)
                if let edges {
                    let shift = CGFloat(edges.offset) * width / CGFloat(backdrop.width)
                    Image(decorative: edges.highlight, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .offset(x: -tilt.width * shift, y: -tilt.height * shift)
                        .blendMode(.screen)
                        .opacity(0.55)
                    Image(decorative: edges.shadow, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .offset(x: tilt.width * shift, y: tilt.height * shift)
                        .blendMode(.multiply)
                        .opacity(0.50)
                }
            }
            .frame(width: width, height: height)
        } else {
            Palette.paper
        }
    }

    // MARK: - Label

    private var labelLayout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            label
                .padding(.horizontal, w(0.05))
                .padding(.bottom, w(0.05))
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !content.roaster.isEmpty {
                roasterLine
            }
            if !content.title.isEmpty {
                Text(content.title)
                    .font(.custom(AppFonts.angustaDemiBold, size: titleSize))
                    .foregroundStyle(titleColor)
                    .lineLimit(density == .tile ? 2 : 3)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, content.roaster.isEmpty ? 0 : w(0.014))
            }
            if content.hasPlaceLine {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
                    .padding(.top, w(0.026))
                    .padding(.bottom, w(0.022))
                placeLine(size: density == .tile ? w(0.04) : w(0.035))
            }
            if density == .detail {
                detailLines
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, w(0.04))
        .padding(.horizontal, w(0.044))
        .padding(.bottom, w(0.042))
        .background {
            RoundedRectangle(cornerRadius: w(0.022), style: .continuous)
                .fill(Self.labelPaper)
                .shadow(color: Color(red: 40 / 255, green: 28 / 255, blue: 16 / 255).opacity(0.18), radius: w(0.004), x: 0, y: w(0.003))
        }
        .overlay {
            RoundedRectangle(cornerRadius: w(0.022), style: .continuous)
                .strokeBorder(Palette.ink.opacity(0.08), lineWidth: 1)
        }
        .overlay(alignment: content.stickerOnRight ? .topTrailing : .topLeading) {
            if let sticker = content.sticker {
                stickerImage(sticker, share: density == .tile ? 0.40 : 0.32)
                    .offset(
                        x: (content.stickerOnRight ? 1 : -1) * w(0.03),
                        y: -(density == .tile ? w(0.26) : w(0.21))
                    )
            }
        }
    }

    private var roasterLine: some View {
        let size = density == .tile ? w(0.034) : w(0.03)
        let hasSticker = content.sticker != nil
        return Text(content.roaster.uppercased())
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .tracking(size * 0.14)
            .foregroundStyle(Palette.inkMuted)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: hasSticker && !content.stickerOnRight ? .trailing : .leading)
            .padding(.trailing, hasSticker && content.stickerOnRight ? w(0.28) : 0)
            .padding(.leading, hasSticker && !content.stickerOnRight ? w(0.30) : 0)
    }

    @ViewBuilder
    private var detailLines: some View {
        if content.hasProcessLine {
            Text([content.process, content.variety].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: w(0.035)))
                .foregroundStyle(Palette.inkMuted)
                .padding(.top, w(0.006))
        }
        if !content.notes.isEmpty {
            VStack(alignment: .leading, spacing: w(0.008)) {
                Text("Notes".uppercased())
                    .font(.system(size: w(0.024), weight: .medium, design: .monospaced))
                    .tracking(w(0.024) * 0.14)
                    .foregroundStyle(Palette.inkMuted)
                Text(content.notes.joined(separator: " · "))
                    .font(.system(size: w(0.035)))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, w(0.024))
        }
        Text(content.footer)
            .font(.system(size: w(0.023), weight: .medium, design: .monospaced))
            .tracking(w(0.023) * 0.12)
            .foregroundStyle(Palette.inkMuted)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .padding(.top, w(0.03))
    }

    // MARK: - Full bleed

    private var bleedLayout: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                if !content.roaster.isEmpty {
                    Text(content.roaster.uppercased())
                        .font(.system(size: density == .tile ? w(0.034) : w(0.03), weight: .medium, design: .monospaced))
                        .tracking(w(0.034) * 0.14)
                        .foregroundStyle(textTone == .paper ? Self.labelPaper.opacity(0.78) : Palette.inkMuted)
                        .lineLimit(1)
                }
                if !content.title.isEmpty {
                    Text(content.title)
                        .font(.custom(AppFonts.angustaDemiBold, size: w(0.14)))
                        .foregroundStyle(bleedInk)
                        .lineLimit(density == .tile ? 3 : 4)
                        .minimumScaleFactor(0.7)
                        .padding(.top, content.roaster.isEmpty ? 0 : w(0.02))
                }
                if content.hasPlaceLine {
                    Text([content.place, content.altitude].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: w(0.038)))
                        .foregroundStyle(bleedInk)
                        .lineLimit(density == .tile ? 1 : 2)
                        .padding(.top, w(0.024))
                }
                if density == .detail, !content.notes.isEmpty {
                    Text(content.notes.joined(separator: " · "))
                        .font(.system(size: w(0.038)))
                        .foregroundStyle(bleedInk)
                        .padding(.top, w(0.01))
                }
            }
            .padding(w(0.06))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let sticker = content.sticker {
                stickerImage(sticker, share: density == .tile ? 0.36 : 0.30)
                    .padding(w(0.04))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }

    private var bleedInk: Color {
        textTone == .paper ? Self.labelPaper : Palette.ink
    }

    // MARK: - Pieces

    private func stickerImage(_ name: String, share: CGFloat) -> some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: w(share), height: w(share))
            .rotationEffect(.degrees(content.stickerRotation))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func placeLine(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if !content.place.isEmpty {
                Text(content.place)
                    .foregroundStyle(Palette.ink)
            }
            if !content.altitude.isEmpty {
                Text(content.place.isEmpty ? content.altitude : " · \(content.altitude)")
                    .foregroundStyle(Palette.inkMuted)
            }
        }
        .font(.system(size: size))
        .lineLimit(density == .tile ? 1 : 2)
        .truncationMode(.tail)
    }

    private var titleSize: CGFloat {
        if density == .tile { return w(0.106) }
        return content.titleUsesSmallSize ? w(0.09) : w(0.104)
    }

    private var titleColor: Color {
        guard let red = content.titleRed, let green = content.titleGreen, let blue = content.titleBlue else {
            return Palette.ink
        }
        return Color(red: red, green: green, blue: blue)
    }

    private var accessibilityText: String {
        var parts = [content.roaster, content.title, content.place, content.altitude]
        if density == .detail {
            parts.append(contentsOf: [content.process, content.variety, content.notes.joined(separator: ", "), content.footer])
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// The field of the card and its label, shown while the full tile is still queued.
/// Never white paper: a waiting tile already has its colours.
struct KohiCardPlaceholder: View {
    let card: CoffeeCard
    let width: CGFloat

    var body: some View {
        let field = CardComposer.shared.placeholderField(for: card)
        KohiCard(
            content: KohiCardContent.make(card, ink: CardFiles.loadStampFile(card.id)),
            density: .tile,
            width: width,
            layout: CardLayout.stored(for: card.id),
            backdrop: field?.image,
            textTone: field?.tone ?? .ink
        )
    }
}
