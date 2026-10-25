import Foundation

/// sRGB ↔ OKLab. Card colours are mixed here: a pink to green blend does not pass through grey.
nonisolated enum OKLab {
    static func fromSRGB(_ r: Double, _ g: Double, _ b: Double) -> SIMD3<Double> {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (lr, lg, lb) = (lin(r), lin(g), lin(b))
        let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s]
    }

    static func toSRGB(_ lab: SIMD3<Double>) -> (Double, Double, Double) {
        let l = pow(lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z, 3)
        let m = pow(lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z, 3)
        let s = pow(lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z, 3)
        func enc(_ c: Double) -> Double {
            let v = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(max(c, 0), 1 / 2.4) - 0.055
            return min(1, max(0, v))
        }
        return (enc(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                enc(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                enc(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
    }

    static func fromHex(_ hex: String) -> SIMD3<Double> {
        let rgb = rgb(hex: hex) ?? (0, 0, 0)
        return fromSRGB(rgb.0, rgb.1, rgb.2)
    }

    static func rgb(hex: String) -> (Double, Double, Double)? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
        return (Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
    }

    /// Rounds through 8-bit sRGB, as the prototype does when it stores a colour as hex.
    static func quantized(_ lab: SIMD3<Double>) -> SIMD3<Double> {
        let (r, g, b) = byte(toSRGB(lab))
        return fromSRGB(r, g, b)
    }

    static func byte(_ rgb: (Double, Double, Double)) -> (Double, Double, Double) {
        ((rgb.0 * 255).rounded() / 255, (rgb.1 * 255).rounded() / 255, (rgb.2 * 255).rounded() / 255)
    }

    static func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: Double) -> SIMD3<Double> {
        a + (b - a) * t
    }

    static func hex(_ lab: SIMD3<Double>) -> String {
        let (r, g, b) = toSRGB(lab)
        return String(format: "#%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// HSV to sRGB, components 0…1, rounded to bytes like the prototype's hex.
    static func hsv(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let i = Int(floor(h * 6)) % 6, f = h * 6 - floor(h * 6)
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        let rgb: (Double, Double, Double)
        switch i {
        case 0: rgb = (v, t, p)
        case 1: rgb = (q, v, p)
        case 2: rgb = (p, v, t)
        case 3: rgb = (p, q, v)
        case 4: rgb = (t, p, v)
        default: rgb = (v, p, q)
        }
        return byte(rgb)
    }

    /// Hue 0…1 of an sRGB colour. Nil for a grey.
    static func hue(_ r: Double, _ g: Double, _ b: Double) -> Double? {
        let maxC = max(r, g, b), minC = min(r, g, b), d = maxC - minC
        guard d > 1e-6 else { return nil }
        var h: Double
        if maxC == r { h = (g - b) / d + (g < b ? 6 : 0) }
        else if maxC == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h /= 6
        return h
    }

    /// Relative luminance of an sRGB colour, 0…1.
    static func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
}
