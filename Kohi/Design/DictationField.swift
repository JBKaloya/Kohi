import SwiftUI

/// Dictate into a free-text binding. The keyboard stays; this is the other
/// way in. Same 1.1 s shade and tap-to-undo as a brew fill. The parent field
/// still shows the text — this is only the mic.
struct DictationField: View {
    @Binding var text: String
    var prompt: String = Copy.dictate

    @State private var dictation = Dictation()
    @State private var trigger = 0
    @State private var before: String?

    var body: some View {
        Group {
            if Dictation.isSupported {
                SayItLabel(
                    isListening: dictation.isListening,
                    transcript: dictation.transcript,
                    prompt: dictation.state == .unavailable ? Copy.dictationUnavailable : prompt,
                    hint: hint
                ) {
                    Task { await toggle() }
                }
                .guessHighlight(trigger: trigger, onUndo: undo)
            }
        }
        .onDisappear { dictation.cancel() }
    }

    private var hint: String? {
        switch dictation.state {
        case .denied: "Dictation needs the microphone. Settings has the switch."
        case .unavailable: Copy.dictationUnavailable
        case .idle, .listening: nil
        }
    }

    private func toggle() async {
        guard dictation.isListening else {
            await dictation.start()
            return
        }
        let spoken = await dictation.stop()
        guard !spoken.isEmpty else { return }
        before = text
        let joined = [text, spoken]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        withAnimation(Motion.snappy) {
            text = joined
            trigger += 1
        }
    }

    private func undo() {
        guard let before else { return }
        withAnimation(Motion.snappy) { text = before }
        self.before = nil
    }
}
