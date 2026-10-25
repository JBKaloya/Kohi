import SwiftUI

/// Shown when a scan reads as a coffee the archive already has.
///
/// Three answers, and none of them merge on their own. Dismissing the sheet
/// throws the scan away; "This is a different coffee" is what keeps it.
struct DuplicateSheet: View {
    let offer: DuplicateOffer
    let onOpen: () -> Void
    let onDifferent: () -> Void
    let onAddPhoto: () -> Void

    private var title: String {
        switch offer.match.confidence {
        case .strong:
            Copy.duplicateTitle
        case .probable:
            Copy.duplicateProbable(offer.match.card.displayName)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(Typography.title)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if offer.match.confidence == .strong {
                        Text(offer.match.card.displayName)
                            .font(Typography.subtitle)
                            .foregroundStyle(Palette.ink)
                    }
                    if !offer.match.card.roaster.isEmpty {
                        Text(offer.match.card.roaster)
                            .font(Typography.subtitle)
                            .foregroundStyle(Palette.inkMuted)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    action(Copy.duplicateOpen, action: onOpen)
                    action(Copy.duplicateDifferent, muted: true, action: onDifferent)
                }

                Spacer(minLength: 24)

                Button(action: onAddPhoto) {
                    Text(Copy.duplicatePhoto)
                        .catalogueLabel()
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationBackground(Palette.paper)
    }

    private func action(_ title: String, muted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typography.value)
                .foregroundStyle(muted ? Palette.inkMuted : Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}
