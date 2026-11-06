import SwiftUI

/// One option in a rolling picker.
struct RollOption<ID: Hashable>: Identifiable {
    var id: ID
    var name: String
    var detail: String = ""
}

/// The counter's slab, for a choice that is not a number.
/// Options roll past the window on `Motion.roll`. Drag sideways, a step every 28 pt.
struct RollingPicker<ID: Hashable>: View {
    var label: String
    var options: [RollOption<ID>]
    @Binding var selection: ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragSteps = 0
    @State private var dragAxis: DragAxis = .undecided
    @State private var stepTick = 0

    private enum DragAxis { case undecided, horizontal, vertical }

    private let cell: CGFloat = 56
    private let keyWidth: CGFloat = 52
    private let corner: CGFloat = 18
    private let inset: CGFloat = 5

    private var index: Int {
        options.firstIndex { $0.id == selection } ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).scalingCatalogueLabel()
            HStack(spacing: 0) {
                RepeatKeyButton(systemName: "chevron.left", label: "Previous", enabled: index > 0) {
                    step(-1)
                }
                window
                RepeatKeyButton(systemName: "chevron.right", label: "Next", enabled: index < options.count - 1) {
                    step(1)
                }
            }
            .padding(inset)
            .background(Palette.well, in: RoundedRectangle(cornerRadius: corner, style: .continuous))

            HStack(spacing: 4) {
                ForEach(options) { option in
                    Rectangle()
                        .fill(option.id == selection ? Palette.ink : Palette.hairline)
                        .frame(width: 16, height: 1.5)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .accessibilityHidden(true)
        }
        .haptic(.step, trigger: stepTick)
    }

    private var window: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            HStack(spacing: 0) {
                ForEach(options) { option in
                    VStack(spacing: 3) {
                        Text(option.name)
                            .font(.system(size: 19, weight: .regular))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if !option.detail.isEmpty {
                            Text(option.detail)
                                .font(Typography.tag)
                                .foregroundStyle(Palette.inkMuted)
                                .lineLimit(1)
                        }
                    }
                    .frame(width: width, height: cell)
                    .opacity(option.id == selection ? 1 : 0.35)
                }
            }
            .offset(x: -CGFloat(index) * width)
            .animation(reduceMotion ? nil : Motion.roll, value: index)
            .frame(width: width, height: cell, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { gesture in
                        let width = gesture.translation.width
                        let height = gesture.translation.height
                        if dragAxis == .undecided {
                            guard abs(width) >= 6 || abs(height) >= 6 else { return }
                            dragAxis = abs(width) >= abs(height) ? .horizontal : .vertical
                        }
                        guard dragAxis == .horizontal else { return }
                        let steps = Int((-width / 28).rounded(.towardZero))
                        let delta = steps - dragSteps
                        if delta != 0 {
                            step(delta)
                            dragSteps = steps
                        }
                    }
                    .onEnded { _ in
                        dragSteps = 0
                        dragAxis = .undecided
                    }
            )
        }
        .frame(height: cell)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(options.first { $0.id == selection }?.name ?? "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
    }

    private func step(_ delta: Int) {
        guard delta != 0, !options.isEmpty else { return }
        let next = min(options.count - 1, max(0, index + delta))
        guard next != index else { return }
        selection = options[next].id
        stepTick += 1
    }
}

private struct RepeatKeyButton: View {
    var systemName: String
    var label: String
    var enabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 52, height: 56)
                .background(Palette.paper, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: Motion.Chrome.keyPressScale))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}
