import SwiftUI

/// The tombstone. Monospaced labels against plain values, hairline rules
/// between, no container of any kind.
struct CaptionBlock: View {
    let card: CoffeeCard

    private struct Row: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    private var rows: [Row] {
        [
            Row(label: "Roaster", value: card.roaster),
            Row(label: "Producer", value: card.producer),
            Row(label: "Region", value: card.region),
            Row(label: "Country", value: card.country),
            Row(label: "Altitude", value: card.altitude),
            Row(label: "Variety", value: card.variety),
            Row(label: "Process", value: card.process),
            Row(label: "Brewed", value: card.brewMethod?.label ?? ""),
            Row(label: "Place", value: card.place?.summary ?? ""),
            Row(label: "Date", value: card.date.formatted(.dateTime.day().month(.wide).year())),
        ]
        .filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Text(row.label)
                        .catalogueLabel()
                        .frame(width: 78, alignment: .leading)
                    Text(row.value)
                        .font(Typography.value)
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 11)
            }
        }
    }
}
