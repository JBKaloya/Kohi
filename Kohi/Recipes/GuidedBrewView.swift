import Combine
import SwiftUI

/// Hands a recipe, a coffee, and a draft brew to the guided timer.
struct GuidedSession: Identifiable {
    let id = UUID()
    let card: CoffeeCard
    let recipe: Recipe
    var brew: Brew
}

/// One block, one step. Tap anywhere is Next. The mass target interpolates
/// through the pour so you can see where the scale should be now.
struct GuidedBrewView: View {
    let card: CoffeeCard
    let recipe: Recipe
    @State var brew: Brew
    var onFinish: (Brew) -> Void
    var onCancel: () -> Void
    /// Tests snapshot the first frame without starting the clock.
    var startsRunning: Bool = true

    @State private var elapsed: TimeInterval = 0
    @State private var running = false
    @State private var start: Date?
    @State private var cancellable: AnyCancellable?
    @State private var index = 0
    @State private var autoArmed = false
    @State private var autoTask: Task<Void, Never>?
    @State private var stepTrigger = 0
    @State private var tickTrigger = 0
    @State private var appeared = true
    @State private var handedOff = false
    @FocusState private var notesFocused: Bool

    private var steps: [RecipeStep] { recipe.steps }

    var body: some View {
        ZStack {
            PourFill(
                fill: tideFill,
                showsTide: GuidedTarget.showsTide(brew.method ?? recipe.method),
                activeRing: GuidedTarget.showsRings(brew.method ?? recipe.method)
                    ? GuidedTarget.activeRing(steps: steps, index: index)
                    : nil
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(steps.isEmpty ? "1 / 1" : "\(min(index + 1, max(steps.count, 1))) / \(max(steps.count, 1))")
                        .catalogueLabel()
                    Spacer()
                    Text(clock)
                        .font(Typography.number)
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 26)
                .padding(.top, 18)

                Spacer(minLength: 12)

                if steps.isEmpty {
                    emptyClock
                } else if isFinished {
                    finishedBlock
                } else {
                    currentBlock
                        .contentShape(Rectangle())
                        .onTapGesture { advance() }
                }

                Spacer()

                if !notesFocused {
                    Button("Stop") {
                        stop(finish: true)
                    }
                    .catalogueLabel()
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 36)
                    .transition(.opacity)
                }
            }
        }
        .animation(Motion.snappy, value: notesFocused)
        .fieldKeyboardClearance()
        .opacity(appeared ? 1 : 0)
        .onAppear {
            if startsRunning { startClock() }
        }
        .onDisappear {
            autoTask?.cancel()
            cancellable?.cancel()
            running = false
            BrewLiveActivity.end()
        }
        .haptic(.stepAdvance, trigger: stepTrigger)
        .haptic(.tick, trigger: tickTrigger)
        .onChange(of: Int(elapsed)) { _, value in
            armAutoAdvanceIfNeeded()
            tickTrigger = value
            pushLiveActivity()
        }
    }

    private var clock: String {
        let seconds = Int(elapsed)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var tideFill: Double {
        GuidedTarget.fill(
            steps: steps,
            index: index,
            elapsed: elapsed,
            total: recipe.seconds,
            water: recipe.water ?? brew.water
        )
    }

    @ViewBuilder
    private var currentBlock: some View {
        let step = steps[index]
        VStack(alignment: .leading, spacing: 10) {
            Text(step.action.label)
                .catalogueLabel()

            if let target = step.targetMass {
                Text("to \(GrindRange.number(target)) g")
                    .font(Typography.number)
                    .foregroundStyle(Palette.ink)

                Text("now \(GrindRange.number(nowMass(for: step))) g")
                    .font(Typography.value)
                    .foregroundStyle(Palette.inkMuted)
                    .monospacedDigit()
            } else {
                Text(step.instruction)
                    .font(Typography.number)
                    .foregroundStyle(Palette.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
            }

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Palette.ink)
                        .frame(width: progressWidth, height: 1)
                }

            HStack {
                if recipe.autoAdvance {
                    Text("auto")
                        .catalogueLabel()
                } else {
                    Text("manual")
                        .catalogueLabel()
                }
                Spacer()
                if let next = nextLine {
                    Text(next)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 26)
    }

    private var emptyClock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Copy.whatYoureDoing)
                .catalogueLabel()
            TextField(
                "Bloom, two pours, a swirl — stop when the cup is done",
                text: $brew.notes,
                axis: .vertical
            )
            .font(Typography.body)
            .foregroundStyle(Palette.ink)
            .lineLimit(3...8)
            .focused($notesFocused)
            .reportsFieldFocus(notesFocused)
            DictationField(text: $brew.notes)
        }
        .padding(.horizontal, 26)
        .scrollDismissesKeyboard(.interactively)
    }

    private var finishedBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Copy.totalBrewTime)
                .catalogueLabel()
            Text(clock)
                .font(Typography.number)
                .foregroundStyle(Palette.ink)
            if let target = recipe.timeLabel {
                Text("target \(target)")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
        }
        .padding(.horizontal, 26)
        .contentShape(Rectangle())
        .onTapGesture { stop(finish: true) }
        .onAppear {
            autoTask?.cancel()
            autoTask = Task {
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled else { return }
                stop(finish: true)
            }
        }
    }

    private var isFinished: Bool {
        !steps.isEmpty && index >= steps.count
    }

    private var nextLine: String? {
        guard index + 1 < steps.count else { return nil }
        let next = steps[index + 1]
        return "next: \(next.instruction.lowercased())"
    }

    private var progressWidth: CGFloat {
        guard !steps.isEmpty, index < steps.count else { return 0 }
        let start = Double(steps[index].at)
        let end = GuidedTarget.targetTime(for: steps, at: index, total: recipe.seconds)
        let span = max(end - start, 1)
        let t = min(max(elapsed - start, 0), span) / span
        return CGFloat(t) * 180
    }

    private func nowMass(for step: RecipeStep) -> Double {
        let startMass = GuidedTarget.startMass(for: steps, at: index)
        let target = step.targetMass ?? startMass
        let startTime = Double(step.at)
        let endTime = GuidedTarget.targetTime(for: steps, at: index, total: recipe.seconds)
        return GuidedTarget.massNow(
            startMass: startMass,
            targetMass: target,
            startTime: startTime,
            targetTime: endTime,
            at: elapsed
        )
    }

    private func startClock() {
        running = true
        let started = Date.now.addingTimeInterval(-elapsed)
        start = started
        BrewLiveActivity.start(
            card: card,
            recipe: recipe,
            brew: brew,
            index: index,
            elapsed: elapsed,
            startedAt: started
        )
        cancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { now in
                guard let start else { return }
                elapsed = now.timeIntervalSince(start)
            }
    }

    private func advance() {
        guard !isFinished, index < steps.count else { return }
        recordCurrent()
        stepTrigger += 1
        withAnimation(Motion.quick) { index += 1 }
        autoArmed = false
        if isFinished {
            brew.seconds = Int(elapsed)
        }
        pushLiveActivity(force: true)
    }

    private func armAutoAdvanceIfNeeded() {
        guard recipe.autoAdvance, !steps.isEmpty, index < steps.count, !autoArmed else { return }
        let end = GuidedTarget.targetTime(for: steps, at: index, total: recipe.seconds)
        guard elapsed >= end else { return }
        autoArmed = true
        autoTask?.cancel()
        autoTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, autoArmed, running else { return }
            advance()
        }
    }

    private func recordCurrent() {
        guard index < steps.count else { return }
        let planned = steps[index]
        brew.steps.append(BrewStep(
            index: index,
            action: planned.action,
            at: Int(elapsed),
            mass: recordedMass(for: planned),
            targetAt: planned.at,
            targetMass: planned.targetMass,
            note: planned.note
        ))
    }

    private func recordedMass(for planned: RecipeStep) -> Double? {
        planned.targetMass.map { _ in nowMass(for: planned) }
    }

    private func pushLiveActivity(force: Bool = false) {
        guard running, let start else { return }
        BrewLiveActivity.update(
            recipe: recipe,
            brew: brew,
            index: index,
            elapsed: elapsed,
            startedAt: start,
            force: force
        )
    }

    private func stop(finish: Bool) {
        guard !handedOff else { return }
        handedOff = true
        autoTask?.cancel()
        cancellable?.cancel()
        running = false
        brew.seconds = Int(elapsed)
        BrewLiveActivity.end()
        if finish {
            onFinish(brew)
        } else {
            onCancel()
        }
    }
}
