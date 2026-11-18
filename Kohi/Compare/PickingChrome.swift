import SwiftUI

/// What a sheet opens on: the series, in pick order.
struct ComparePick: Identifiable {
    let id = UUID()
    let series: [CompareSeries]
}

/// The mark on a tile in selection mode: its pick number, or an empty ring.
struct PickMark: View {
    let number: Int?

    var body: some View {
        Group {
            if let number {
                CompareBadge(number: number)
            } else {
                Circle()
                    .stroke(Palette.paper, lineWidth: 1.5)
                    .background(Circle().fill(Palette.ink.opacity(0.18)))
                    .frame(width: 22, height: 22)
            }
        }
        .padding(8)
        .allowsHitTesting(false)
    }
}

/// Compare and Delete, in place of the buttons at the bottom.
struct PickBar: View {
    let count: Int
    var showsCompare = true
    let onCompare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 28) {
            if showsCompare {
                Button(count > CompareSeries.limit ? Copy.compareUpToThree : Copy.compare, action: onCompare)
                    .disabled(!CompareSelection.canCompare(count))
            }
            Button(Copy.delete, role: .destructive, action: onDelete)
                .disabled(count == 0)
        }
        .font(Typography.label)
        .tracking(Typography.labelTracking)
        .textCase(.uppercase)
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
        .modifier(GlassCapsule())
    }
}

/// "3 coffees deleted · Undo", for the length of the undo window.
struct UndoBanner: View {
    let text: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Text(text)
                .font(Typography.tag)
                .foregroundStyle(Palette.ink)
            Button("Undo", action: onUndo)
                .catalogueLabel()
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .modifier(GlassCapsule())
    }
}

private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        }
    }
}
