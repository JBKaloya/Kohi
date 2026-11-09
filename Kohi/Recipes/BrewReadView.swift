import SwiftUI

/// For next time. The cup is already noted; this is where you say what you'd
/// change, see what the extraction and the coffee say about it, and keep one
/// move. Reachable again from every past brew, and saved as you go.
struct BrewReadView: View {
    @Bindable var session: BrewSession
    var previous: Brew?
    var onAgain: (() -> Void)?
    var onDone: () -> Void

    @State private var pickedMove: Int?
    @State private var correction: SuggestedCorrection?
    @State private var didLoad = false
    @State private var isAsking = false
    @Environment(AIFlags.self) private var flags
    @Environment(AIFeedbackStore.self) private var feedback
    @Environment(CardStore.self) private var store
    @Environment(SetupStore.self) private var setup
    @Environment(AIEventLog.self) private var events

    private var reading: ExtractionReading {
        ExtractionReading.read(session.brew, card: session.card)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text(Copy.improveTitle)
                    .font(Typography.question)
                    .foregroundStyle(Palette.ink)

                wishes
                extraction
                coffee
                intelligence

                compareBlock

                if session.brew.tds != nil || session.brew.extractionYield != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TDS & yield").catalogueLabel()
                        Text(yieldLine).font(Typography.value)
                    }
                }

                if let onAgain {
                    Button(action: onAgain) {
                        Text(Copy.brewAgain)
                            .font(Typography.label)
                            .tracking(Typography.labelTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.paper)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Palette.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button("Done", action: onDone)
                    .catalogueLabel()
                    .frame(maxWidth: .infinity)
            }
            .padding(26)
        }
        .scrollIndicators(.hidden)
        .background(Palette.paper.ignoresSafeArea())
        .onAppear(perform: load)
    }

    // MARK: - What you'd change

    private var wishes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Copy.whatYoudChange).catalogueLabel()
            ForEach(BrewWish.Axis.allCases) { axis in
                CorrectionAxis(
                    name: axis.label,
                    value: wishBinding(axis),
                    caption: { BrewWish.caption(axis, wish: $0) }
                )
            }
        }
    }

    private func wishBinding(_ axis: BrewWish.Axis) -> Binding<Int> {
        Binding(
            get: { BrewWish.wish(axis, of: session.brew) },
            set: { wish in
                BrewWish.set(axis, wish: wish, on: &session.brew)
                session.saveEdits(store: store, events: events)
                pickedMove = nil
                correction = fallback()
            }
        )
    }

    // MARK: - Your extraction, the coffee

    private var extraction: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Copy.yourExtraction).catalogueLabel()
            Text(session.brew.actualSource.provenance)
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
            PourCurve(
                actual: session.brew.actualSteps,
                planned: session.brew.plannedSteps,
                rates: session.brew.pourRates,
                highlightUntil: reading.firstMinuteFlow == nil ? nil : 60
            )
            factorRows(reading.extractionFactors)
        }
    }

    @ViewBuilder
    private var coffee: some View {
        let rows = reading.coffeeFactors
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(Copy.theCoffee).catalogueLabel()
                factorRows(rows)
            }
        }
    }

    private func factorRows(_ rows: [ExtractionReading.Factor]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.label)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                        .frame(width: 96, alignment: .leading)
                    Text(row.value)
                        .font(Typography.value)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                }
            }
        }
    }

    // MARK: - Coffee Intelligence

    @ViewBuilder
    private var intelligence: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let correction {
                SuggestedCorrectionView(
                    correction: correction,
                    pickedRank: $pickedMove
                ) { move in
                    session.recordSuggestion(move.change, store: store, events: events)
                }
                if flags.isOn(.aiFeedback), let eventID = correction.eventID {
                    AIFeedbackScale(eventID: eventID, feature: .suggestedCorrection, store: feedback)
                }
            } else {
                Text(Copy.notEnoughToGoOn)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
            if flags.isOn(.suggestedCorrection), correction?.isModel != true {
                HStack(spacing: 10) {
                    CoffeeIntelligenceButton(subtitle: nil, action: askModel)
                        .disabled(isAsking)
                    if isAsking { ProgressView().controlSize(.mini) }
                }
            }
            if let next = session.brew.nextTimeSuggestion, !next.isEmpty {
                Text("\(Copy.useNextTime): \(next)")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.ink)
            }
        }
    }

    private func fallback() -> SuggestedCorrection? {
        SuggestedCorrection.fallback(
            from: session.brew,
            card: session.card,
            equipment: setup.equipment,
            filterStock: setup.filterStock,
            tasting: TastingIntent.confirmed(from: session.brew.notes)
        )
    }

    private func askModel() {
        isAsking = true
        Task {
            if let ranked = await SuggestedCorrection.ranked(
                for: session.brew,
                card: session.card,
                comment: session.brew.notes,
                equipment: setup.equipment,
                filterStock: setup.filterStock,
                flags: flags,
                events: events
            ) {
                correction = ranked
                pickedMove = nil
            }
            isAsking = false
        }
    }

    /// A note that already said "lacks complexity" fills that wish, once.
    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let before = session.brew
        TastingIntent.prefill(&session.brew, from: TastingIntent.confirmed(from: session.brew.notes))
        if session.brew != before { session.saveEdits(store: store, events: events) }
        correction = session.brew == before ? (session.frozenCorrection ?? fallback()) : fallback()
        if let next = session.brew.nextTimeSuggestion {
            pickedMove = correction?.moves.first { $0.change == next }?.rank
        }
    }

    // MARK: - Compare

    @ViewBuilder
    private var compareBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Compare").catalogueLabel()
            if session.brew.ratingHalves == nil {
                Text(Copy.addRatingToCompareLater)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            } else if let previous {
                Text(BrewDiagnosis.compare(session.brew, to: previous).joined(separator: " · "))
                    .font(Typography.value)
                    .foregroundStyle(Palette.ink)
            } else {
                Text("No earlier brew of this coffee")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
        }
    }

    private var yieldLine: String {
        var parts: [String] = []
        if let tds = session.brew.tds { parts.append("TDS \(GrindRange.number(tds))") }
        if let yield = session.brew.extractionYield { parts.append("yield \(GrindRange.number(yield)) %") }
        return parts.joined(separator: " · ")
    }
}
