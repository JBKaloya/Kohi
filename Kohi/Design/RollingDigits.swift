import SwiftUI

/// One digit, drawn as a strip of 0…base and a second 0, sitting at `position`
/// taken round `base`. `position` is a count, not a digit: see `RollMath`.
struct RollColumn: View, Animatable {
    var position: Double
    var base: Int
    var cell: CGFloat
    var fontSize: CGFloat
    var reduceMotion: Bool

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        let b = max(base, 1)
        let wrapped = position.rollMod(Double(b))
        let fraction = abs(position - position.rounded())
        let smear = reduceMotion ? 0 : min(3, fraction * 6)
        let width = fontSize * 0.62
        VStack(spacing: 0) {
            ForEach(0...b, id: \.self) { digit in
                Text("\(digit % b)")
                    .font(.system(size: fontSize, weight: .regular))
                    .monospacedDigit()
                    .frame(width: width, height: cell)
            }
        }
        .offset(y: -CGFloat(wrapped) * cell)
        .frame(width: width, height: cell, alignment: .top)
        .clipped()
        .blur(radius: smear > 0.15 ? smear : 0)
    }
}

/// A row of rolling columns. Least-significant place is `counts[0]`.
/// `separators[place]` is drawn to the left of that column — a decimal point
/// sits at place 0, a clock's colon at place 1.
struct RollingDigits: View {
    var counts: [Int]
    var bases: [Int]
    var show: Int
    var separators: [Int: String] = [:]
    var cell: CGFloat
    var fontSize: CGFloat
    var color: Color = Palette.ink

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var positions: [Double]

    init(
        counts: [Int],
        bases: [Int],
        show: Int,
        separators: [Int: String] = [:],
        cell: CGFloat,
        fontSize: CGFloat,
        color: Color = Palette.ink
    ) {
        self.counts = counts
        self.bases = bases
        self.show = show
        self.separators = separators
        self.cell = cell
        self.fontSize = fontSize
        self.color = color
        _positions = State(initialValue: counts.map(Double.init))
    }

    var body: some View {
        let places = counts.count
        HStack(spacing: 0) {
            ForEach((0..<places).reversed(), id: \.self) { place in
                let visible = place < show
                if let mark = separators[place] {
                    Text(mark)
                        .font(.system(size: fontSize, weight: .regular))
                        .foregroundStyle(color)
                        .frame(width: place + 1 < show ? fontSize * 0.32 : 0)
                        .clipped()
                        .opacity(place + 1 < show ? 1 : 0)
                }
                RollColumn(
                    position: positions.indices.contains(place) ? positions[place] : Double(counts[place]),
                    base: bases.indices.contains(place) ? bases[place] : 10,
                    cell: cell,
                    fontSize: fontSize,
                    reduceMotion: reduceMotion
                )
                .foregroundStyle(color)
                .frame(width: visible ? fontSize * 0.62 : 0)
                .clipped()
                .opacity(visible ? 1 : 0)
                .animation(columnAnimation(place: place), value: positions.indices.contains(place) ? positions[place] : 0)
            }
        }
        .mask(fade)
        .onChange(of: counts) { _, new in sync(to: new) }
    }

    private var fade: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.18),
                .init(color: .black, location: 0.82),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func columnAnimation(place: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return Motion.roll.delay(Double(place) * Motion.rollStagger)
    }

    private func sync(to new: [Int]) {
        var next = positions
        if next.count != new.count {
            next = new.map(Double.init)
        }
        var jumped = false
        for place in new.indices {
            let base = Double(bases.indices.contains(place) ? bases[place] : 10)
            let landed = RollMath.jumped(from: next[place], to: Double(new[place]), base: base)
            if landed != next[place] {
                next[place] = landed
                jumped = true
            }
        }
        let target = new.map(Double.init)
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { positions = target }
            return
        }
        // A jump and the spring have to be two updates. One assignment is
        // coalesced, and the column then spins the whole gap.
        if jumped {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { positions = next }
            DispatchQueue.main.async { positions = target }
        } else {
            positions = target
        }
    }
}

private extension Double {
    func rollMod(_ base: Double) -> Double {
        let remainder = truncatingRemainder(dividingBy: base)
        return remainder < 0 ? remainder + base : remainder
    }
}
