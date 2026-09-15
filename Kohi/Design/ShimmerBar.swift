import SwiftUI

/// A rounded bar that pulses with a travelling highlight, used as a field
/// placeholder while the OCR read is in progress.
struct ShimmerBar: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Palette.hairline.opacity(0.55))
            .frame(width: .random(in: 60...120), height: 14)
            .overlay {
                GeometryReader { geo in
                    let w = geo.size.width
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.clear, Palette.paperShade, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: w * 0.6)
                        .offset(x: -w * 0.3 + phase * w * 1.3)
                }
                .clipped()
            }
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}
