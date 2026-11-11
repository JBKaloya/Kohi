import SwiftUI

/// Dose and water for this cup. Temperature, grind, and equipment stay on the
/// recipe and the kit; they are not edited here.
struct BrewDialView: View {
    @Bindable var session: BrewSession
    var onBack: () -> Void
    var onClose: () -> Void
    var onBrewNow: () -> Void
    var onAlreadyBrewed: () -> Void

    @Environment(SetupStore.self) private var setup
    @Environment(RecipeStore.self) private var recipes
    @State private var lift: CGFloat = 0
    @State private var resizeTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Palette.ink.ignoresSafeArea()
            VStack {
                Spacer()
                brewPreview
                    .padding(.bottom, 160)
            }
            StepFlow(
                step: session.progressIndex,
                total: session.progressTotal,
                question: Copy.howMuch,
                onBack: onBack,
                onClose: onClose,
                bottom: AnyView(brewBar),
                sheetLift: lift
            ) {
            VStack(alignment: .leading, spacing: 22) {
                if session.logsElsewhere {
                    Text(Copy.logWithoutTimerHint)
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                }
                if let applied = session.lastApplication {
                    AppliedFromLastBlock(
                        change: applied.change,
                        onKeep: { session.keepLastApplication() },
                        onUndo: { session.undoLastApplication() }
                    )
                }
                if let source = sourceLine {
                    Text(source)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
                KitSummaryRow(session: session)
                advanceRow
                parameters
                if !session.logsElsewhere {
                    Text(Copy.logWithoutTimerHint)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            .padding(.bottom, 24)
        }
        .onAppear {
            BrewPrefill.ensureMatchingBrewer(on: &session.brew, setup: setup)
        }
        .onDisappear { resizeTask?.cancel() }
        }
    }

    /// The swipe lives on the ink bar, and logging without the timer sits on
    /// that same bar: the swipe replaces the sheet's footer, so a control left
    /// up in the sheet scrolls out of reach.
    private var brewBar: some View {
        VStack(spacing: 0) {
            if !session.logsElsewhere {
                Button(action: onAlreadyBrewed) {
                    Text(Copy.logWithoutTimer)
                        .catalogueLabel()
                        .foregroundStyle(Palette.paper)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            SwipeToStart(lift: $lift) {
                withAnimation(Motion.Lift.commit) { onBrewNow() }
            }
        }
        .background(Palette.ink)
    }

    /// Auto by default. Tap waits for you, Cues shows what to look for.
    private var advanceRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(Copy.advance).catalogueLabel()
                .frame(width: 74, alignment: .leading)
            ChipRail {
                ForEach(AdvanceMode.allCases) { mode in
                    TagChip(text: Self.advanceLabel(mode), isSelected: session.advanceMode == mode) {
                        session.setAdvanceMode(mode, store: recipes)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.advance)
    }

    static func advanceLabel(_ mode: AdvanceMode) -> String {
        switch mode {
        case .auto: "Auto"
        case .manual: "Tap"
        case .cues: "Cues"
        }
    }

    private var brewPreview: some View {
        VStack(spacing: 8) {
            Text(sourceLine ?? "")
                .font(Typography.tag)
                .foregroundStyle(Palette.paper.opacity(0.55))
            RollingDigits(
                counts: RollMath.clockCounts(seconds: 0).counts,
                bases: RollMath.clockCounts(seconds: 0).bases,
                show: 3,
                separators: [1: ":"],
                cell: 48,
                fontSize: 40,
                color: Palette.paper
            )
        }
    }

    private var ratioRow: some View {
        HStack {
            Text("Ratio").catalogueLabel()
            Spacer()
            if let scaled = ratioScaled {
                HStack(spacing: 0) {
                    Text("1:")
                        .font(.system(size: 20))
                        .foregroundStyle(Palette.ink)
                    RollingDigits(
                        counts: RollMath.counts(of: scaled, places: 4),
                        bases: Array(repeating: 10, count: 4),
                        show: RollMath.shownPlaces(scaled: scaled, decimals: 1, places: 4),
                        separators: [0: "."],
                        cell: 28,
                        fontSize: 20
                    )
                }
            } else {
                Text("—")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.hairline)
            }
        }
        .frame(height: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    private var ratioScaled: Int? {
        guard let dose = session.brew.dose, dose > 0,
              let liquid = session.brew.water ?? session.brew.beverage, liquid > 0
        else { return nil }
        return Int(((liquid / dose) * 10).rounded())
    }

    /// Rinse comes from the paper and the brewer. Preheat and tare are the
    /// rest of what has to be true before the first pour. Nothing here is saved.
    private var prepItems: [String] {
        var items: [String] = []
        let brewer = session.brew.equipmentIDs
            .compactMap { setup.equipment(id: $0) }
            .first { BrewKit.isCupboard($0.kind) }
        let stock = session.brew.filterStockId.flatMap { setup.filterStock(id: $0) }
        if let brewer, let caption = RinseRule.caption(for: stock, brewer: brewer) {
            items.append(caption.prefix(1).uppercased() + caption.dropFirst())
        } else {
            items.append(Copy.rinseTheFilter)
        }
        items.append(Copy.preheatTheServer)
        items.append(Copy.tareTheScale)
        return items
    }

    private var sourceLine: String? {
        let name = (session.recipe?.name ?? session.brew.recipeName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty { return name }
        return session.brew.method?.label
    }

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let note = scaleNote {
                Text(note)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                if let scale = session.brew.waterScale, scale != 1,
                   RecipeScaling.factorBounds.contains(scale) {
                    Button("Reset") {
                        if let nominal = session.nominalRecipe {
                            session.brew.dose = nominal.dose
                            session.brew.water = nominal.water
                            session.brew.beverage = nominal.beverage
                            session.resizeRecipeToBrew()
                        }
                    }
                    .catalogueLabel()
                }
            }

            RollingCounter(
                Copy.coffeeDose,
                value: doseBinding,
                range: .dose,
                unit: "g",
                placeholder: Placeholders.text(.brewDose),
                presence: .useful,
                hint: session.nominalRecipe?.dose.map { "Recipe \(GrindRange.number($0)) g" },
                style: .brew
            )

            ratioRow

            RollingCounter(
                session.brew.method == .espresso ? Copy.beverage : Copy.waterWeight,
                value: waterBinding,
                range: session.brew.method == .espresso ? .beverage : .water,
                unit: "g",
                placeholder: session.brew.method == .espresso
                    ? Placeholders.text(.brewBeverage)
                    : Placeholders.text(.brewWater),
                presence: .useful,
                style: .brew
            )

            TickList(title: Copy.beforeYouPour, items: prepItems)

            if let label = rescaledLabel {
                Text(label)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }

            if let cups = RecipeScaling.cupEstimateLabel(for: session.brew.water ?? session.brew.beverage) {
                Text(cups).catalogueLabel()
            }
        }
    }

    private var scaleNote: String? {
        guard let nominal = session.nominalRecipeLiquid,
              let live = RecipeScaling.liquid(of: session.brew),
              abs(live - nominal) > 1
        else { return nil }
        let factor = live / nominal
        if !RecipeScaling.factorBounds.contains(factor) {
            return Copy.tooFarFromRecipe
        }
        return "Scaled from \(GrindRange.number(nominal)) g → \(GrindRange.number(live)) g"
    }

    /// Dose binding. The dose alone does not resize the sequence: the step
    /// masses follow the water, not the coffee.
    private var doseBinding: Binding<Double?> {
        Binding(
            get: { session.brew.dose },
            set: { newDose in
                session.brew.dose = newDose
                session.brew.captureSource = .typed
            }
        )
    }

    /// Water (or beverage out, on espresso). Writing it resizes the attached
    /// recipe through `BrewSession`, which owns the nominal baseline.
    private var waterBinding: Binding<Double?> {
        if session.brew.method == .espresso {
            return Binding(
                get: { session.brew.beverage },
                set: { newVal in
                    session.brew.beverage = newVal
                    session.brew.captureSource = .typed
                    scheduleResize()
                }
            )
        }
        return Binding(
            get: { session.brew.water },
            set: { newVal in
                session.brew.water = newVal
                session.brew.captureSource = .typed
                scheduleResize()
            }
        )
    }

    /// A held key steps the number every few dozen milliseconds. The binding
    /// updates each step; the recipe resize waits until the finger pauses.
    private func scheduleResize() {
        resizeTask?.cancel()
        resizeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            session.resizeRecipeToBrew()
        }
    }

    /// Confirmation line, shown only when the sequence actually moved off the
    /// recipe as written.
    private var rescaledLabel: String? {
        guard session.recipe != nil,
              let nominal = session.nominalRecipeLiquid,
              let live = RecipeScaling.liquid(of: session.brew),
              abs(live - nominal) > 1
        else { return nil }
        return "Steps rescaled to \(GrindRange.number(live)) g"
    }
}
