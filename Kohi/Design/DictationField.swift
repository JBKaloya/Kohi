import SwiftUI

/// Dictate into a free-text binding. The keyboard stays; this is the other
/// way in. Same 1.1 s shade and tap-to-undo as a brew fill. The parent field
/// still shows the text — this is only the mic.
struct DictationField: View {
    @Binding var text: String
    var prompt: String = Copy.dictate
    /// Words this field expects, from `CoffeeLexicon`. Built when the mic
    /// opens rather than on every render of the form around it.
    var vocabulary: () -> [String] = { [] }

    @State private var dictation = Dictation()
    @State private var trigger = 0
    @State private var before: String?

    var body: some View {
        SayItLabel(
            isListening: dictation.isListening,
            transcript: dictation.transcript,
            prompt: promptForState,
            listeningPrompt: Copy.listeningTapToStop,
            hint: hint
        ) {
            Task { await toggle() }
        }
        .guessHighlight(trigger: trigger, onUndo: undo)
        .onDisappear { dictation.cancel() }
    }

    private var promptForState: String {
        switch dictation.state {
        case .unavailable: Copy.dictationUnavailable
        case .busy: Copy.anotherFieldIsListening
        case .paused: Copy.dictationPaused
        case .denied, .idle, .listening: prompt
        }
    }

    private var hint: String? {
        switch dictation.state {
        case .denied: "Dictation needs the microphone. Settings has the switch."
        case .unavailable: Copy.dictationUnavailable
        case .busy: Copy.anotherFieldIsListening
        case .paused: Copy.dictationPaused
        case .idle, .listening: nil
        }
    }

    private func toggle() async {
        if dictation.isListening || dictation.state == .paused {
            let spoken = await dictation.stop()
            guard !spoken.isEmpty else { return }
            before = text
            withAnimation(Motion.snappy) {
                text = DictationTranscript.apply(spoken, to: text)
                trigger += 1
            }
            return
        }
        dictation.reset()
        dictation.contextualStrings = vocabulary()
        await dictation.start()
    }

    private func undo() {
        guard let before else { return }
        withAnimation(Motion.snappy) { text = before }
        self.before = nil
    }
}
