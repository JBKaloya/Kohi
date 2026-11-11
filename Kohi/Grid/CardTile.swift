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
    @State private var placeholder: CardComposer.Placeholder?
    @Environment(\.displayScale) private var displayScale

    private var face: CardLook { looks.resolved(card) }

    var body: some View {
        Button(action: action) {
            Group {
                if face == .scan {
                    HybridCardFace(card: card, width: width)
                } else {
                    ZStack {
                        if let kohiImage {
                            Image(decorative: kohiImage, scale: 1)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: width, height: width / CardTileLayout.aspectRatio)
                                .transition(.opacity)
                        } else if let placeholder {
                            KohiCard(
                                content: placeholder.content,
                                density: .tile,
                                width: width,
                                layout: looks.layout(for: card.id),
                                backdrop: placeholder.field,
                                textTone: placeholder.tone
                            )
                            .transition(.opacity)
                        } else {
                            RoundedRectangle(cornerRadius: width * 0.05, style: .continuous)
                                .fill(Palette.hairline.opacity(0.4))
                                .frame(width: width, height: width / CardTileLayout.aspectRatio)
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
            let composer = CardComposer.shared
            let pixels = Int((width / CardTileLayout.aspectRatio * displayScale).rounded(.up))
            if let cached = await composer.cachedDisplayTile(for: card, maxPixel: pixels) {
                kohiImage = cached
                return
            }
            if kohiImage == nil {
                placeholder = await composer.placeholder(for: card)
            }
            guard !Task.isCancelled else { return }
            if let drawn = await composer.displayTile(for: card, maxPixel: pixels) {
                kohiImage = drawn
            }
        }
    }

    /// Cheap on purpose: it runs on every body. The token itself is worked out off the main thread.
    private var kohiTask: String {
        var fields = Hasher()
        fields.combine(card.name)
        fields.combine(card.roaster)
        fields.combine(card.country)
        fields.combine(card.region)
        fields.combine(card.producer)
        fields.combine(card.farm)
        fields.combine(card.washStation)
        fields.combine(card.altitude)
        fields.combine(card.variety)
        fields.combine(card.process)
        fields.combine(card.tastingNotes)
        fields.combine(card.roastLevel)
        fields.combine(card.isDecaf)
        fields.combine(card.roastedOn)
        fields.combine(card.createdAt)
        return [
            face.rawValue,
            looks.layout(for: card.id).rawValue,
            String(stamps.revision(for: card.id)),
            card.id.uuidString,
            String(fields.finalize()),
            String(Int(width)),
        ].joined(separator: "-")
    }
}
