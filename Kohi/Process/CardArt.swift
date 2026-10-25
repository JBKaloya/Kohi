import Foundation

/// Everything a Kohi card paints, decided from the fields and the identifier.
/// Read bottom to top: the ground of the origin, the notes, the sky of the altitude.
/// Pure: same card, same art. The draw order is part of the contract.
nonisolated struct CardArt: Equatable, Sendable {
    static let version = 1

    enum Role: String, Sendable {
        case ground, terroir, sky, note, ink, process
    }

    struct Blob: Equatable, Sendable {
        var x: Double
        var y: Double
        var sx: Double
        var sy: Double
        var rot: Double
        var weight: Double
        var lab: SIMD3<Double>
        var role: Role
        var cos: Double
        var sin: Double

        init(x: Double, y: Double, sx: Double, sy: Double, rot: Double, weight: Double, lab: SIMD3<Double>, role: Role) {
            self.x = x
            self.y = y
            self.sx = sx
            self.sy = sy
            self.rot = rot
            self.weight = weight
            self.lab = lab
            self.role = role
            self.cos = Foundation.cos(rot)
            self.sin = Foundation.sin(rot)
        }
    }

    var seed: UInt32
    var iso: String?
    var processKey: Terroir.ProcessKey
    var process: Terroir.ProcessSettings
    /// Share of air, 0…1.
    var altitudeShare: Double
    var blobs: [Blob]
    /// Note colours, or the ground's tones when the card has no recognised note.
    var fieldColors: [SIMD3<Double>]
    /// True when `fieldColors` come from the notes.
    var hasAromaNotes: Bool
    /// The pack's ink, HSV(hue, 0.72, 0.84). Nil when the scan had no frank colour.
    var ink: SIMD3<Double>?
    /// Title ink in OKLab, L = 0.36.
    var titleInk: SIMD3<Double>
    var warpSeed: Int
    var chroma: Double
    var lightness: Double
    var stickerOnRight: Bool
    /// Degrees.
    var stickerRotation: Double
    /// Five draws for the symbol: width, centre x, centre y, rotation, auto treatment.
    var symbolDraws: [Double]

    static let noteLayouts: [[(Double, Double)]] = [
        [(0.28, 0.36), (0.74, 0.52), (0.38, 0.72)],
        [(0.72, 0.32), (0.26, 0.54), (0.66, 0.76)],
        [(0.50, 0.38), (0.18, 0.66), (0.84, 0.64)],
        [(0.30, 0.28), (0.72, 0.44), (0.50, 0.70)],
    ]

    static func make(_ card: CoffeeCard, ink file: StampFile?) -> CardArt {
        var hue: Double?
        if let r = file?.inkRed, let g = file?.inkGreen, let b = file?.inkBlue {
            hue = OKLab.hue(r, g, b)
        }
        return make(
            id: card.id,
            country: card.country,
            altitude: card.altitude,
            process: card.process,
            roast: card.roastLevel,
            decaf: card.isDecaf,
            notes: KohiCardContent.faceNotes(card),
            inkHue: hue
        )
    }

    static func make(
        id: UUID,
        country: String,
        altitude: String,
        process rawProcess: String,
        roast: RoastLevel?,
        decaf: Bool,
        notes: [String],
        inkHue: Double?
    ) -> CardArt {
        let seed = CardSeed.seed(for: id)
        var rnd = Mulberry32(seed: seed)
        let iso = OriginCode.alpha2(for: country)
        let land = Terroir.land(iso: iso)
        let processKey = Terroir.classify(process: rawProcess)
        let process = Terroir.settings(processKey)
        let h = Terroir.altitudeShare(altitude)

        let ground = OKLab.fromHex(land.ground)
        let tone1 = OKLab.fromHex(land.tone1)
        let tone2 = OKLab.fromHex(land.tone2)

        let faceNotes = notes
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(3)
        let aromas = faceNotes.compactMap { AromaPalette.shared.color(forNote: $0) }
        var fieldColors = aromas
        let hasAromaNotes = !aromas.isEmpty
        if aromas.isEmpty {
            fieldColors = [tone1, tone2, OKLab.quantized(OKLab.mix(tone1, ground, 0.45))]
            if let inkHue {
                let rgb = OKLab.hsv(inkHue, 0.62, 0.78)
                fieldColors[0] = OKLab.fromSRGB(rgb.0, rgb.1, rgb.2)
            }
        } else if fieldColors.count < 3 {
            fieldColors = Array((fieldColors + [tone1, tone2]).prefix(3))
        }

        let skyDoc = Terroir.document.sky
        let lightest = fieldColors.max { $0.x < $1.x } ?? tone1
        var sky = OKLab.mix(OKLab.fromHex(skyDoc.lowAltitude), OKLab.fromHex(skyDoc.highAltitude), h)
        sky = OKLab.mix(sky, lightest, skyDoc.tintFromLightestNote)
        sky.x = max(sky.x, skyDoc.minL)

        var blobs: [Blob] = []
        do {
            let x = 0.5 + rnd.jitter(0.15)
            let rot = rnd.jitter(0.4)
            blobs.append(Blob(x: x, y: 1.06 + 0.06 * h, sx: 0.78, sy: 0.30, rot: rot, weight: 1.15, lab: ground, role: .ground))
        }
        do {
            let x = rnd.unit() < 0.5 ? 0.08 : 0.92
            let rot = rnd.jitter(0.6)
            blobs.append(Blob(x: x, y: 0.9, sx: 0.28, sy: 0.18, rot: rot, weight: 0.5, lab: tone1, role: .terroir))
        }
        do {
            let x = 0.5 + rnd.jitter(0.2)
            let rot = rnd.jitter(0.3)
            blobs.append(Blob(x: x, y: -0.1, sx: 0.85, sy: 0.18 + 0.26 * h, rot: rot, weight: 0.5 + 0.75 * h, lab: sky, role: .sky))
        }
        let layout = noteLayouts[min(noteLayouts.count - 1, Int(floor(rnd.unit() * Double(noteLayouts.count))))]
        let weights = [1.0, 0.86, 0.74]
        for (i, color) in fieldColors.enumerated() {
            var lab = color
            if process.warmShift != 0 {
                lab.y += process.warmShift
                lab.z += process.warmShift * 0.6
            }
            let x = layout[i].0 + rnd.jitter(0.06)
            let y = layout[i].1 + rnd.jitter(0.06)
            let sx = 0.2 + rnd.unit() * 0.12
            let sy = 0.18 + rnd.unit() * 0.12
            let rot = rnd.jitter(1.5)
            blobs.append(Blob(x: x, y: y, sx: sx, sy: sy, rot: rot, weight: weights[i], lab: lab, role: .note))
        }

        var ink: SIMD3<Double>?
        if let inkHue {
            let rgb = OKLab.hsv(inkHue, 0.72, 0.84)
            let lab = OKLab.fromSRGB(rgb.0, rgb.1, rgb.2)
            ink = lab
            let x = rnd.unit() < 0.5 ? 0.06 + rnd.unit() * 0.12 : 0.82 + rnd.unit() * 0.12
            let y = 0.16 + rnd.unit() * 0.4
            blobs.append(Blob(x: x, y: y, sx: 0.12, sy: 0.12, rot: 0, weight: 0.62, lab: lab, role: .ink))
        }
        if let extra = process.extraBlob {
            let x = 0.2 + rnd.unit() * 0.6
            let y = 0.45 + rnd.unit() * 0.3
            let rot = rnd.jitter(1)
            blobs.append(Blob(
                x: x, y: y, sx: extra.sigma, sy: extra.sigma * 0.9, rot: rot,
                weight: extra.weight, lab: OKLab.fromHex(extra.color), role: .process
            ))
        }

        let titleBase: SIMD3<Double>
        if let first = aromas.first {
            titleBase = first
        } else if let inkHue {
            let rgb = OKLab.hsv(inkHue, 0.62, 0.5)
            titleBase = OKLab.fromSRGB(rgb.0, rgb.1, rgb.2)
        } else {
            titleBase = ground
        }
        let chromaT = (titleBase.y * titleBase.y + titleBase.z * titleBase.z).squareRoot()
        let k = chromaT > 0.0001 ? min(1, 0.13 / chromaT) : 1
        let titleInk = OKLab.quantized([0.36, titleBase.y * k, titleBase.z * k])

        let stickerOnRight = rnd.unit() < 0.68
        let stickerRotation = rnd.jitter(9)
        let symbolDraws = (0..<5).map { _ in rnd.unit() }

        return CardArt(
            seed: seed,
            iso: iso,
            processKey: processKey,
            process: process,
            altitudeShare: h,
            blobs: blobs,
            fieldColors: fieldColors,
            hasAromaNotes: hasAromaNotes,
            ink: ink,
            titleInk: titleInk,
            warpSeed: Int(seed % 9973),
            chroma: process.chroma * (decaf ? 0.7 : 1),
            lightness: Terroir.roastLightness(roast) - process.darken,
            stickerOnRight: stickerOnRight,
            stickerRotation: stickerRotation,
            symbolDraws: symbolDraws
        )
    }

    /// OKLab colour of the field at (u, v), u across, v down, both 0…1.
    func color(u: Double, v: Double) -> SIMD3<Double> {
        var x = u, y = v
        if process.warp > 0 {
            x += process.warp * (Noise.fbm(u * 2.2 + 3.1, v * 2.2, warpSeed) - 0.5) * 2
            y += process.warp * (Noise.fbm(u * 2.2, v * 2.2 + 5.3, warpSeed + 1) - 0.5) * 2
        }
        if process.swirl > 0 {
            let dx = x - 0.5, dy = (y - 0.55) * 1.25, r = (dx * dx + dy * dy).squareRoot()
            let a = process.swirl * exp(-r * r * 6)
            let ca = Foundation.cos(a), sa = Foundation.sin(a)
            x = 0.5 + dx * ca - dy * sa
            y = 0.55 + (dx * sa + dy * ca) / 1.25
        }
        var sum = SIMD3<Double>(repeating: 0), total = 0.0
        for b in blobs {
            let dx = x - b.x, dy = (y - b.y) * 1.25
            let rx = (dx * b.cos + dy * b.sin) / b.sx, ry = (-dx * b.sin + dy * b.cos) / b.sy
            let w = pow(b.weight * exp(-0.5 * (rx * rx + ry * ry)), process.sharpness)
            sum += w * b.lab
            total += w
        }
        let e = 1e-4
        var lab = (sum + e * blobs[0].lab) / (total + e)
        lab.x += lightness + 0.03 * (1 - v) * altitudeShare - 0.02 * v
        lab.y *= chroma
        lab.z *= chroma
        return lab
    }

    /// sRGB 0…1 of the field at (u, v).
    func rgb(u: Double, v: Double) -> (Double, Double, Double) {
        OKLab.toSRGB(color(u: u, v: v))
    }

    /// Title ink as sRGB 0…1.
    var titleRGB: (Double, Double, Double) { OKLab.toSRGB(titleInk) }

    var noteBlobs: [Blob] { blobs.filter { $0.role == .note } }
}

nonisolated enum Noise {
    static func hash(_ ix: Int, _ iy: Int, _ s: Int) -> Double {
        func u(_ v: Int) -> UInt32 { UInt32(truncatingIfNeeded: v) }
        var h = (u(ix) &* 374761393) ^ (u(iy) &* 668265263) ^ (u(s) &* 1442695041)
        h = (h ^ (h >> 13)) &* 1274126177
        return Double(h ^ (h >> 16)) / 4_294_967_295
    }

    static func value(_ x: Double, _ y: Double, _ s: Int) -> Double {
        let ix = Int(floor(x)), iy = Int(floor(y)), fx = x - floor(x), fy = y - floor(y)
        let ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy)
        let a = hash(ix, iy, s), b = hash(ix + 1, iy, s), c = hash(ix, iy + 1, s), d = hash(ix + 1, iy + 1, s)
        return (a + (b - a) * ux) + ((c + (d - c) * ux) - (a + (b - a) * ux)) * uy
    }

    static func fbm(_ x: Double, _ y: Double, _ s: Int) -> Double {
        0.65 * value(x, y, s) + 0.35 * value(x * 2.03 + 11.1, y * 2.03 + 7.7, s + 7)
    }
}
