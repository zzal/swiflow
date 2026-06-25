# SwiflowUI M8 — Contrast Tokens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SwiflowUI's hand-guessed text-on-background colors with CSS that derives them from the background token at render time, proven WCAG-correct on the shipped defaults by a Swift test.

**Architecture:** The library ships **no color math** — the browser derives the text color at render time via `oklch(from …)` (soft-tint text) and `contrast-color()` (solid-fill text), each layered over its current hand-tuned literal as a progressive-enhancement fallback. A **test-only** Swift color pipeline replicates the browser's math and asserts the default palette clears its WCAG target. Only `Sources/SwiflowUI/Theme.swift` changes in shipping code; everything else is new test files.

**Tech Stack:** Swift 6.3, Swift Testing (`import Testing`, `@Suite`/`@Test`/`#expect`), Foundation. CSS: `light-dark()`, `oklch(from …)` (Baseline 2024), `contrast-color()` (Baseline 2026), `color-mix(in oklab, …)`.

**Spec:** [`docs/superpowers/specs/2026-06-25-swiflowui-contrast-tokens-design.md`](../specs/2026-06-25-swiflowui-contrast-tokens-design.md)

---

## File Structure

| File | Responsibility | Ships? |
|------|----------------|--------|
| `Tests/SwiflowUITests/Support/ContrastColor.swift` | Pure color pipeline: sRGB↔OKLab/OKLCH, WCAG ratio, `color-mix`, `oklch(from)`, `contrast-color` | test-only |
| `Tests/SwiflowUITests/Support/CSSValueParsing.swift` | Extract hex / `oklch` lightness values out of the emitted sheet (single source of truth) | test-only |
| `Tests/SwiflowUITests/ContrastColorTests.swift` | Unit tests for the pipeline | test-only |
| `Tests/SwiflowUITests/ThemeContrastTests.swift` | The proof: default palette clears WCAG on the real tint/fill | test-only |
| `Sources/SwiflowUI/Theme.swift` | The token declarations (`-strong`, `-text`, `prefers-contrast: more`) | **ships** |
| `Tests/SwiflowUITests/ThemeTests.swift` | Add structural assertions that the static+dynamic pairs are emitted | test-only |

**Conventions to follow (already in the codebase):**
- Tests use Swift Testing: `import Testing`, `@Suite("Name") @MainActor struct …`, `@Test("desc") func …()`, `#expect(…)`. See `Tests/SwiflowUITests/ThemeTests.swift`.
- The emitted sheet is read via `SwiflowUI.baseStyleSheet.cssString(scopeClass: "")` (it's `@testable import SwiflowUI`).
- `Theme.swift`'s `baseStyleSheet` is one `raw("""…""")` block: a `:root { … }` rule then five `@media` layers. Edit the CSS string in place.

---

### Task 1: Color pipeline — conversions, luminance, WCAG ratio

**Files:**
- Create: `Tests/SwiflowUITests/Support/ContrastColor.swift`
- Create: `Tests/SwiflowUITests/ContrastColorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowUITests/ContrastColorTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiflowUI

@Suite("ContrastColor")
struct ContrastColorTests {
    @Test("Hex parses to linear sRGB with correct WCAG luminance")
    func luminanceEndpoints() {
        #expect(abs(Color.hex("#ffffff").luminance - 1.0) < 1e-9)
        #expect(abs(Color.hex("#000000").luminance - 0.0) < 1e-9)
    }

    @Test("WCAG contrast: white on black is 21:1; #767676 on white is ~4.54:1")
    func wcagKnownPairs() {
        #expect(abs(Color.wcagContrast(.white, .black) - 21.0) < 0.01)
        let midGrayOnWhite = Color.wcagContrast(Color.hex("#767676"), .white)
        #expect(abs(midGrayOnWhite - 4.54) < 0.05)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ContrastColor`
Expected: FAIL — `Color` / `LinRGB` undefined (compile error).

- [ ] **Step 3: Write minimal implementation**

Create `Tests/SwiflowUITests/Support/ContrastColor.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ContrastColor`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Tests/SwiflowUITests/Support/ContrastColor.swift Tests/SwiflowUITests/ContrastColorTests.swift
git commit -m "test(swiflowui): color pipeline core — hex, luminance, WCAG ratio"
```

---

### Task 2: Color pipeline — OKLab/OKLCH, color-mix, oklch(from), contrast-color

**Files:**
- Modify: `Tests/SwiflowUITests/Support/ContrastColor.swift`
- Modify: `Tests/SwiflowUITests/ContrastColorTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `ContrastColorTests.swift` (inside the `struct`):

```swift
    @Test("OKLab round-trips linear sRGB within tolerance")
    func okLabRoundTrip() {
        for hex in ["#3b82f6", "#dc2626", "#16a34a", "#1a1a1a", "#f6f7f9"] {
            let c = Color.hex(hex)
            let back = Color.okLabToLinRGB(Color.linRGBToOKLab(c))
            #expect(abs(back.r - c.r) < 1e-6)
            #expect(abs(back.g - c.g) < 1e-6)
            #expect(abs(back.b - c.b) < 1e-6)
        }
    }

    @Test("color-mix(in oklab) endpoints and identity")
    func mixOKLab() {
        // Mixing a color with itself returns the same color.
        let blue = Color.hex("#3b82f6")
        let same = Color.mixOKLab(blue, blue, weightBase: 0.15)
        #expect(abs(same.luminance - blue.luminance) < 1e-9)
        // weightBase 1.0 → all base; 0.0 → all other.
        #expect(Color.mixOKLab(.white, .black, weightBase: 1.0).luminance > 0.99)
        #expect(Color.mixOKLab(.white, .black, weightBase: 0.0).luminance < 0.01)
    }

    @Test("oklch(from …) keeps hue, replaces lightness")
    func oklchFrom() {
        let out = Color.oklchFrom(Color.hex("#3b82f6"), lightness: 0.40)
        let lch = Color.okLabToOKLCH(Color.linRGBToOKLab(out))
        #expect(abs(lch.L - 0.40) < 0.02)   // clamp may nudge slightly
    }

    @Test("contrast-color picks the higher-contrast of black/white")
    func contrastColor() {
        #expect(Color.contrastColor(against: .white) == .black)
        #expect(Color.contrastColor(against: .black) == .white)
        // Default light accent #3b82f6 → black wins (5.7:1 vs white 3.68:1).
        #expect(Color.contrastColor(against: Color.hex("#3b82f6")) == .black)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ContrastColor`
Expected: FAIL — `linRGBToOKLab`, `okLabToLinRGB`, `okLabToOKLCH`, `mixOKLab`, `oklchFrom`, `contrastColor`, `OKLab`, `OKLCH` undefined.

- [ ] **Step 3: Write minimal implementation**

Add to `ContrastColor.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ContrastColor`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Tests/SwiflowUITests/Support/ContrastColor.swift Tests/SwiflowUITests/ContrastColorTests.swift
git commit -m "test(swiflowui): color pipeline — OKLab/OKLCH, color-mix, oklch-from, contrast-color"
```

---

### Task 3: CSS value parsing helpers (single source of truth)

**Files:**
- Create: `Tests/SwiflowUITests/Support/CSSValueParsing.swift`
- Modify: `Tests/SwiflowUITests/ContrastColorTests.swift`

- [ ] **Step 1: Write the failing test**

Append a new suite to `ContrastColorTests.swift` (top level, after the existing struct):

```swift
@Suite("CSSValueParsing")
@MainActor
struct CSSValueParsingTests {
    private var sheet: String { SwiflowUI.baseStyleSheet.cssString(scopeClass: "") }

    @Test("baseRegion stops before the first media layer")
    func baseRegionSplit() {
        let base = CSSValueParsing.baseRegion(sheet)
        #expect(base.contains("--sw-accent"))
        #expect(!base.contains("@media"))
    }

    @Test("lightDarkHex reads the current accent/surface/accent-text literals")
    func lightDarkHexReads() {
        let base = CSSValueParsing.baseRegion(sheet)
        #expect(CSSValueParsing.lightDarkHex(base, "--sw-accent")!  == ("#3b82f6", "#60a5fa"))
        #expect(CSSValueParsing.lightDarkHex(base, "--sw-surface")! == ("#ffffff", "#1a1a1a"))
    }

    @Test("contrastMoreRegion isolates the prefers-contrast block")
    func contrastMoreRegionReads() {
        let region = CSSValueParsing.contrastMoreRegion(sheet)
        #expect(region.contains("--sw-border-width: 2px"))
        #expect(!region.contains("color-gamut"))   // a different layer
    }

    @Test("oklchLightnesses parses an L pair from a sample declaration")
    func oklchLightnessesParses() {
        let sample = "--sw-accent-strong: light-dark(oklch(from var(--sw-accent) 0.40 c h), oklch(from var(--sw-accent) 0.80 c h));"
        let L = CSSValueParsing.oklchLightnesses(sample, "--sw-accent-strong")!
        #expect(abs(L.light - 0.40) < 1e-9)
        #expect(abs(L.dark - 0.80) < 1e-9)
    }
}
```

Note: `==` on the returned `(light:String, dark:String)` tuple works because Swift synthesizes tuple equality for same-typed labeled tuples.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CSSValueParsing`
Expected: FAIL — `CSSValueParsing` undefined (compile error).

- [ ] **Step 3: Write minimal implementation**

Create `Tests/SwiflowUITests/Support/CSSValueParsing.swift`:

```swift
import Foundation

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

    /// `<token>: light-dark(oklch(from … L1 c h), oklch(from … L2 c h))` → (L1, L2).
    static func oklchLightnesses(_ region: String, _ token: String) -> (light: Double, dark: Double)? {
        let t = NSRegularExpression.escapedPattern(for: token)
        // Match the inner var(--sw-…) explicitly — a `[^)]` class would stop at the ")"
        // that closes var(), never reaching the lightness.
        let oklch = "oklch\\(from var\\(--sw-[a-z]+\\)\\s+([0-9.]+) c h\\)"
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
```

Note on prefix safety: the `\s*:` after the escaped token means `--sw-accent` will NOT match inside `--sw-accent-strong:` / `--sw-accent-text:` (the next char there is `-`, not whitespace/colon), so each token resolves to its own declaration.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CSSValueParsing`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Tests/SwiflowUITests/Support/CSSValueParsing.swift Tests/SwiflowUITests/ContrastColorTests.swift
git commit -m "test(swiflowui): CSS value parsing helpers for contrast proofs"
```

---

### Task 4: Part A — soft-tint `-strong` tokens (WCAG 4.5, normal)

**Files:**
- Create: `Tests/SwiflowUITests/ThemeContrastTests.swift`
- Modify: `Sources/SwiflowUI/Theme.swift:67-72` (the `-strong` declarations)

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowUITests/ThemeContrastTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiflowUI

@Suite("Theme contrast")
@MainActor
struct ThemeContrastTests {
    private var sheet: String { SwiflowUI.baseStyleSheet.cssString(scopeClass: "") }

    private static let hues = [("--sw-accent-strong", "--sw-accent"),
                               ("--sw-danger-strong", "--sw-danger"),
                               ("--sw-success-strong", "--sw-success")]

    /// Rebuild tint = color-mix(in oklab, hue 15%, surface); text = oklch(from hue, L);
    /// return their WCAG contrast.
    private func tintContrast(hueHex: String, surfaceHex: String, textL: Double) -> Double {
        let tint = Color.mixOKLab(Color.hex(hueHex), Color.hex(surfaceHex), weightBase: 0.15)
        return Color.wcagContrast(Color.oklchFrom(Color.hex(hueHex), lightness: textL), tint)
    }

    @Test("Soft-tint -strong text clears WCAG 4.5 on the 15% tint (light & dark)")
    func softTintMeetsAA() {
        let base = CSSValueParsing.baseRegion(sheet)
        let surface = CSSValueParsing.lightDarkHex(base, "--sw-surface")!
        for (strong, hue) in Self.hues {
            let hueHex = CSSValueParsing.lightDarkHex(base, hue)!
            let L = CSSValueParsing.oklchLightnesses(base, strong)!
            #expect(tintContrast(hueHex: hueHex.light, surfaceHex: surface.light, textL: L.light) >= 4.5,
                    "\(strong) light fails AA")
            #expect(tintContrast(hueHex: hueHex.dark, surfaceHex: surface.dark, textL: L.dark) >= 4.5,
                    "\(strong) dark fails AA")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "Theme contrast"`
Expected: FAIL — `oklchLightnesses(base, strong)!` force-unwraps `nil` (no `oklch(from …)` declarations exist yet), crashing the test.

- [ ] **Step 3: Write minimal implementation**

In `Sources/SwiflowUI/Theme.swift`, replace the three `-strong` lines (currently lines 67–72, the comment + three `light-dark(#…, #…)` declarations) with static-fallback + dynamic pairs:

```css
          /* "strong" = semantic-hue text readable on a 15% tint of that hue.
             Static fallback first (hand-tuned, kept for pre-Baseline browsers); the
             dynamic oklch(from …) derivation below re-pins lightness to clear WCAG 4.5
             on the tint and recomputes when an app overrides the base hue.
             Lightnesses proven by ThemeContrastTests. */
          --sw-accent-strong: light-dark(#1d4ed8, #60a5fa);
          --sw-accent-strong: light-dark(oklch(from var(--sw-accent) 0.40 c h), oklch(from var(--sw-accent) 0.80 c h));
          --sw-danger-strong: light-dark(#b91c1c, #f87171);
          --sw-danger-strong: light-dark(oklch(from var(--sw-danger) 0.40 c h), oklch(from var(--sw-danger) 0.80 c h));
          --sw-success-strong: light-dark(#15803d, #4ade80);
          --sw-success-strong: light-dark(oklch(from var(--sw-success) 0.40 c h), oklch(from var(--sw-success) 0.80 c h));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "Theme contrast"`
Expected: PASS. If any hue/mode fails, **tune that L** and re-run: in light mode *lower* L (darker text → more contrast on the pale tint); in dark mode *raise* L (lighter text → more contrast on the dark tint). Move in 0.02 steps until ≥ 4.5 with a small margin, then keep the value. (Starting values 0.40/0.80 are expected to pass for all three hues.)

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowUI/Theme.swift Tests/SwiflowUITests/ThemeContrastTests.swift
git commit -m "feat(swiflowui): derive -strong soft-tint text via oklch(from); proven WCAG 4.5"
```

---

### Task 5: Part A — higher-contrast layer (WCAG 7, `prefers-contrast: more`)

**Files:**
- Modify: `Tests/SwiflowUITests/ThemeContrastTests.swift`
- Modify: `Sources/SwiflowUI/Theme.swift` (the `@media (prefers-contrast: more)` block, currently lines 102–111)

- [ ] **Step 1: Write the failing test**

Append to `ThemeContrastTests` (inside the struct):

```swift
    @Test("Under prefers-contrast: more, -strong clears WCAG 7 on the 15% tint")
    func softTintMeetsAAA() {
        let base = CSSValueParsing.baseRegion(sheet)
        let more = CSSValueParsing.contrastMoreRegion(sheet)
        let surface = CSSValueParsing.lightDarkHex(base, "--sw-surface")!
        for (strong, hue) in Self.hues {
            let hueHex = CSSValueParsing.lightDarkHex(base, hue)!
            let L = CSSValueParsing.oklchLightnesses(more, strong)!
            #expect(tintContrast(hueHex: hueHex.light, surfaceHex: surface.light, textL: L.light) >= 7.0,
                    "\(strong) light fails AAA under more-contrast")
            #expect(tintContrast(hueHex: hueHex.dark, surfaceHex: surface.dark, textL: L.dark) >= 7.0,
                    "\(strong) dark fails AAA under more-contrast")
        }
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "Theme contrast"`
Expected: FAIL — `oklchLightnesses(more, strong)!` is `nil` (the more-contrast block has no `-strong` overrides yet).

- [ ] **Step 3: Write minimal implementation**

In `Theme.swift`, inside the existing `@media (prefers-contrast: more) { :root { … } }` block, add `-strong` overrides after the existing `--sw-shadow` line:

```css
            /* -strong pushed to WCAG 7 on the tint (proven by ThemeContrastTests). */
            --sw-accent-strong: light-dark(oklch(from var(--sw-accent) 0.30 c h), oklch(from var(--sw-accent) 0.88 c h));
            --sw-danger-strong: light-dark(oklch(from var(--sw-danger) 0.30 c h), oklch(from var(--sw-danger) 0.88 c h));
            --sw-success-strong: light-dark(oklch(from var(--sw-success) 0.30 c h), oklch(from var(--sw-success) 0.88 c h));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "Theme contrast"`
Expected: PASS. If a case fails, tune L the same way (light: lower toward 0.25; dark: raise toward 0.92) until ≥ 7.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowUI/Theme.swift Tests/SwiflowUITests/ThemeContrastTests.swift
git commit -m "feat(swiflowui): -strong reaches WCAG 7 under prefers-contrast: more"
```

---

### Task 6: Part B — solid-fill `--sw-accent-text` via contrast-color

**Files:**
- Modify: `Tests/SwiflowUITests/ThemeContrastTests.swift`
- Modify: `Sources/SwiflowUI/Theme.swift:64` (the `--sw-accent-text` declaration)

- [ ] **Step 1: Write the failing test**

Append to `ThemeContrastTests` (inside the struct):

```swift
    @Test("Solid-fill accent text clears WCAG 4.5 (contrast-color result AND fallback)")
    func solidFillMeetsAA() {
        let base = CSSValueParsing.baseRegion(sheet)
        let accent = CSSValueParsing.lightDarkHex(base, "--sw-accent")!
        let fallback = CSSValueParsing.lightDarkHex(base, "--sw-accent-text")!
        for (accentHex, fallbackHex) in [(accent.light, fallback.light), (accent.dark, fallback.dark)] {
            let bg = Color.hex(accentHex)
            let derived = Color.contrastColor(against: bg)        // what the browser renders
            #expect(Color.wcagContrast(derived, bg) >= 4.5, "contrast-color on \(accentHex) fails AA")
            #expect(Color.wcagContrast(Color.hex(fallbackHex), bg) >= 4.5, "fallback \(fallbackHex) on \(accentHex) fails AA")
        }
        #expect(base.contains("contrast-color(var(--sw-accent))"), "dynamic declaration missing")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "Theme contrast"`
Expected: FAIL — two ways: the fallback is still `#ffffff` in light mode (white on `#3b82f6` = 3.68:1 < 4.5), and the sheet has no `contrast-color(var(--sw-accent))` declaration.

- [ ] **Step 3: Write minimal implementation**

In `Theme.swift`, replace the current `--sw-accent-text: light-dark(#ffffff, #0b1220);` (line 64) with:

```css
          /* Solid-fill text: contrast-color() picks black on the accent (both modes — the
             accent is medium/light blue), fixing today's sub-AA white (3.68:1 on #3b82f6).
             Fallback is dark in BOTH arms so pre-Baseline browsers also pass. See Button. */
          --sw-accent-text: light-dark(#0b1220, #0b1220);
          --sw-accent-text: contrast-color(var(--sw-accent));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "Theme contrast"`
Expected: PASS (all `Theme contrast` tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowUI/Theme.swift Tests/SwiflowUITests/ThemeContrastTests.swift
git commit -m "feat(swiflowui): solid-fill --sw-accent-text via contrast-color; fixes sub-AA button"
```

---

### Task 7: Structural assertions — both layers are emitted

**Files:**
- Modify: `Tests/SwiflowUITests/ThemeTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `struct ThemeTests` in `Tests/SwiflowUITests/ThemeTests.swift`:

```swift
    @Test("Each derived text token ships a static fallback AND a dynamic layer")
    func progressiveEnhancementPairsEmitted() {
        let css = sheet
        // -strong: a light-dark hex fallback and an oklch(from …) dynamic layer.
        for token in ["--sw-accent-strong", "--sw-danger-strong", "--sw-success-strong"] {
            let hue = token.replacingOccurrences(of: "-strong", with: "")  // e.g. --sw-accent
            #expect(css.contains("\(token): light-dark(#"), "\(token) missing static fallback")
            #expect(css.contains("oklch(from var(\(hue))"), "\(token) missing oklch(from …) dynamic layer")
        }
        // -text: dark fallback + contrast-color dynamic layer.
        #expect(css.contains("--sw-accent-text: light-dark(#0b1220, #0b1220)"))
        #expect(css.contains("--sw-accent-text: contrast-color(var(--sw-accent))"))
    }
```

- [ ] **Step 2: Run test to verify it fails (then passes)**

Run: `swift test --filter Theme`
Expected: PASS immediately — Tasks 4–6 already added these declarations, so this test locks them in as a regression guard. (If it fails, a token declaration drifted from the exact strings above; reconcile the test's expected substrings with `Theme.swift`.)

- [ ] **Step 3: Run the full SwiflowUI suite**

Run: `swift test --filter SwiflowUITests`
Expected: PASS — no existing test regressed (notably `ThemeTests.forwardContractTokens`, which already asserts the `-strong`/`-text` tokens are present by name).

- [ ] **Step 4: Commit**

```bash
git add Tests/SwiflowUITests/ThemeTests.swift
git commit -m "test(swiflowui): lock both fallback+dynamic layers of the contrast tokens"
```

---

## Final verification (after all tasks)

- [ ] Run the full suite: `swift test` → all green.
- [ ] Confirm no shipping color math leaked into `Sources/SwiflowUI/` — only `Theme.swift` changed there: `git diff --stat main -- Sources/` shows `Sources/SwiflowUI/Theme.swift` and nothing else.
- [ ] Build the demo to eyeball the button restyle (per [[ci-skips-example-builds]] CI won't): `swift build -c release --product swiflow && swiflow build --path examples/SwiflowUIDemo` — primary buttons show dark labels on the blue accent in light mode; Badges remain readable.
- [ ] Dispatch the final code reviewer (subagent-driven-development's end-of-plan step).

## Notes for the implementer

- **No component files change.** `Badge`, `Button`, `Autocomplete`, `Dropdown` already read the tokens; touching them is out of scope.
- **The L constants are owned by the test, not the spec.** If a default hue is ever re-tuned, the contrast tests fail loudly and the L values get re-found — that's the intended safety net.
- **Why the color math lives in tests:** the browser is the runtime engine (`oklch(from)`, `contrast-color`); Swift only proves the defaults. Shipping the pipeline would add dead weight to the wasm. If a future 1.1 builds a palette *generator*, promote `Support/ContrastColor.swift` into the module then.
- **Stated limitation (Part A):** absolute-L pinning is proven only for the three default hues; a custom app hue gets best-effort readability, not a proof. This is by design (pure CSS can't compute a ratio).
