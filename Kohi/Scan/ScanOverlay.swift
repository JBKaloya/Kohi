import SwiftUI

/// The outline that follows the card, plus one line of coaching. Everything
/// here is driven by the tracker; there is no state of its own.
struct ScanOverlay: View {
    let detection: DocumentTracker.Detection?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                if let detection {
                    let mapper = PreviewMapper(
                        frameSize: detection.frameSize,
                        viewSize: proxy.size
                    )
                    QuadOutline(
                        quad: mapper.map(detection.quad),
                        progress: detection.coaching.progress
                    )
                }

                coaching
                    .padding(.bottom, 138)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var coaching: some View {
        let state = detection?.coaching ?? .searching
        return Text(state.message)
            .font(Typography.coaching)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.black.opacity(0.34), in: .capsule)
            .id(state.message)
            .transition(.opacity.combined(with: .offset(y: 6)))
            .animation(Motion.snappy, value: state.message)
    }
}

/// Maps points from the camera frame into the preview, matching the preview
/// layer's aspect-fill crop.
struct PreviewMapper {
    let frameSize: CGSize
    let viewSize: CGSize

    func map(_ point: CGPoint) -> CGPoint {
        guard frameSize.width > 0, frameSize.height > 0 else { return .zero }
        let scale = max(viewSize.width / frameSize.width, viewSize.height / frameSize.height)
        let scaled = CGSize(width: frameSize.width * scale, height: frameSize.height * scale)
        let origin = CGPoint(
            x: (viewSize.width - scaled.width) / 2,
            y: (viewSize.height - scaled.height) / 2
        )
        return CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale)
    }

    func map(_ quad: Quad) -> Quad {
        Quad(
            topLeft: map(quad.topLeft),
            topRight: map(quad.topRight),
            bottomRight: map(quad.bottomRight),
            bottomLeft: map(quad.bottomLeft)
        )
    }
}

/// The card's edges, with corner ticks that close in as the lock completes.
private struct QuadOutline: View {
    let quad: Quad
    let progress: Double

    var body: some View {
        Canvas { context, _ in
            var path = Path()
            path.move(to: quad.topLeft)
            path.addLine(to: quad.topRight)
            path.addLine(to: quad.bottomRight)
            path.addLine(to: quad.bottomLeft)
            path.closeSubpath()

            let settle = Motion.Overlay.settle
            context.fill(
                path,
                with: .color(.white.opacity(settle(Motion.Overlay.fillOpacity, progress)))
            )
            context.stroke(
                path,
                with: .color(.white.opacity(settle(Motion.Overlay.strokeOpacity, progress))),
                lineWidth: settle(Motion.Overlay.strokeWidth, progress)
            )

            // Ticks at each corner grow toward the lock, so the moment of
            // capture is visible before it happens.
            let length = settle(Motion.Overlay.tickLength, progress)
            for (corner, neighbours) in [
                (quad.topLeft, [quad.topRight, quad.bottomLeft]),
                (quad.topRight, [quad.topLeft, quad.bottomRight]),
                (quad.bottomRight, [quad.topRight, quad.bottomLeft]),
                (quad.bottomLeft, [quad.bottomRight, quad.topLeft]),
            ] {
                var tick = Path()
                for neighbour in neighbours {
                    let dx = neighbour.x - corner.x
                    let dy = neighbour.y - corner.y
                    let distance = max(hypot(dx, dy), 0.001)
                    tick.move(to: corner)
                    tick.addLine(
                        to: CGPoint(
                            x: corner.x + dx / distance * length,
                            y: corner.y + dy / distance * length
                        )
                    )
                }
                context.stroke(
                    tick,
                    with: .color(.white),
                    lineWidth: settle(Motion.Overlay.tickWidth, progress)
                )
            }
        }
        .blendMode(.plusLighter)
    }
}
