import SwiftUI

/* ══ Liquid toggle ════════════════════════════════════════
   Ported from Bencho's "Liquid toggle" (MIT, bencho.dev/licence).
   The original is React + framer-motion + CSS; this is the same
   geometry, the same springs and the same reasoning in SwiftUI.
   Notes that only described a CSS or Framer mechanism (the
   `scale` vs `transform` order, `left: 0` on inline elements,
   pointer capture throwing) have no SwiftUI equivalent and are
   not carried over.

   ── tokens ──────────────────────────────────────────────
   Bencho's --ink and --fill-on are Palette.ink. --fill-slab and
   --card, the light end of the ramp, are Palette.paperShade.
   --board is Palette.paper. --pane-edge is Palette.hairline. They
   live as constants on the component so nothing leaks out.
   --nod-r belongs to Bencho's node card, not to this block. */
struct LiquidToggle: View {
    @Binding var isOn: Bool
    let label: String
    /// The track's height. Everything else is derived from it, so the
    /// proportions of the 46 px original hold at any size.
    var height: CGFloat = 46
    /// How much the droplet lengthens into its own travel, 0...100.
    var stretch: Double = 36
    /// How fast it crosses, 0...100.
    var speed: Double = 50

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /* ── NO GOO. There is nothing left for it to merge. ──────
       The goo filter existed to fuse the thumb with a straggler
       running behind it. With the straggler gone it had one
       circle to work on, and a blur-then-threshold pass over a
       single round shape cannot improve it, it can only soften
       the edge. A plain circle is drawn at device resolution and
       stays crisp; the stretch is a transform, so nothing here
       needs the pass. That is why there is no #liq-goo. */

    /* the switch's own colours, the two ends of the fill's ramp */
    private static let slab = Palette.paperShade
    private static let fillOn = Palette.ink
    private static let board = Palette.paper
    private static let edge = Palette.hairline

    /* ── OFF IS THE SLAB, NOT A GREY ─────────────────────────
       The track carries the state and the dot is along for the
       ride. OFF: slab track, a grey dot mixed toward it. ON is
       the inversion, ink track and slab dot. The grey is a mix
       and not an alpha so the droplet stays opaque. */
    private static let offThumb = slab.mix(with: fillOn, by: 0.19)

    /* ── the droplet, and the air round it ─────────────────────
       36 in a 46 track, so five pixels of track show all the way
       round. 40 with three is a thumb pressed into its slot; five
       is a droplet sitting in one.

       PAD is the same five, and it has to be: the inset at the
       ends and the inset above and below are the same gap seen
       twice. */
    private var track: CGFloat { height * 2 }
    private var thumb: CGFloat { height * 36 / 46 }
    private var pad: CGFloat { (height - thumb) / 2 }

    /* the two ends of the thumb's travel, and the line between */
    private var shutX: CGFloat { pad }
    private var openX: CGFloat { track - thumb - pad }
    private var midX: CGFloat { (shutX + openX) / 2 }
    private var rest: CGFloat { isOn ? openX : shutX }

    /* ── ONE POSITION, WRITTEN TWO WAYS ──────────────────────
       A drag writes it directly, a release animates it. `nil`
       means "wherever isOn says". */
    @State private var x: CGFloat?
    /* held, so the settling spring keeps out of the way while a
       finger owns the thumb */
    @State private var held = false
    @State private var grab: CGFloat?
    @State private var moved = false
    /* the drag's own lengthening, eased by a spring like Bencho's
       `useSpring(velocity)` */
    @State private var dragLengthen: CGFloat = 1
    @State private var flips = 0

    var body: some View {
        let position = x ?? rest
        ZStack(alignment: .leading) {
            Capsule(style: .circular)
                .fill(isOn ? Self.fillOn : Self.slab)
                /* the ground here is paper, not a darker board, so
                   the slab needs its hairline to read as an object */
                .overlay(Capsule(style: .circular).strokeBorder(Self.edge, lineWidth: isOn ? 0 : 1))
                .animation(colour, value: isOn)
            Circle()
                .fill(isOn ? Self.board : Self.offThumb)
                .frame(width: thumb, height: thumb)
                /* the colour is the only thing that eases; the position
                   belongs to the spring, and an ease on the same change
                   would lag the droplet behind the finger */
                .animation(colour, value: isOn)
                .modifier(Droplet(
                    x: position,
                    dragLengthen: dragLengthen,
                    held: held,
                    shutX: shutX,
                    openX: openX,
                    stretch: stretch,
                    /* the press swell, the touch twin of Bencho's hover:
                       about the droplet's own centre, position untouched */
                    swell: held ? 1.035 : 1
                ))
        }
        .frame(width: track, height: height)
        .contentShape(Capsule())
        .gesture(drag)
        .haptic(.tap, trigger: flips)
        /* VoiceOver still gets a plain switch */
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityAction { flip(to: !isOn) }
        .onAppear { if x == nil { x = rest } }
        .onChange(of: isOn) { _, _ in
            guard !held else { return }
            withAnimation(settle) { x = rest }
        }
    }

    private var colour: Animation {
        .easeInOut(duration: reduceMotion ? 0.16 : 0.42)
    }

    /* ── how the thumb lands when it is let go ───────────────
       170/21.5 is zeta 0.87: it still arrives with a hint of
       give, and the hint is the whole of it. 220/20 (zeta 0.71)
       was a switch throwing itself to the other side.

       Damping is a constant. A switch is not a thing anybody
       wants a bounce dial on. Speed still moves, because how fast
       a switch crosses is a real question. */
    private var settle: Animation {
        .interpolatingSpring(
            mass: 0.9,
            stiffness: 170 - (50 - speed) * 1.1,
            damping: 21.5
        )
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !held {
                    held = true
                    moved = false
                    grab = nil
                    x = x ?? rest
                }
                /* ── NO OFFSET YET. It is taken at the first MOVE. ──
                   Deciding it at the press made an off-thumb press
                   teleport the droplet under the finger in a single
                   frame. Taken here, the first move asks for exactly
                   the position it already has, and every one after it
                   tracks the delta. No press can make it jump. */
                let at = value.location.x
                let current = x ?? rest
                if grab == nil { grab = at - current }
                let next = min(openX, max(shutX, at - (grab ?? 0)))
                if abs(next - current) > 0.4 { moved = true }
                x = next
                /* ── the divisor is the whole tuning ───────────────
                   Dividing by 600 puts the peak at about 1.09 at the
                   default, and the cap at 0.4 leaves the top of the
                   knob somewhere to go. */
                let target = 1 + min(0.4, abs(value.velocity.width) / 600) * CGFloat(stretch / 100)
                withAnimation(.interpolatingSpring(mass: 0.6, stiffness: 380, damping: 34)) {
                    dragLengthen = target
                }
                /* it flips as it passes the middle rather than on
                   release, so the track answers under your finger */
                let past = next > midX
                if past != isOn { flip(to: past) }
            }
            .onEnded { _ in
                held = false
                grab = nil
                withAnimation(.interpolatingSpring(mass: 0.6, stiffness: 380, damping: 34)) {
                    dragLengthen = 1
                }
                /* A press that never travelled is a TAP, and a tap
                   toggles. The switch has to keep working as one. */
                if !moved {
                    flip(to: !isOn)
                } else {
                    withAnimation(settle) { x = rest }
                }
            }
    }

    private func flip(to value: Bool) {
        flips += 1
        isOn = value
    }
}

/* ── ONE BODY. STRETCH, NOT A TRAIL. ─────────────────────
   The one droplet lengthens along its direction of travel and
   thins across it, so the elasticity is in the shape of the thing
   moving rather than in something left behind. Area is kept:
   scaleY is 1/scaleX.

   While held, the stretch comes from the drag's velocity. While
   the settle spring carries it, SwiftUI does not hand out a
   velocity, so the stretch is read from where the droplet is on
   its travel instead: nothing at either end, most at the middle,
   which is where the spring is fastest. The 0.25 makes that peak
   about 1.09 at the default, the same as the drag. */
private struct Droplet: ViewModifier, Animatable {
    var x: CGFloat
    var dragLengthen: CGFloat
    let held: Bool
    let shutX: CGFloat
    let openX: CGFloat
    let stretch: Double
    var swell: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(x, AnimatablePair(dragLengthen, swell)) }
        set {
            x = newValue.first
            dragLengthen = newValue.second.first
            swell = newValue.second.second
        }
    }

    func body(content: Content) -> some View {
        let travel = max(1, openX - shutX)
        let progress = min(1, max(0, (x - shutX) / travel))
        let crossing = 1 + 0.25 * sin(.pi * progress) * CGFloat(stretch / 100)
        let lengthen = held ? dragLengthen : crossing
        content
            .scaleEffect(x: lengthen * swell, y: swell / lengthen)
            .offset(x: x)
    }
}
