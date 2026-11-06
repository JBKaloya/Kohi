import SwiftUI

/// The way a brew starts. Drag the sheet up by the footer. Past
/// `Motion.Lift.threshold` the arrow fills and letting go commits;
/// short of it, the sheet drops back. VoiceOver gets a Brew action,
/// because a swipe has no location a blind user can find.
struct SwipeToStart: View {
    @Binding var lift: CGFloat
    var title: String = Copy.swipeToBrew
    var armedTitle: String = Copy.releaseToBrew
    var onCommit: () -> Void

    @State private var armed = false
    @State private var armedTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 17

    private var progress: CGFloat {
        min(1, max(0, lift / Motion.Lift.threshold))
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(armed ? Palette.ink : Palette.paper)
                .frame(width: 40, height: 40)
                .background(armed ? Palette.paper : Color.clear, in: Circle())
                .scaleEffect(armed ? 1.08 : 1)
                .offset(y: armed || lift > 0 ? 0 : (reduceMotion ? 0 : -2))
                .animation(Motion.roll, value: armed)
            Text(armed ? armedTitle : title)
                .font(.system(size: titleSize, weight: .medium))
                .foregroundStyle(Palette.paper)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.bottom, 28)
        .background(Palette.ink)
        .gesture(drag)
        .haptic(.armed, trigger: armedTick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAction(named: "Brew") {
            onCommit()
        }
        .onChange(of: lift) { _, new in
            let now = new >= Motion.Lift.threshold
            if now, !armed { armedTick += 1 }
            armed = now
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { gesture in
                let dy = -gesture.translation.height
                let threshold = Motion.Lift.threshold
                if dy <= 0 {
                    lift = dy * 0.15
                } else if dy < threshold {
                    lift = dy
                } else {
                    lift = threshold + (dy - threshold) * Motion.Lift.rubber
                }
            }
            .onEnded { _ in
                let commit = lift >= Motion.Lift.threshold
                if commit {
                    onCommit()
                } else {
                    withAnimation(reduceMotion ? nil : Motion.Lift.giveUp) { lift = 0 }
                }
            }
    }
}
