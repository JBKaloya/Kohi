import SwiftUI

/// Seven axes as a hairline heptagon, ink on paper.
struct TasteRadar: View {
    let taste: TasteProfile
    var previous: TasteProfile?
    var size: CGFloat = 168
    /// Current series. Comparison overlays pass `Palette.primary`.
    var currentColor: Color = Palette.ink
    /// Previous series. Comparison overlays pass `Palette.secondary`.
    var previousColor: Color = Palette.inkMuted

    private let axes = TasteAxis.allCases

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(canvasSize.width, canvasSize.height) / 2 - Motion.Radar.labelOffset
            drawWeb(context, center: center, radius: radius)
            if let previous, !previous.isEmpty {
                drawShape(
                    previous,
                    in: context,
                    center: center,
                    radius: radius,
                    stroke: previousColor,
                    fill: true,
                    dots: true
                )
            }
            if !taste.isEmpty {
                drawShape(
                    taste,
                    in: context,
                    center: center,
                    radius: radius,
                    stroke: currentColor,
                    fill: true,
                    dots: true
                )
            }
        }
        .overlay { labels }
        .frame(width: size, height: size)
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .animation(Motion.quick, value: taste)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(taste.accessibilityLabel)
    }

    private var labels: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = min(proxy.size.width, proxy.size.height) / 2 - Motion.Radar.labelOffset
            ForEach(Array(axes.enumerated()), id: \.element.id) { index, axis in
                Text(axis.label.uppercased())
                    .font(Typography.label)
                    .tracking(Typography.labelTracking)
                    .foregroundStyle(taste[axis] == nil ? Palette.hairline : Palette.inkMuted)
                    .position(labelPoint(index: index, center: center, radius: radius))
            }
        }
    }

    private func drawWeb(_ context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        for ring in Motion.Radar.rings {
            var path = Path()
            for index in axes.indices {
                let point = point(index: index, value: Double(ring), center: center, radius: radius)
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            path.closeSubpath()
            context.stroke(path, with: .color(Palette.hairline), lineWidth: Motion.Radar.stroke)
        }
        for index in axes.indices {
            var spoke = Path()
            spoke.move(to: center)
            spoke.addLine(to: point(index: index, value: 10, center: center, radius: radius))
            context.stroke(spoke, with: .color(Palette.hairline), lineWidth: Motion.Radar.stroke)
        }
    }

    private func drawShape(
        _ profile: TasteProfile,
        in context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        stroke: Color,
        fill: Bool,
        dots: Bool
    ) {
        let scored = axes.enumerated().compactMap { index, axis -> (Int, Int)? in
            guard let value = profile[axis] else { return nil }
            return (index, value)
        }
        guard scored.count >= 2 else {
            if let only = scored.first {
                let p = point(index: only.0, value: Double(only.1), center: center, radius: radius)
                if dots {
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(stroke))
                }
            }
            return
        }
        var path = Path()
        for (i, pair) in scored.enumerated() {
            let p = point(index: pair.0, value: Double(pair.1), center: center, radius: radius)
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        if fill {
            context.fill(path, with: .color(stroke.opacity(Motion.Radar.fillOpacity)))
        }
        context.stroke(path, with: .color(stroke), lineWidth: Motion.Radar.stroke)
        if dots {
            for pair in scored {
                let p = point(index: pair.0, value: Double(pair.1), center: center, radius: radius)
                let r = Motion.Radar.vertex
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - r / 2, y: p.y - r / 2, width: r, height: r)),
                    with: .color(stroke)
                )
            }
        }
    }

    private func angle(index: Int) -> Double {
        -.pi / 2 + 2 * .pi * Double(index) / Double(axes.count)
    }

    private func point(index: Int, value: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let theta = angle(index: index)
        let r = radius * CGFloat(value) / 10
        return CGPoint(x: center.x + r * cos(theta), y: center.y + r * sin(theta))
    }

    private func labelPoint(index: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let theta = angle(index: index)
        let r = radius + Motion.Radar.labelOffset
        return CGPoint(x: center.x + r * cos(theta), y: center.y + r * sin(theta))
    }
}
