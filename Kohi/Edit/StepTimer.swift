import SwiftUI

/// The guided timer: one instruction at a time, and a record of when you
/// actually did each one.
///
/// Reads as a single line of type over a hairline, not as a dashboard. What you
/// need mid-pour is the target mass and the next action; everything else is in
/// the way when your hands are full.
struct StepTimer: View {
    let steps: [RecipeStep]
    /// Seconds elapsed, owned by the brew sheet so the clock survives a scroll.
    let elapsed: Int
    let isRunning: Bool
    /// The real steps recorded so far.
    @Binding var recorded: [BrewStep]

    let onStart: () -> Void
    let onAdvance: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            clock

            if let current {
                currentStep(current)
            } else if isFinished {
                Text("Every step logged. Stop the clock when the cup is done.")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }

            progress

            if !recorded.isEmpty { recordedSteps }
        }
    }

    // MARK: - Pieces

    private var clock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(String(format: "%d:%02d", elapsed / 60, elapsed % 60))
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
                .contentTransition(.numericText())

            Spacer()

            if isRunning {
                Button(current == nil ? "Stop" : "Next") {
                    if current == nil { onStop() } else { onAdvance() }
                }
                .font(Typography.tag)
                .foregroundStyle(Palette.ink)

                if current != nil {
                    Button("Stop", action: onStop)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
            } else {
                Button(elapsed > 0 ? "Resume" : "Start", action: onStart)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.ink)
            }
        }
        .animation(Motion.quick, value: isRunning)
    }

    /// The step you are on: its instruction, its target time, and how far off
    /// the clock is right now.
    private func currentStep(_ step: RecipeStep) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(step.instruction)
                .font(Typography.value)
                .foregroundStyle(Palette.ink)

            HStack(spacing: 10) {
                Text("at \(step.timeLabel)")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)

                if isRunning {
                    Text(dueLine(step))
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                        .contentTransition(.numericText())
                }

                if !step.note.isEmpty {
                    Text(step.note)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(1)
                }
            }
        }
    }

    /// "in 12 s" before, "12 s late" after. Never a warning: a late pour is
    /// information, not a failure.
    private func dueLine(_ step: RecipeStep) -> String {
        let delta = step.at - elapsed
        if delta > 0 { return "in \(delta) s" }
        if delta == 0 { return "now" }
        return "\(-delta) s late"
    }

    /// One tick per step, filled as they are logged. A progress bar would
    /// promise a smoothness the steps do not have.
    private var progress: some View {
        HStack(spacing: 3) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, _ in
                Rectangle()
                    .fill(index < recorded.count ? Palette.ink : Palette.hairline)
                    .frame(height: index < recorded.count ? 2 : 1)
            }
        }
        .frame(height: 2)
        .animation(Motion.quick, value: recorded.count)
    }

    private var recordedSteps: some View {
        VStack(spacing: 0) {
            ForEach(recorded) { step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(step.timeLabel)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                        .frame(width: 44, alignment: .leading)

                    Text(step.action.label)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.ink)

                    Spacer()

                    if let delta = step.timingDelta {
                        Text(delta)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }
                }
                .padding(.vertical, 7)
            }
        }
    }

    // MARK: - State

    /// The step the timer is waiting on, or nil once they are all logged.
    private var current: RecipeStep? {
        guard recorded.count < steps.count else { return nil }
        return steps[recorded.count]
    }

    private var isFinished: Bool {
        !steps.isEmpty && recorded.count >= steps.count
    }
}
