import SwiftUI

/// Three ranked moves under a reading. Tap one to keep it for next time.
struct SuggestedCorrectionView: View {
    let correction: SuggestedCorrection
    @Binding var pickedRank: Int?
    var onPick: (SuggestedCorrection.Move) -> Void

    var body: some View {
        InsightBlock(
            title: Copy.suggestedCorrection,
            bodyText: correction.reading,
            provenance: correction.isModel
                ? "DERIVED FROM THIS BREW"
                : "SOURCE: RULE G7",
            isModel: correction.isModel
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(correction.moves) { move in
                    Button {
                        pickedRank = move.rank
                        onPick(move)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if pickedRank == move.rank {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(move.line)
                                    .font(Typography.value)
                                    .foregroundStyle(Palette.ink)
                                Text(move.why)
                                    .font(Typography.tag)
                                    .foregroundStyle(Palette.inkMuted)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .touchTarget()
                }
                if pickedRank != nil {
                    Text("Use next time")
                        .catalogueLabel()
                }
            }
        }
    }
}
