// Sources/SwiflowColor/Contrast.swift

/// Contrast metrics. Inputs are `oklch(L C H)` or hex (`#rgb`/`#rrggbb`); malformed input
/// throws `ThemeError.invalidColor`/`.invalidHex`. oklch seeds are gamut-clamped to sRGB
/// before the (sRGB-based) contrast math runs.
public enum Contrast {
    /// WCAG 2.x contrast ratio (1…21), order-independent.
    public static func wcag(_ a: String, _ b: String) throws -> Double {
        let x = try Color.normalizeColor(a)
        let y = try Color.normalizeColor(b)
        return Color.wcagContrast(Color.hex(x), Color.hex(y))
    }

    /// APCA-W3 perceptual lightness contrast (signed Lc; advisory). Negative = light text on
    /// a dark background; compare `abs(_:)` to a target.
    public static func apca(text: String, bg: String) throws -> Double {
        let t = try Color.normalizeColor(text)
        let b = try Color.normalizeColor(bg)
        return Color.apcaContrast(textHex: t, bgHex: b)
    }
}
