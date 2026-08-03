import SwiftUI

/// One card lying on the paper. No frame, no label, no chrome: the object and
/// its shadow are the whole tile.
struct CardTile: View {
    let card: CoffeeCard
    let width: CGFloat
    let namespace: Namespace.ID
    let action: () -> Void

    @Environment(CardStore.self) private var store
    @State private var isPressed = false
    /// 0 while the card is still in the air, 1 once it is lying on the paper.
    @State private var landing: Double = 1
    @State private var touchdown = 0

    var body: some View {
        Button(action: action) {
            CardImageView(card: card, targetWidth: width)
                // The shadow is what sells the descent: wide and soft while the
                // card is above the paper, tight and close once it settles.
                .shadow(
                    color: Palette.cardShadow
                        .opacity(Motion.Tile.settle(Motion.Tile.shadowOpacity, landing)),
                    radius: width * Motion.Tile.settle(Motion.Tile.shadowRadius, landing),
                    x: 0,
                    y: width * Motion.Tile.settle(Motion.Tile.shadowDrop, landing)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? Motion.Tile.pressScale : 1)
        .animation(Motion.quick, value: isPressed)
        .onLongPressGesture(minimumDuration: 0, pressing: { isPressed = $0 }, perform: {})
        .matchedTransitionSource(id: card.id, in: namespace)
        .scaleEffect(1 + Motion.Tile.landScale * (1 - landing))
        .offset(y: -Motion.Tile.landLift * (1 - landing))
        .opacity(Motion.Tile.settle((air: Motion.Tile.landOpacity, rest: 1), landing))
        .haptic(.landing, trigger: touchdown)
        .task(id: card.id) {
            guard store.landingCardID == card.id else {
                landing = 1
                return
            }
            landing = 0
            withAnimation(Motion.land) { landing = 1 }
            // The spring overshoots for a while after this; the tap is meant to
            // coincide with first contact, not with the end of the animation.
            try? await Task.sleep(for: Motion.Tile.touchdown)
            touchdown += 1
        }
    }
}
