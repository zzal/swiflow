import Foundation

/// A color in linear-light sRGB. Components are nominally 0...1 but may fall
/// outside during intermediate math (clamp before using as a rendered color).
struct LinRGB: Equatable {
    var r: Double, g: Double, b: Double
    /// WCAG relative luminance.
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
    static let black = LinRGB(r: 0, g: 0, b: 0)
    static let white = LinRGB(r: 1, g: 1, b: 1)
}

/// Test-only color pipeline that replicates the browser math the base stylesheet
/// relies on, so `ThemeContrastTests` can prove the shipped defaults meet WCAG.
/// Nothing here ships in the SwiflowUI module.
enum Color {
    /// sRGB gamma-encoded channel (0...1) → linear-light.
    static func gammaToLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    /// "#rrggbb" → linear-light sRGB.
    static func hex(_ hex: String) -> LinRGB {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt32(h, radix: 16)!
        let r = Double((v >> 16) & 0xff) / 255.0
        let g = Double((v >> 8) & 0xff) / 255.0
        let b = Double(v & 0xff) / 255.0
        return LinRGB(r: gammaToLinear(r), g: gammaToLinear(g), b: gammaToLinear(b))
    }
    /// WCAG 2.x contrast ratio between two colors (order-independent).
    static func wcagContrast(_ x: LinRGB, _ y: LinRGB) -> Double {
        let hi = max(x.luminance, y.luminance), lo = min(x.luminance, y.luminance)
        return (hi + 0.05) / (lo + 0.05)
    }
}

/// OKLab (L, a, b) — Björn Ottosson's perceptual space.
struct OKLab: Equatable { var L: Double, a: Double, b: Double }
/// OKLCH (L, C, H in radians).
struct OKLCH: Equatable { var L: Double, C: Double, H: Double }

extension Color {
    static func linRGBToOKLab(_ c: LinRGB) -> OKLab {
        let l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b
        let m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b
        let s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b
        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)
        return OKLab(
            L: 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            a: 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            b: 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
    }
    static func okLabToLinRGB(_ c: OKLab) -> LinRGB {
        let l_ = c.L + 0.3963377774 * c.a + 0.2158037573 * c.b
        let m_ = c.L - 0.1055613458 * c.a - 0.0638541728 * c.b
        let s_ = c.L - 0.0894841775 * c.a - 1.2914855480 * c.b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return LinRGB(
            r:  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            g: -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            b: -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }
    static func okLabToOKLCH(_ c: OKLab) -> OKLCH {
        OKLCH(L: c.L, C: (c.a * c.a + c.b * c.b).squareRoot(), H: atan2(c.b, c.a))
    }
    static func okLCHToOKLab(_ c: OKLCH) -> OKLab {
        OKLab(L: c.L, a: c.C * cos(c.H), b: c.C * sin(c.H))
    }
    /// Per-channel clamp into the sRGB gamut. The browser does CSS Color 4 chroma-
    /// reduction; a per-channel clamp is a close-enough approximation for a luminance
    /// assertion, and barely triggers for our in-gamut hues at the chosen lightnesses.
    static func clampGamut(_ c: LinRGB) -> LinRGB {
        LinRGB(r: min(max(c.r, 0), 1), g: min(max(c.g, 0), 1), b: min(max(c.b, 0), 1))
    }
    /// CSS `color-mix(in oklab, base <weightBase·100>%, other)`: lerp in OKLab.
    static func mixOKLab(_ base: LinRGB, _ other: LinRGB, weightBase w: Double) -> LinRGB {
        let a = linRGBToOKLab(base), b = linRGBToOKLab(other)
        return clampGamut(okLabToLinRGB(OKLab(
            L: w * a.L + (1 - w) * b.L,
            a: w * a.a + (1 - w) * b.a,
            b: w * a.b + (1 - w) * b.b)))
    }
    /// CSS `oklch(from <source> <lightness> c h)`: source chroma+hue, replaced lightness.
    static func oklchFrom(_ source: LinRGB, lightness: Double) -> LinRGB {
        let lch = okLabToOKLCH(linRGBToOKLab(source))
        return clampGamut(okLabToLinRGB(okLCHToOKLab(OKLCH(L: lightness, C: lch.C, H: lch.H))))
    }
    /// CSS `contrast-color(<bg>)`: black or white, whichever maximizes WCAG contrast.
    static func contrastColor(against bg: LinRGB) -> LinRGB {
        wcagContrast(.black, bg) >= wcagContrast(.white, bg) ? .black : .white
    }
}
