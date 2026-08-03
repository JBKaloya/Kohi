import SwiftUI

/// The card as a thing rather than a picture: it sits above the paper, catches
/// the light as you tilt the phone, and can be turned over to read its back.
struct CardObject: View {
    let card: CoffeeCard
    let width: CGFloat

    @Environment(\.scenePhase) private var scenePhase
    @State private var tilt = DeviceTilt()

    /// Turns, in half revolutions. 0 is the front, 1 the back, and the value in
    /// between is where a drag has got to.
    @State private var turns: Double = 0
    /// Where the current drag started, so a turn can be interrupted mid flight.
    @State private var turnStart: Double = 0
    @State private var isTurning = false
    @State private var flipTrigger = 0

    private var angle: Double { turns * 180 }
    private var showsBack: Bool {
        let normalised = (turns.truncatingRemainder(dividingBy: 2) + 2)
            .truncatingRemainder(dividingBy: 2)
        return normalised > 0.5 && normalised < 1.5
    }

    var body: some View {
        face
            .frame(width: width)
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 0, y: 1, z: 0),
                perspective: Motion.Flip.perspective
            )
            // Tilt is applied outside the flip so the two do not multiply into
            // something neither of them asked for.
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
                color: Palette.cardShadow,
                radius: width * Motion.Object.shadowRadius,
                // The shadow lags the card, which is what makes the card look
                // like it is above the paper rather than printed on it.
                x: -tilt.roll * Motion.Parallax.shadowCounterShift,
                y: width * Motion.Object.shadowDrop - tilt.pitch * Motion.Parallax.shadowCounterShift
            )
            .contentShape(.rect)
            // Simultaneous, not exclusive: the card sits in a scroll view, and
            // claiming the drag outright would mean you could not scroll the
            // page from the largest thing on it. The gesture ignores anything
            // that is mostly vertical, so the two do not fight.
            .simultaneousGesture(turnGesture)
            .haptic(.flip, trigger: flipTrigger)
            .onChange(of: showsBack) { _, _ in flipTrigger += 1 }
            .task {
                tilt.start()
                #if DEBUG
                // The back cannot otherwise be reached without a finger.
                if DebugHooks.showsCardBack { turns = 1 }
                #endif
            }
            .onDisappear { tilt.stop() }
            .onChange(of: scenePhase) { _, phase in
                phase == .active ? tilt.start() : tilt.stop()
            }
    }

    @ViewBuilder
    private var face: some View {
        if tilt.isAvailable {
            currentFace
                .overlay { sheen }
                // Masking with the same view keeps the sheen inside the card's
                // own silhouette, so a cut-out card does not catch light on the
                // paper around it. The second load is a memory cache hit.
                .mask { currentFace }
        } else {
            currentFace
        }
    }

    @ViewBuilder
    private var currentFace: some View {
        if showsBack {
            CardBackView(card: card, width: width)
                // Counter-rotated, or the back reads mirrored.
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        } else {
            CardImageView(card: card, targetWidth: width)
        }
    }

    /// A soft band of light that slides across the card as you tilt it. This is
    /// most of what separates "a photo of a card" from "a card".
    ///
    /// The band is a moving gradient stop rather than an offset shape, so it has
    /// no edges of its own to give the trick away. `face` leaves it out entirely
    /// where there is no device motion, rather than parking a highlight in the
    /// middle of the card forever.
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
            // Slightly off vertical, the way a light source above and to one
            // side would actually fall across a card held in one hand.
            startPoint: UnitPoint(x: 0, y: 0.15),
            endPoint: UnitPoint(x: 1, y: 0.85)
        )
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    /// Horizontal only, so it does not fight the scroll under it or the
    /// downward drag that dismisses the screen.
    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: Motion.Flip.minimumDrag)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if !isTurning {
                    isTurning = true
                    turnStart = turns
                }
                turns = turnStart + value.translation.width / Motion.Flip.dragDistance
            }
            .onEnded { _ in
                guard isTurning else { return }
                isTurning = false
                // Past the threshold the turn completes; short of it the card
                // falls back to the face it came from.
                let travelled = turns - turnStart
                let settled: Double
                if travelled > Motion.Flip.threshold {
                    settled = turnStart + 1
                } else if travelled < -Motion.Flip.threshold {
                    settled = turnStart - 1
                } else {
                    settled = turnStart
                }
                withAnimation(Motion.Flip.animation) { turns = settled }
            }
    }
}
