import SwiftUI

/// Four-level usefulness scale under every model output.
struct AIFeedbackScale: View {
    var eventID: UUID?
    var feature: AIFeature
    var store: AIFeedbackStore

    @State private var score: AIFeedbackScore?
    @State private var comment = ""
    @State private var tapCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How useful was this?")
                .catalogueLabel()

            HStack(spacing: 0) {
                ForEach(AIFeedbackScore.allCases) { level in
                    Button {
                        tapCount += 1
                        score = level
                        save()
                    } label: {
                        VStack(spacing: 6) {
                            if score == level {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                            } else {
                                Color.clear.frame(height: 10)
                            }
                            Text(level.label)
                                .catalogueLabel()
                                .foregroundStyle(score == level ? Palette.ink : Palette.inkMuted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }

            if score != nil {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("What would have helped?", text: $comment, axis: .vertical)
                        .font(Typography.body)
                        .lineLimit(1...4)
                        .onChange(of: comment) { _, _ in save() }
                    DictationField(text: $comment)
                }
            }
        }
        .haptic(.tap, trigger: tapCount)
        .onAppear {
            if let eventID, let existing = store.items.first(where: { $0.aiEventId == eventID }) {
                score = existing.score
                comment = existing.comment ?? ""
            }
        }
    }

    private func save() {
        guard let score else { return }
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        store.add(AIFeedback(
            aiEventId: eventID,
            feature: feature,
            score: score,
            comment: trimmed.isEmpty ? nil : trimmed
        ))
    }
}
