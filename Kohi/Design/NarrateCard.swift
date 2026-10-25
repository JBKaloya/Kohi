import SwiftUI

/// A compact card for the brew timer that explains and controls Narrate.
///
/// Before the first tap it shows one sentence of context so the tester
/// knows what the button does. Once recording, the card collapses to the
/// live timer and the stop-label — same grammar as the rest of the screen.
///
/// Design rules:
/// - Same hairline border as `FieldGroup`, so it reads as a form cell.
/// - Never takes more vertical space than necessary.
/// - No microphone icon is shown while recording: the dot on `SayItLabel`
///   is breathing already, that is enough motion.
struct NarrateCard: View {
    var note: BrewVoiceNote
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title row — always visible.
            Text("Narrate")
                .catalogueLabel()

            // Body: context before recording, live timer during.
            Group {
                if note.isRecording {
                    recordingBody
                } else {
                    idleBody
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(note.isRecording ? Palette.ink : Palette.hairline, lineWidth: 1)
        )
        .animation(Motion.snappy, value: note.isRecording)
    }

    // MARK: - States

    private var idleBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Talk while you pour — say what you're doing, any detour from the plan, or a quick tasting note. It lands in What you did after the brew.")
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            SayItLabel(
                isListening: false,
                transcript: "",
                prompt: Copy.narrate,
                listeningPrompt: Copy.recordingTapToStop,
                action: action
            )
        }
    }

    private var recordingBody: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            SayItLabel(
                isListening: true,
                transcript: elapsed(at: context.date),
                prompt: Copy.narrate,
                listeningPrompt: Copy.recordingTapToStop,
                action: action
            )
        }
    }

    // MARK: - Helpers

    private func elapsed(at now: Date) -> String {
        guard let started = note.startedAt else { return "" }
        let seconds = max(Int(now.timeIntervalSince(started)), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
