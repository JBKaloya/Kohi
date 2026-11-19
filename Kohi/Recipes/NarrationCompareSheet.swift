import SwiftUI

/// Testers only. Every reading of the same Live note, blind and in the order
/// given, to pick the one closest to what was said, or none, and say what
/// should change. The pick becomes the brew's steps; Skip changes nothing.
struct NarrationCompareSheet: View {
    var candidates: [NarrationCompare.Candidate]
    var onAnswer: (NarrationCompare.Answer) -> Void

    @State private var selected: String?
    @State private var noneRight = false
    @State private var comment = ""
    @FocusState private var commentFocused: Bool

    var body: some View {
        StepFlow(
            step: 0,
            total: 1,
            question: Copy.compareQuestion,
            onBack: nil,
            onClose: { onAnswer(.skip) },
            onSkip: { onAnswer(.skip) },
            primaryTitle: primaryTitle,
            onPrimary: send,
            secondaryTitle: primaryTitle == nil ? nil : "Skip",
            onSecondary: { onAnswer(.skip) }
        ) {
            VStack(alignment: .leading, spacing: 18) {
                Text(Copy.compareExplainer)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                    version(candidate, number: index + 1)
                }
                noneRow
                VStack(alignment: .leading, spacing: 8) {
                    Text(Copy.compareChange).catalogueLabel()
                    TextField("Optional", text: $comment, axis: .vertical)
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2...6)
                        .focused($commentFocused)
                        .reportsFieldFocus(commentFocused)
                }
                .padding(.top, 6)
            }
            .padding(.bottom, 24)
        }
    }

    private var primaryTitle: String? {
        if noneRight { return "Send" }
        guard let selected, let index = candidates.firstIndex(where: { $0.pipeline == selected }) else { return nil }
        return "Use version \(index + 1)"
    }

    private func send() {
        onAnswer(NarrationCompare.Answer(
            chosen: noneRight ? nil : selected,
            noneRight: noneRight,
            comment: comment
        ))
    }

    private func version(_ candidate: NarrationCompare.Candidate, number: Int) -> some View {
        let isSelected = selected == candidate.pipeline && !noneRight
        return Button {
            guard candidate.ok else { return }
            withAnimation(Motion.snappy) {
                selected = candidate.pipeline
                noneRight = false
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Version \(number)").catalogueLabel()
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                    }
                }
                if !candidate.ok {
                    Text(Copy.compareNoAnswer)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                } else {
                    Text(candidate.transcript.isEmpty ? Copy.compareNothingHeard : candidate.transcript)
                        .font(Typography.body)
                        .foregroundStyle(candidate.transcript.isEmpty ? Palette.inkMuted : Palette.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if candidate.steps.isEmpty {
                        Text("No step").font(Typography.tag).foregroundStyle(Palette.inkMuted)
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(candidate.steps) { step in
                                stepLine(step)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Palette.ink : Palette.hairline, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(candidate.ok ? 1 : 0.6)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func stepLine(_ step: SpokenBrewParser.TimedStep) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(step.timeLabel)
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
                .monospacedDigit()
                .frame(width: 40, alignment: .leading)
            Text(step.note.isEmpty || step.action != .wait ? step.action.label : step.note)
                .catalogueLabel()
            if let mass = step.mass {
                Text("\(GrindRange.number(mass)) g")
                    .font(Typography.value)
                    .foregroundStyle(Palette.ink)
            }
        }
    }

    private var noneRow: some View {
        Button {
            withAnimation(Motion.snappy) { noneRight.toggle() }
        } label: {
            HStack {
                Text(Copy.compareNoneRight)
                    .font(Typography.value)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: noneRight ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(noneRight ? Palette.ink : Palette.hairline)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
