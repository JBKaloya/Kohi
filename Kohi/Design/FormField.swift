import SwiftUI
import UIKit

/// Whether an empty field should still catch the eye.
///
/// Kohi has no required asterisk. A useful field unlocks a later capability
/// (a name, a comparable brew, a dedupe key). Everything else is optional and
/// ghosts at rest.
nonisolated enum FieldPresence: Equatable, Sendable {
    case optional
    case useful
}

/// The three inks a field may speak in. Mapped to `Palette` in the view.
nonisolated enum FieldTone: Equatable, Sendable {
    case ink
    case inkMuted
    case hairline
    /// Only for a field Save is waiting on. The one place coffee brown is chrome.
    case primary
}

/// Copy that lives on the field, never as a paragraph under the form.
nonisolated enum FieldCopy {
    static let roasterShared = "Shared. Adding one here spares everyone else the typing."
    static let roasterPlace = "City and country keep two roasteries apart."
    static let roasterNameTooShort = "Need at least two letters"
    static let recipeNameMissing = "Name it to keep it"
    static let filterNameMissing = "Name this paper"
    static let filterModelMissing = "Pick a paper, or tap Custom"
    static let shapeMissing = "Pick a shape"
    static let settingMissing = "The setting is the reference"
    static let equipmentNameMissing = "Name the brand or the model"

    static func boiling(_ temperature: Double) -> String? {
        guard temperature > 100 else { return nil }
        return "\(GrindRange.number(temperature)) °C is past boiling"
    }
}

/// Colours and rule weight for the five faces of a catalogue row.
/// Empty / filled / focus / invalid — presence only changes the empty rest.
nonisolated enum FieldChrome {
    static func label(
        presence: FieldPresence,
        isEmpty: Bool,
        isFocused: Bool,
        hasError: Bool = false
    ) -> FieldTone {
        if hasError { return .primary }
        if isFocused { return .inkMuted }
        if isEmpty, presence == .optional { return .hairline }
        return .inkMuted
    }

    static func placeholder() -> FieldTone { .hairline }

    static func rule(
        presence: FieldPresence,
        isEmpty: Bool,
        isFocused: Bool,
        hasError: Bool
    ) -> (tone: FieldTone, opacity: Double) {
        if hasError { return (.primary, 1) }
        if isFocused { return (.ink, 1) }
        if isEmpty, presence == .optional {
            return (.hairline, 0.55)
        }
        return (.hairline, 1)
    }

    static func unit(isEmpty: Bool) -> FieldTone {
        isEmpty ? .hairline : .inkMuted
    }
}

extension FieldTone {
    var color: Color {
        switch self {
        case .ink: Palette.ink
        case .inkMuted: Palette.inkMuted
        case .hairline: Palette.hairline
        case .primary: Palette.primary
        }
    }
}

/// A labelled line with a hairline under it. The five states live here so
/// every sheet does not invent its own empty / focus / error chrome.
struct FormField<Value: View>: View {
    let label: String
    var labelWidth: CGFloat = 92
    var presence: FieldPresence = .optional
    var isEmpty = false
    var isFocused = false
    var hint: String?
    var error: String?
    @ViewBuilder var value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(label)
                    .catalogueLabel(missing: error != nil)
                    .foregroundStyle(chromeLabel.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: labelWidth, alignment: .leading)
                value
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background { focusShade }
            }
            Rectangle()
                .fill(rule.tone.color.opacity(rule.opacity))
                .frame(height: 1)

            if let error {
                whisper(error)
                    .transition(.opacity)
            } else if isFocused, let hint {
                Text(hint)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .transition(
                        .opacity.combined(with: .offset(y: Motion.Field.hintRise))
                    )
            }
        }
        .animation(Motion.quick, value: isEmpty)
        .animation(Motion.snappy, value: isFocused)
        .animation(Motion.snappy, value: error)
        .reportsFieldFocus(isFocused)
    }

    private var chromeLabel: FieldTone {
        FieldChrome.label(presence: presence, isEmpty: isEmpty, isFocused: isFocused, hasError: error != nil)
    }

    private var rule: (tone: FieldTone, opacity: Double) {
        FieldChrome.rule(
            presence: presence,
            isEmpty: isEmpty,
            isFocused: isFocused,
            hasError: error != nil
        )
    }

    @ViewBuilder
    private var focusShade: some View {
        if isFocused {
            RoundedRectangle(cornerRadius: Motion.Field.focusShadeRadius)
                .fill(Palette.paperShade)
                .padding(.horizontal, -Motion.Field.focusShadePad.h)
                .padding(.vertical, -Motion.Field.focusShadePad.v)
        }
    }

    private func whisper(_ text: String) -> some View {
        Text(text)
            .font(Typography.tag)
            .foregroundStyle(Palette.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: Motion.Field.focusShadeRadius)
                    .fill(Palette.paperShade)
                    .overlay {
                        RoundedRectangle(cornerRadius: Motion.Field.focusShadeRadius)
                            .stroke(Palette.hairline, lineWidth: 1)
                    }
            }
            .padding(.leading, labelWidth + 16)
    }
}

/// Text entry, the common case. Completions sit under the row while it is
/// focused, the same chips a known roaster already offers.
struct TextRow: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var labelWidth: CGFloat = 92
    var presence: FieldPresence = .optional
    var hint: String?
    var error: String?
    var isPending = false
    var capitalization: TextInputAutocapitalization = .words
    var completions: [String] = []
    var onComplete: ((String) -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FormField(
                label: label,
                labelWidth: labelWidth,
                presence: presence,
                isEmpty: text.trimmingCharacters(in: .whitespaces).isEmpty,
                isFocused: isFocused,
                hint: completions.isEmpty ? hint : nil,
                error: error
            ) {
                ZStack(alignment: .leading) {
                    TextField(
                        "",
                        text: $text,
                        prompt: Text(placeholder).foregroundStyle(FieldChrome.placeholder().color)
                    )
                    .formValue()
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .opacity(isPending && text.isEmpty ? 0 : 1)

                    if isPending, text.isEmpty {
                        ShimmerBar()
                            .transition(.opacity)
                    }
                }
            }

            if isFocused, !completions.isEmpty {
                FlowLayout {
                    ForEach(completions, id: \.self) { item in
                        TagChip(text: item) { onComplete?(item) }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.snappy, value: isFocused)
        .animation(Motion.snappy, value: completions)
    }
}

/// A derived figure (ratio, flow) that shows the previous value struck when it
/// is overwritten, then lets it shrink away.
struct DerivedValue: View {
    let text: String
    var empty = "—"

    @State private var residue: String?

    var body: some View {
        ZStack {
            if let residue {
                Text(residue)
                    .font(Typography.tag)
                    .strikethrough()
                    .foregroundStyle(Palette.hairline)
                    .scaleEffect(x: 0.92, y: 1, anchor: .center)
            }
            Text(text)
                .font(Typography.tag)
                .foregroundStyle(text == empty ? Palette.hairline : Palette.inkMuted)
        }
        .animation(Motion.snappy, value: text)
        .onChange(of: text) { old, new in
            guard old != new, old != empty, !old.isEmpty else { return }
            residue = old
            Task {
                try? await Task.sleep(for: Motion.Field.residueHold)
                withAnimation(Motion.quick) { residue = nil }
            }
        }
    }
}

extension View {
    /// The look every form value shares.
    func formValue() -> some View {
        font(Typography.value)
            .foregroundStyle(Palette.ink)
            .tint(Palette.ink)
    }

    func reportsFieldFocus(_ focused: Bool) -> some View {
        preference(key: FieldFocusPreference.self, value: focused)
    }

    /// Number pads have no Return. Step screens call this from Done, Back, and a tap on the paper.
    func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    /// Extra inset while any catalogue field in this subtree is focused.
    /// Kept as a hook; iOS already lifts the scroll view for the keyboard.
    func fieldKeyboardClearance() -> some View {
        modifier(FieldKeyboardClearance())
    }

    /// Pulses `GuessHighlight` on this row when it is one of the missing
    /// comparable fields and the completeness tag is tapped.
    func completenessPulse(
        _ field: Completeness.Field,
        completeness: Completeness,
        trigger: Int
    ) -> some View {
        modifier(CompletenessPulse(field: field, completeness: completeness, trigger: trigger))
    }
}

struct FieldFocusPreference: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct FieldKeyboardClearance: ViewModifier {
    @State private var focused = false

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(FieldFocusPreference.self) { focused = $0 }
            .padding(.bottom, focused ? Motion.Field.keyboardClearance : 0)
            .animation(Motion.snappy, value: focused)
    }
}

/// Applies a bottom safe-area bar only while it is on screen. An empty
/// `safeAreaInset` still eats space above the keyboard.
struct VisibleBottomInset<Bar: View>: ViewModifier {
    var isVisible: Bool
    @ViewBuilder var bar: () -> Bar

    func body(content: Content) -> some View {
        if isVisible {
            content.safeAreaInset(edge: .bottom, spacing: 0, content: bar)
        } else {
            content
        }
    }
}

private struct CompletenessPulse: ViewModifier {
    let field: Completeness.Field
    let completeness: Completeness
    let trigger: Int

    func body(content: Content) -> some View {
        if case .missing(let fields) = completeness, fields.contains(field) {
            content.guessHighlight(trigger: trigger)
        } else {
            content
        }
    }
}

/// A binding that shows a number as text and writes nil back when the field is
/// cleared. Numeric optionals are everywhere in Setup, and a `formatter:`
/// either insists on a value or leaves a zero behind.
nonisolated enum NumberText {
    static func binding(_ source: Binding<Double?>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue.map { GrindRange.number($0) } ?? "" },
            set: { source.wrappedValue = parse($0) }
        )
    }

    static func binding(_ source: Binding<Int?>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue.map(String.init) ?? "" },
            set: { source.wrappedValue = parse($0).map { Int($0.rounded()) } }
        )
    }

    /// Accepts a comma as the decimal separator: a French keypad gives you one,
    /// and refusing it silently drops the digits.
    static func parse(_ text: String) -> Double? {
        var cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        if cleaned.hasSuffix(".") { cleaned.removeLast() }
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }
}

/// Single-choice chips over `TagChip`. Tapping the selected one clears it.
/// The haptic belongs to the enclosing sheet, which already owns a tap trigger.
struct ChipPicker<Item: Identifiable & Equatable>: View {
    let items: [Item]
    let label: (Item) -> String
    @Binding var selection: Item?
    var allowsDeselect = true
    var onPick: () -> Void = {}

    var body: some View {
        FlowLayout {
            ForEach(items) { item in
                TagChip(text: label(item), isSelected: selection == item) {
                    if selection == item, allowsDeselect {
                        selection = nil
                    } else {
                        selection = item
                    }
                    onPick()
                }
            }
        }
    }
}

/// Multi-choice chips, for "default for" method lists.
struct ChipToggles<Item: Identifiable & Hashable>: View {
    let items: [Item]
    let label: (Item) -> String
    let isOn: (Item) -> Bool
    let toggle: (Item, Bool) -> Void

    var body: some View {
        FlowLayout {
            ForEach(items) { item in
                TagChip(text: label(item), isSelected: isOn(item)) {
                    toggle(item, !isOn(item))
                }
            }
        }
    }
}
