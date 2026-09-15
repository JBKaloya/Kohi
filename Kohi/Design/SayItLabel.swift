import SwiftUI

/// Dictate — the keyboard-free way into a form.
///
/// A line of type with a dot, not a microphone button: pressing it should feel
/// like starting to talk, not like operating a recorder. While it listens the
/// dot breathes and the transcript appears underneath, so you can see it
/// hearing you before you trust it with a whole sentence.
struct SayItLabel: View {
    let isListening: Bool
    let transcript: String
    var prompt: String = "Dictate"
    var hint: String?
    let action: () -> Void

    @State private var breathing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "mic")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isListening ? Palette.ink : Palette.inkMuted)
                        .scaleEffect(breathing ? 1.15 : 1)
                        .opacity(breathing ? 0.55 : 1)

                    Text(isListening ? "Listening — tap to stop" : prompt)
                        .catalogueLabel()
                }
            }
            .buttonStyle(.plain)
            .touchTarget()

            if isListening, !transcript.isEmpty {
                Text(transcript)
                    .font(Typography.body)
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            } else if let hint, !isListening {
                Text(hint)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
        }
        .animation(Motion.quick, value: isListening)
        .animation(Motion.quick, value: transcript)
        .onChange(of: isListening) { _, listening in
            guard listening else { breathing = false; return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
        .haptic(.listening, trigger: isListening)
    }
}

/// The paper shade that says "this was filled in for you".
///
/// It fades after 1.1 s and a tap on it undoes the fill. Nothing is ever
/// silently written into a field you did not touch: either you see it arrive,
/// or it did not happen.
struct GuessHighlight: ViewModifier {
    /// Bumped by the caller each time something is filled in.
    let trigger: Int
    /// Called when the highlight is tapped, which means "put it back".
    var onUndo: (() -> Void)?

    @State private var isShowing = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: Motion.Field.focusShadeRadius)
                    .fill(Palette.paperShade)
                    .opacity(isShowing ? 1 : 0)
                    .padding(.horizontal, -Motion.Field.focusShadePad.h)
                    .padding(.vertical, -Motion.Field.focusShadePad.v)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard isShowing, let onUndo else { return }
                onUndo()
                withAnimation(Motion.quick) { isShowing = false }
            }
            .onChange(of: trigger) { _, _ in
                withAnimation(Motion.quick) { isShowing = true }
                Task {
                    try? await Task.sleep(for: .milliseconds(1100))
                    withAnimation(Motion.gentle) { isShowing = false }
                }
            }
    }
}

extension View {
    /// Marks a field that was just filled in on your behalf.
    func guessHighlight(trigger: Int, onUndo: (() -> Void)? = nil) -> some View {
        modifier(GuessHighlight(trigger: trigger, onUndo: onUndo))
    }
}
