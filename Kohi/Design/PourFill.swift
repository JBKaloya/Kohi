import SwiftUI

/// The cup filling behind the guided timer. A straight tide, no waves.
/// V60 adds three hairline circles: bloom, main pour, wide pour.
struct PourFill: View {
    var fill: Double
    var showsTide: Bool
    var activeRing: Int?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Palette.paper
                if showsTide {
                    tide(in: geo.size)
                }
                if let activeRing {
                    rings(in: geo.size, active: activeRing)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tide(in size: CGSize) -> some View {
        let height = size.height * min(max(fill, 0), 1)
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
            Rectangle()
                .fill(Palette.paperShade)
                .frame(height: height)
        }
    }

    private func rings(in size: CGSize, active: Int) -> some View {
        let shortest = min(size.width, size.height)
        let diameters: [CGFloat] = [0.28, 0.52, 0.72]
        return ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .strokeBorder(
                        ring == active ? Palette.ink : Palette.hairline,
                        lineWidth: 1
                    )
                    .frame(width: shortest * diameters[ring], height: shortest * diameters[ring])
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}
