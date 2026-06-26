// Sources/SwiflowColor/Contrast.swift

/// Hex-based contrast metrics. Inputs are `#rgb` or `#rrggbb`; malformed input throws
/// `ThemeError.invalidHex`.
public enum Contrast {
    /// WCAG 2.x contrast ratio (1…21), order-independent.
    public static func wcag(_ aHex: String, _ bHex: String) throws -> Double {
        let a = try Color.normalizeHex(aHex)
        let b = try Color.normalizeHex(bHex)
        return Color.wcagContrast(Color.hex(a), Color.hex(b))
    }

    /// APCA-W3 perceptual lightness contrast (signed Lc; advisory). Negative = light text on
    /// a dark background; compare `abs(_:)` to a target.
    public static func apca(textHex: String, bgHex: String) throws -> Double {
        let t = try Color.normalizeHex(textHex)
        let b = try Color.normalizeHex(bgHex)
        return Color.apcaContrast(textHex: t, bgHex: b)
    }
}
