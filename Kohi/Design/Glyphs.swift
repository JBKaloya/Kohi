import SwiftUI

/// Equipment drawn as a hairline label, the same way the empty state draws a
/// card: a `Path` in code, never an imported asset.
///
/// Grid is 24 × 24 with a 2 pt margin. Stroke 1 pt, round cap and join, no fill.
nonisolated enum EquipmentGlyph: String, CaseIterable, Identifiable, Sendable {
    case handGrinder
    case electricGrinder
    case coneDripper
    case flatDripper
    case chemex
    case aeropress
    case immersionSwitch
    case frenchPress
    case moka
    case espressoMachine
    case gooseneckKettle
    case scale
    case paperFilter
    case bottledWater
    case mineralDrops
    case leverEspresso
    case coldBrew
    case accessory

    var id: String { rawValue }

    /// Drawn in the 24-point glyph grid. Tests pin that the path is non-empty
    /// and stays inside the box.
    var path: Path {
        switch self {
        case .handGrinder: Self.handGrinderPath
        case .electricGrinder: Self.electricGrinderPath
        case .coneDripper: Self.coneDripperPath
        case .flatDripper: Self.flatDripperPath
        case .chemex: Self.chemexPath
        case .aeropress: Self.aeropressPath
        case .immersionSwitch: Self.immersionSwitchPath
        case .frenchPress: Self.frenchPressPath
        case .moka: Self.mokaPath
        case .espressoMachine: Self.espressoMachinePath
        case .gooseneckKettle: Self.gooseneckKettlePath
        case .scale: Self.scalePath
        case .paperFilter: Self.paperFilterPath
        case .bottledWater: Self.bottledWaterPath
        case .mineralDrops: Self.mineralDropsPath
        case .leverEspresso: Self.leverEspressoPath
        case .coldBrew: Self.coldBrewPath
        case .accessory: Self.accessoryPath
        }
    }

    static func forKit(_ kind: EquipmentKind, family: BrewerFamily?) -> EquipmentGlyph {
        switch kind {
        case .grinder: .handGrinder
        case .brewer: family?.glyph ?? .coneDripper
        case .espressoMachine: .espressoMachine
        case .kettle: .gooseneckKettle
        case .scale: .scale
        case .accessory: .accessory
        }
    }

    static func forKit(_ item: Equipment) -> EquipmentGlyph {
        switch item.kind {
        case .grinder:
            if let ref = item.grinderRef,
               let known = ReferenceBase.grinders.first(where: { $0.id == ref }),
               known.isManual == false {
                return .electricGrinder
            }
            return .handGrinder
        case .brewer:
            return item.brewerFamily?.glyph
                ?? ReferenceBase.brewer(id: item.brewerRef ?? "")?.dripperFamily.glyph
                ?? .coneDripper
        case .espressoMachine:
            let hay = "\(item.brand) \(item.model) \(item.brewerType ?? "")".lowercased()
            return hay.contains("lever") ? .leverEspresso : .espressoMachine
        case .kettle:
            return .gooseneckKettle
        case .scale:
            return .scale
        case .accessory:
            return .accessory
        }
    }

    static func forWater(_ source: WaterSource) -> EquipmentGlyph {
        source == .recipe ? .mineralDrops : .bottledWater
    }
}

/// A glyph at 28 pt in a row or 44 pt in the onboarding grid.
struct EquipmentGlyphView: View {
    let glyph: EquipmentGlyph
    var size: CGFloat = 28
    var color: Color = Palette.inkMuted

    var body: some View {
        GlyphShape(glyph: glyph)
            .stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct GlyphShape: Shape {
    let glyph: EquipmentGlyph

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: scale, y: scale)
        return glyph.path.applying(transform)
    }
}

// MARK: - Paths (24 × 24, margin 2)

nonisolated private extension EquipmentGlyph {
    static var handGrinderPath: Path {
        var p = Path()
        // Body
        p.addRoundedRect(in: CGRect(x: 8, y: 9, width: 8, height: 12), cornerSize: CGSize(width: 1.2, height: 1.2))
        p.move(to: CGPoint(x: 8, y: 13))
        p.addLine(to: CGPoint(x: 16, y: 13))
        // Hopper lip
        p.move(to: CGPoint(x: 9, y: 9))
        p.addLine(to: CGPoint(x: 9, y: 7.5))
        p.addLine(to: CGPoint(x: 15, y: 7.5))
        p.addLine(to: CGPoint(x: 15, y: 9))
        // Crank
        p.move(to: CGPoint(x: 12, y: 7.5))
        p.addLine(to: CGPoint(x: 12, y: 4))
        p.addLine(to: CGPoint(x: 17.5, y: 4))
        p.addEllipse(in: CGRect(x: 16.6, y: 3.1, width: 1.8, height: 1.8))
        return p
    }

    static var electricGrinderPath: Path {
        var p = Path()
        // Hopper
        p.move(to: CGPoint(x: 8.5, y: 10))
        p.addLine(to: CGPoint(x: 10.5, y: 4))
        p.addLine(to: CGPoint(x: 13.5, y: 4))
        p.addLine(to: CGPoint(x: 15.5, y: 10))
        p.closeSubpath()
        p.addEllipse(in: CGRect(x: 10.7, y: 5.2, width: 2.6, height: 2.6))
        // Body
        p.addRoundedRect(in: CGRect(x: 7.5, y: 10, width: 9, height: 10), cornerSize: CGSize(width: 1.4, height: 1.4))
        p.move(to: CGPoint(x: 7.5, y: 14.5))
        p.addLine(to: CGPoint(x: 16.5, y: 14.5))
        // Spout
        p.move(to: CGPoint(x: 16.5, y: 16))
        p.addLine(to: CGPoint(x: 19.5, y: 16))
        p.addLine(to: CGPoint(x: 19.5, y: 18.5))
        p.addLine(to: CGPoint(x: 16.5, y: 18.5))
        return p
    }

    static var coneDripperPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 5.5, y: 6))
        p.addLine(to: CGPoint(x: 18.5, y: 6))
        p.addLine(to: CGPoint(x: 13.2, y: 19))
        p.addLine(to: CGPoint(x: 10.8, y: 19))
        p.closeSubpath()
        p.move(to: CGPoint(x: 8.2, y: 10))
        p.addLine(to: CGPoint(x: 15.8, y: 10))
        p.move(to: CGPoint(x: 9.4, y: 13.5))
        p.addLine(to: CGPoint(x: 14.6, y: 13.5))
        p.addEllipse(in: CGRect(x: 11.1, y: 19.2, width: 1.8, height: 1.8))
        // Handle
        p.move(to: CGPoint(x: 18.5, y: 6.5))
        p.addQuadCurve(to: CGPoint(x: 21.5, y: 10), control: CGPoint(x: 21.8, y: 6.8))
        return p
    }

    static var flatDripperPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 5, y: 6.5))
        p.addLine(to: CGPoint(x: 19, y: 6.5))
        p.addLine(to: CGPoint(x: 16.2, y: 17.5))
        p.addLine(to: CGPoint(x: 7.8, y: 17.5))
        p.closeSubpath()
        p.move(to: CGPoint(x: 7.5, y: 10.5))
        p.addLine(to: CGPoint(x: 16.5, y: 10.5))
        p.move(to: CGPoint(x: 8.6, y: 14))
        p.addLine(to: CGPoint(x: 15.4, y: 14))
        p.addEllipse(in: CGRect(x: 11.1, y: 17.8, width: 1.8, height: 1.8))
        return p
    }

    static var chemexPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 7, y: 3.5))
        p.addLine(to: CGPoint(x: 17, y: 3.5))
        p.addLine(to: CGPoint(x: 13.3, y: 11.5))
        p.addLine(to: CGPoint(x: 16.5, y: 20.5))
        p.addQuadCurve(to: CGPoint(x: 7.5, y: 20.5), control: CGPoint(x: 12, y: 22.5))
        p.addLine(to: CGPoint(x: 10.7, y: 11.5))
        p.closeSubpath()
        p.move(to: CGPoint(x: 8.6, y: 14.5))
        p.addLine(to: CGPoint(x: 15.4, y: 14.5))
        p.addEllipse(in: CGRect(x: 10.6, y: 6.2, width: 2.8, height: 2.8))
        return p
    }

    static var aeropressPath: Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 8.5, y: 7, width: 7, height: 14), cornerSize: CGSize(width: 1, height: 1))
        p.move(to: CGPoint(x: 8.5, y: 16))
        p.addLine(to: CGPoint(x: 15.5, y: 16))
        // Plunger
        p.move(to: CGPoint(x: 10, y: 7))
        p.addLine(to: CGPoint(x: 10, y: 3.5))
        p.addLine(to: CGPoint(x: 14, y: 3.5))
        p.addLine(to: CGPoint(x: 14, y: 7))
        p.move(to: CGPoint(x: 8.2, y: 3.5))
        p.addLine(to: CGPoint(x: 15.8, y: 3.5))
        // Cap
        p.addEllipse(in: CGRect(x: 9.7, y: 19.6, width: 4.6, height: 1.6))
        return p
    }

    static var immersionSwitchPath: Path {
        var p = coneDripperPath
        // Closed valve
        p.move(to: CGPoint(x: 10.2, y: 19.2))
        p.addLine(to: CGPoint(x: 13.8, y: 19.2))
        p.move(to: CGPoint(x: 12, y: 18.5))
        p.addLine(to: CGPoint(x: 12, y: 21.2))
        return p
    }

    static var frenchPressPath: Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 7.5, y: 7, width: 9, height: 13.5), cornerSize: CGSize(width: 1.2, height: 1.2))
        p.move(to: CGPoint(x: 7.5, y: 10))
        p.addLine(to: CGPoint(x: 16.5, y: 10))
        // Lid + plunger
        p.move(to: CGPoint(x: 7, y: 7))
        p.addLine(to: CGPoint(x: 17, y: 7))
        p.move(to: CGPoint(x: 12, y: 7))
        p.addLine(to: CGPoint(x: 12, y: 3.5))
        p.addEllipse(in: CGRect(x: 10.7, y: 2.5, width: 2.6, height: 1.6))
        // Mesh
        p.move(to: CGPoint(x: 8.5, y: 13.5))
        p.addLine(to: CGPoint(x: 15.5, y: 13.5))
        // Handle
        p.move(to: CGPoint(x: 16.5, y: 11))
        p.addQuadCurve(to: CGPoint(x: 16.5, y: 18), control: CGPoint(x: 20.5, y: 14.5))
        return p
    }

    static var mokaPath: Path {
        var p = Path()
        // Lower chamber
        p.move(to: CGPoint(x: 8, y: 21.5))
        p.addLine(to: CGPoint(x: 8, y: 15))
        p.addLine(to: CGPoint(x: 7, y: 13.5))
        p.addLine(to: CGPoint(x: 17, y: 13.5))
        p.addLine(to: CGPoint(x: 16, y: 15))
        p.addLine(to: CGPoint(x: 16, y: 21.5))
        p.closeSubpath()
        // Upper
        p.move(to: CGPoint(x: 8.5, y: 13.5))
        p.addLine(to: CGPoint(x: 8.5, y: 7.5))
        p.addLine(to: CGPoint(x: 15.5, y: 7.5))
        p.addLine(to: CGPoint(x: 15.5, y: 13.5))
        // Lid
        p.addEllipse(in: CGRect(x: 10.6, y: 4.8, width: 2.8, height: 2.8))
        p.move(to: CGPoint(x: 12, y: 4.8))
        p.addLine(to: CGPoint(x: 12, y: 3.2))
        // Spout
        p.move(to: CGPoint(x: 15.5, y: 9.5))
        p.addQuadCurve(to: CGPoint(x: 19, y: 8), control: CGPoint(x: 18.2, y: 9.6))
        // Handle
        p.move(to: CGPoint(x: 8.5, y: 9))
        p.addQuadCurve(to: CGPoint(x: 8.5, y: 16), control: CGPoint(x: 4.2, y: 12.5))
        return p
    }

    static var espressoMachinePath: Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 4.5, y: 6, width: 15, height: 14.5), cornerSize: CGSize(width: 1.2, height: 1.2))
        p.move(to: CGPoint(x: 4.5, y: 10))
        p.addLine(to: CGPoint(x: 19.5, y: 10))
        // Group head
        p.addRoundedRect(in: CGRect(x: 7.2, y: 10, width: 5.2, height: 3.2), cornerSize: CGSize(width: 0.6, height: 0.6))
        // Portafilter
        p.move(to: CGPoint(x: 8.2, y: 13.2))
        p.addLine(to: CGPoint(x: 11.4, y: 13.2))
        p.addLine(to: CGPoint(x: 11.4, y: 15.4))
        p.addLine(to: CGPoint(x: 8.2, y: 15.4))
        p.closeSubpath()
        p.move(to: CGPoint(x: 11.4, y: 14.2))
        p.addLine(to: CGPoint(x: 16.5, y: 16.5))
        // Steam wand
        p.move(to: CGPoint(x: 16.8, y: 10))
        p.addLine(to: CGPoint(x: 16.8, y: 14.8))
        p.addLine(to: CGPoint(x: 18.2, y: 16.4))
        // Drip tray
        p.move(to: CGPoint(x: 6, y: 18.2))
        p.addLine(to: CGPoint(x: 18, y: 18.2))
        return p
    }

    static var gooseneckKettlePath: Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: 4.5, y: 8, width: 11.5, height: 12.5))
        // Lid
        p.addEllipse(in: CGRect(x: 8.2, y: 5.2, width: 4, height: 3.2))
        p.move(to: CGPoint(x: 10.2, y: 5.2))
        p.addLine(to: CGPoint(x: 10.2, y: 3.4))
        // Gooseneck
        p.move(to: CGPoint(x: 15.6, y: 12))
        p.addCurve(
            to: CGPoint(x: 20.8, y: 6.2),
            control1: CGPoint(x: 20.5, y: 12.5),
            control2: CGPoint(x: 21.6, y: 8.4)
        )
        // Handle
        p.move(to: CGPoint(x: 5.2, y: 11))
        p.addQuadCurve(to: CGPoint(x: 5.2, y: 18.5), control: CGPoint(x: 1.8, y: 14.8))
        return p
    }

    static var scalePath: Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 4, y: 8.5, width: 16, height: 11.5), cornerSize: CGSize(width: 1.4, height: 1.4))
        p.addRoundedRect(in: CGRect(x: 6.2, y: 11.2, width: 11.6, height: 6.4), cornerSize: CGSize(width: 0.8, height: 0.8))
        p.addRoundedRect(in: CGRect(x: 8.5, y: 5.5, width: 7, height: 3.2), cornerSize: CGSize(width: 0.7, height: 0.7))
        return p
    }

    static var paperFilterPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 5.5, y: 5))
        p.addLine(to: CGPoint(x: 18.5, y: 5))
        p.addLine(to: CGPoint(x: 12, y: 21))
        p.closeSubpath()
        p.move(to: CGPoint(x: 8.2, y: 5))
        p.addLine(to: CGPoint(x: 12, y: 21))
        p.move(to: CGPoint(x: 12, y: 5))
        p.addLine(to: CGPoint(x: 12, y: 21))
        p.move(to: CGPoint(x: 15.8, y: 5))
        p.addLine(to: CGPoint(x: 12, y: 21))
        return p
    }

    static var bottledWaterPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 9, y: 8))
        p.addLine(to: CGPoint(x: 9, y: 21))
        p.addQuadCurve(to: CGPoint(x: 15, y: 21), control: CGPoint(x: 12, y: 22.2))
        p.addLine(to: CGPoint(x: 15, y: 8))
        p.addLine(to: CGPoint(x: 13.5, y: 6.2))
        p.addLine(to: CGPoint(x: 10.5, y: 6.2))
        p.closeSubpath()
        p.addRoundedRect(in: CGRect(x: 10.4, y: 3.2, width: 3.2, height: 3.2), cornerSize: CGSize(width: 0.6, height: 0.6))
        p.move(to: CGPoint(x: 10, y: 12.5))
        p.addLine(to: CGPoint(x: 14, y: 12.5))
        return p
    }

    static var mineralDropsPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 12, y: 3.5))
        p.addCurve(
            to: CGPoint(x: 12, y: 20.5),
            control1: CGPoint(x: 20.5, y: 11),
            control2: CGPoint(x: 18.5, y: 20.5)
        )
        p.addCurve(
            to: CGPoint(x: 12, y: 3.5),
            control1: CGPoint(x: 5.5, y: 20.5),
            control2: CGPoint(x: 3.5, y: 11)
        )
        p.closeSubpath()
        return p
    }

    static var leverEspressoPath: Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 5.5, y: 9, width: 11.5, height: 12), cornerSize: CGSize(width: 1.2, height: 1.2))
        p.move(to: CGPoint(x: 5.5, y: 13))
        p.addLine(to: CGPoint(x: 17, y: 13))
        // Group
        p.addRoundedRect(in: CGRect(x: 7.5, y: 13, width: 4.8, height: 3), cornerSize: CGSize(width: 0.5, height: 0.5))
        p.move(to: CGPoint(x: 12.3, y: 14.4))
        p.addLine(to: CGPoint(x: 16.6, y: 16.6))
        // Lever
        p.move(to: CGPoint(x: 14.2, y: 9))
        p.addLine(to: CGPoint(x: 14.2, y: 4.2))
        p.addLine(to: CGPoint(x: 20.2, y: 3.5))
        p.addEllipse(in: CGRect(x: 19.4, y: 2.7, width: 1.8, height: 1.8))
        return p
    }

    static var coldBrewPath: Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 7.5, y: 6.5, width: 9, height: 14.5), cornerSize: CGSize(width: 1.6, height: 1.6))
        p.move(to: CGPoint(x: 7.5, y: 9.5))
        p.addLine(to: CGPoint(x: 16.5, y: 9.5))
        p.addEllipse(in: CGRect(x: 9.8, y: 3.8, width: 4.4, height: 2.8))
        p.move(to: CGPoint(x: 9.2, y: 13.5))
        p.addLine(to: CGPoint(x: 14.8, y: 13.5))
        return p
    }

    static var accessoryPath: Path {
        var p = Path()
        // Handle
        p.addRoundedRect(in: CGRect(x: 10.4, y: 3, width: 3.2, height: 8), cornerSize: CGSize(width: 1, height: 1))
        p.move(to: CGPoint(x: 8.5, y: 11))
        p.addLine(to: CGPoint(x: 15.5, y: 11))
        // Needles
        for x in [9.0, 10.8, 12.6, 14.4] {
            p.move(to: CGPoint(x: x, y: 11))
            p.addLine(to: CGPoint(x: x, y: 21))
        }
        return p
    }
}
