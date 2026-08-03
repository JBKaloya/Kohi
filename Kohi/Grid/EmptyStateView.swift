import SwiftUI

/// What the archive looks like before it has anything in it. One outlined card
/// and one line of type; the scan button is the only thing to press.
struct EmptyStateView: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 26) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1.2)
                .frame(width: 132, height: 176)
                .overlay(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule()
                                .fill(Palette.hairline)
                                .frame(width: [64.0, 44.0, 54.0][index], height: 1.2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 34)
                }

            VStack(spacing: 7) {
                Text("Nothing collected yet")
                    .font(Typography.value)
                    .foregroundStyle(Palette.ink)
                Text("Scan the card that comes with your next coffee")
                    .font(Typography.subtitle)
                    .foregroundStyle(Palette.inkMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : Motion.Chrome.emptyStateRise)
        .onAppear {
            withAnimation(Motion.gentle.delay(Motion.Chrome.emptyStateDelay)) { appeared = true }
        }
    }
}

#Preview {
    ZStack {
        Palette.paper.ignoresSafeArea()
        EmptyStateView()
    }
}
