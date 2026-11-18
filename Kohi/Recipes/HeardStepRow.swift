import SwiftUI

/// One step heard in a Live brew: when it was said, what, how much, and
/// what else was said with it.
struct HeardStepRow: View {
    var step: BrewStep
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(step.timeLabel)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .monospacedDigit()
                    .frame(width: 40, alignment: .leading)
                Text(step.action.label)
                    .catalogueLabel()
                if let mass = step.mass {
                    Text("\(GrindRange.number(mass)) g")
                        .font(Typography.value)
                        .foregroundStyle(Palette.ink)
                }
                if let until = step.targetAt, until > step.at {
                    Text("until \(String(format: "%d:%02d", until / 60, until % 60))")
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
                Spacer(minLength: 8)
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.inkMuted)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(step.action.label)")
            }
            if !step.note.isEmpty {
                Text(step.note)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.leading, 50)
            }
        }
    }
}

/// The parts of a split, side by side, ink and muted in turn.
struct SplitBar: View {
    var shares: [Double]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                    Rectangle()
                        .fill(index.isMultiple(of: 2) ? Palette.ink : Palette.inkMuted)
                        .frame(width: max(proxy.size.width * share - 2, 0))
                }
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
