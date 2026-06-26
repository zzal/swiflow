# Public `SwiflowColor` theme generator — Design

> **Date:** 2026-06-26 · **Status:** approved, ready for implementation plan
> **Milestone:** M8 follow-up — the **"promote `SwiflowColor` to a public (shipping) generator"**
> item, the last M8 deferral.
> **Builds on:** the `swiflow theme` generator + WCAG/APCA validation in
> `Sources/SwiflowColor/ContrastColor.swift`.

## Problem

The `swiflow theme` **CLI** already ships (it's part of the released `swiflow` binary), but the
underlying color library, `SwiflowColor`, is an internal SwiftPM **target** — not a `.library`
product — so nothing outside the repo can depend on it. Its ~20 `public` members are public mostly
so tests can reach them: a grab-bag mixing low-level color math (`hex`, `mixOKLab`, `oklchFrom`,
`hexString`, OKLab/OKLCH conversions, p3 math) with the actual generator surface (`accentThemeCSS`,
the `validate*` functions, `PaletteFailure`). There is no intentional, supported API for generating
a Swiflow theme programmatically (e.g. from a build plugin, a design tool, or a user's own Swift
tooling).

## Goal

Ship `SwiflowColor` as a **public `.library` product** with a **small, curated API** for
programmatic theme generation, and demote the color-math internals to `internal`. The generation
*behavior* (accent/status/neutral/p3/APCA) is unchanged — this is a packaging + API-curation pass,
not new color features. The CLI keeps identical output.

## Decisions (from brainstorming)

1. **Curated library API + product** (not a build-tool plugin, not expose-the-current-surface-as-is).
2. **Structured-result error model:** `generate(...)` returns the CSS *plus* any contrast failures;
   it never throws for contrast shortfalls. Only malformed hex throws.
3. **Public surface = generator + contrast utilities:** the `ThemeGenerator` facade, its config and
   result types, `PaletteFailure`, `ThemeError`, **and** the two contrast metrics (`Contrast.wcag` /
   `Contrast.apca`, hex-based). Everything else becomes `internal`.

## Public API

```swift
/// Inputs for a generated theme (mirrors the `swiflow theme` flags).
public struct ThemeOptions: Equatable, Sendable {
    public var primary: String                              // brand hex (required)
    public var danger: String?
    public var success: String?
    public var warning: String?
    public var info: String?                                // defaults to the accent when nil
    public var includeNeutrals: Bool
    public init(primary: String, danger: String? = nil, success: String? = nil,
                warning: String? = nil, info: String? = nil, includeNeutrals: Bool = false)
}

/// The outcome of a generation: the CSS is ALWAYS produced; `failures` lists every
/// contrast shortfall (empty == all pass). The caller decides whether to treat failures
/// as fatal — the CLI does; another tool might warn.
public struct ThemeResult: Equatable, Sendable {
    public let css: String
    public let failures: [PaletteFailure]
    public var isValid: Bool { failures.isEmpty }
}

public enum ThemeGenerator {
    /// Generate a Swiflow `:root` theme override. Throws `ThemeError.invalidHex` ONLY for
    /// malformed hex input; contrast shortfalls are returned in `result.failures`, not thrown.
    public static func generate(_ options: ThemeOptions) throws -> ThemeResult
}

/// Hex-based contrast metrics (no `LinRGB` in the public surface).
public enum Contrast {
    /// WCAG 2.x contrast ratio (1…21) between two `#rgb`/`#rrggbb` colors. Throws on malformed hex.
    public static func wcag(_ aHex: String, _ bHex: String) throws -> Double
    /// APCA-W3 perceptual Lc (signed; advisory) for `textHex` on `bgHex`. Throws on malformed hex.
    public static func apca(textHex: String, bgHex: String) throws -> Double
}

/// One contrast shortfall for a generated token, in one color scheme, with its advisory APCA
/// reading. (Moved to top level; fields unchanged from today.)
public struct PaletteFailure: Equatable, Sendable, CustomStringConvertible {
    public let token: String
    public let mode: String          // "light" | "dark"
    public let ratio: Double
    public let target: Double
    public let apcaLc: Double
    public let apcaTarget: Double
    public var description: String   // "… < … required — APCA Lc … (suggests ≥ … for …)"
}

public enum ThemeError: Error, CustomStringConvertible {
    case invalidHex(String)
    public var description: String   // "invalid theme color hex: … (expected #rgb or #rrggbb)"
}
```

Usage:

```swift
import SwiflowColor
let result = try ThemeGenerator.generate(.init(primary: "#7c3aed", danger: "#e11d48",
                                               includeNeutrals: true))
if result.isValid { write(result.css) } else { result.failures.forEach { print($0) } }
```

### Error-model change (deliberate)

Today `accentThemeCSS` *throws* `PaletteError.contrastFailures([...])` and returns no CSS on
failure. The new `generate` always returns CSS and surfaces failures in `result.failures`. The
`contrastFailures` thrown case is therefore **removed**; the only thrown case is `invalidHex`
(renamed into `ThemeError`). The CLI reproduces today's behavior by checking `result.failures`.

## What becomes internal

`enum Color` and **all** its members — `LinRGB` / `OKLab` / `OKLCH`, every space conversion,
`mixOKLab`, `oklchFrom`, `contrastColor`, `hexString`, `darkAccent`, `wcagContrast(LinRGB,LinRGB)`,
`apcaContrast`, the p3 helpers, `accentThemeCSS`, and the three `validate*` functions — drop to
`internal`. They remain the engine behind `ThemeGenerator.generate`; tests reach them via
`@testable import`. The public `Contrast.wcag/apca` are thin hex-based wrappers over the internal
`Color.wcagContrast(hex(a), hex(b))` / `Color.apcaContrast`.

## Packaging

Add to `Package.swift` `products`:

```swift
.library(name: "SwiflowColor", targets: ["SwiflowColor"]),
```

The `SwiflowColor` target already exists and is depended on by `SwiflowCLI`, `SwiflowColorTests`,
and `SwiflowUITests`; this only makes it externally consumable. **It stays native-only** — never a
dependency of the wasm `SwiflowUI` (it uses host `Double`/`Foundation` math). A module-header note
records this boundary so a future contributor doesn't wire it into a browser target.

## File split

`Sources/SwiflowColor/ContrastColor.swift` (~500 lines doing everything) is now a shipping module;
split by responsibility so the public surface is obvious and each file is focused. Pure
code-movement, no behavior change:

| File | Contents | Visibility |
|------|----------|------------|
| `Color.swift` | `LinRGB`/`OKLab`/`OKLCH`, conversions, `mixOKLab`/`oklchFrom`/`contrastColor`/`hexString`/`darkAccent`/p3, `wcagContrast`/`apcaContrast` primitives | internal |
| `Contrast.swift` | public `Contrast.wcag` / `Contrast.apca` (hex wrappers) | public |
| `PaletteFailure.swift` | public `PaletteFailure` + `ThemeError` | public |
| `ThemeGenerator.swift` | public `ThemeOptions` / `ThemeResult` / `ThemeGenerator.generate`; the internal `accentThemeCSS` + `validate*` engine it drives | mixed |

`ContrastColor.swift` is removed.

## Migration (behavior-identical)

- **CLI `Sources/SwiflowCLI/Commands/ThemeCommand.swift`** — replace `Color.accentThemeCSS(...)` +
  `catch PaletteError` with `ThemeGenerator.generate(...)`. If `result.failures` is non-empty, print
  the same per-token diagnostic block and exit non-zero (today's build-fails-on-shortfall behavior);
  otherwise print `result.css`. Malformed hex still errors. The `swiflow theme` stdout for any given
  input is **byte-identical** to before.
- **Tests** — `SwiflowColorTests` and the `SwiflowUITests` contrast tests that reach `Color.*` use
  `@testable import SwiflowColor` (most already do; any plain `import` that now references an
  internal is switched). No assertion changes — `accentThemeCSS`/`validate*` still exist internally.

## Testing

- **New public-API tests** (`Tests/SwiflowColorTests/PublicAPITests.swift`, **plain**
  `import SwiflowColor` — the real proof the shipped surface is usable):
  - `ThemeGenerator.generate(.init(primary: "#3b82f6"))` → non-empty `css`, `failures.isEmpty`,
    `isValid == true`.
  - A washed-out seed (e.g. `primary` ok + `danger: "#f1a9a9"`) → `isValid == false`, `failures`
    names `--sw-danger`, and a failure carries its `apcaLc`/`apcaTarget` — **without throwing**.
  - `generate(.init(primary: "#nope"))` throws `ThemeError.invalidHex`.
  - `Contrast.wcag("#000000", "#ffffff")` ≈ 21; `Contrast.apca(textHex: "#000000", bgHex: "#ffffff")`
    ≈ 106 within tolerance; both throw on malformed hex.
- **Internal tests** keep their `@testable` coverage of `Color.*` and `accentThemeCSS`/`validate*`.
- **CLI smoke:** `swiflow theme --primary "#3b82f6" --danger "#e11d48" --neutrals` output is
  byte-identical to `main`'s; a failing seed still exits non-zero with the same diagnostic.

## Components & boundaries

| Unit | Change | New? |
|------|--------|------|
| `ThemeGenerator` / `ThemeOptions` / `ThemeResult` | public facade + config + result | new |
| `Contrast` (`wcag`/`apca`, hex) | public contrast metrics | new |
| `PaletteFailure`, `ThemeError` | promoted to top-level public types | moved |
| `Color` + all math/`accentThemeCSS`/`validate*` | demoted to `internal` | changed |
| `Package.swift` | add `SwiflowColor` `.library` product | changed |
| `ThemeCommand` | migrate to `ThemeGenerator.generate` | changed |
| `docs/guides/swiflowcolor.md` | new public-API guide | new |

## Non-goals

- **No new generation capability** — accent/status/neutral/p3/APCA behavior is unchanged.
- **No wasm/browser exposure** — `SwiflowColor` stays native-only.
- **No CLI flag changes** — `swiflow theme` output is unchanged.
- **No APCA/WCAG threshold changes.**

## Decisions resolved during brainstorming

1. **Deliverable** → curated library API + `.library` product (build-tool plugin and
   expose-as-is rejected).
2. **Error model** → structured `ThemeResult` (CSS + `failures`); only malformed hex throws.
3. **Surface** → generator facade + `Contrast.wcag`/`apca`; all color-space math goes internal.
4. **Packaging** → native-only `.library`; never a wasm `SwiflowUI` dependency.
5. **Structure** → split `ContrastColor.swift` into `Color` / `Contrast` / `PaletteFailure` /
   `ThemeGenerator` files (code-movement only).
