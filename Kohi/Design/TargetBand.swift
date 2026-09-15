import SwiftUI

/// A value against a reference range, drawn as a hairline.
///
/// Used for water: TDS, hardness, alkalinity. The band is the SCA acceptable
/// range with a tick at the target, and a mark where your value sits. It states
/// where you are, never whether that is good — water below the alkalinity band
/// is exactly where the light-roast filter crowd aims on purpose.
///
/// No colour, no icons, no red: the whole point of the hairline vocabulary is
/// that a measurement can be shown without being judged.
struct TargetBand: View {
    let value: Double?
    let range: ClosedRange<Double>
    let target: Double

    /// How far past the range the axis extends, so a value outside it is still
    /// placed rather than pinned to the edge without explanation.
    private let overshoot: Double = 0.25

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                // Full axis.
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .center)

                // The acceptable range, drawn heavier than the axis.
                Rectangle()
                    .fill(Palette.inkMuted)
                    .frame(width: max(1, span(width)), height: 1)
                    .offset(x: position(range.lowerBound, width: width))
                    .frame(maxHeight: .infinity, alignment: .center)

                // Target tick.
                Rectangle()
                    .fill(Palette.inkMuted)
                    .frame(width: 1, height: 5)
                    .offset(x: position(target, width: width))
                    .frame(maxHeight: .infinity, alignment: .center)

                if let value {
                    Rectangle()
                        .fill(Palette.ink)
                        .frame(width: 2, height: 9)
                        .offset(x: position(value, width: width) - 1)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .frame(height: 10)
        .animation(Motion.snappy, value: value)
    }

    private var axis: ClosedRange<Double> {
        let padding = (range.upperBound - range.lowerBound) * overshoot
        return (range.lowerBound - padding)...(range.upperBound + padding)
    }

    private func position(_ value: Double, width: CGFloat) -> CGFloat {
        let axis = axis
        let fraction = (value - axis.lowerBound) / (axis.upperBound - axis.lowerBound)
        return width * CGFloat(min(max(fraction, 0), 1))
    }

    private func span(_ width: CGFloat) -> CGFloat {
        position(range.upperBound, width: width) - position(range.lowerBound, width: width)
    }
}

/// A water value with its band underneath: label, number, unit, hairline.
struct TargetRow: View {
    let label: String
    let value: Double?
    let range: ClosedRange<Double>
    let target: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text(label)
                    .catalogueLabel()
                    .frame(width: 78, alignment: .leading)
                if let value {
                    Text("\(GrindRange.number(value)) \(unit)")
                        .font(Typography.value)
                        .foregroundStyle(Palette.ink)
                } else {
                    Text("—")
                        .font(Typography.value)
                        .foregroundStyle(Palette.hairline)
                }
                Spacer()
                Text("target \(GrindRange.number(target))")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
            TargetBand(value: value, range: range, target: target)
        }
    }
}
