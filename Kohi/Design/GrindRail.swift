import SwiftUI

/// Fine on the left, coarse on the right. Always seven notches; the click
/// count is a linked trailing column when the grinder has a span.
struct GrindRail: View {
    @Binding var setting: GrindSetting
    var grinder: Equipment?
    var method: BrewMethod?
    /// Particle-size proxy, shown under the click count. The trailing column
    /// always reserves a second line so Temp / Filter do not jump when it appears.
    var microns: String? = nil
    var onChange: () -> Void = {}
    var onSetRange: (() -> Void)? = nil

    @State private var tracking = false
    @FocusState private var clickFocused: Bool

    private var span: GrindSpan? {
        GrindSpan.make(grinder: grinder, method: method, current: setting.value)
    }

    private var grade: GrindGrade {
        GrindGrade.notch(setting.resolvedNotch)
    }

    private var band: ClosedRange<Double> {
        method.flatMap { RecipeRules.microns(for: $0) } ?? 400...700
    }

    private var notchPosition: Double {
        Double(setting.resolvedNotch - 1) / 6
    }

    private var usesClickRail: Bool {
        span?.band != nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            GrindPreview(
                microns: band,
                position: usesClickRail ? (setting.value.flatMap { span?.position(of: $0) } ?? notchPosition) : notchPosition,
                isSet: setting.position != nil || setting.value != nil || GrindGrade.parse(setting.raw) != nil
            )
            .animation(tracking ? nil : Motion.snappy, value: setting.resolvedNotch)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    rail
                        .frame(minHeight: 44)
                    labels
                }
                if span != nil {
                    clickColumn
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Grind")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(1)
            case .decrement: nudge(-1)
            @unknown default: break
            }
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Fine")
                Spacer()
                if usesClickRail {
                    Text("Medium")
                    Spacer()
                } else {
                    Text(grade.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                }
                Text("Coarse")
            }
            .font(Typography.tag)
            .foregroundStyle(Palette.inkMuted)
            if !usesClickRail, let onSetRange {
                Button(Copy.setYourRange, action: onSetRange)
                    .catalogueLabel()
            }
        }
    }

    private var accessibilityValue: String {
        if let span, let value = setting.value {
            let number = "\(GrindRange.number(value)) \(span.unit)"
            return microns.map { "\(number), \($0)" } ?? number
        }
        return grade.label
    }

    private var clickColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("", text: clickText)
                    .font(Typography.number)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .focused($clickFocused)
                    .fixedSize(horizontal: true, vertical: false)
                    .monospacedDigit()
                Text(span?.unit ?? "")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minWidth: 108, alignment: .trailing)
            Text(microns ?? " ")
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 108, alignment: .trailing)
                .opacity(microns == nil ? 0 : 1)
                .accessibilityHidden(microns == nil)
        }
        .frame(minWidth: 108)
        .reportsFieldFocus(clickFocused)
    }

    private var clickText: Binding<String> {
        Binding(
            get: {
                guard let value = setting.value else { return "" }
                return GrindRange.number(value)
            },
            set: { text in
                guard let span, let parsed = NumberText.parse(text) else { return }
                var next = setting
                next.setValue(parsed, span: span, grinderId: grinder?.id)
                setting = next
                onChange()
            }
        )
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
                        if usesClickRail, let span {
                            ForEach(clickMarks(in: span), id: \.self) { value in
                                let selected = setting.value.map { abs($0 - value) < span.step / 2 } ?? false
                                Circle()
                                    .fill(selected ? Palette.ink : Palette.hairline)
                                    .frame(width: selected ? 8 : 3, height: selected ? 8 : 3)
                                    .position(x: span.position(of: value) * width, y: 17)
                            }
                        } else {
                            ForEach(GrindGrade.allCases) { grade in
                                let selected = setting.resolvedNotch == grade.notch
                                Circle()
                                    .fill(selected ? Palette.ink : Palette.hairline)
                                    .frame(width: selected ? 8 : 3, height: selected ? 8 : 3)
                                    .position(x: grade.position * width, y: 17)
                            }
                        }
                    }
                    .frame(width: width, height: 34)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onChanged { gesture in
                                tracking = true
                                apply(position: gesture.location.x / width)
                            }
                            .onEnded { _ in
                                tracking = false
                                onChange()
                            }
                    )
                    .simultaneousGesture(
                        SpatialTapGesture().onEnded { gesture in
                            apply(position: gesture.location.x / width)
                            onChange()
                        }
                    )
                }
            }
            .animation(tracking ? nil : Motion.snappy, value: setting)
    }

    private func apply(position raw: Double) {
        if usesClickRail, let span {
            var next = setting
            next.setValue(span.value(at: raw), span: span, grinderId: grinder?.id)
            guard next != setting else { return }
            setting = next
            return
        }
        let grade = GrindGrade.nearest(position: raw)
        var next = setting
        next.setNotch(grade.notch, span: span, grinderId: grinder?.id)
        guard next != setting else { return }
        setting = next
    }

    private func clickMarks(in span: GrindSpan) -> [Double] {
        guard let band = span.band, span.step > 0 else { return [] }
        var marks: [Double] = []
        var value = band.lowerBound
        while value <= band.upperBound + span.step / 2 {
            marks.append(span.snap(value))
            value += span.step
        }
        if marks.count > 24 {
            let stride = max(1, marks.count / 16)
            return marks.enumerated().compactMap { $0.offset % stride == 0 ? $0.element : nil }
        }
        return marks
    }

    private func nudge(_ steps: Int) {
        let next = min(max(setting.resolvedNotch + steps, 1), 7)
        var updated = setting
        updated.setNotch(next, span: span, grinderId: grinder?.id)
        setting = updated
        onChange()
    }
}