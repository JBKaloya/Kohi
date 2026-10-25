import SwiftUI

/// The scan, or the Kohi card, in the seat at the top of the fiche.
/// A tap turns it over. Pinch and double-tap stay on the scan.
struct CardFaceStage: View {
    let card: CoffeeCard
    let scanWidth: CGFloat
    let kohiWidth: CGFloat
    let look: CardLook
    var layout: CardLayout = .label
    var mark: MarkSource?
    var ink: StampFile?
    let onFlip: (CardLook) -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @State private var angle: Double = 0
    @State private var flips = 0
    @State private var rendered: CardBackdrop.Rendered?
    @State private var renderedKey = ""
    @State private var tilt = DeviceTilt()

    var body: some View {
        face
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.55
            )
            .animation(Motion.gentle, value: look)
            .haptic(.detectionLock, trigger: flips)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(look == .scan ? "Scan" : "Kohi card")
            .accessibilityHint("Tap to turn the card over")
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var face: some View {
        if look == .scan {
            CardObject(card: card, width: scanWidth) {
                turn(to: .kohi)
            }
        } else {
            let art = CardArt.make(card, ink: ink)
            let treatment = ink?.treatment(draw: art.symbolDraws[4]) ?? .none
            let key = renderKey(art: art)
            let waiting = rendered == nil ? CardComposer.shared.placeholderField(for: card) : nil
            KohiCard(
                content: KohiCardContent.make(card, art: art),
                density: .detail,
                width: kohiWidth,
                layout: layout,
                backdrop: rendered?.image ?? waiting?.image,
                textTone: rendered?.textTone ?? waiting?.tone ?? .ink,
                edges: rendered?.edges,
                tilt: CGSize(width: tilt.roll, height: -tilt.pitch)
            )
            .contentShape(Rectangle())
            .onTapGesture { turn(to: .scan) }
            .task(id: key) {
                await render(art: art, treatment: treatment, key: key)
            }
            .task { if treatment == .emboss { tilt.start() } }
            .onDisappear { tilt.stop() }
            .onChange(of: scenePhase) { _, phase in
                guard treatment == .emboss else { return }
                phase == .active ? tilt.start() : tilt.stop()
            }
        }
    }

    private func renderKey(art: CardArt) -> String {
        let symbol = CardComposer.symbolSignature(ink, art: art)
        let token = KohiCardContent.make(card, art: art).cacheToken(symbol: symbol, layout: layout, density: .detail)
        return "\(token)-\(Int(kohiWidth))"
    }

    private func render(art: CardArt, treatment: SymbolTreatment, key: String) async {
        guard renderedKey != key else { return }
        let scale = max(2, displayScale)
        let size = CGSize(width: kohiWidth * scale, height: kohiWidth * scale / CardTileLayout.aspectRatio)
        let mark = mark
        let result = await Task.detached(priority: .userInitiated) {
            CardBackdrop.render(
                art,
                mark: treatment == .none ? nil : mark,
                treatment: treatment,
                size: size,
                separateEmbossEdges: treatment == .emboss
            )
        }.value
        guard !Task.isCancelled else { return }
        withAnimation(Motion.quick) {
            rendered = result
        }
        renderedKey = key
    }

    private func turn(to next: CardLook) {
        flips += 1
        withAnimation(Motion.gentle) { angle = 90 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            onFlip(next)
            angle = -90
            withAnimation(Motion.gentle) { angle = 0 }
        }
    }
}
