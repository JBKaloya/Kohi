import SwiftUI
import Testing
@testable import Kohi

@MainActor
struct GlyphSnapshotTests {
    @Test func glyphsAt28InkMuted() {
        SnapshotSupport.image(
            of: GlyphGallery(size: 28, color: Palette.inkMuted),
            height: 420,
            named: "28-muted"
        )
    }

    @Test func glyphsAt28Ink() {
        SnapshotSupport.image(
            of: GlyphGallery(size: 28, color: Palette.ink),
            height: 420,
            named: "28-ink"
        )
    }

    @Test func glyphsAt44InkMuted() {
        SnapshotSupport.image(
            of: GlyphGallery(size: 44, color: Palette.inkMuted),
            height: 520,
            named: "44-muted"
        )
    }

    @Test func glyphsAt44Ink() {
        SnapshotSupport.image(
            of: GlyphGallery(size: 44, color: Palette.ink),
            height: 520,
            named: "44-ink"
        )
    }
}

private struct GlyphGallery: View {
    let size: CGFloat
    let color: Color

    var body: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(EquipmentGlyph.allCases) { glyph in
                EquipmentGlyphView(glyph: glyph, size: size, color: color)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Palette.paper)
    }
}
