import SwiftUI

/// A number between a minus and a plus.
///
/// Three ways to change it: press a key for one step; hold it and it repeats,
/// faster and in tens the longer it is held; or drag the number, a step every
/// 12 points, and let go while it is moving to fling it. Tapping the number
/// opens the keyboard, because 1000 g is not something you reach by tapping.
struct RollingCounter: View {
    enum Style {
        /// The brew dial. 56 pt digits, 52 pt keys, the full width of the column.
        case brew
        /// A catalogue row. The label sits to the left, the slab is 44 pt tall.
        case row
    }

    let label: String
    @Binding var value: Double?
    var range: NumberRange
    var unit: String = ""
    var placeholder: String = ""
    var labelWidth: CGFloat = 92
    var presence: FieldPresence = .optional
    var hint: String?
    var error: String?
    var style: Style = .row
    /// A typed number over the max is said and dropped, never cut down to it.
    var refusesOutOfRange = false
    /// Said under the counter without marking the field as missing.
    var notice: String?

    init(
        _ label: String,
        value: Binding<Double?>,
        range: NumberRange,
        unit: String = "",
        placeholder: String = "",
        labelWidth: CGFloat = 92,
        presence: FieldPresence = .optional,
        hint: String? = nil,
        error: String? = nil,
        style: Style = .row,
        refusesOutOfRange: Bool = false,
        notice: String? = nil
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.unit = unit
        self.placeholder = placeholder
        self.labelWidth = labelWidth
        self.presence = presence
        self.hint = hint
        self.error = error
        self.style = style
        self.refusesOutOfRange = refusesOutOfRange
        self.notice = notice
    }

    init(
        _ label: String,
        value: Binding<Int?>,
        range: NumberRange,
        unit: String = "",
        placeholder: String = "",
        labelWidth: CGFloat = 92,
        presence: FieldPresence = .optional,
        hint: String? = nil,
        error: String? = nil,
        style: Style = .row
    ) {
        self.init(
            label,
            value: Binding(
                get: { value.wrappedValue.map(Double.init) },
                set: { value.wrappedValue = $0.map { Int($0.rounded()) } }
            ),
            range: range,
            unit: unit,
            placeholder: placeholder,
            labelWidth: labelWidth,
            presence: presence,
            hint: hint,
            error: error,
            style: style
        )
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether the keyboard field is on screen. Kept apart from the focus:
    /// focus can only land on a field that already exists, so the field is
    /// shown first and takes focus once it has appeared.
    @State private var editing = false
    @FocusState private var focused: Bool
    @State private var draft = ""
    @State private var holdTask: Task<Void, Never>?
    @State private var flingTask: Task<Void, Never>?
    @State private var stepTick = 0
    /// What was typed and not kept, said until the next change.
    @State private var refused: String?
    @State private var dragSteps = 0
    @State private var dragAxis: DragAxis = .undecided

    private enum DragAxis { case undecided, vertical, horizontal }

    private var labelTone: Color {
        FieldChrome.label(presence: presence, isEmpty: value == nil, isFocused: editing, hasError: error != nil).color
    }

    private var scale: Double { pow(10, Double(range.decimals)) }
    private var cell: CGFloat { style == .brew ? 56 : 34 }
    private var fontSize: CGFloat { style == .brew ? 34 : 17 }
    private var keyWidth: CGFloat { style == .brew ? 52 : 36 }
    private var corner: CGFloat { style == .brew ? 18 : 12 }
    private var inset: CGFloat { 5 }

    var body: some View {
        Group {
            if style == .brew {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(label).scalingCatalogueLabel(missing: error != nil).foregroundStyle(labelTone)
                        Spacer(minLength: 8)
                        if let hint {
                            Text(hint).scalingCatalogueLabel()
                        }
                    }
                    slab
                    message
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 12) {
                        if !label.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label)
                                    .scalingCatalogueLabel(missing: error != nil)
                                    .foregroundStyle(labelTone)
                                if let hint {
                                    Text(hint)
                                        .font(Typography.tag)
                                        .foregroundStyle(Palette.inkMuted)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                            }
                            .frame(width: labelWidth, alignment: .leading)
                        }
                        slab
                    }
                    message
                }
            }
        }
        .reportsFieldFocus(editing)
        .haptic(.step, trigger: stepTick)
        .onDisappear {
            holdTask?.cancel()
            flingTask?.cancel()
        }
    }

    private var slab: some View {
        HStack(spacing: 0) {
            RepeatKey(
                systemName: "minus",
                label: "Less",
                width: keyWidth,
                height: cell,
                corner: corner - inset,
                enabled: canStep(-1)
            ) {
                beginHold(-1)
            } onEnd: {
                holdTask?.cancel()
            } onTap: {
                bump(-1, audible: true)
            }

            number
                .frame(maxWidth: .infinity)

            RepeatKey(
                systemName: "plus",
                label: "More",
                width: keyWidth,
                height: cell,
                corner: corner - inset,
                enabled: canStep(1)
            ) {
                beginHold(1)
            } onEnd: {
                holdTask?.cancel()
            } onTap: {
                bump(1, audible: true)
            }
        }
        .padding(inset)
        .background(Palette.well, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    @ViewBuilder
    private var number: some View {
        if editing {
            TextField("", text: $draft)
                .font(.system(size: fontSize, weight: .regular))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .keyboardType(range.decimals > 0 ? .decimalPad : .numberPad)
                .focused($focused)
                .frame(height: cell)
                .onAppear { focused = true }
                .onSubmit { endEditing() }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { endEditing() }
                }
        } else if value == nil, !placeholder.isEmpty {
            Text(placeholder)
                .font(.system(size: min(fontSize, 17), weight: .regular))
                .foregroundStyle(Palette.inkMuted)
                .frame(height: cell)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { beginEditing() }
        } else {
            HStack(spacing: 6) {
                digits
                if !unit.isEmpty {
                    Text(unit)
                        .font(style == .brew ? .system(size: 15) : Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            .frame(height: cell)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { beginEditing() }
            .simultaneousGesture(drag)
        }
    }

    private var digits: some View {
        let scaled = scaledValue(value ?? range.default)
        let places = max(range.places, String(abs(scaled)).count)
        return RollingDigits(
            counts: RollMath.counts(of: scaled, places: places),
            bases: Array(repeating: 10, count: places),
            show: RollMath.shownPlaces(scaled: scaled, decimals: range.decimals, places: places),
            separators: range.decimals > 0 ? [range.decimals - 1: "."] : [:],
            cell: cell,
            fontSize: fontSize
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spoken)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: bump(1, audible: true)
            case .decrement: bump(-1, audible: true)
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private var message: some View {
        if let error {
            Text(error)
                .font(Typography.tag)
                .foregroundStyle(Palette.primary)
        } else if let notice = refused ?? notice {
            Text(notice)
                .font(Typography.tag)
                .foregroundStyle(Palette.primary)
        }
    }

    private var spoken: String {
        guard let value else { return placeholder.isEmpty ? "Not set" : placeholder }
        return unit.isEmpty ? GrindRange.number(value) : "\(GrindRange.number(value)) \(unit)"
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { gesture in
                let height = gesture.translation.height
                let width = gesture.translation.width
                if dragAxis == .undecided {
                    guard abs(height) >= 6 || abs(width) >= 6 else { return }
                    dragAxis = abs(height) >= abs(width) ? .vertical : .horizontal
                }
                guard dragAxis == .vertical else { return }
                let steps = Int((-height / 12).rounded(.towardZero))
                let delta = steps - dragSteps
                if delta != 0 {
                    bump(delta, audible: false)
                    dragSteps = steps
                }
            }
            .onEnded { gesture in
                let wasVertical = dragAxis == .vertical
                dragSteps = 0
                dragAxis = .undecided
                guard wasVertical, !reduceMotion else { return }
                let predicted = -gesture.predictedEndTranslation.height
                let travelled = -gesture.translation.height
                let extra = predicted - travelled
                guard abs(extra) > 24 else { return }
                fling(pointsPerFrame: extra / 8)
            }
    }

    private func beginHold(_ direction: Int) {
        holdTask?.cancel()
        flingTask?.cancel()
        bump(direction, audible: true)
        let started = Date()
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(HoldRepeat.arm))
            while !Task.isCancelled {
                let held = Date().timeIntervalSince(started)
                guard !Task.isCancelled else { return }
                bump(direction * HoldRepeat.magnitude(held: held), audible: false)
                try? await Task.sleep(for: .seconds(HoldRepeat.interval(held: held)))
            }
        }
    }

    private func bump(_ steps: Int, audible: Bool) {
        guard steps != 0 else { return }
        let origin = value ?? range.default
        let next: Double
        if value == nil {
            next = range.clamp(range.default)
        } else {
            next = range.clamp(origin + Double(steps) * range.step)
        }
        guard next != value else { return }
        if steps > 0, let value, next < value { return }
        refused = nil
        value = next
        if audible { stepTick += 1 }
    }

    private func canStep(_ direction: Int) -> Bool {
        let origin = value ?? range.default
        let next = value == nil
            ? range.clamp(range.default)
            : range.clamp(origin + Double(direction) * range.step)
        if direction > 0, let value, next < value { return false }
        return next != value
    }

    private func fling(pointsPerFrame: CGFloat) {
        flingTask?.cancel()
        var velocity = pointsPerFrame
        var accumulator: CGFloat = 0
        flingTask = Task { @MainActor in
            while !Task.isCancelled, abs(velocity) > 0.4 {
                accumulator += velocity
                let steps = accumulator > 0 ? Int(floor(accumulator / 12)) : Int(ceil(accumulator / 12))
                if steps != 0 {
                    bump(steps, audible: false)
                    accumulator -= CGFloat(steps) * 12
                }
                velocity *= 0.94
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func beginEditing() {
        holdTask?.cancel()
        flingTask?.cancel()
        draft = value.map { range.text($0) } ?? ""
        refused = nil
        editing = true
    }

    private func endEditing() {
        guard editing else { return }
        commitDraft()
        editing = false
        focused = false
    }

    private func commitDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            value = nil
            return
        }
        guard let parsed = NumberText.parse(trimmed, decimals: range.decimals) else { return }
        if refusesOutOfRange, parsed > range.max {
            refused = "\(range.text(parsed)) is over \(range.max.formatted(.number.precision(.fractionLength(0)))). Not kept."
            return
        }
        value = range.clamp(parsed)
    }

    private func scaledValue(_ number: Double) -> Int {
        Int((number * scale).rounded())
    }
}

/// A counter with a well beside it on the same line: most of the width for
/// the number, a quarter for what qualifies it, such as a price's currency.
/// With an empty label the counter starts at the edge, under a label above.
struct CounterRow<Accessory: View>: View {
    let label: String
    @Binding var value: Double?
    var range: NumberRange
    var placeholder: String = ""
    var labelWidth: CGFloat = 92
    var hint: String?
    var notice: String?
    @ViewBuilder let accessory: Accessory

    init(
        _ label: String = "",
        value: Binding<Double?>,
        range: NumberRange,
        placeholder: String = "",
        labelWidth: CGFloat = 92,
        hint: String? = nil,
        notice: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.placeholder = placeholder
        self.labelWidth = labelWidth
        self.hint = hint
        self.notice = notice
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RollingCounter(
                label,
                value: $value,
                range: range,
                placeholder: placeholder,
                labelWidth: labelWidth,
                hint: hint,
                refusesOutOfRange: true,
                notice: notice
            )
            accessory
                .frame(width: WellMenuLabel.width)
        }
    }
}

/// The face of a menu that sits beside a counter: same well, same height, the
/// value on the left and a key with a chevron where the plus would be.
struct WellMenuLabel: View {
    let text: String

    static let width: CGFloat = 92

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .font(.system(size: 15, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 30, height: 34)
                .background(Palette.paper, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(5)
        .background(Palette.well, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// An upright key. Pressing scales it to 0.9; holding repeats through the
/// caller's `onBegin`, which is expected to arm `HoldRepeat`.
private struct RepeatKey: View {
    var systemName: String
    var label: String
    var width: CGFloat
    var height: CGFloat
    var corner: CGFloat
    var enabled: Bool
    var onBegin: () -> Void
    var onEnd: () -> Void
    var onTap: () -> Void

    @State private var down = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .frame(width: width, height: height)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: max(0, corner), style: .continuous))
            .scaleEffect(down && enabled ? Motion.Chrome.keyPressScale : 1)
                .animation(down ? .easeOut(duration: 0.11) : Motion.quick, value: down)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard enabled, !down else { return }
                        down = true
                        onBegin()
                    }
                    .onEnded { _ in
                        guard down else { return }
                        down = false
                        onEnd()
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
            .accessibilityRespondsToUserInteraction(enabled)
    }
}
