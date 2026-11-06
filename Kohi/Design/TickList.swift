import SwiftUI

/// A short list you tick off. One spring per row, and the fill, the tick,
/// the strike and the fading words are four readings of it.
///
/// The fill takes the raw value, so the box swells past full and settles.
/// The tick and the strike take it clamped: a tick that overshoots draws
/// past its own end, and a strike that overshoots runs off the word.
/// The strike starts a tenth of the way in and finishes a little early,
/// so the box answers first and the words are crossed out after.
struct TickList: View {
    var title: String
    var items: [String]
    @State private var done: [Bool] = []

    var body: some View {
        let flags = aligned
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).scalingCatalogueLabel()
                Spacer(minLength: 8)
                Text(flags.allSatisfy { $0 } && !flags.isEmpty ? "Ready" : "\(flags.filter { $0 }.count) / \(items.count)")
                    .scalingCatalogueLabel()
                    .foregroundStyle(flags.allSatisfy { $0 } && !flags.isEmpty ? Palette.ink : Palette.inkMuted)
            }
            .padding(.bottom, 2)
            ForEach(items.indices, id: \.self) { index in
                TickRow(text: items[index], on: flags[index]) {
                    if done.count != items.count { done = items.map { _ in false } }
                    done[index].toggle()
                }
            }
        }
        .onAppear {
            if done.count != items.count { done = items.map { _ in false } }
        }
        .onChange(of: items) { _, new in
            done = new.map { _ in false }
        }
    }

    private var aligned: [Bool] {
        if done.count == items.count { return done }
        return items.map { _ in false }
    }
}

private struct TickRow: View {
    var text: String
    var on: Bool
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0
    @State private var checkTick = 0

    private let side: CGFloat = 20

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                box
                words
                Spacer(minLength: 0)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(on ? "Checked" : "Not checked")
        .haptic(.check, trigger: checkTick)
        .onAppear { progress = on ? 1 : 0 }
        .onChange(of: on) { _, new in
            if reduceMotion {
                progress = new ? 1 : 0
            } else {
                withAnimation(Motion.tick) { progress = new ? 1 : 0 }
            }
            if new { checkTick += 1 }
        }
    }

    private var held: Double { min(1, max(0, progress)) }

    private var cut: Double {
        min(1, max(0, (held - Motion.tickLag) / Motion.tickRun))
    }

    private var box: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.32, style: .continuous)
                .strokeBorder(Palette.ink.opacity(0.28), lineWidth: 1.5)
            RoundedRectangle(cornerRadius: side * 0.32, style: .continuous)
                .fill(Palette.ink)
                .scaleEffect(progress)
            CheckStroke()
                .trim(from: 0, to: held)
                .stroke(Palette.paper, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: side * 0.68, height: side * 0.68)
        }
        .frame(width: side, height: side)
        .clipped()
    }

    private var words: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Palette.ink.opacity(1 - 0.58 * held))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Palette.ink)
                    .frame(height: 1.5)
                    .scaleEffect(x: cut, y: 1, anchor: .leading)
            }
    }
}

/// The tick, as a path that can be trimmed from its start.
private struct CheckStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.40, y: rect.maxY - rect.height * 0.22))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.22))
        return path
    }
}
