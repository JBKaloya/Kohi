import SwiftUI

/// One thing in the cupboard, as a catalogue row: glyph, name, kind.
struct KitRow: View {
    let item: Equipment
    var isSelected: Bool = false
    var onTap: () -> Void
    var onRemove: (() -> Void)?

    @State private var reveal = false
    @State private var deleted = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            if reveal, onRemove != nil {
                Button("Remove") {
                    deleted += 1
                    onRemove?()
                }
                .catalogueLabel()
                .padding(.trailing, 4)
            }

            Group {
                if onRemove == nil {
                    tappableRow
                } else {
                    tappableRow.gesture(removeGesture)
                }
            }
        }
        .haptic(.deleted, trigger: deleted)
    }

    private var tappableRow: some View {
        Button {
            if reveal {
                withAnimation(Motion.quick) { reveal = false }
            } else {
                onTap()
            }
        } label: {
            row
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .offset(x: reveal ? -72 : 0)
    }

    private var removeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                withAnimation(Motion.quick) {
                    reveal = value.translation.width < -40
                }
            }
    }

    private var row: some View {
        VStack(spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                EquipmentGlyphView(
                    glyph: EquipmentGlyph.forKit(item),
                    size: 28,
                    color: item.isDefaultFor.isEmpty ? Palette.inkMuted : Palette.ink
                )
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 6 }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(Typography.value)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                CatalogueMark(text: item.kind.label, isSelected: isSelected)
                    .multilineTextAlignment(.trailing)
            }
            Rectangle().fill(CatalogueChoice.rule(isSelected)).frame(height: 1)
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        if item.kind == .grinder {
            var parts: [String] = []
            if let unit = item.adjustment?.unitLabel, !unit.isEmpty { parts.append(unit) }
            let ranges = item.ranges
                .map { "\($0.method.label) \($0.label)" }
                .joined(separator: " · ")
            if !ranges.isEmpty { parts.append(ranges) }
            return parts.joined(separator: " · ")
        }
        return item.summary
    }
}

/// A water profile in the same grammar as a kit row.
struct WaterKitRow: View {
    let profile: WaterProfile
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    EquipmentGlyphView(
                        glyph: EquipmentGlyph.forWater(profile.source),
                        size: 28,
                        color: profile.isDefault ? Palette.ink : Palette.inkMuted
                    )
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 6 }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.displayName)
                            .font(Typography.value)
                            .foregroundStyle(Palette.ink)
                        if !profile.summary.isEmpty {
                            Text(profile.summary)
                                .font(Typography.tag)
                                .foregroundStyle(Palette.inkMuted)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if profile.isDefault {
                        CatalogueMark(text: "Default", isSelected: true)
                    }
                }
                Rectangle().fill(CatalogueChoice.rule(profile.isDefault)).frame(height: 1)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}
