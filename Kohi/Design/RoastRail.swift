import SwiftUI

/// Six roast crans on a hairline, light on the left. Picking a cran can
/// suggest an Agtron; it never overwrites one the bag already printed.
struct RoastRail: View {
    @Binding var level: RoastLevel?
    var onChange: (RoastLevel?) -> Void = { _ in }

    private let levels = RoastLevel.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                rail
                Text(level?.label ?? "—")
                    .font(Typography.tag)
                    .foregroundStyle(level == nil ? Palette.hairline : Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 88, alignment: .trailing)
            }
            .frame(minHeight: 44)

            HStack {
                Text("Light")
                Spacer()
                Text("Dark")
            }
            .font(Typography.tag)
            .foregroundStyle(Palette.inkMuted)
            .padding(.trailing, 104)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Roast")
        .accessibilityValue(level?.label ?? "unset")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(1)
            case .decrement: nudge(-1)
            @unknown default: break
            }
        }
    }

    private var rail: some View {
        Color.clear
            .frame(height: 34)
            .contentShape(Rectangle())
            .overlay {
                GeometryReader { proxy in
                    let width = max(proxy.size.width, 1)
                    let count = CGFloat(max(levels.count - 1, 1))
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(red: 0.86, green: 0.78, blue: 0.66),
                                Color(red: 0.42, green: 0.28, blue: 0.18),
                                Color(red: 0.16, green: 0.11, blue: 0.08),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 1)

                        ForEach(Array(levels.enumerated()), id: \.element) { index, roast in
                            let selected = level == roast
                            Circle()
                                .fill(selected ? Palette.ink : Palette.paper)
                                .overlay(Circle().stroke(Palette.ink, lineWidth: selected ? 0 : 1))
                                .frame(width: selected ? 10 : 6, height: selected ? 10 : 6)
                                .position(x: CGFloat(index) / count * width, y: 17)
                        }
                    }
                    .frame(width: width, height: 34)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onEnded { gesture in
                                pick(at: gesture.location.x / width)
                            }
                    )
                    .simultaneousGesture(
                        SpatialTapGesture().onEnded { gesture in
                            pick(at: gesture.location.x / width)
                        }
                    )
                }
            }
    }

    private func pick(at position: CGFloat) {
        let clamped = min(max(position, 0), 1)
        let index = Int((clamped * CGFloat(levels.count - 1)).rounded())
        let next = levels[index]
        onChange(next)
    }

    private func nudge(_ steps: Int) {
        let current = level.flatMap { levels.firstIndex(of: $0) } ?? 0
        let index = min(max(current + steps, 0), levels.count - 1)
        onChange(levels[index])
    }
}
