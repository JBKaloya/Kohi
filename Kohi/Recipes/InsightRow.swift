import SwiftUI

/// One insight as a catalogue row: the title on the left, the finding on the
/// right, the parameters underneath.
///
/// An insight below its threshold keeps its row and says what is missing. That
/// is deliberate — a section that appears once there is enough data is a
/// section nobody discovers, and the count is itself a reason to log the next
/// brew.
struct InsightRow: View {
    let insight: Insight

    var body: some View {
        InsightBlock(
            title: insight.kind.title,
            bodyText: insight.isReady ? insight.finding : insight.waiting,
            provenance: insight.isReady
                ? "DERIVED FROM \(insight.sampleSize) BREWS"
                : "WAITING ON \(insight.threshold) BREWS"
        ) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if insight.isReady, !insight.detail.isEmpty {
                    Text(insight.detail)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
                Spacer(minLength: 4)
                Text("\(insight.sampleSize)/\(insight.threshold)")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.hairline)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}
