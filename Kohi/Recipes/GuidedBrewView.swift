import Combine
import os
import SwiftUI
import UIKit

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
    var voiceNote: BrewVoiceNote
    var equipment: [Equipment] = []
    var onFinish: (Brew) -> Void
    var onCancel: () -> Void
    /// Tests snapshot the first frame without starting the clock.
    var startsRunning: Bool = true
    var journeyStep: Int = 3
    var journeyTotal: Int = 5

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
    /// 3, 2, 1 before the clock. Nil once the brew is running.
    @State private var countdown: Int?
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
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .touchTarget()
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 4) {
                        ForEach(0..<max(journeyTotal, 1), id: \.self) { index in
                            Rectangle()
                                .fill(index == journeyStep ? Palette.ink : Palette.hairline)
                                .frame(width: 24, height: 1)
                        }
                    }
                    Spacer(minLength: 8)
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
                    finishedBlock
                } else if isFinished {
                    finishedBlock
                } else if let countdown {
                    Text("\(countdown)")
                        .font(Typography.number)
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { skipCountdown() }
                } else {
                    currentBlock
                        .contentShape(Rectangle())
                        .onTapGesture { advance() }
                    if isRinse {
                        Button("Skip") { skipRinse() }
                            .catalogueLabel()
                            .padding(.horizontal, 26)
                            .padding(.top, 8)
                    }
                    voiceNoteRow
                        .padding(.horizontal, 26)
                        .padding(.top, 18)
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
        .clipped()
        .animation(Motion.snappy, value: notesFocused)
        .fieldKeyboardClearance()
        .opacity(appeared ? 1 : 0)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            seedPlan()
            if startsRunning, !isRinse { beginCountdown() }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            autoTask?.cancel()
            cancellable?.cancel()
            running = false
            voiceNote.stop()
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

    private var isWait: Bool {
        guard index < steps.count else { return false }
        let action = steps[index].action
        return action == .wait || action == .steep
    }

    private var tideFill: Double {
        let base = GuidedTarget.fill(
            steps: steps,
            index: index,
            elapsed: elapsed,
            total: recipe.seconds,
            water: recipe.water ?? brew.water
        )
        guard isWait, running, index < steps.count else { return base }
        let start = Double(steps[index].at)
        let end = GuidedTarget.targetTime(for: steps, at: index, total: recipe.seconds)
        let span = max(end - start, 1)
        let t = min(max(elapsed - start, 0), span) / span
        return base * (1 - 0.45 * t)
    }

    @ViewBuilder
    private var currentBlock: some View {
        let step = steps[index]
        VStack(alignment: .leading, spacing: 10) {
            Text(step.action.label)
                .catalogueLabel()

            if step.action == .rinse {
                Text(rinseHeadline(step))
                    .font(Typography.number)
                    .foregroundStyle(Palette.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                if let prep = prepLine {
                    Text(prep)
                        .font(Typography.value)
                        .foregroundStyle(Palette.inkMuted)
                }
            } else if isWait {
                Text("Wait")
                    .font(Typography.number)
                    .foregroundStyle(Palette.ink)
                if let next = nextLine {
                    Text(next)
                        .font(Typography.value)
                        .foregroundStyle(Palette.ink)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                }
            } else if let target = step.targetMass, step.action == .pour || step.action == .bloom {
                Text("to \(GrindRange.number(target)) g")
                    .font(Typography.number)
                    .foregroundStyle(Palette.ink)

                Text("now \(GrindRange.number(nowMass(for: step))) g")
                    .font(Typography.value)
                    .foregroundStyle(Palette.inkMuted)
                    .monospacedDigit()
                if let agitation = step.agitation, agitation != .none {
                    Text("Agitation · \(agitation.label)")
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
            } else {
                Text(step.instruction)
                    .font(Typography.number)
                    .foregroundStyle(Palette.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
            }

            if let with = accessoryLine(for: step) {
                Text(with)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
            if recipe.advanceMode == .cues, let cue = step.cue {
                Text(cue.label)
                    .font(Typography.value)
                    .foregroundStyle(Palette.ink)
            } else if let next = nextLine, !isWait {
                Text(next)
                    .font(Typography.value)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 26)
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
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                stop(finish: true)
            }
        }
    }

    private var isFinished: Bool {
        !steps.isEmpty && index >= steps.count
    }

    private var isRinse: Bool {
        index < steps.count && steps[index].action == .rinse
    }

    private func rinseHeadline(_ step: RecipeStep) -> String {
        var parts = [step.action.label]
        if let mass = step.targetMass {
            parts.append("\(GrindRange.number(mass)) g")
        }
        let extra = step.note.trimmingCharacters(in: .whitespaces)
        if !extra.isEmpty { parts.append(extra) }
        return parts.joined(separator: " · ")
    }

    private var nextLine: String? {
        guard index + 1 < steps.count else { return nil }
        let next = steps[index + 1]
        if isWait { return "next pour at \(next.timeLabel)" }
        return "next: \(next.instruction.lowercased())"
    }

    private var prepLine: String? {
        let names = brew.equipmentIDs.compactMap { id -> String? in
            guard let item = equipment.first(where: { $0.id == id }), item.kind == .accessory else { return nil }
            return item.displayName
        }
        guard !names.isEmpty else { return nil }
        return names.joined(separator: " · ")
    }

    private func accessoryLine(for step: RecipeStep) -> String? {
        let names = step.accessoryIDs.compactMap { id in
            equipment.first { $0.id == id }?.displayName
        }
        guard !names.isEmpty else { return nil }
        return "with " + names.joined(separator: " · ")
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

    private func beginCountdown() {
        guard countdown == nil, !running else { return }
        if recipe.advanceMode == .cues {
            startClock()
            return
        }
        countdown = 3
        tickTrigger += 1
        autoTask?.cancel()
        autoTask = Task {
            for value in [2, 1] {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, countdown != nil else { return }
                countdown = value
                tickTrigger += 1
            }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, countdown != nil else { return }
            countdown = nil
            startClock()
        }
    }

    private func skipCountdown() {
        autoTask?.cancel()
        countdown = nil
        if !running { startClock() }
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
            startedAt: started,
            isRecording: voiceNote.isRecording
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
        let leavingRinse = isRinse
        recordCurrent(skipped: false)
        stepTrigger += 1
        withAnimation(Motion.quick) { index += 1 }
        autoArmed = false
        if leavingRinse, !running, startsRunning {
            beginCountdown()
        }
        if isFinished {
            brew.seconds = Int(elapsed)
        }
        pushLiveActivity(force: true)
    }

    private func skipRinse() {
        guard isRinse else { return }
        recordCurrent(skipped: true)
        stepTrigger += 1
        withAnimation(Motion.quick) { index += 1 }
        autoArmed = false
        if !running, startsRunning { beginCountdown() }
        pushLiveActivity(force: true)
    }

    private func armAutoAdvanceIfNeeded() {
        guard recipe.advanceMode == .auto, !steps.isEmpty, index < steps.count, !autoArmed, !isRinse else { return }
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

    private func recordCurrent(skipped: Bool = false) {
        guard index < steps.count else { return }
        let planned = steps[index]
        brew.steps.append(BrewStep(
            index: index,
            action: planned.action,
            at: planned.action == .rinse ? 0 : Int(elapsed),
            mass: skipped ? nil : recordedMass(for: planned),
            targetAt: planned.untilSeconds ?? planned.at,
            targetMass: planned.targetMass,
            note: planned.note,
            skipped: skipped,
            agitation: planned.agitation
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
            force: force,
            isRecording: voiceNote.isRecording
        )
    }

    private func stop(finish: Bool) {
        guard !handedOff else { return }
        handedOff = true
        autoTask?.cancel()
        cancellable?.cancel()
        running = false
        brew.seconds = Int(elapsed)
        if index < steps.count {
            recordCurrent(skipped: false)
        }
        brew.actualSource = brew.actualSource == .none ? .timer : brew.actualSource
        brew.recipeName = brew.recipeName ?? recipe.name
        brew.refreshPourRates()
        voiceNote.stop()
        BrewLiveActivity.end()
        if finish {
            onFinish(brew)
        } else {
            onCancel()
        }
    }

    private func seedPlan() {
        brew.plannedSteps = steps.enumerated().map { index, step in
            BrewStep(
                index: index,
                action: step.action,
                at: 0,
                targetAt: step.untilSeconds ?? step.at,
                targetMass: step.targetMass,
                note: step.note,
                agitation: step.agitation
            )
        }
        if brew.recipeName == nil { brew.recipeName = recipe.name }
    }

    private var voiceNoteRow: some View {
        VoiceNoteControl(note: voiceNote, action: toggleVoiceNote)
    }

    private func toggleVoiceNote() {
        if voiceNote.isRecording || voiceNote.state == .paused {
            voiceNote.stop()
            pushLiveActivity(force: true)
            return
        }
        Task {
            await voiceNote.start(brewID: brew.id)
            pushLiveActivity(force: true)
        }
    }
}
