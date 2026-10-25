import SwiftUI

/// One card lying on the paper. No frame, no label, no chrome: the object and
/// its shadow are the whole tile.
struct CardTile: View {
    let card: CoffeeCard
    let width: CGFloat
    let namespace: Namespace.ID
    let action: () -> Void

    @Environment(CardStore.self) private var store
    @Environment(CardLookStore.self) private var looks
    @Environment(StampLibrary.self) private var stamps
    /// 0 while the card is still in the air, 1 once it is lying on the paper.
    @State private var landing: Double = 1
    @State private var touchdown = 0
    @State private var kohiImage: CGImage?

    private var face: CardLook { looks.resolved(card) }

    var body: some View {
        Button(action: action) {
            Group {
                if face == .scan {
                    CardImageView(card: card, targetWidth: width, aspect: CardTileLayout.aspectRatio)
                } else {
                    ZStack {
                        if let kohiImage {
                            Image(decorative: kohiImage, scale: 3)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: width, height: width / CardTileLayout.aspectRatio)
                                .transition(.opacity)
                        } else {
                            KohiCardPlaceholder(card: card, width: width)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .shadow(
                color: Palette.cardShadow
                    .opacity(Motion.Tile.settle(Motion.Tile.shadowOpacity, landing)),
                radius: width * Motion.Tile.settle(Motion.Tile.shadowRadius, landing),
                x: 0,
                y: width * Motion.Tile.settle(Motion.Tile.shadowDrop, landing)
            )
        }
        .buttonStyle(PressStyle(scale: Motion.Tile.pressScale))
        .matchedTransitionSource(id: card.id, in: namespace)
        .scaleEffect(1 + Motion.Tile.landScale * (1 - landing))
        .offset(y: -Motion.Tile.landLift * (1 - landing))
        .opacity(Motion.Tile.settle((air: Motion.Tile.landOpacity, rest: 1), landing))
        .haptic(.landing, trigger: touchdown)
        .animation(Motion.quick, value: kohiImage == nil)
        .task(id: card.id) {
            guard store.landingCardID == card.id else {
                landing = 1
                return
            }
            landing = 0
            withAnimation(Motion.land) { landing = 1 }
            try? await Task.sleep(for: Motion.Tile.touchdown)
            touchdown += 1
        }
        .task(id: "measure-\(card.id)-\(CardFiles.scanRevision(card.id))") {
            await InkStampPipeline.backfill(
                cardID: card.id,
                library: stamps,
                roasterName: card.roaster
            )
        }
        .task(id: kohiTask) {
            guard face == .kohi else {
                kohiImage = nil
                return
            }
            kohiImage = await CardComposer.shared.tile(for: card)
        }
    }

    /// Changes when the coffee, the stamp, or the face changes, and not otherwise.
    private var kohiTask: String {
        let token = CardComposer.shared.token(for: card)
        return "\(face.rawValue)-\(looks.layout(for: card.id).rawValue)-\(stamps.revision(for: card.id))-\(token)"
    }
}
