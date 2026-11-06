import SwiftUI

/// A switch whose track carries the state. Off is a well with a grey thumb;
/// on is an ink track with a paper thumb. The thumb lengthens along its
/// travel and thins across it, so the amount of it stays the same.
///
/// A drag flips the switch as the thumb passes the middle. A press that
/// never travelled is a tap, and a tap toggles.
struct LiquidToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        LiquidSwitch(configuration: configuration)
    }
}

extension ToggleStyle where Self == LiquidToggleStyle {
    static var liquid: LiquidToggleStyle { LiquidToggleStyle() }
}

private struct LiquidSwitch: View {
    var configuration: ToggleStyleConfiguration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var x: CGFloat = 4
    @State private var stretch: CGFloat = 1
    @State private var origin: CGFloat?
    @State private var moved = false

    private let trackWidth: CGFloat = 80
    private let thumb: CGFloat = 36
    private let pad: CGFloat = 4
    private var open: CGFloat { trackWidth - thumb - pad }
    private var shut: CGFloat { pad }
    private var mid: CGFloat { (shut + open) / 2 }

    var body: some View {
        HStack(spacing: 12) {
            configuration.label
            Capsule()
                .fill(configuration.isOn ? Palette.ink : Palette.ink.opacity(0.08))
                .frame(width: trackWidth, height: thumb + pad * 2)
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(configuration.isOn ? Palette.paper : Palette.ink.opacity(0.24))
                        .frame(width: thumb, height: thumb)
                        .scaleEffect(x: stretch, y: 1 / max(stretch, 0.01))
                        .offset(x: x)
                }
                .contentShape(Capsule())
                .gesture(drag)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            configuration.isOn.toggle()
        }
        .onAppear { x = configuration.isOn ? open : shut }
        .onChange(of: configuration.isOn) { _, on in
            guard origin == nil else { return }
            if reduceMotion {
                x = on ? open : shut
            } else {
                withAnimation(Motion.thumb) { x = on ? open : shut }
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if origin == nil {
                    origin = x
                    moved = false
                }
                let next = min(open, max(shut, (origin ?? shut) + gesture.translation.width))
                if abs(next - x) > 0.4 { moved = true }
                x = next
                let speed = abs(gesture.velocity.width)
                let lengthen = 1 + min(
                    Motion.Thumb.stretchCap,
                    speed / Motion.Thumb.stretchDivisor
                ) * Motion.Thumb.stretch
                stretch = reduceMotion ? 1 : lengthen
                let past = next > mid
                if past != configuration.isOn {
                    configuration.isOn = past
                }
            }
            .onEnded { _ in
                stretch = 1
                if !moved {
                    configuration.isOn.toggle()
                }
                origin = nil
                let on = configuration.isOn
                if reduceMotion {
                    x = on ? open : shut
                } else {
                    withAnimation(Motion.thumb) { x = on ? open : shut }
                }
            }
    }
}
