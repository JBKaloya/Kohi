import SwiftUI

/// The blocks that score a cup: five dots, the radar and its rails, the
/// flavours, the three correction axes. One definition, used after a brew and
/// again when a coffee is scored out, so the two read and behave the same.

/// Five dots, tap to set, tap again to clear.
struct RatingPicker: View {
    @Binding var rating: Int?
    var enabled = true
    var onChange: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Copy.rating).catalogueLabel()
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { step in
                    Button {
                        onChange()
                        rating = rating == step ? nil : step
                    } label: {
                        Circle()
                            .fill((rating ?? 0) >= step ? Palette.ink : Color.clear)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Palette.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .touchTarget()
                    .disabled(!enabled)
                }
            }
        }
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
            Text(Copy.inYourCup)
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
            FlavorPicker(selection: $selection, recent: recent, declared: declared)
        }
    }

    /// Tapping a word the pack printed says you tasted it, same as in the picker.
    private func declaredChip(_ tag: FlavorTag) -> some View {
        let selected = selection.contains { $0.id == tag.id }
        return TagChip(text: tag.displayName, isSelected: selected) {
            withAnimation(Motion.quick) {
                if selected {
                    selection.removeAll { $0.id == tag.id }
                } else {
                    selection.append(tag)
                }
            }
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
