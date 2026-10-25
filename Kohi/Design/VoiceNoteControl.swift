import SwiftUI

/// Record a brew-length note. Same mic grammar as `SayItLabel`, with elapsed
/// time while the file is open.
struct VoiceNoteControl: View {
    var note: BrewVoiceNote
    var action: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            SayItLabel(
                isListening: note.isRecording,
                transcript: note.isRecording ? elapsed(at: context.date) : "",
                prompt: prompt,
                listeningPrompt: Copy.recordingTapToStop,
                hint: hint
            ) {
                action()
            }
        }
    }

    private var prompt: String {
        switch note.state {
        case .failed: Copy.dictationUnavailable
        case .denied: Copy.narrate
        case .paused: Copy.dictationPaused
        case .transcribing: Copy.transcribingBrewNote
        case .idle, .recording: Copy.narrate
        }
    }

    private var hint: String? {
        switch note.state {
        case .failed: Copy.dictationUnavailable
        case .denied: Copy.microphoneDenied
        case .paused: Copy.dictationPaused
        default: nil
        }
    }

    private func elapsed(at now: Date) -> String {
        guard let started = note.startedAt else { return "" }
        let seconds = max(Int(now.timeIntervalSince(started)), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
