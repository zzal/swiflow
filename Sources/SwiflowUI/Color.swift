// Sources/SwiflowUI/Color.swift
//
// A typed color VALUE for the theme DSL. OKLCH-primary: `.oklch(l:c:h:)` is the
// intended way to DEFINE a color; `.hex(_)` and string literals are escape hatches.
// This is a PURE CSS-string formatter — no gamut/contrast math — so SwiflowUI stays
// wasm-safe and never pulls in the native-only SwiflowColor engine. The `ThemeToken`
// factories take this alongside their raw-String overloads (see ThemeScope.swift).

/// A CSS color value for `Theme` token overrides. Prefer `.oklch(l:c:h:)` — OKLCH is
/// perceptually uniform and adapts to the display gamut natively; `.hex(_)` and string
/// literals remain for legacy/opaque values (`"var(--brand)"`).
///
///     Theme(.accent(.oklch(l: 0.62, c: 0.17, h: 255)))   // → --sw-accent: oklch(0.62 0.17 255)
///     Theme(.surface(.hex("#1a1a1a")))
public struct Color: Sendable, Equatable, ExpressibleByStringLiteral {
    /// The rendered CSS value, e.g. `"oklch(0.62 0.17 255)"`.
    public let css: String

    /// Wrap a raw CSS color string verbatim (`"oklch(…)"`, `"#1a1a1a"`, `"var(--brand)"`).
    public init(_ css: String) { self.css = css }
    public init(stringLiteral value: String) { self.css = value }

    /// OKLCH — the primary definition form. `l` is 0…1 (perceptual lightness), `c` is
    /// chroma (~0…0.4), `h` is hue in degrees (0…360). `alpha` (0…1) is emitted only when
    /// below 1. Renders `oklch(L C H)` or `oklch(L C H / A)`.
    public static func oklch(l: Double, c: Double, h: Double, alpha: Double = 1) -> Color {
        let head = "oklch(\(fmt(l)) \(fmt(c)) \(fmt(h))"
        return Color(alpha < 1 ? "\(head) / \(fmt(alpha)))" : "\(head))")
    }

    /// Escape hatch for a hex color (`#rgb`/`#rrggbb`), stored verbatim.
    public static func hex(_ value: String) -> Color { Color(value) }

    /// Integral values print without a decimal point (`255`); everything else uses the
    /// shortest round-trippable form (`0.62`). Foundation-free — keeps the wasm bundle lean.
    private static func fmt(_ v: Double) -> String {
        v.rounded() == v && v.magnitude < 1e9 ? "\(Int(v))" : "\(v)"
    }
}
