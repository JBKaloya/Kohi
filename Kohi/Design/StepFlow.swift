import SwiftUI

/// One question, one block. Hairline progress, a 22 pt question, 52 pt
/// choice circles, SKIP in the catalogue voice. Drawn from the stoic. step
/// screens: one filled mark per screen, nothing else competing.
struct StepFlow<Content: View>: View {
    var step: Int
    var total: Int
    var question: String
    var onBack: (() -> Void)?
    var onClose: (() -> Void)?
    var onSkip: (() -> Void)?
    var nextTitle: String = "Next"
    var nextEnabled: Bool = true
    var onNext: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 26)
                .padding(.top, 14)

            Text(question)
                .font(Typography.question)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 26)
                .padding(.top, 28)

            ScrollView {
                content()
                    .padding(.horizontal, 26)
                    .padding(.top, 22)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            footer
                .padding(.horizontal, 26)
                .padding(.bottom, 28)
                .padding(.top, 12)
        }
        .background(Palette.paper.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .touchTarget()
                }
                .buttonStyle(.plain)
            }

            progress
            Spacer(minLength: 8)

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.inkMuted)
                        .touchTarget()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Rectangle()
                    .fill(index == step ? Palette.ink : Palette.hairline)
                    .frame(width: 24, height: 1)
            }
        }
        .accessibilityLabel("\(step + 1) of \(total)")
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack {
                if let onSkip {
                    Button("Skip", action: onSkip)
                        .catalogueLabel()
                        .touchTarget()
                }
                Spacer()
                if let onNext {
                    Button(action: onNext) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.paper)
                            .frame(width: 52, height: 52)
                            .background(nextEnabled ? Palette.ink : Palette.hairline, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!nextEnabled)
                    .accessibilityLabel(nextTitle)
                }
            }
        }
    }
}

/// A 52 pt choice circle. Only one should read as filled on a given screen.
struct StepChoice: View {
    var glyph: EquipmentGlyph?
    var systemName: String?
    var label: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Palette.ink : Color.clear)
                        .overlay(Circle().stroke(Palette.hairline, lineWidth: isSelected ? 0 : 1))
                        .frame(width: 52, height: 52)
                    if let glyph {
                        EquipmentGlyphView(
                            glyph: glyph,
                            size: 22,
                            color: isSelected ? Palette.paper : Palette.ink
                        )
                    } else if let systemName {
                        Image(systemName: systemName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(isSelected ? Palette.paper : Palette.ink)
                    }
                }
                Text(label)
                    .font(Typography.tag)
                    .foregroundStyle(isSelected ? Palette.ink : Palette.inkMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
                    .frame(height: 28)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .touchTarget(52)
    }
}
