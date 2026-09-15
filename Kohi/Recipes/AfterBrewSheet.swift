import SwiftUI

/// After the pour: rating, taste, correction, comment, suggested correction, save.
struct AfterBrewSheet: View {
    let card: CoffeeCard
    let recipe: Recipe
    @State var draft: Brew
    var onSave: (Brew) -> Void

    @Environment(SetupStore.self) private var setup
    @Environment(AIFlags.self) private var flags
    @Environment(AIEventLog.self) private var events
    @Environment(AIFeedbackStore.self) private var feedback
    @Environment(LotFlags.self) private var lotFlags
    @Environment(\.dismiss) private var dismiss

    @State private var showParameters = false
    @State private var tapCount = 0
    @State private var correction: SuggestedCorrection?
    @State private var pickedMove: Int?
    @State private var saveTrigger = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Rectangle()
                                .fill(i == 2 ? Palette.ink : Palette.hairline)
                                .frame(width: 24, height: 1)
                        }
                    }
                    .padding(.bottom, 8)

                    rating
                    if lotFlags.isOn(.taste7) { taste }
                    axes
                    comment
                    suggested
                    parameters
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.medium)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text("Save")
                        .font(Typography.label)
                        .tracking(Typography.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.paper)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Palette.ink, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 26)
                .padding(.bottom, 18)
            }
        }
        .tint(Palette.ink)
        .haptic(.tap, trigger: tapCount)
        .haptic(.saved, trigger: saveTrigger)
        .task { await loadCorrection() }
    }

    private var rating: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rating").catalogueLabel()
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { step in
                    Button {
                        tapCount += 1
                        draft.rating = draft.rating == step ? nil : step
                    } label: {
                        Circle()
                            .fill((draft.rating ?? 0) >= step ? Palette.ink : Color.clear)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Palette.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .touchTarget()
                }
            }
        }
    }

    private var taste: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Taste").catalogueLabel()
            AxisRails(taste: $draft.taste) { tapCount += 1 }
        }
    }

    private var axes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Correction").catalogueLabel()
            axis("Acidity", value: $draft.acidity)
            axis("Bitterness", value: $draft.bitterness)
            axis("Body", value: $draft.body)
        }
    }

    private func axis(_ name: String, value: Binding<Int>) -> some View {
        HStack(spacing: 14) {
            Text(name)
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
                .frame(width: 74, alignment: .leading)
            ForEach([-1, 0, 1], id: \.self) { step in
                Button {
                    tapCount += 1
                    value.wrappedValue = value.wrappedValue == step ? 0 : step
                } label: {
                    Text(step < 0 ? "−" : step > 0 ? "+" : "·")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(value.wrappedValue == step ? Palette.paper : Palette.ink)
                        .frame(width: 28, height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(value.wrappedValue == step ? Palette.ink : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Palette.hairline, lineWidth: value.wrappedValue == step ? 0 : 1)
                                )
                        }
                }
                .buttonStyle(.plain)
                .touchTarget()
            }
        }
    }

    private var comment: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comment").catalogueLabel()
            TextField(Placeholders.text(.brewNotes), text: $draft.notes, axis: .vertical)
                .font(Typography.body)
                .lineLimit(2...6)
            DictationField(text: $draft.notes)
        }
    }

    @ViewBuilder
    private var suggested: some View {
        if let correction {
            VStack(alignment: .leading, spacing: 12) {
                SuggestedCorrectionView(
                    correction: correction,
                    pickedRank: $pickedMove
                ) { move in
                    draft.nextTimeSuggestion = move.change
                }

                if flags.isOn(.aiFeedback), let eventID = correction.eventID {
                    AIFeedbackScale(eventID: eventID, feature: .suggestedCorrection, store: feedback)
                }
            }
        }
    }

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(Motion.snappy) { showParameters.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Parameters").catalogueLabel()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Palette.inkMuted)
                        .rotationEffect(.degrees(showParameters ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if showParameters {
                Text(recipe.compactLine)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                if let tbt = recipe.timeLabel, let actual = draft.timeLabel {
                    Text("\(Copy.totalBrewTime) · target \(tbt) · \(actual)")
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
        }
    }

    private func loadCorrection() async {
        correction = await SuggestedCorrection.ranked(
            for: draft,
            card: card,
            comment: draft.notes,
            equipment: setup.equipment,
            flags: flags,
            events: events
        )
    }

    private func save() {
        saveTrigger += 1
        onSave(draft)
        dismiss()
    }
}
