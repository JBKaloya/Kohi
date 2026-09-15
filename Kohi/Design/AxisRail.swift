import SwiftUI

/// One taste axis as a hairline rail, 0…10. Tap a tick or drag. Tapping the
/// current value clears it.
struct AxisRail: View {
    let axis: TasteAxis
    @Binding var value: Int?
    var onChange: () -> Void = {}

    @State private var gestureOrigin: Int?
    @State private var didMove = false
    @State private var tracking = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(axis.label)
                .catalogueLabel()
                .frame(width: 74, alignment: .leading)

            rail

            Text(value.map(String.init) ?? "—")
                .font(Typography.tag)
                .foregroundStyle(Palette.ink)
                .frame(width: 18, alignment: .trailing)
                .monospacedDigit()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle().inset(by: -10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(axis.label)
        .accessibilityValue(value.map(String.init) ?? "not scored")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(min((value ?? -1) + 1, 10))
            case .decrement:
                if let current = value, current > 0 { set(current - 1) }
                else { set(nil) }
            @unknown default: break
            }
        }
    }

    private var rail: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
                ForEach(0...10, id: \.self) { tick in
                    Circle()
                        .fill(value == tick ? Palette.ink : Palette.hairline)
                        .frame(width: value == tick ? 8 : 3, height: value == tick ? 8 : 3)
                        .position(x: x(for: tick, width: width), y: 17)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !tracking {
                            gestureOrigin = value
                            tracking = true
                            didMove = false
                        }
                        if abs(gesture.translation.width) > 4 { didMove = true }
                        let tick = Int((gesture.location.x / width * 10).rounded())
                        set(min(max(tick, 0), 10))
                    }
                    .onEnded { gesture in
                        let tick = Int((gesture.location.x / width * 10).rounded())
                        let snapped = min(max(tick, 0), 10)
                        if !didMove, gestureOrigin == snapped {
                            set(nil)
                        }
                        tracking = false
                        didMove = false
                        gestureOrigin = nil
                    }
            )
        }
        .frame(height: 34)
    }

    private func x(for tick: Int, width: CGFloat) -> CGFloat {
        width * CGFloat(tick) / 10
    }

    private func set(_ next: Int?) {
        guard value != next else { return }
        value = next
        onChange()
    }
}

/// The seven rails, in radar order.
struct AxisRails: View {
    @Binding var taste: TasteProfile
    var onChange: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            ForEach(TasteAxis.allCases) { axis in
                AxisRail(
                    axis: axis,
                    value: Binding(
                        get: { taste[axis] },
                        set: { taste[axis] = $0 }
                    ),
                    onChange: onChange
                )
            }
        }
    }
}
