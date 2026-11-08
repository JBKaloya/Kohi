import SwiftUI

/// A slider whose value has mass. The handle stays under the finger.
/// The fill is a second spring behind it: a fast drag throws it past the
/// handle, into the end stop, and rocks it back. The leading edge leans
/// in the direction of travel, so the lag reads as liquid rather than latency.
///
/// Taste scores stay whole numbers. The score follows the finger in whole
/// steps, so the number and the radar move with the drag; a tap on the
/// current score clears it.
struct SloshRail: View {
    var label: String
    @Binding var value: Int?
    var enabled = true
    var onChange: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sim = SloshSim(value: 0)
    @State private var running = false
    @State private var lastDate: Date?
    /// The score before the finger came down. The binding follows the finger,
    /// so by the time a tap ends it already holds the tapped score.
    @State private var startValue: Int?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(label)
                .scalingCatalogueLabel()
                .frame(width: 74, alignment: .leading)
            track
            Text(value.map(String.init) ?? "—")
                .font(Typography.tag)
                .foregroundStyle(Palette.ink)
                .frame(width: 18, alignment: .trailing)
                .monospacedDigit()
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value.map(String.init) ?? "not scored")
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            switch direction {
            case .increment: set(min((value ?? -1) + 1, 10))
            case .decrement:
                if let current = value, current > 0 { set(current - 1) }
                else { set(nil) }
            @unknown default: break
            }
        }
        .onAppear { park(at: value) }
        .onChange(of: value) { _, new in
            guard !sim.held else { return }
            let percent = new.map { Double($0) / 10 * 100 }
            if let percent {
                sim.value = percent
                sim.velocity = 0
                if !running { sim.fill = percent }
                wake()
            } else {
                sim.value = 0
                sim.velocity = 0
                wake()
            }
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.well)
                liquid(width: width)
                handle(width: width)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(drag(width: width))
        }
        .frame(height: 40)
        .background {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !running)) { context in
                Color.clear
                    .onChange(of: context.date) { _, date in
                        let dt = lastDate.map { date.timeIntervalSince($0) * 60 } ?? 1
                        lastDate = date
                        sim.reduced = reduceMotion
                        sim.tick(dt: dt)
                        if let snapped = value, abs(sim.value - Double(snapped) / 10 * 100) < 0.4, sim.atRest {
                            running = false
                            lastDate = nil
                        } else if value == nil, sim.atRest {
                            running = false
                            lastDate = nil
                        }
                    }
            }
        }
    }

    private func liquid(width: CGFloat) -> some View {
        let lean = SloshSim.lean(
            fillVelocity: sim.fillVelocity,
            tilt: Motion.Slosh.tilt,
            reduced: reduceMotion
        )
        return SloshFill(lean: lean)
            .fill(Palette.ink.opacity(0.16))
            .frame(width: width * CGFloat(min(100, max(0, sim.fill)) / 100))
    }

    private func handle(width: CGFloat) -> some View {
        Capsule()
            .fill(Palette.ink)
            .frame(width: 3, height: 28)
            .offset(x: width * CGFloat(sim.value / 100) - 1.5)
            .opacity(value == nil && !sim.held ? 0 : 1)
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                guard enabled else { return }
                if !sim.held {
                    sim.held = true
                    sim.velocity = 0
                    startValue = value
                }
                let percent = min(100, max(0, gesture.location.x / width * 100))
                sim.velocity = percent - sim.value
                sim.value = percent
                set(SloshSim.snap(percent))
                wake()
            }
            .onEnded { gesture in
                guard enabled else { return }
                sim.held = false
                let percent = min(100, max(0, gesture.location.x / width * 100))
                let tapped = abs(gesture.translation.width) < 8 && abs(gesture.translation.height) < 8
                if tapped {
                    let snapped = SloshSim.snap(percent)
                    set(startValue == snapped ? nil : snapped)
                    sim.velocity = 0
                } else {
                    sim.velocity = reduceMotion ? 0 : min(6, max(-6, sim.velocity))
                    set(SloshSim.snap(sim.value))
                }
                wake()
            }
    }

    private func park(at score: Int?) {
        let percent = score.map { Double($0) / 10 * 100 } ?? 0
        sim = SloshSim(value: percent)
        if score == nil { sim.fill = 0 }
    }

    private func set(_ next: Int?) {
        if next == nil {
            sim.value = 0
            sim.velocity = 0
        }
        guard value != next else { return }
        value = next
        onChange()
    }

    private func wake() {
        if !running {
            lastDate = nil
            running = true
        }
    }
}

/// The leading edge, slanted by a clip rather than a skew, so the bottom
/// stays on the floor of the track.
private struct SloshFill: Shape {
    var lean: Double

    var animatableData: Double {
        get { lean }
        set { lean = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let lean = CGFloat(self.lean)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX + lean, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - lean, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
