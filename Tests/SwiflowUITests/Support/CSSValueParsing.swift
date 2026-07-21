import Foundation
@testable import SwiflowColor

/// Test-only helpers that read values back out of the emitted base stylesheet,
/// so contrast assertions use the SAME numbers the CSS ships (no drift).
enum CSSValueParsing {
    /// The base `:root` region — everything before the first `@media` override layer.
    static func baseRegion(_ css: String) -> String {
        guard let r = css.range(of: "@media") else { return css }
        return String(css[..<r.lowerBound])
    }

    /// The body (including braces) of the `@media (prefers-contrast: more)` block.
    static func contrastMoreRegion(_ css: String) -> String {
        guard let start = css.range(of: "@media (prefers-contrast: more)"),
              let open = css.range(of: "{", range: start.upperBound..<css.endIndex)
        else { return "" }
        var depth = 0
        var i = open.lowerBound
        while i < css.endIndex {
            if css[i] == "{" { depth += 1 }
            else if css[i] == "}" { depth -= 1; if depth == 0 { return String(css[open.lowerBound...i]) } }
            i = css.index(after: i)
        }
        return ""
    }

    /// First `<token>: light-dark(#rrggbb, #rrggbb)` in `region` → (light, dark).
    static func lightDarkHex(_ region: String, _ token: String) -> (light: String, dark: String)? {
        let t = NSRegularExpression.escapedPattern(for: token)
        let pattern = "\(t)\\s*:\\s*light-dark\\(\\s*(#[0-9a-fA-F]{6})\\s*,\\s*(#[0-9a-fA-F]{6})\\s*\\)"
        guard let g = firstMatch(pattern, in: region) else { return nil }
        return (g[1], g[2])
    }

    /// First `<token>: light-dark(<c>, <c>)` where each `<c>` is an absolute `oklch(L C H)`
    /// or `#rrggbb` — resolved to linear-sRGB via `Color.parseColor` (the same OKLCH-primary
    /// input door the generator uses). Format-agnostic, so contrast tests read whatever the
    /// sheet actually ships. Returns UNCLAMPED LinRGB — callers clamp per gamut (sRGB vs P3).
    static func lightDarkColor(_ region: String, _ token: String) -> (light: LinRGB, dark: LinRGB)? {
        let t = NSRegularExpression.escapedPattern(for: token)
        let c = "(oklch\\([^)]*\\)|#[0-9a-fA-F]{6})"   // absolute oklch has no nested parens
        let pattern = "\(t)\\s*:\\s*light-dark\\(\\s*\(c)\\s*,\\s*\(c)\\s*\\)"
        guard let g = firstMatch(pattern, in: region),
              let light = try? Color.parseColor(g[1]), let dark = try? Color.parseColor(g[2])
        else { return nil }
        return (light, dark)
    }

    /// `<token>: light-dark(oklch(from … L1 c h), oklch(from … L2 c h))` → (L1, L2).
    static func oklchLightnesses(_ region: String, _ token: String) -> (light: Double, dark: Double)? {
        let t = NSRegularExpression.escapedPattern(for: token)
        // Match the inner var(--sw-…) explicitly — a `[^)]` class would stop at the ")"
        // that closes var(), never reaching the lightness.
        let oklch = "oklch\\(from var\\(--sw-[a-z][a-z-]*\\)\\s+([0-9.]+) c h\\)"
        let pattern = "\(t)\\s*:\\s*light-dark\\(\\s*\(oklch)\\s*,\\s*\(oklch)\\s*\\)"
        guard let g = firstMatch(pattern, in: region), let a = Double(g[1]), let b = Double(g[2]) else { return nil }
        return (a, b)
    }

    /// Capture groups of the first regex match (index 0 = whole match), or nil.
    private static func firstMatch(_ pattern: String, in s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: s).map { String(s[$0]) } ?? "" }
    }
}
