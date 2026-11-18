import SwiftUI

/// Two or three coffees, brews or tastings on one radar. Each keeps the
/// colour of its card, a line and a marker of its own, and a number that
/// follows the order they were picked in.
struct CompareView: View {
    let series: [CompareSeries]

    @Environment(\.dismiss) private var dismiss

    private var inks: [SIMD3<Double>] { CompareColors.inks(series.map(\.cardInk)) }

    private var radarSeries: [RadarSeries] {
        series.enumerated().map { index, one in
            RadarSeries(
                taste: one.taste,
                color: CompareColors.color(inks[index]),
                style: .at(index),
                label: "\(one.title), \(one.detail)"
            )
        }
    }

    private var brews: [Brew]? {
        let brews = series.compactMap(\.brew)
        return brews.count == series.count ? brews : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Spacer()
                        TasteRadar(series: radarSeries, size: 220)
                        Spacer()
                    }
                    legend
                    if let brews { parameters(brews) }
                }
                .padding(.horizontal, 26)
                .padding(.top, 14)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.medium)
                }
            }
        }
        .tint(Palette.ink)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(series.enumerated()), id: \.element.id) { index, one in
                let color = CompareColors.color(inks[index])
                HStack(spacing: 12) {
                    CompareBadge(number: index + 1, color: color)
                    SeriesSwatch(style: .at(index), color: color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(one.title)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.ink)
                        Text(one.detail)
                            .catalogueLabel()
                    }
                    Spacer()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(index + 1), \(one.title), \(one.detail), \(SeriesStyle.at(index).spoken)")
            }
        }
    }

    private func parameters(_ brews: [Brew]) -> some View {
        let rows: [(String, (Brew) -> String)] = [
            ("Dose", { $0.dose.map { "\(GrindRange.number($0)) g" } ?? "—" }),
            ("Water", { ($0.water ?? $0.beverage).map { "\(GrindRange.number($0)) g" } ?? "—" }),
            ("Ratio", { $0.ratio ?? "—" }),
            ("Grind", { $0.grind.isEmpty ? "—" : $0.grind.display() }),
            ("Temp", { $0.temperature.map { "\(GrindRange.number($0)) °C" } ?? "—" }),
            ("Time", { $0.seconds.map { String(format: "%d:%02d", $0 / 60, $0 % 60) } ?? "—" }),
        ]
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("").frame(width: 64)
                ForEach(brews.indices, id: \.self) { index in
                    Text("\(index + 1)")
                        .catalogueLabel()
                        .foregroundStyle(CompareColors.color(inks[index]))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 4)
            ForEach(rows, id: \.0) { label, value in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(label)
                        .catalogueLabel()
                        .frame(width: 64, alignment: .leading)
                    ForEach(brews.indices, id: \.self) { index in
                        Text(value(brews[index]))
                            .font(Typography.tag)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 8)
                Rectangle().fill(Palette.hairline).frame(height: 1)
            }
        }
    }
}

/// The number a picked item carries, on its tile and in the legend.
struct CompareBadge: View {
    let number: Int
    var color: Color = Palette.ink

    var body: some View {
        Text("\(number)")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.paper)
            .frame(width: 22, height: 22)
            .background(color, in: Circle())
            .accessibilityHidden(true)
    }
}

/// A short stretch of the series' line with its marker.
struct SeriesSwatch: View {
    let style: SeriesStyle
    let color: Color

    var body: some View {
        Canvas { context, size in
            var line = Path()
            line.move(to: CGPoint(x: 0, y: size.height / 2))
            line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.6, dash: style.dash))
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r: CGFloat = 3.5
            let marker: Path
            switch style.marker {
            case .circle: marker = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            case .square: marker = Path(CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            case .triangle:
                var path = Path()
                path.move(to: CGPoint(x: c.x, y: c.y - r * 1.2))
                path.addLine(to: CGPoint(x: c.x + r * 1.1, y: c.y + r * 0.8))
                path.addLine(to: CGPoint(x: c.x - r * 1.1, y: c.y + r * 0.8))
                path.closeSubpath()
                marker = path
            }
            context.fill(marker, with: .color(color))
        }
        .frame(width: 28, height: 12)
        .accessibilityHidden(true)
    }
}
