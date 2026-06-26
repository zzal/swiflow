# Public `SwiflowColor` theme generator — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `SwiflowColor` as a public `.library` product with a small, curated theme-generation API (`ThemeGenerator.generate` → `ThemeResult`, `Contrast.wcag`/`apca`), demoting the color-math internals to `internal` — with behavior-identical CLI output.

**Architecture:** Extract the public surface (`ThemeOptions`/`ThemeResult`/`ThemeGenerator`, `Contrast`, `PaletteFailure`, `ThemeError`) into focused new files; refactor the internal `accentThemeCSS` to return `(css, failures)` instead of throwing on contrast shortfalls; migrate the CLI to the facade; demote `enum Color` to `internal`; add the `.library` product. Each task ends with a green build + full test suite.

**Tech Stack:** Swift, Swift Testing (`@Suite`/`@Test`/`#expect`), SwiftPM. `SwiflowColor` is native-only (CLI + tests), never a wasm dependency.

---

## File structure (target)

`Sources/SwiflowColor/ContrastColor.swift` (one ~500-line file) splits into:

| File | Responsibility | Visibility (final) |
|------|----------------|--------------------|
| `Color.swift` (renamed from `ContrastColor.swift`) | color math: `LinRGB`/`OKLab`/`OKLCH`, conversions, `mixOKLab`/`oklchFrom`/`contrastColor`/`hexString`/`darkAccent`/p3, `wcagContrast`/`apcaContrast`, `normalizeHex`, `accentThemeCSS` + `validate*` engine | internal (Task 4) |
| `PaletteFailure.swift` (new) | public `PaletteFailure` + `ThemeError` | public |
| `ThemeGenerator.swift` (new) | public `ThemeOptions` / `ThemeResult` / `ThemeGenerator.generate` | public |
| `Contrast.swift` (new) | public `Contrast.wcag` / `Contrast.apca` (hex wrappers) | public |

Tasks 1–3 keep `Color` **public** (so nothing else breaks while the surface is built); Task 4 demotes it to `internal` and switches the two `SwiflowUITests` files to `@testable`. Task 5 adds the product + public-API tests. Task 6 docs.

## Context every task needs

- **Spec:** `docs/superpowers/specs/2026-06-26-swiflowcolor-public-generator-design.md`.
- The engine lives in `Sources/SwiflowColor/ContrastColor.swift` inside `public enum Color`. Key members: `hex`, `wcagContrast(LinRGB,LinRGB)`, `apcaContrast(textHex:bgHex:)`, `normalizeHex` (internal, currently throws `PaletteError.invalidHex`), `accentThemeCSS(primaryHex:dangerHex:successHex:warningHex:infoHex:includeNeutrals:) throws -> String`, `validateAccentFamily`/`validateStatusFamily`/`validateNeutrals`, and the nested `PaletteFailure` struct + `PaletteError` enum.
- `accentThemeCSS` currently `throw PaletteError.contrastFailures(failures)` at two `guard failures.isEmpty else { … }` sites (one per return path) and assembles CSS only when failures are empty.
- The CLI is `Sources/SwiflowCLI/Commands/ThemeCommand.swift` (`import SwiflowColor`; calls `Color.accentThemeCSS(...)`).
- Tests: `Tests/SwiflowColorTests/*` all use `@testable import SwiflowColor`. `Tests/SwiflowUITests/ContrastColorTests.swift` and `ThemeContrastTests.swift` use **plain** `import SwiflowColor` and reach `Color.*`. `Tests/SwiflowCLITests/ThemeCommandTests.swift` (`@testable import SwiflowCLI`) asserts the bad-seed case with `#expect(throws: (any Error).self)` — no SwiflowColor types referenced.
- **Run:** `swift build` and `swift test` (host). Authoritative for everything (no wasm here).

---

## Task 1: Public result + error types (`PaletteFailure.swift`)

**Files:**
- Create: `Sources/SwiflowColor/PaletteFailure.swift`
- Modify: `Sources/SwiflowColor/ContrastColor.swift` (remove the nested `PaletteFailure` + `PaletteError`; point `normalizeHex` at `ThemeError`)
- Modify: `Tests/SwiflowColorTests/AccentThemeTests.swift` (the two throw-tests)

- [ ] **Step 1: Create the public types file**

Create `Sources/SwiflowColor/PaletteFailure.swift`:

```swift
// Sources/SwiflowColor/PaletteFailure.swift
//
// Public result/error types for the theme generator. SwiflowColor is native-only
// (CLI + host tooling) — NEVER add it to the wasm SwiflowUI target.
import Foundation

/// One contrast shortfall for a generated token, in one color scheme, with its advisory
/// APCA reading. Returned in `ThemeResult.failures`.
public struct PaletteFailure: Equatable, Sendable, CustomStringConvertible {
    public let token: String
    public let mode: String        // "light" | "dark"
    public let ratio: Double
    public let target: Double
    /// Signed APCA Lc for this token's text/surface pairing (advisory; `abs` is compared).
    public let apcaLc: Double
    /// APCA's recommended Lc for this usage (75 text, 45 non-text). Guidance, never gated.
    public let apcaTarget: Double

    public init(token: String, mode: String, ratio: Double, target: Double,
                apcaLc: Double, apcaTarget: Double) {
        self.token = token; self.mode = mode; self.ratio = ratio; self.target = target
        self.apcaLc = apcaLc; self.apcaTarget = apcaTarget
    }

    public var description: String {
        let wcag = String(format: "%@ (%@): %.2f:1 < %.1f:1 required", token, mode, ratio, target)
        let usage = apcaTarget >= 75 ? "text" : "non-text"
        let apca = String(format: " — APCA Lc %.0f (suggests ≥ %.0f for %@)",
                          abs(apcaLc), apcaTarget, usage)
        return wcag + apca
    }
}

/// Errors thrown by the theme generator. Contrast shortfalls are NOT errors — they are
/// returned in `ThemeResult.failures`. Only malformed input throws.
public enum ThemeError: Error, CustomStringConvertible {
    case invalidHex(String)
    public var description: String {
        switch self {
        case .invalidHex(let s): return "invalid theme color hex: \(s) (expected #rgb or #rrggbb)"
        }
    }
}
```

- [ ] **Step 2: Remove the nested `PaletteFailure` struct and `PaletteError` enum from `ContrastColor.swift`**

Delete the entire nested `public struct PaletteFailure: … { … }` block and the entire `public enum PaletteError: Error … { … }` block from `ContrastColor.swift` (they now live in `PaletteFailure.swift`; `PaletteError` is replaced by `ThemeError`).

- [ ] **Step 3: Point `normalizeHex` at `ThemeError`**

In `ContrastColor.swift`, in `normalizeHex`, change the throw:

```swift
        guard ok, h.count == 3 || h.count == 6 else { throw PaletteError.invalidHex(raw) }
```
to:
```swift
        guard ok, h.count == 3 || h.count == 6 else { throw ThemeError.invalidHex(raw) }
```

- [ ] **Step 4: Update the two throw-tests in `AccentThemeTests.swift`**

`accentThemeCSS` still throws on contrast failures *at this point in the plan* (its refactor is Task 2), but `PaletteError` is gone. Temporarily these two tests must reference the type that is actually thrown. Since Task 2 changes the behavior, write them in their FINAL form now and accept that they fail until Task 2 (the suite is run green at the end of Task 2). Replace:

```swift
    func badSeedThrows() {
        // ...
        #expect(throws: Color.PaletteError.self) {
            _ = try Color.accentThemeCSS(primaryHex: "#fde047")
        }
    }
```
with:
```swift
    func badSeedReturnsFailures() throws {
        // #fde047 (yellow) can't meet the accent-as-text bar; the generator now RETURNS the
        // shortfalls rather than throwing (only malformed hex throws).
        let result = try Color.accentThemeCSS(primaryHex: "#fde047")
        #expect(!result.failures.isEmpty)
    }
```
and replace:
```swift
    @Test("Invalid hex throws invalidHex")
    func invalidHexThrows() {
        #expect(throws: Color.PaletteError.self) {
            _ = try Color.accentThemeCSS(primaryHex: "nope")
        }
    }
```
with:
```swift
    @Test("Invalid hex throws invalidHex")
    func invalidHexThrows() {
        #expect(throws: ThemeError.self) {
            _ = try Color.accentThemeCSS(primaryHex: "nope")
        }
    }
```

> NOTE: do not run the suite green yet — `accentThemeCSS` still returns `String` until Task 2, so `result.failures` won't compile. Steps 1–4 are committed together with Task 2's refactor producing the first green bar. (If your workflow requires a green commit here, do Task 2 before committing; otherwise commit Tasks 1+2 together.)

- [ ] **Step 5: Build-check the non-test sources compile**

Run: `swift build`
Expected: FAIL only in test compilation referencing `result.failures` (sources compile once Task 2 lands). Proceed to Task 2 before the green commit.

---

## Task 2: Refactor `accentThemeCSS` to return `(css, failures)`

**Files:**
- Modify: `Sources/SwiflowColor/ContrastColor.swift`
- Modify: `Tests/SwiflowColorTests/AccentThemeTests.swift` (the good-seed call sites)

- [ ] **Step 1: Change the signature**

In `ContrastColor.swift`, change:
```swift
    public static func accentThemeCSS(primaryHex: String,
                                      dangerHex: String? = nil,
                                      successHex: String? = nil,
                                      warningHex: String? = nil,
                                      infoHex: String? = nil,
                                      includeNeutrals: Bool = false) throws -> String {
```
to:
```swift
    public static func accentThemeCSS(primaryHex: String,
                                      dangerHex: String? = nil,
                                      successHex: String? = nil,
                                      warningHex: String? = nil,
                                      infoHex: String? = nil,
                                      includeNeutrals: Bool = false) throws -> (css: String, failures: [PaletteFailure]) {
```

- [ ] **Step 2: Remove the throw-guards and return the tuple (non-neutrals path)**

Replace:
```swift
        if !includeNeutrals {
            guard failures.isEmpty else { throw PaletteError.contrastFailures(failures) }
            let rootBody = (tokenLines("--sw-accent", light, dark) + statusLines)
                .joined(separator: "\n")
            return """
            /* Generated by `swiflow theme --primary \(light)\(flagEcho)`. Include after SwiflowUI's styles.
               Re-points --sw-accent; hover/active/text/strong derive from it automatically. */
            :root {
            \(rootBody)
            }
            """ + "\n"
        }
```
with:
```swift
        if !includeNeutrals {
            let rootBody = (tokenLines("--sw-accent", light, dark) + statusLines)
                .joined(separator: "\n")
            let css = """
            /* Generated by `swiflow theme --primary \(light)\(flagEcho)`. Include after SwiflowUI's styles.
               Re-points --sw-accent; hover/active/text/strong derive from it automatically. */
            :root {
            \(rootBody)
            }
            """ + "\n"
            return (css: css, failures: failures)
        }
```

- [ ] **Step 3: Remove the throw-guard and return the tuple (neutrals path)**

Replace:
```swift
        let neutrals = neutralPalette(accentHex: light)
        failures += validateNeutrals(neutrals)
        guard failures.isEmpty else { throw PaletteError.contrastFailures(failures) }

        let rootLines = (tokenLines("--sw-accent", light, dark)
```
with (drop only the `guard` line):
```swift
        let neutrals = neutralPalette(accentHex: light)
        failures += validateNeutrals(neutrals)

        let rootLines = (tokenLines("--sw-accent", light, dark)
```
and change the final `return """ … """ + "\n"` (the neutrals return at the end of the function) to wrap in the tuple. Replace:
```swift
        return """
        /* Generated by `swiflow theme --primary \(light)\(flagEcho) --neutrals`. Include after SwiflowUI's styles.
           Re-points --sw-accent (family cascades) + the accent-tinted neutral ramp. */
        :root {
        \(rootLines)
        }
        @media (prefers-contrast: more) {
          :root {
        \(moreLines)
          }
        }
        """ + "\n"
    }
```
with:
```swift
        let css = """
        /* Generated by `swiflow theme --primary \(light)\(flagEcho) --neutrals`. Include after SwiflowUI's styles.
           Re-points --sw-accent (family cascades) + the accent-tinted neutral ramp. */
        :root {
        \(rootLines)
        }
        @media (prefers-contrast: more) {
          :root {
        \(moreLines)
          }
        }
        """ + "\n"
        return (css: css, failures: failures)
    }
```

- [ ] **Step 4: Update the good-seed call sites in `AccentThemeTests.swift`**

Every `try Color.accentThemeCSS(...)` that reads the CSS must now read `.css`. Update each (there are several — `goodSeedEmitsCSS`, `normalizesHex` ×2, `mediumDarkAccentPasses`, `accentOnlyUnchanged` ×2, `fullPaletteEmitted`, `statusSeedsEmit`, and any others). Examples:

```swift
let css = try Color.accentThemeCSS(primaryHex: "#3b82f6").css
```
```swift
let css6 = try Color.accentThemeCSS(primaryHex: "3b82f6").css
let css3 = try Color.accentThemeCSS(primaryHex: "#06f").css
```
```swift
let a = try Color.accentThemeCSS(primaryHex: "#3b82f6").css
let b = try Color.accentThemeCSS(primaryHex: "#3b82f6", includeNeutrals: false).css
```

Grep to be exhaustive: `grep -n "accentThemeCSS" Tests/SwiflowColorTests/AccentThemeTests.swift` — every result that feeds a `String` (i.e. all except the Task-1 `badSeedReturnsFailures`, which keeps the tuple and reads `.failures`) gets `.css`.

- [ ] **Step 5: Build + run the full suite green**

Run: `swift build && swift test`
Expected: PASS — all `SwiflowColorTests` (incl. the rewritten `badSeedReturnsFailures` + `invalidHexThrows`), plus the CLI/UI suites still green (the CLI still calls `Color.accentThemeCSS` — wait: it now returns a tuple, so the CLI will FAIL to compile here). **Before running, also do Task 3 Step 1** (CLI migration) so the build is whole — OR temporarily patch the CLI call to `.css` and discard failures. To keep this task self-contained, apply the CLI migration (Task 3) now and commit Tasks 1–3 together.

> Sequencing note: Tasks 1, 2, and 3 form one atomic compile unit (the `accentThemeCSS` signature change ripples into the CLI). Implement Steps from Tasks 1→2→3, then run `swift build && swift test` once, then commit once. The task boundaries are for reading clarity; the first green commit is after Task 3.

---

## Task 3: Add the facade + Contrast, migrate the CLI

**Files:**
- Create: `Sources/SwiflowColor/ThemeGenerator.swift`
- Create: `Sources/SwiflowColor/Contrast.swift`
- Modify: `Sources/SwiflowCLI/Commands/ThemeCommand.swift`

- [ ] **Step 1: Create `ThemeGenerator.swift`**

```swift
// Sources/SwiflowColor/ThemeGenerator.swift

/// Inputs for a generated theme (mirror the `swiflow theme` flags).
public struct ThemeOptions: Equatable, Sendable {
    public var primary: String                 // brand hex (required)
    public var danger: String?
    public var success: String?
    public var warning: String?
    public var info: String?                   // defaults to the accent when nil
    public var includeNeutrals: Bool
    public init(primary: String, danger: String? = nil, success: String? = nil,
                warning: String? = nil, info: String? = nil, includeNeutrals: Bool = false) {
        self.primary = primary; self.danger = danger; self.success = success
        self.warning = warning; self.info = info; self.includeNeutrals = includeNeutrals
    }
}

/// The outcome of a generation: `css` is always produced; `failures` lists every contrast
/// shortfall (empty == all pass). The caller decides whether failures are fatal.
public struct ThemeResult: Equatable, Sendable {
    public let css: String
    public let failures: [PaletteFailure]
    public var isValid: Bool { failures.isEmpty }
    public init(css: String, failures: [PaletteFailure]) {
        self.css = css; self.failures = failures
    }
}

public enum ThemeGenerator {
    /// Generate a Swiflow `:root` theme override. Throws `ThemeError.invalidHex` ONLY for
    /// malformed hex input; contrast shortfalls are returned in `result.failures`, not thrown.
    public static func generate(_ options: ThemeOptions) throws -> ThemeResult {
        let r = try Color.accentThemeCSS(primaryHex: options.primary,
                                         dangerHex: options.danger,
                                         successHex: options.success,
                                         warningHex: options.warning,
                                         infoHex: options.info,
                                         includeNeutrals: options.includeNeutrals)
        return ThemeResult(css: r.css, failures: r.failures)
    }
}
```

- [ ] **Step 2: Create `Contrast.swift`**

```swift
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
```

- [ ] **Step 3: Migrate `ThemeCommand.swift`**

Replace the `func run() throws { … }` body and add a CLI-local error that reproduces today's exact failure message. Replace:

```swift
    func run() throws {
        let css = try Color.accentThemeCSS(primaryHex: primary,
                                           dangerHex: danger,
                                           successHex: success,
                                           warningHex: warning,
                                           infoHex: info,
                                           includeNeutrals: neutrals)
        if let out {
            try css.write(toFile: out, atomically: true, encoding: .utf8)
        } else {
            print(css)
        }
    }
}
```
with:
```swift
    func run() throws {
        let result = try ThemeGenerator.generate(.init(primary: primary,
                                                        danger: danger,
                                                        success: success,
                                                        warning: warning,
                                                        info: info,
                                                        includeNeutrals: neutrals))
        guard result.isValid else { throw ContrastFailuresError(failures: result.failures) }
        if let out {
            try result.css.write(toFile: out, atomically: true, encoding: .utf8)
        } else {
            print(result.css)
        }
    }
}

/// Reproduces the pre-public-API `PaletteError.contrastFailures` message so `swiflow theme`
/// output on a failing seed is byte-identical to before.
private struct ContrastFailuresError: Error, CustomStringConvertible {
    let failures: [PaletteFailure]
    var description: String {
        "brand color fails WCAG for the derived accent family:\n  "
            + failures.map(\.description).joined(separator: "\n  ")
    }
}
```

- [ ] **Step 4: Build + run the full suite green (first green commit)**

Run: `swift build && swift test`
Expected: PASS — all suites green. The CLI now uses the facade; `ThemeCommandTests.badColorThrows` still passes (it asserts `(any Error)`, and `ContrastFailuresError` is thrown).

- [ ] **Step 5: Smoke-test byte-identical CLI output**

Run:
```bash
swift run swiflow theme --primary "#3b82f6" --danger "#e11d48" --neutrals > /tmp/new.css
git stash; swift run swiflow theme --primary "#3b82f6" --danger "#e11d48" --neutrals > /tmp/old.css 2>/dev/null || true; git stash pop
diff /tmp/old.css /tmp/new.css && echo "IDENTICAL"
```
(If stashing is awkward mid-task, instead compare against a capture taken from `origin/main` before starting.) Also confirm a failing seed still errors:
```bash
swift run swiflow theme --primary "#fde047"; echo "exit=$?"
```
Expected: the good run prints CSS (identical), the bad run prints `brand color fails WCAG …` and `exit=1`.

- [ ] **Step 6: Rename `ContrastColor.swift` → `Color.swift` and commit**

```bash
git mv Sources/SwiflowColor/ContrastColor.swift Sources/SwiflowColor/Color.swift
swift build && swift test   # rename is path-only; still green
git add -A
git commit -m "feat(swiflowcolor): public ThemeGenerator facade + Contrast; CLI on facade

PaletteFailure/ThemeError become top-level public types; accentThemeCSS returns
(css, failures) instead of throwing on shortfalls; ThemeGenerator.generate and
Contrast.wcag/apca added; ThemeCommand migrated (output byte-identical). Color
math still public — internalized next.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Demote `Color` (and math types) to `internal`

**Files:**
- Modify: `Sources/SwiflowColor/Color.swift`
- Modify: `Tests/SwiflowUITests/ContrastColorTests.swift`, `Tests/SwiflowUITests/ThemeContrastTests.swift`

- [ ] **Step 1: Switch the two SwiflowUITests files to `@testable`**

In both `Tests/SwiflowUITests/ContrastColorTests.swift` and `Tests/SwiflowUITests/ThemeContrastTests.swift`, change:
```swift
import SwiflowColor
```
to:
```swift
@testable import SwiflowColor
```
(They reach `Color.*` / `LinRGB` etc., which become internal in Step 2.) If either file references `Color.PaletteError` or `Color.PaletteFailure`, change `Color.PaletteFailure` → `PaletteFailure` and drop/relocate any `Color.PaletteError` use (it no longer exists; those were already removed in Task 1). Grep both files: `grep -n "Color.PaletteError\|Color.PaletteFailure" Tests/SwiflowUITests/`.

- [ ] **Step 2: Demote `Color` and the color-space types to `internal`**

In `Sources/SwiflowColor/Color.swift`:
- `public enum Color {` → `enum Color {`
- `public struct LinRGB` → `struct LinRGB`; `public struct OKLab` → `struct OKLab`; `public struct OKLCH` → `struct OKLCH` (and `public var`/`public let`/`public static`/`public init` inside them → drop `public`).
- Remove `public` from every `static func`/`static let`/`typealias` member of `Color` (`hex`, `wcagContrast`, `apcaContrast`, `linRGBToOKLab`, `okLabToLinRGB`, `okLabToOKLCH`, `mixOKLab`, `oklchFrom`, `contrastColor`, `hexString`, `darkAccent`, `p3OKLCHString`, `accentThemeCSS`, `validateAccentFamily`, `validateStatusFamily`, `validateNeutrals`, `neutralPalette`, `neutralContrastMore`, `TokenPair`, etc.). `normalizeHex` is already internal.

Quick way to find them: `grep -n "public " Sources/SwiflowColor/Color.swift` — every hit in this file should become non-`public` (the only `public` types now live in `PaletteFailure.swift`/`ThemeGenerator.swift`/`Contrast.swift`).

- [ ] **Step 3: Build + run the full suite green**

Run: `swift build && swift test`
Expected: PASS — `Contrast`/`ThemeGenerator` still reach `Color.*` (same module); `SwiflowColorTests` + the two `@testable` `SwiflowUITests` files reach internals; `SwiflowCLI` only touches the public facade.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor(swiflowcolor): internalize Color math; curate the public surface

enum Color and all color-space/contrast/generation internals drop to internal;
the only public API is ThemeGenerator/ThemeOptions/ThemeResult, Contrast, and
PaletteFailure/ThemeError. SwiflowUITests switched to @testable.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Ship the `.library` product + public-API tests

**Files:**
- Modify: `Package.swift`
- Create: `Tests/SwiflowColorTests/PublicAPITests.swift`

- [ ] **Step 1: Write the public-API test (plain import — the shipped-surface proof)**

Create `Tests/SwiflowColorTests/PublicAPITests.swift` (NOTE: **plain** `import`, no `@testable` — this verifies the curated surface is sufficient):

```swift
import Testing
import Foundation
import SwiflowColor   // plain — exercises ONLY the public API

@Suite("PublicAPI")
struct PublicAPITests {
    @Test("generate returns valid CSS for a good seed") func goodSeed() throws {
        let r = try ThemeGenerator.generate(.init(primary: "#3b82f6"))
        #expect(r.isValid)
        #expect(r.failures.isEmpty)
        #expect(r.css.contains("--sw-accent: light-dark(#3b82f6, #"))
    }

    @Test("generate returns failures (not a throw) for a washed-out seed") func failingSeed() throws {
        let r = try ThemeGenerator.generate(.init(primary: "#3b82f6", danger: "#f1a9a9"))
        #expect(!r.isValid)
        #expect(r.failures.contains { $0.token == "--sw-danger" })
        // advisory APCA reading rides along on each failure
        #expect(r.failures.allSatisfy { $0.apcaTarget == 75 || $0.apcaTarget == 45 })
    }

    @Test("generate throws invalidHex on malformed input") func invalidHex() {
        #expect(throws: ThemeError.self) {
            _ = try ThemeGenerator.generate(.init(primary: "#nope"))
        }
    }

    @Test("Contrast metrics work from hex") func contrastMetrics() throws {
        #expect(abs(try Contrast.wcag("#000000", "#ffffff") - 21.0) < 0.1)
        #expect(abs(try Contrast.apca(textHex: "#000000", bgHex: "#ffffff") - 106.04) < 0.1)
        #expect(throws: ThemeError.self) { _ = try Contrast.wcag("zzz", "#fff") }
    }
}
```

- [ ] **Step 2: Run the public-API test**

Run: `swift test --filter PublicAPITests`
Expected: PASS (the test target already depends on the `SwiflowColor` target, so plain `import` resolves even before the `.library` product exists). This test's value is regression-locking the public surface: because it uses **plain** `import` (no `@testable`), it fails to *compile* if any symbol it touches isn't `public` — proving the curation in Task 4 is correct.

- [ ] **Step 3: Add the `.library` product**

In `Package.swift`, in the `products:` array (after the other `.library` lines, before `.executable`), add:
```swift
        .library(name: "SwiflowColor", targets: ["SwiflowColor"]),
```

- [ ] **Step 4: Verify the package resolves and builds**

Run: `swift build && swift test`
Expected: PASS — the new product builds; full suite green.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Tests/SwiflowColorTests/PublicAPITests.swift
git commit -m "feat(swiflowcolor): ship SwiflowColor as a public .library product

Adds the .library product + public-API tests (plain import) that lock the curated
surface: ThemeGenerator.generate, Contrast.wcag/apca, PaletteFailure, ThemeError.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Docs + roadmap

**Files:**
- Create: `docs/guides/swiflowcolor.md`
- Modify: `docs/guides/swiflowui-theming.md` (cross-link)
- Modify: `docs/future-work/swiflowui-1.0-roadmap.md`

- [ ] **Step 1: Write the library guide**

Create `docs/guides/swiflowcolor.md`:

```markdown
# SwiflowColor — programmatic theme generation

`SwiflowColor` is the contrast-validated color library behind `swiflow theme`. It is a
**native-only** Swift library (macOS/Linux host tooling, build plugins, design scripts) — it is
NOT for the browser and is never a dependency of the wasm `SwiflowUI` module.

Add it to a host tool/target:

```swift
.product(name: "SwiflowColor", package: "Swiflow")
```

## Generating a theme

```swift
import SwiflowColor

let result = try ThemeGenerator.generate(
    .init(primary: "#7c3aed", danger: "#e11d48", includeNeutrals: true)
)

if result.isValid {
    try result.css.write(toFile: "theme.css", atomically: true, encoding: .utf8)
} else {
    for failure in result.failures { print(failure) }   // WCAG + advisory APCA per token
}
```

`generate(_:)` throws `ThemeError.invalidHex` only for malformed hex. Contrast shortfalls are
**returned** in `result.failures` (each carries the WCAG ratio + an advisory APCA Lc), never
thrown — the caller decides whether to treat them as fatal (the `swiflow theme` CLI does).

`ThemeOptions` mirrors the CLI flags: `primary` (required), optional `danger`/`success`/
`warning`/`info` status seeds, and `includeNeutrals`.

## Contrast metrics

```swift
let ratio = try Contrast.wcag("#1d4ed8", "#ffffff")        // WCAG 2.x ratio (1…21)
let lc = try Contrast.apca(textHex: "#1d4ed8", bgHex: "#ffffff")  // APCA Lc (advisory)
```

Both validate hex and throw `ThemeError.invalidHex` on malformed input.
```

- [ ] **Step 2: Cross-link from the theming guide**

In `docs/guides/swiflowui-theming.md`, in the "Generating a theme from brand colors" section, add a line:

```markdown
The generator is also a public Swift library — see [SwiflowColor](swiflowcolor.md) to call
`ThemeGenerator.generate` from your own host tooling instead of the CLI.
```

- [ ] **Step 3: Mark the deferral shipped in the roadmap**

In `docs/future-work/swiflowui-1.0-roadmap.md`, update the M8 deferral line (currently noting APCA shipped + SwiflowColor public deferred):

```markdown
**Deferred from M8 to a later pass:** ~~APCA as an opt-in algorithm~~ — **shipped** as an advisory
APCA-W3 reading in failed-seed diagnostics (WCAG 2.x stays the gate); promoting `SwiflowColor` into
a public (shipping) generator remains deferred.
```
Replace with:
```markdown
**M8 fully shipped.** ~~APCA as an opt-in algorithm~~ — shipped as an advisory APCA-W3 reading in
failed-seed diagnostics. ~~promoting `SwiflowColor` into a public (shipping) generator~~ — shipped:
`SwiflowColor` is now a public `.library` product (`ThemeGenerator.generate`, `Contrast.wcag/apca`);
see [`docs/guides/swiflowcolor.md`](../guides/swiflowcolor.md).
```

- [ ] **Step 4: Verify + commit**

Run: `swift build && swift test`
Expected: green (docs-only change).

```bash
git add docs/guides/swiflowcolor.md docs/guides/swiflowui-theming.md docs/future-work/swiflowui-1.0-roadmap.md
git commit -m "docs(swiflowcolor): public library guide; mark M8 fully shipped

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final review (after all tasks)

Dispatch a code-review subagent over `git diff origin/main...HEAD`. Verify: the only `public` symbols in `Sources/SwiflowColor/` are `ThemeOptions`/`ThemeResult`/`ThemeGenerator`, `Contrast`, `PaletteFailure`, `ThemeError` (grep `public ` across the four files); `enum Color` and all math are `internal`; the `.library` product is declared; `swiflow theme` output is byte-identical (the smoke from Task 3 Step 5); and `SwiflowColor` is NOT added to any wasm/SwiflowUI target dependency. Then confirm `swift test` is fully green.
```
