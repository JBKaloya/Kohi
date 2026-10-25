import SwiftUI

/// The tombstone. Monospaced labels against plain values, hairline rules
/// between, no container of any kind.
struct CaptionBlock: View {
    let card: CoffeeCard
    var placeTag: String? = nil

    @Environment(\.openURL) private var openURL

    private struct Row: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        var isTappable: Bool = false
        var url: URL? = nil
    }

    private var rows: [Row] {
        let hasPlace = card.place != nil
        var result = [
            Row(label: "Roaster", value: card.roaster),
            Row(label: "Producer", value: card.producer),
            Row(label: "Farm", value: card.farm ?? ""),
            Row(label: "Station", value: card.washStation ?? ""),
            Row(label: "Region", value: card.region),
            Row(label: "Country", value: card.country),
            Row(label: "Altitude", value: card.altitude),
            Row(label: "Variety", value: card.variety),
            Row(label: "Process", value: card.process),
            Row(label: "Species", value: speciesValue),
            Row(label: "Harvest", value: card.harvest ?? ""),
            Row(label: "Lot", value: card.lot ?? ""),
            Row(label: "Roast", value: roastValue),
            Row(label: Copy.roastedOn, value: roastedValue),
            Row(label: "Score", value: scoreValue),
            Row(label: "Price", value: card.priceLine ?? ""),
            Row(label: "Place", value: placeValue, isTappable: hasPlace, url: card.place?.appleMapsURL),
        ]
        if let link = productLink {
            result.append(Row(label: "Link", value: link.host, isTappable: true, url: link.url))
        }
        if let code = card.labelCode, !code.isEmpty {
            let display = code.hasPrefix("http")
                ? (URL(string: code)?.host ?? code)
                : code
            result.append(Row(label: "Label", value: display))
        }
        return result
            .filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var placeValue: String {
        guard var value = card.place?.summary, !value.isEmpty else { return "" }
        if let placeTag, !placeTag.isEmpty {
            value += " · \(placeTag)"
        }
        return value
    }

    /// Roast level and Agtron share a row: they say the same thing on two
    /// scales, and cards that print the number usually print the word too.
    private var roastValue: String {
        var parts: [String] = []
        if let level = card.roastLevel { parts.append(level.label) }
        if let agtron = card.agtron { parts.append("Agtron \(agtron)") }
        if card.isDecaf {
            parts.append(card.decafMethod?.label ?? "Decaf")
        }
        return parts.joined(separator: " · ")
    }

    private var speciesValue: String {
        card.species == .arabica ? "" : card.species.label
    }

    private var productLink: (host: String, url: URL)? {
        guard let raw = card.productURL, let url = URL(string: raw), url.scheme?.hasPrefix("http") == true
        else { return nil }
        return (url.host ?? raw, url)
    }

    /// The roast date is only half the story; days off roast is the half you
    /// actually brew by.
    private var roastedValue: String {
        guard let roastedOn = card.roastedOn else { return "" }
        let date = roastedOn.formatted(.dateTime.day().month(.abbreviated).year())
        guard let days = card.daysOffRoast() else { return date }
        if days == 0 { return "\(date) · today" }
        return "\(date) · \(days) d"
    }

    private var scoreValue: String {
        guard let score = card.cuppingScore else { return "" }
        return score == score.rounded()
            ? String(format: "%.0f", score)
            : String(format: "%.1f", score)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)
                }

                if row.isTappable, let url = row.url {
                    Button {
                        openURL(url)
                    } label: {
                        rowContent(row, tappable: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    rowContent(row)
                }
            }
        }
    }

    private func rowContent(_ row: Row, tappable: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(row.label)
                .catalogueLabel()
                .frame(width: 78, alignment: .leading)
            Text(row.value)
                .font(Typography.value)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if tappable {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.ink)
            }
        }
        .padding(.vertical, 11)
    }
}
