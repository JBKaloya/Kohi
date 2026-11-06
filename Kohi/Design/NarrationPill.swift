import SwiftUI

/// Tap to record, tap the disc to keep, × to throw it away.
///
/// Bencho's original is hold-to-record. A brew note is not a quick message:
/// the hands are on the kettle, and the note can run for a minute, so the
/// gesture is a toggle. Slide-to-cancel went with the hold.
///
/// The level while recording comes from `BrewVoiceNote`. Nothing here opens
/// the microphone itself.
struct NarrationPill: View {
    var note: BrewVoiceNote
    var brewID: UUID
    var tone: Tone = .paper

    enum Tone {
        case paper, ink
    }

    private let openWidth: CGFloat = 300
    private let idleWidth: CGFloat = 216
    private let height: CGFloat = 56
    private let bars = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var labelSize: CGFloat = 16

    private var open: Bool {
        note.isRecording || note.state == .paused || showsClip
    }

    private var showsClip: Bool {
        note.hasFile && !note.isRecording && note.state != .paused && note.state != .transcribing
    }

    var body: some View {
        VStack(spacing: 8) {
            pill
                .frame(width: open ? openWidth : idleWidth, height: height)
                .background(slab, in: Capsule())
                .foregroundStyle(ink)
                .animation(reduceMotion ? nil : Motion.open, value: open)
            hint
                .frame(height: 18)
        }
        .frame(width: openWidth)
    }

    private var slab: Color {
        tone == .ink ? Palette.ink : Palette.well
    }

    private var ink: Color {
        tone == .ink ? Palette.paper : Palette.ink
    }

    private var sub: Color {
        tone == .ink ? Palette.paper.opacity(0.55) : Palette.inkMuted
    }

    @ViewBuilder
    private var pill: some View {
        if note.isRecording || note.state == .paused {
            recording
        } else if showsClip {
            clip
        } else {
            idle
        }
    }

    private var idle: some View {
        Button {
            Task { await note.start(brewID: brewID) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text(Copy.tapToNarrate)
                    .font(.system(size: labelSize, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Copy.tapToNarrate)
    }

    private var recording: some View {
        HStack(spacing: 10) {
            disc(label: "Stop and keep") { stopKeeping() } 
                icon: {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(tone == .ink ? Palette.ink : Palette.paper)
                        .frame(width: 13, height: 13)
                }
            Circle()
                .fill(Color(red: 0.745, green: 0.290, blue: 0.235))
                .frame(width: 7, height: 7)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(elapsed(at: context.date))
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .frame(width: 40, alignment: .leading)
            }
            wave(note.levels, progress: nil)
            Button {
                note.discard()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(sub)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Discard")
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
    }

    private var clip: some View {
        HStack(spacing: 10) {
            disc(label: note.isPlaying ? "Pause" : "Play") {
                note.togglePlayback()
            } icon: {
                Image(systemName: note.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tone == .ink ? Palette.ink : Palette.paper)
                    .contentTransition(.symbolEffect(.replace))
            }
            wave(note.levels, progress: note.progress)
                .gesture(scrub)
            Text(clipTime)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(sub)
                .frame(width: 40)
            Button {
                note.discard()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(sub)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Discard")
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
    }

    private func disc<Icon: View>(label: String, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            icon()
                .frame(width: 44, height: 44)
                .background(ink, in: Circle())
        }
        .buttonStyle(PressStyle(scale: 0.96))
        .accessibilityLabel(label)
    }

    private func wave(_ samples: [Double], progress: Double?) -> some View {
        let drawn = resample(samples, count: bars)
        return HStack(alignment: .center, spacing: 0) {
            ForEach(drawn.indices, id: \.self) { index in
                let level = min(1, max(0, drawn[index] * 1.1))
                Capsule()
                    .fill(ink)
                    .frame(width: 3, height: 4 + level * 28)
                    .opacity(barOpacity(index: index, progress: progress))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 32)
    }

    private func barOpacity(index: Int, progress: Double?) -> Double {
        guard let progress else { return 1 }
        return progress * Double(bars) > Double(index) ? 1 : 0.3
    }

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let width = max(openWidth - 160, 1)
                note.seek(to: gesture.location.x / width)
            }
    }

    @ViewBuilder
    private var hint: some View {
        if note.isRecording || note.state == .paused {
            Text(note.state == .paused ? Copy.dictationPaused : Copy.tapStopWhenDone)
                .font(.system(size: 13))
                .foregroundStyle(sub)
        } else if note.state == .denied {
            Text(Copy.microphoneDenied)
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
        } else if note.state == .failed {
            Text(Copy.dictationUnavailable)
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
        } else {
            Color.clear
        }
    }

    private func stopKeeping() {
        let took = note.startedAt.map { Date().timeIntervalSince($0) } ?? 0
        if took < 0.5 {
            note.discard()
        } else {
            note.stop()
        }
    }

    private func elapsed(at now: Date) -> String {
        guard let started = note.startedAt else { return "0:00" }
        let seconds = max(Int(now.timeIntervalSince(started)), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var clipTime: String {
        let total = max(note.recordedSeconds, 0)
        let shown = note.progress > 0 && note.progress < 1 ? note.progress * total : total
        let seconds = Int(shown)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func resample(_ source: [Double], count: Int) -> [Double] {
        guard !source.isEmpty else { return Array(repeating: 0, count: count) }
        return (0..<count).map { index in
            let start = source.count * index / count
            let end = max(start + 1, source.count * (index + 1) / count)
            return source[start..<min(end, source.count)].max() ?? 0
        }
    }
}
