import SwiftUI

/// One question, one answer, its sources named underneath.
///
/// Not a chat: there is no thread, no history, no follow-up. A question about
/// extraction is answered and the sheet closes — turning this into a
/// conversation would make the app somewhere to talk about coffee rather than
/// somewhere to keep it.
struct AskSheet: View {
    @Environment(AIFlags.self) private var flags
    @Environment(AIEventLog.self) private var events
    @Environment(AIFeedbackStore.self) private var feedback
    @Environment(\.dismiss) private var dismiss

    var topic: String?

    @State private var question = ""
    @State private var answer: Ask.Answer?
    @State private var isAsking = false
    @State private var failed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    field

                    if isAsking {
                        ShimmerBar()
                            .frame(height: 1)
                    }

                    if let answer { answerBlock(answer) }
                    if failed { failureBlock }

                    if answer == nil, !isAsking, !failed { examples }
                }
                .padding(.horizontal, 26)
                .padding(.top, 18)
                .padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .tint(Palette.ink)
        .task { isFocused = true }
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(Placeholders.text(.askQuestion), text: $question, axis: .vertical)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .lineLimit(1...4)
                .focused($isFocused)
                .onSubmit(ask)

            DictationField(text: $question)

            Rectangle().fill(Palette.hairline).frame(height: 1)

            Button("Ask", action: ask)
                .font(Typography.tag)
                .foregroundStyle(question.trimmed == nil ? Palette.hairline : Palette.ink)
                .disabled(question.trimmed == nil || isAsking)
        }
    }

    private func answerBlock(_ answer: Ask.Answer) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            InsightBlock(
                title: "Answer",
                bodyText: answer.text,
                provenance: askProvenance(answer),
                isModel: true
            ) {
                if !answer.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(answer.sources) { source in
                            Text("\(source.title) · \(source.source)")
                                .font(Typography.tag)
                                .foregroundStyle(Palette.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if flags.isOn(.aiFeedback) {
                AIFeedbackScale(eventID: answer.eventID, feature: .ask, store: feedback)
            }
        }
        .transition(.opacity)
    }

    private func askProvenance(_ answer: Ask.Answer) -> String {
        if !answer.isCovered, answer.tag == "general" {
            return "GENERAL COFFEE KNOWLEDGE"
        }
        if let first = answer.sources.first {
            return "SOURCE: \(first.source)"
        }
        return "SOURCE: KNOWLEDGE BASE"
    }

    private var failureBlock: some View {
        Text("No answer came back. Check the connection and try again.")
            .font(Typography.tag)
            .foregroundStyle(Palette.inkMuted)
    }

    /// What the base actually covers, so the first question is not a guess at
    /// the feature's boundaries.
    private var examples: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("It knows about").catalogueLabel()
            ForEach([
                "How grind size changes extraction",
                "What TDS and extraction yield mean",
                "Which water hardness suits filter coffee",
                "Why a coffee needs to rest after roasting",
            ], id: \.self) { example in
                Button(example) {
                    question = example
                    ask()
                }
                .font(Typography.body)
                .foregroundStyle(Palette.inkMuted)
                .multilineTextAlignment(.leading)
            }
        }
    }

    private func ask() {
        guard let text = question.trimmed, !isAsking else { return }
        isAsking = true
        failed = false
        answer = nil
        Task {
            let result = await Ask.answer(to: text, topic: topic, flags: flags, events: events)
            withAnimation(Motion.snappy) {
                answer = result
                failed = result == nil
                isAsking = false
            }
        }
    }
}
