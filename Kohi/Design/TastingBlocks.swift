import SwiftUI

/// The blocks that score a cup: five dots, the radar and its rails, the
/// flavours, the three correction axes. One definition, used after a brew and
/// again when a coffee is scored out, so the two read and behave the same.

/// Five dots in half points, after a brew and for a tasting alike. Tap an
/// empty dot for its whole score, the last full dot again to halve it, a half
/// dot to clear. Slide along the dots to set it by halves. VoiceOver adjusts
/// by half a point. Each change ticks, like a counter step.
struct RatingPicker: View {
    @Binding var halves: Int?
    var enabled = true

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 22
    @State private var dotsWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Copy.rating).catalogueLabel()
            HStack(spacing: 4) {
                HStack(spacing: 0) {
                    ForEach(1...5, id: \.self) { dot in
                        RatingDot(fill: HalfRating.dot(dot, of: halves), size: size)
                            .frame(width: max(44, size + 32), height: 44)
                    }
                }
                .opacity(enabled ? 1 : 0.5)
                .contentShape(Rectangle())
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { dotsWidth = $0 }
                .gesture(slide.exclusively(before: tap), including: enabled ? .all : .none)
                Text(halves.map(HalfRating.text) ?? "—")
                    .font(Typography.value)
                    .monospacedDigit()
                    .foregroundStyle(halves == nil ? Palette.inkMuted : Palette.ink)
                    .contentTransition(.numericText())
            }
            .haptic(.step, trigger: halves)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.rating)
            .accessibilityValue(HalfRating.spoken(halves))
            .accessibilityAdjustableAction { direction in
                guard enabled else { return }
                switch direction {
                case .increment: halves = HalfRating.step(halves, by: 1)
                case .decrement: halves = HalfRating.step(halves, by: -1)
                @unknown default: break
                }
            }
        }
    }

    /// Horizontal only, so a vertical swipe that starts on the dots does not rate.
    private var slide: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                let next = HalfRating.slide(x: value.location.x, width: dotsWidth)
                if next != halves {
                    withAnimation(Motion.quick) { halves = next }
                }
            }
    }

    private var tap: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let dot = StepHit.index(x: value.location.x, width: dotsWidth, count: 5)
                withAnimation(Motion.quick) { halves = HalfRating.tap(halves, dot: dot) }
            }
    }
}

/// One dot of a rating: ink, ink on its left half, or an outline.
struct RatingDot: View {
    let fill: HalfRating.Dot
    var size: CGFloat = 22
    var empty: Color = .clear
    var stroke: Color = Palette.hairline

    var body: some View {
        ZStack {
            Circle().fill(fill == .full ? Palette.ink : empty)
            if fill == .half {
                Circle()
                    .fill(Palette.ink)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: size / 2)
                    }
            }
            Circle().stroke(fill == .empty ? stroke : Palette.ink, lineWidth: 1)
        }
        .frame(width: size, height: size)
    }
}

/// The seven axes: a collapsible header, the radar, then the rails.
struct TasteBlock: View {
    @Binding var taste: TasteProfile
    var previous: TasteProfile?
    /// Shown under the radar when a lighter shape is drawn behind the current one.
    var previousCaption: String?
    var enabled = true
    var onChange: () -> Void = {}

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                onChange()
                withAnimation(Motion.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(Copy.taste).catalogueLabel()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Palette.inkMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Spacer()
                    if !taste.isEmpty, !isExpanded {
                        Text("\(taste.scoredAxes.count) of 7")
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Spacer()
                        TasteRadar(taste: taste, previous: previous)
                        Spacer()
                    }
                    if let previousCaption, previous != nil {
                        Text(previousCaption)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }
                    AxisRails(taste: $taste, enabled: enabled, onChange: onChange)
                }
            }
        }
    }
}

/// What the bag claims, then what you actually tasted.
struct FlavorsBlock: View {
    @Binding var selection: [FlavorTag]
    var declared: [FlavorTag] = []
    var recent: [FlavorTag] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Copy.flavors).catalogueLabel()
            if !declared.isEmpty {
                Text(Copy.onThePack)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                FlowLayout {
                    ForEach(declared) { tag in
                        declaredChip(tag)
                    }
                }
            }
            HStack {
                Text(Copy.inYourCup)
                Spacer()
                if !selection.isEmpty {
                    Text(Copy.intensityOptional)
                }
            }
            .font(Typography.tag)
            .foregroundStyle(Palette.inkMuted)
            FlavorIntensityList(selection: $selection)
            FlavorPicker(selection: $selection, recent: recent, declared: declared, showsSummary: false)
        }
        .haptic(.step, trigger: selection)
    }

    /// Tapping a word the pack printed says you tasted it, same as in the picker.
    private func declaredChip(_ tag: FlavorTag) -> some View {
        let selected = selection.contains { $0.id == tag.id }
        return TagChip(text: tag.displayName, isSelected: selected) {
            withAnimation(Motion.quick) {
                if selected {
                    selection.removeAll { $0.id == tag.id }
                } else {
                    selection.append(tag.unrated)
                }
            }
        }
    }
}

/// The notes you tasted, one per row, each with how strong it was if you
/// want to say: tap or slide along five steps, tap the active one to clear.
struct FlavorIntensityList: View {
    @Binding var selection: [FlavorTag]

    var body: some View {
        if !selection.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(selection) { tag in
                    IntensityRow(tag: tag) { level in
                        selection.setIntensity(level, of: tag.id)
                    }
                }
            }
        }
    }
}

private struct IntensityRow: View {
    let tag: FlavorTag
    let set: (Int?) -> Void

    @State private var width: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            Text(tag.displayName)
                .font(Typography.value)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(Array(FlavorTag.intensities), id: \.self) { level in
                    Capsule()
                        .fill((tag.intensity ?? 0) >= level ? Palette.ink : Palette.hairline)
                        .frame(height: 6)
                        .padding(.horizontal, 2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .frame(width: 130)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .gesture(slide.exclusively(before: tap))
            Text(tag.intensity.map(FlavorTag.intensityLabel) ?? Copy.intensityNotSet)
                .font(Typography.tag)
                .foregroundStyle(tag.intensity == nil ? Palette.inkMuted : Palette.ink)
                .lineLimit(1)
                .frame(width: 78, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tag.displayName)
        .accessibilityValue(tag.intensity.map(FlavorTag.intensityLabel) ?? Copy.intensityNotSet)
        .accessibilityAdjustableAction { direction in
            let current = tag.intensity ?? 0
            switch direction {
            case .increment: set(min(FlavorTag.intensities.upperBound, current + 1))
            case .decrement: set(current <= 1 ? nil : current - 1)
            @unknown default: break
            }
        }
    }

    private func level(at x: CGFloat) -> Int {
        StepHit.index(x: x, width: width, count: FlavorTag.intensities.upperBound)
    }

    private var slide: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                let next = level(at: value.location.x)
                if next != tag.intensity {
                    withAnimation(Motion.quick) { set(next) }
                }
            }
    }

    private var tap: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let next = level(at: value.location.x)
                withAnimation(Motion.quick) { set(tag.intensity == next ? nil : next) }
            }
    }
}

/// One correction row: −, ·, +. Tapping the active step returns to balanced.
/// The caption reads the current value back in words ("less acidity").
struct CorrectionAxis: View {
    let name: String
    @Binding var value: Int
    var caption: ((Int) -> String)? = nil
    var enabled = true
    var onChange: () -> Void = {}

    var body: some View {
        HStack(spacing: caption == nil ? 14 : 4) {
            Text(name)
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
                .frame(width: 74, alignment: .leading)
            ForEach([-1, 0, 1], id: \.self) { step in
                Button {
                    onChange()
                    value = value == step ? 0 : step
                } label: {
                    Text(step < 0 ? "−" : step > 0 ? "+" : "·")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(value == step ? Palette.paper : Palette.ink)
                        .frame(width: 28, height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(value == step ? Palette.ink : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Palette.hairline, lineWidth: value == step ? 0 : 1)
                                )
                        }
                }
                .buttonStyle(.plain)
                .touchTarget()
                .disabled(!enabled)
            }
            if let caption {
                Text(caption(value))
                    .font(Typography.tag)
                    .foregroundStyle(value == 0 ? Palette.inkMuted : Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)
                    .padding(.leading, 6)
                    .contentTransition(.opacity)
            }
        }
    }
}
