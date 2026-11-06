import SwiftUI

/// "What are you scanning?", asked from the home when you stand at a café.
///
/// The rows name the object, not the place: you can be in a café and scan a
/// bag you are taking home. Swiping the sheet down answers nothing.
struct ScanIntentSheet: View {
    static let height: CGFloat = 250

    let suggestion: PlaceSuggestion
    let onAnswer: (ScanAnswer) -> Void

    @State private var answered = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(Copy.whatAreYouScanning)
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                row(Copy.aCupAt(suggestion.place.name), detail: Copy.addATasting) {
                    answer(.cup)
                }
                Rectangle().fill(Palette.hairline).frame(height: 1)
                row(Copy.aBagForMyCollection, detail: Copy.addToCoffeeCollection) {
                    answer(.bag)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.paper.ignoresSafeArea())
        .presentationDetents([.height(Self.height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.paper)
        .haptic(.step, trigger: answered)
    }

    private func answer(_ answer: ScanAnswer) {
        answered += 1
        onAnswer(answer)
    }

    private func row(_ title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Typography.value)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(detail)
                        .catalogueLabel()
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.inkMuted)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
