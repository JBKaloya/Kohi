import SwiftUI

/// Maps between an image's pixel space and the rectangle it is drawn in, for an
/// image shown aspect-**fit**.
///
/// The live overlay's `PreviewMapper` fits the other way, filling and cropping,
/// because that is what the camera preview layer does. Here nothing may be
/// cropped: a corner you cannot see is a corner you cannot drag.
struct FitMapper {
    let imageSize: CGSize
    let viewSize: CGSize

    /// Scale from image pixels to points.
    var scale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
    }

    /// Where the image actually sits inside the view.
    var frame: CGRect {
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (viewSize.width - size.width) / 2,
            y: (viewSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    func map(_ point: CGPoint) -> CGPoint {
        CGPoint(x: frame.minX + point.x * scale, y: frame.minY + point.y * scale)
    }

    func map(_ quad: Quad) -> Quad {
        Quad(
            topLeft: map(quad.topLeft),
            topRight: map(quad.topRight),
            bottomRight: map(quad.bottomRight),
            bottomLeft: map(quad.bottomLeft)
        )
    }

    /// View point back to image pixels, clamped so a corner cannot be dragged
    /// off the picture.
    func unmap(_ point: CGPoint) -> CGPoint {
        guard scale > 0 else { return .zero }
        return CGPoint(
            x: min(max((point.x - frame.minX) / scale, 0), imageSize.width),
            y: min(max((point.y - frame.minY) / scale, 0), imageSize.height)
        )
    }
}

/// The four corners of the crop, laid over the still, each one draggable.
struct QuadEditor: View {
    @Binding var quad: Quad
    let imageSize: CGSize
    /// Drawn magnified in the loupe, so you can see under your thumb.
    let preview: CGImage?

    @State private var dragging: Int?

    private static let handleSize: CGFloat = 30
    private static let loupeSize: CGFloat = 118
    private static let loupeZoom: CGFloat = 2.4

    var body: some View {
        GeometryReader { proxy in
            let mapper = FitMapper(imageSize: imageSize, viewSize: proxy.size)
            let onScreen = mapper.map(quad)

            ZStack(alignment: .topLeading) {
                shade(around: onScreen, in: proxy.size)
                edges(of: onScreen)

                ForEach(0..<4, id: \.self) { index in
                    handle(at: onScreen[index], index: index, mapper: mapper)
                }

                if let dragging {
                    loupe(at: onScreen[dragging], mapper: mapper, in: proxy.size)
                }
            }
        }
    }

    /// Everything outside the crop goes down, which is most of what tells you
    /// what you are about to keep.
    private func shade(around quad: Quad, in size: CGSize) -> some View {
        Canvas { context, _ in
            var path = Path(CGRect(origin: .zero, size: size))
            path.addPath(outline(of: quad))
            context.fill(path, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
    }

    private func edges(of quad: Quad) -> some View {
        Canvas { context, _ in
            context.stroke(outline(of: quad), with: .color(.white.opacity(0.9)), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }

    private func outline(of quad: Quad) -> Path {
        var path = Path()
        path.move(to: quad.topLeft)
        path.addLine(to: quad.topRight)
        path.addLine(to: quad.bottomRight)
        path.addLine(to: quad.bottomLeft)
        path.closeSubpath()
        return path
    }

    private func handle(at point: CGPoint, index: Int, mapper: FitMapper) -> some View {
        let isDragging = dragging == index
        return Circle()
            .fill(.white)
            .frame(width: isDragging ? 18 : 13, height: isDragging ? 18 : 13)
            .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            // The touch target is larger than the dot it draws.
            .frame(width: Self.handleSize, height: Self.handleSize)
            .contentShape(.circle)
            .position(point)
            .animation(Motion.quick, value: isDragging)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        dragging = index
                        quad[index] = mapper.unmap(value.location)
                    }
                    .onEnded { _ in dragging = nil }
            )
    }

    /// Pinned to a top corner rather than following the finger, so it never ends
    /// up under the hand that is placing the point.
    private func loupe(at point: CGPoint, mapper: FitMapper, in size: CGSize) -> some View {
        let frame = mapper.frame
        let zoom = Self.loupeZoom
        let radius = Self.loupeSize / 2

        return Color.black
            .frame(width: Self.loupeSize, height: Self.loupeSize)
            // The magnified image is positioned against the loupe's own top-left
            // corner, which only holds if the loupe already has its size. As a
            // plain stack child the scaled-up image would size the stack instead
            // and take that origin with it, leaving a black circle.
            .overlay(alignment: .topLeading) {
                if let preview {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: frame.width * zoom, height: frame.height * zoom)
                        // Slide the enlarged image until the corner being
                        // dragged sits under the crosshair.
                        .offset(
                            x: radius - (point.x - frame.minX) * zoom,
                            y: radius - (point.y - frame.minY) * zoom
                        )
                }
            }
            .overlay { crosshair }
            .clipShape(.circle)
            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
            .position(
                // Opposite side to the finger.
                x: point.x > size.width / 2 ? radius + 22 : size.width - radius - 22,
                y: radius + 74
            )
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    private var crosshair: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.85)).frame(width: 1, height: 22)
            Rectangle().fill(.white.opacity(0.85)).frame(width: 22, height: 1)
        }
    }
}
