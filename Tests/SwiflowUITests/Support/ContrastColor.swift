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
