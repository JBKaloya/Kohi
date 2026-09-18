import SwiftUI

/// Fine on the left, coarse on the right. A hairline like `AxisRail`, never a
/// system slider. Clicks when the grinder has a span; verbal grades otherwise.
struct GrindRail: View {
    @Binding var setting: GrindSetting
    var grinder: Equipment?
    var method: BrewMethod?
    var onChange: () -> Void = {}

    @State private var tracking = false

    private var span: GrindSpan? {
        GrindSpan.make(grinder: grinder, method: method, current: setting.value)
    }

    private var position: Double? {
        if let value = setting.value, let span {
            return span.position(of: value)
        }
        return GrindGrade.parse(setting.raw)?.position
    }

    private var caption: String {
        if let value = setting.value {
            let number = GrindRange.number(value)
            if let span, !span.unit.isEmpty { return "\(number) \(span.unit)" }
            if let unit = grinder?.unitLabel, !unit.isEmpty { return "\(number) \(unit)" }
            return number
        }
        if let raw = setting.raw, !raw.isEmpty { return raw }
        return "—"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            GrindSample(position: position ?? 0.5, isSet: position != nil)
                .animation(tracking ? nil : Motion.snappy, value: position)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 16) {
                    rail
                    Text(caption)
                        .font(Typography.tag)
                        .foregroundStyle(caption == "—" ? Palette.hairline : Palette.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 88, alignment: .trailing)
                }
                .frame(minHeight: 44)

                HStack {
                    Text("Fine")
                    Spacer()
                    Text("Coarse")
                }
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
                .padding(.trailing, 104)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Grind")
        .accessibilityValue(caption)
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
                    ZStack {
                        Rectangle()
                            .fill(Palette.hairline)
                            .frame(height: 1)
                        if let span, let band = span.band, span.width > 0 {
                            let start = span.position(of: band.lowerBound) * width
                            let end = span.position(of: band.upperBound) * width
                            Rectangle()
                                .fill(Palette.inkMuted)
                                .frame(width: max(1, end - start), height: 1)
                                .offset(x: (start + end) / 2 - width / 2)
                        }
                        if span == nil {
                            ForEach(GrindGrade.allCases) { grade in
                                let selected = GrindGrade.parse(setting.raw) == grade
                                Circle()
                                    .fill(selected ? Palette.ink : Palette.hairline)
                                    .frame(width: selected ? 8 : 3, height: selected ? 8 : 3)
                                    .position(x: grade.position * width, y: 17)
                            }
                        } else if let position {
                            Circle()
                                .fill(Palette.ink)
                                .frame(width: 8, height: 8)
                                .position(x: position * width, y: 17)
                        }
                    }
                    .frame(width: width, height: 34)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                tracking = true
                                apply(position: gesture.location.x / width)
                            }
                            .onEnded { gesture in
                                apply(position: gesture.location.x / width)
                                tracking = false
                                onChange()
                            }
                    )
                }
            }
            .animation(tracking ? nil : Motion.snappy, value: setting)
    }

    private func apply(position raw: Double) {
        let position = min(max(raw, 0), 1)
        var next = setting
        if let span {
            next.value = span.value(at: position)
            if next.grinderId == nil { next.grinderId = grinder?.id }
        } else {
            let grade = GrindGrade.nearest(position: position)
            next.value = nil
            next.raw = grade.label
        }
        guard next != setting else { return }
        setting = next
    }

    private func nudge(_ steps: Int) {
        if let span {
            let current = setting.value ?? span.value(at: position ?? 0.5)
            apply(position: span.position(of: current + span.step * Double(steps)))
        } else {
            let grade = GrindGrade.nearest(position: position ?? 0.5)
            let next = min(max(grade.rawValue + steps, 0), GrindGrade.allCases.count - 1)
            apply(position: (GrindGrade(rawValue: next) ?? grade).position)
        }
        onChange()
    }
}
