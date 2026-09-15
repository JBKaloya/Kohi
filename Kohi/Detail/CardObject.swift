import SwiftUI

/// The card as a thing rather than a picture: it sits above the paper and catches
/// the light as you tilt the phone.
struct CardObject: View {
    let card: CoffeeCard
    let width: CGFloat
    var variant: ThumbnailVariant = .poster

    @Environment(\.scenePhase) private var scenePhase
    @State private var tilt = DeviceTilt()

    var body: some View {
        face
            .frame(width: width)
            .rotation3DEffect(
                .degrees(tilt.roll * Motion.Parallax.tilt),
                axis: (x: 0, y: 1, z: 0),
                perspective: Motion.Parallax.perspective
            )
            .rotation3DEffect(
                .degrees(-tilt.pitch * Motion.Parallax.tilt),
                axis: (x: 1, y: 0, z: 0),
                perspective: Motion.Parallax.perspective
            )
            .offset(
                x: tilt.roll * Motion.Parallax.shift,
                y: tilt.pitch * Motion.Parallax.shift
            )
            .shadow(
                color: .black.opacity(0.10),
                radius: width * 0.006,
                x: 0, y: width * 0.003
            )
            .shadow(
                color: Palette.cardShadow,
                radius: width * Motion.Object.shadowRadius,
                x: -tilt.roll * Motion.Parallax.shadowCounterShift,
                y: width * Motion.Object.shadowDrop - tilt.pitch * Motion.Parallax.shadowCounterShift
            )
            .task { tilt.start() }
            .onDisappear { tilt.stop() }
            .onChange(of: scenePhase) { _, phase in
                phase == .active ? tilt.start() : tilt.stop()
            }
    }

    @ViewBuilder
    private var face: some View {
        if tilt.isAvailable {
            CardImageView(card: card, targetWidth: width, variant: variant)
                .overlay { sheen }
                .mask { CardImageView(card: card, targetWidth: width, variant: variant) }
        } else {
            CardImageView(card: card, targetWidth: width, variant: variant)
        }
    }

    /// A soft band of light that slides across the card as you tilt it.
    private var sheen: some View {
        let centre = 0.5 + tilt.roll * Motion.Parallax.sheenTravel / 2
        let half = Motion.Parallax.sheenWidth / 2
        return LinearGradient(
            stops: [
                .init(color: .clear, location: min(max(centre - half, 0), 1)),
                .init(
                    color: .white.opacity(Motion.Parallax.sheenOpacity),
                    location: min(max(centre, 0), 1)
                ),
                .init(color: .clear, location: min(max(centre + half, 0), 1)),
            ],
            startPoint: UnitPoint(x: 0, y: 0.15),
            endPoint: UnitPoint(x: 1, y: 0.85)
        )
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}
