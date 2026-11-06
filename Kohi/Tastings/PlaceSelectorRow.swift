import SwiftUI

/// The first thing in a tasting: where it was. The nearest place arrives
/// already chosen and reads as a fact, with Change beside it. A suggestion
/// without a location fix still reads as a question until it is tapped.
struct PlaceSelectorRow: View {
    let place: Place?
    let suggestion: PlaceSuggestion?
    var isMissing = false
    let onAccept: (PlaceSuggestion) -> Void
    let onChoose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Copy.placeTitle).catalogueLabel(missing: isMissing)
            if let place {
                Button(action: onChoose) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(place.name)
                                .font(Typography.subtitle)
                                .foregroundStyle(Palette.ink)
                            if let line = detail(place) {
                                Text(line)
                                    .font(Typography.tag)
                                    .foregroundStyle(Palette.inkMuted)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(Copy.change).catalogueLabel()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Change the place")
            } else {
                HStack(spacing: 10) {
                    if let suggestion {
                        Button { onAccept(suggestion) } label: {
                            Text(Copy.placeSuggestion(suggestion.place.name))
                                .font(Typography.tag)
                                .foregroundStyle(Palette.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .overlay(Capsule().stroke(isMissing ? Palette.primary : Palette.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: onChoose) {
                        Text(suggestion == nil ? Copy.choosePlace : Copy.placeOther)
                            .font(suggestion == nil ? Typography.subtitle : Typography.tag)
                            .foregroundStyle(suggestion == nil ? (isMissing ? Palette.primary : Palette.ink) : Palette.inkMuted)
                    }
                    .buttonStyle(.plain)
                    .touchTarget()
                }
                .animation(Motion.snappy, value: isMissing)
            }
        }
    }

    private func detail(_ place: Place) -> String? {
        let parts = [place.address, place.city ?? ""]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
