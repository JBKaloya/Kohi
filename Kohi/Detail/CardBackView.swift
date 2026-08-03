import SwiftUI

/// The back of the card: the same object, printed rather than photographed.
///
/// Built at a fixed nominal width and scaled to whatever the card actually is,
/// so the type keeps its proportions against the front no matter what shape the
/// scan turned out to be. Laying it out responsively would let a wide card give
/// it small type and a narrow one large type, which would read as two different
/// stocks rather than two sides of one.
struct CardBackView: View {
    let card: CoffeeCard
    let width: CGFloat

    /// The width every measurement below is drawn for.
    private static let nominalWidth: CGFloat = 320

    private var height: CGFloat {
        width / max(card.aspectRatio, 0.1)
    }

    var body: some View {
        content
            .frame(
                width: Self.nominalWidth,
                height: Self.nominalWidth / max(card.aspectRatio, 0.1)
            )
            .scaleEffect(width / Self.nominalWidth, anchor: .topLeading)
            .frame(width: width, height: height)
            .background(Palette.paperShade)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(card.displayName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)

            if !card.originLine.isEmpty {
                Text(card.originLine)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.top, 3)
            }

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
                .padding(.top, 14)

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.label)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .tracking(Typography.labelTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.inkMuted)
                            .frame(width: 62, alignment: .leading)
                        Text(row.value)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 5)
                }
            }
            .padding(.top, 4)

            if !card.tastingNotes.isEmpty {
                Text(card.tastingNotes.joined(separator: " · "))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 10)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Text(card.date.formatted(.dateTime.day().month(.wide).year()))
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .tracking(Typography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(Palette.inkMuted)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private struct Row: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    /// The back carries what the front cannot: everything typed in afterwards.
    private var rows: [Row] {
        [
            Row(label: "Roaster", value: card.roaster),
            Row(label: "Producer", value: card.producer),
            Row(label: "Altitude", value: card.altitude),
            Row(label: "Variety", value: card.variety),
            Row(label: "Process", value: card.process),
            Row(label: "Brewed", value: card.brewMethod?.label ?? ""),
            Row(label: "Place", value: card.place?.summary ?? ""),
        ]
        .filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

#Preview {
    ZStack {
        Palette.paper.ignoresSafeArea()
        CardBackView(
            card: CoffeeCard(
                name: "Kenya Tekangu",
                roaster: "Coffee Collective",
                country: "Kenya",
                region: "Nyeri",
                producer: "Tekangu Cooperative",
                altitude: "1800m",
                variety: "SL28, SL34",
                process: "Washed",
                tastingNotes: ["Floral", "Red Currant", "Vanilla"],
                brewMethod: .v60,
                aspectRatio: 0.72
            ),
            width: 260
        )
        .shadow(color: Palette.cardShadow, radius: 16, y: 8)
    }
}
