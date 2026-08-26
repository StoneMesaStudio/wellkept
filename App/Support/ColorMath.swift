import Foundation

//  ColorMath.swift
//  Wellkept — App/Support
//
//  Ported from Lode (`Core/Sources/TesseraCore/Design/ColorMath.swift`).
//
//  Colour arithmetic — **pure numbers, no SwiftUI**, so a test can reach it. The dial's failure
//  mode is silent: a wrong component pair (linear vs gamma-encoded) or a bad HSB inverse gives
//  colours that are subtly wrong *everywhere*, each one individually plausible, with nothing to
//  point at. Lode shipped that bug once — #2563EB rendering as #0520D4 — and the only thing that
//  catches it is a round-trip test on a known hex, which needs code that is not inside a view.
//
//  Everything here works in **gamma-encoded sRGB, 0…1** — the space `#RRGGBB` is written in, and
//  the space `Color(.sRGB, red:green:blue:)` expects.

public enum ColorMath {

    // MARK: - Types

    /// Gamma-encoded sRGB, each component 0…1.
    public struct RGB: Equatable, Sendable {
        public var r: Double, g: Double, b: Double
        public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    }

    /// Hue 0…1 (not degrees), saturation 0…1, brightness 0…1.
    public struct HSB: Equatable, Sendable {
        public var h: Double, s: Double, b: Double
        public init(_ h: Double, _ s: Double, _ b: Double) { self.h = h; self.s = s; self.b = b }
    }

    /// Perceptual lightness `L` (0…1) with opponent axes `a` (green↔red) and `b` (blue↔yellow).
    ///
    /// Used for mixing and for the ink decision, where sRGB arithmetic misleads: the midpoint of
    /// two sRGB values is not the colour halfway between them, and a 50% mix toward the ground in
    /// sRGB lands visibly darker than the eye expects.
    public struct OKLab: Equatable, Sendable {
        public var L: Double, a: Double, b: Double
        public init(_ L: Double, _ a: Double, _ b: Double) { self.L = L; self.a = a; self.b = b }
    }

    // MARK: - Hex

    /// Parse `#RRGGBB`. `nil` if malformed — a caller that substitutes black for a typo turns a
    /// bad string into an invisible page.
    public static func rgb(hex: String) -> RGB? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        return RGB(Double((v >> 16) & 0xFF) / 255,
                   Double((v >> 8) & 0xFF) / 255,
                   Double(v & 0xFF) / 255)
    }

    /// Format as `#RRGGBB`, rounding each component to the nearest 1/255.
    public static func hex(_ c: RGB) -> String {
        func byte(_ x: Double) -> Int { Int((min(1, max(0, x)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.r), byte(c.g), byte(c.b))
    }

    // MARK: - RGB ⇄ HSB

    public static func hsb(_ c: RGB) -> HSB {
        let r = min(1, max(0, c.r)), g = min(1, max(0, c.g)), b = min(1, max(0, c.b))
        let maxV = max(r, g, b), minV = min(r, g, b)
        let delta = maxV - minV
        // Achromatic: hue is undefined, and inventing one is how a grey acquires a tint the moment
        // saturation is scaled back up. Report 0 and let saturation 0 make it irrelevant.
        guard delta > 0 else { return HSB(0, 0, maxV) }
        var h: Double
        switch maxV {
        case r: h = (g - b) / delta
        case g: h = 2 + (b - r) / delta
        default: h = 4 + (r - g) / delta
        }
        h /= 6
        if h < 0 { h += 1 }
        return HSB(h, delta / maxV, maxV)
    }

    public static func rgb(_ c: HSB) -> RGB {
        let s = min(1, max(0, c.s)), v = min(1, max(0, c.b))
        guard s > 0 else { return RGB(v, v, v) }
        var h = c.h.truncatingRemainder(dividingBy: 1)
        if h < 0 { h += 1 }
        let sector = h * 6
        let i = floor(sector)
        let f = sector - i
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))
        switch Int(i) % 6 {
        case 0: return RGB(v, t, p)
        case 1: return RGB(q, v, p)
        case 2: return RGB(p, v, t)
        case 3: return RGB(p, q, v)
        case 4: return RGB(t, p, v)
        default: return RGB(v, p, q)
        }
    }

    // MARK: - sRGB ⇄ linear

    /// One component, gamma-encoded → linear.
    public static func toLinear(_ x: Double) -> Double {
        let v = min(1, max(0, x))
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    /// One component, linear → gamma-encoded.
    public static func toGamma(_ x: Double) -> Double {
        let v = min(1, max(0, x))
        return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    // MARK: - sRGB ⇄ OKLab

    public static func oklab(_ c: RGB) -> OKLab {
        let r = toLinear(c.r), g = toLinear(c.g), b = toLinear(c.b)

        let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)

        return OKLab(0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
                     1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
                     0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
    }

    public static func rgb(_ c: OKLab) -> RGB {
        let l_ = c.L + 0.3963377774 * c.a + 0.2158037573 * c.b
        let m_ = c.L - 0.1055613458 * c.a - 0.0638541728 * c.b
        let s_ = c.L - 0.0894841775 * c.a - 1.2914855480 * c.b

        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_

        let r =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

        return RGB(toGamma(r), toGamma(g), toGamma(b))
    }

    /// Perceptual lightness alone, 0…1. Cheaper to read than `oklab(_:).L` at a call site that
    /// only wants "how light is this".
    public static func lightness(_ c: RGB) -> Double { oklab(c).L }

    // MARK: - Mixing

    /// Straight sRGB interpolation, `t` from 0 (`a`) to 1 (`b`).
    ///
    /// This is the mix the text colours are stated as: `textSecondary` is `.primary` at
    /// `textSecondaryFraction` over the page, `textTertiary` at `textTertiaryFraction`. Written as
    /// an opacity in `Theme` rather than as a frozen hex, because a fraction of `.primary` is
    /// still correct after the user switches to dark mode and a hex is not.
    public static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        let k = min(1, max(0, t))
        return RGB(a.r + (b.r - a.r) * k,
                   a.g + (b.g - a.g) * k,
                   a.b + (b.b - a.b) * k)
    }

    /// Interpolation through OKLab — the mix that looks halfway when `t` is 0.5.
    ///
    /// Use it for a plate or a wash derived from a strong colour: an sRGB midpoint between bronze
    /// and paper is muddier than either, which is how a "soft" plate ends up reading as dirt.
    public static func mixPerceptual(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        let k = min(1, max(0, t))
        let x = oklab(a), y = oklab(b)
        return rgb(OKLab(x.L + (y.L - x.L) * k,
                         x.a + (y.a - x.a) * k,
                         x.b + (y.b - x.b) * k))
    }

    /// The two supporting-text fractions, named here so `Theme`, Settings and the guard test all
    /// read the same numbers. See `Theme.textSecondary` for why the system pair is unusable.
    public static let textSecondaryFraction: Double = 0.78
    public static let textTertiaryFraction: Double = 0.62

    // MARK: - Contrast

    /// WCAG relative luminance, from gamma-encoded sRGB.
    public static func luminance(_ c: RGB) -> Double {
        0.2126 * toLinear(c.r) + 0.7152 * toLinear(c.g) + 0.0722 * toLinear(c.b)
    }

    /// WCAG contrast ratio, 1…21. Order-independent.
    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// White or near-black on a given fill — **computed, never guessed.**
    ///
    /// The house has already paid for the guess twice: InForm hard-codes white on its gradients
    /// and gets away with it only because all four happen to be dark, and Conjunction shipped
    /// white on honey. Wellkept hits it immediately, because its own bronze is dark in light mode
    /// (white ink, 8∶1) and light in dark mode (dark ink, 7.5∶1) — one fixed ink colour is
    /// illegible in one appearance or the other.
    public static func ink(on fill: RGB) -> RGB {
        let white = RGB(1, 1, 1)
        let black = RGB(0.08, 0.08, 0.08)
        return contrast(fill, white) >= contrast(fill, black) ? white : black
    }

    // MARK: - The dial

    /// Scale a colour's **vividness** — its saturation — leaving hue and brightness alone.
    ///
    /// Saturation and not brightness on purpose: a green drained toward grey is still recognisably
    /// where the green was, where a green *darkened* toward grey reads as a different value in a
    /// column of figures. `factor == 1` is the identity, and `hex(desaturate(x, by: 1)) == hex(x)`
    /// is the round-trip a test should assert.
    public static func desaturate(_ c: RGB, by factor: Double) -> RGB {
        guard factor != 1 else { return c }
        var h = hsb(c)
        h.s = min(1, max(0, h.s * factor))
        return rgb(h)
    }

    /// The brightness floor: **draining colour may never make something harder to read.**
    ///
    /// Pulling saturation out of a mid-tone lightens it, which on a pale page costs contrast — so
    /// a colour could go quieter *and* fainter at once, which is the one outcome the dial must not
    /// produce. After the drain, brightness is walked back toward the readable end until the
    /// colour is at least as legible against the page as it was before.
    ///
    /// Stated as "at least as good as before" rather than as a fixed AA target deliberately: an
    /// absolute target would move colours the user never asked to change, and the dial's contract
    /// is that **Full is exactly the app's own colour.**
    public static func preserveContrast(_ drained: RGB, original: RGB, ground: RGB) -> RGB {
        meet(drained, against: ground, target: contrast(original, ground))
    }

    /// Walk a colour's brightness until it reaches `target` contrast against `other`, or
    /// brightness runs out. Two uses: holding a drained colour's legibility
    /// (`preserveContrast`), and darkening a *fill* enough for the white text sitting on it.
    public static func meet(_ c: RGB, against other: RGB, target: Double) -> RGB {
        guard contrast(c, other) < target - 0.001 else { return c }
        var h = hsb(c)
        let ground = other
        // Move away from the ground: darken on a light page, lighten on a dark one.
        let darken = luminance(ground) > 0.5
        var lo = darken ? 0.0 : h.b
        var hi = darken ? h.b : 1.0
        // If the far end can't reach the target either, take the far end — the best available.
        let far = HSB(h.h, h.s, darken ? lo : hi)
        guard contrast(rgb(far), ground) >= target else { return rgb(far) }
        for _ in 0..<24 {                          // ~1e-7 on brightness; well past 1/255
            let mid = (lo + hi) / 2
            h.b = mid
            if contrast(rgb(h), ground) >= target { if darken { lo = mid } else { hi = mid } }
            else { if darken { hi = mid } else { lo = mid } }
        }
        h.b = darken ? lo : hi
        return rgb(h)
    }
}
