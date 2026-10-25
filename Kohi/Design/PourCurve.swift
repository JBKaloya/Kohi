import SwiftUI

/// Cumulative mass against time. The slope is the pour rate.
struct PourCurve: View {
    var actual: [BrewStep]
    var planned: [BrewStep]
    var rates: [PourRate]
    var height: CGFloat = 160
    /// Shades the curve up to this second: the first minute, where the
    /// agitation that sets bitterness happens.
    var highlightUntil: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Copy.pourRateIsAgitation).catalogueLabel()
            if actual.isEmpty {
                Text("No pour recorded")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            } else {
                Canvas { context, size in
                    draw(context: context, size: size)
                }
                .frame(height: height)
                .background(Palette.paper)
                .accessibilityLabel("Pour curve")
                if !planned.isEmpty && !actual.isEmpty {
                    Text("Target · You")
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
                ForEach(rates) { rate in
                    Text(rate.tag)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
        }
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        let all = actual + planned
        let maxMass = max(all.compactMap(\.mass).max() ?? 0, all.compactMap(\.targetMass).max() ?? 0, 50)
        let maxTime = max(all.map(\.at).max() ?? 1, all.compactMap(\.targetAt).max() ?? 1, 1)
        let massCeiling = ceil(maxMass / 50) * 50

        func point(time: Int, mass: Double) -> CGPoint {
            let x = CGFloat(time) / CGFloat(maxTime) * size.width
            let y = size.height - CGFloat(mass) / massCeiling * size.height
            return CGPoint(x: x, y: y)
        }

        var grid = Path()
        var grams = 50.0
        while grams <= massCeiling {
            let y = point(time: 0, mass: grams).y
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
            grams += 50
        }
        context.stroke(grid, with: .color(Palette.hairline), lineWidth: 1)

        if let highlightUntil, highlightUntil > 0 {
            let x = min(size.width, point(time: highlightUntil, mass: 0).x)
            context.fill(
                Path(CGRect(x: 0, y: 0, width: x, height: size.height)),
                with: .color(Palette.hairline.opacity(0.35))
            )
        }

        let both = !planned.isEmpty && !actual.isEmpty
        if !planned.isEmpty {
            context.stroke(
                path(steps: planned, point: point, mass: \.targetMass, time: \.targetAt),
                with: .color(both ? Palette.secondary : Palette.ink),
                lineWidth: 1
            )
        }
        if !actual.isEmpty {
            context.stroke(
                path(steps: actual, point: point, mass: \.mass, time: { $0.at }),
                with: .color(both ? Palette.primary : Palette.ink),
                lineWidth: 1
            )
        }
    }

    private func path(
        steps: [BrewStep],
        point: (Int, Double) -> CGPoint,
        mass: (BrewStep) -> Double?,
        time: (BrewStep) -> Int?
    ) -> Path {
        var path = Path()
        var last = CGPoint(x: 0, y: point(0, 0).y)
        path.move(to: last)
        for step in steps.sorted(by: { (time($0) ?? $0.at) < (time($1) ?? $1.at) }) {
            guard let grams = mass(step) else { continue }
            let at = time(step) ?? step.at
            let next = point(at, grams)
            path.addLine(to: next)
            last = next
        }
        return path
    }
}
