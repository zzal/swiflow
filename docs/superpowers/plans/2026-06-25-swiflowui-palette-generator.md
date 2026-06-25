# SwiflowUI Palette Generator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A build-time `swiflow theme --primary "#hex"` that emits a contrast-validated `--sw-accent` override, plus making the accent family derive from `--sw-accent` so one token re-skins it all.

**Architecture:** (P1) `baseStyleSheet`'s `--sw-accent-hover`/`-active` become `oklch(from var(--sw-accent) …)` derivations. (P2) the M8 color pipeline moves from the test target into a new **native-only `SwiflowColor`** library; a new `swiflow theme` CLI command derives the dark-mode accent from the light seed, validates the whole family against WCAG (failing the build on a bad color), and emits the override CSS. `SwiflowColor` is depended on by `SwiflowCLI` and the test targets — never by the wasm `SwiflowUI` library, so no color math ships in wasm.

**Tech Stack:** Swift 6 (language mode v6), Swift Testing (`import Testing`/`@Suite`/`@Test`/`#expect`), swift-argument-parser, Foundation. CSS: `light-dark()`, `oklch(from … calc(l ±) c h)`, `contrast-color()` (all Baseline).

**Spec:** [`docs/superpowers/specs/2026-06-25-swiflowui-palette-generator-design.md`](../specs/2026-06-25-swiflowui-palette-generator-design.md)

---

## File Structure

| File | Responsibility | Ships in wasm? |
|------|----------------|----------------|
| `Sources/SwiflowUI/Theme.swift` | P1: hover/active derive from `--sw-accent` | yes (CSS only) |
| `Sources/SwiflowColor/ContrastColor.swift` | the color pipeline (moved from tests, made `public`) + `darkAccent`/validation/generator | **no** (native-only lib) |
| `Sources/SwiflowCLI/Commands/ThemeCommand.swift` | the `swiflow theme` command | no (CLI) |
| `Sources/SwiflowCLI/Swiflow.swift` | register the subcommand | no |
| `Package.swift` | add `SwiflowColor` + `SwiflowColorTests` targets; wire deps | n/a |
| `Tests/SwiflowColorTests/*` | unit tests for `darkAccent`/validation/generator | no |
| `Tests/SwiflowUITests/*` | M8 proofs — re-pointed to `import SwiflowColor` | no |

**Swift Testing filter gotcha (this repo):** `swift test --filter` matches **type identifiers**, not `@Suite("display name")`. Filter on the struct name (e.g. `--filter ThemeContrastTests`, `--filter SwiflowColorTests`) and confirm runs report a non-zero test count — never trust a `0 tests in 0 suites` "pass".

---

### Task 1: P1 — accent hover/active derive from `--sw-accent`

**Files:**
- Modify: `Sources/SwiflowUI/Theme.swift` (the `--sw-accent-hover`/`-active` declarations)
- Modify: `Tests/SwiflowUITests/ThemeTests.swift` (add one `@Test`)

- [ ] **Step 1: Write the failing test** — Add inside `struct ThemeTests` (before its closing brace):

```swift
    @Test("Accent hover/active derive from --sw-accent with a calc lightness step")
    func accentRampDerivesFromAccent() {
        let css = sheet
        for token in ["--sw-accent-hover", "--sw-accent-active"] {
            #expect(css.contains("\(token): light-dark(#"), "\(token) missing literal fallback")
        }
        #expect(css.contains("--sw-accent-hover: light-dark(oklch(from var(--sw-accent) calc(l - 0.08) c h)"),
                "hover missing derived layer")
        #expect(css.contains("--sw-accent-active: light-dark(oklch(from var(--sw-accent) calc(l - 0.16) c h)"),
                "active missing derived layer")
    }
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter ThemeTests`. Expected: the new test FAILS (no `oklch(from …)` on hover/active yet).

- [ ] **Step 3: Implement** — In `Theme.swift`, find:

```
          --sw-accent-hover: light-dark(#2563eb, #7cb0fb);
          --sw-accent-active: light-dark(#1d4ed8, #93c1fc);
```

and replace with:

```
          /* hover/active derive from --sw-accent (darken in light, lighten in dark) so
             re-pointing --sw-accent cascades the whole accent family. Literal fallback
             first for pre-oklch(from) browsers. */
          --sw-accent-hover: light-dark(#2563eb, #7cb0fb);
          --sw-accent-hover: light-dark(oklch(from var(--sw-accent) calc(l - 0.08) c h), oklch(from var(--sw-accent) calc(l + 0.08) c h));
          --sw-accent-active: light-dark(#1d4ed8, #93c1fc);
          --sw-accent-active: light-dark(oklch(from var(--sw-accent) calc(l - 0.16) c h), oklch(from var(--sw-accent) calc(l + 0.16) c h));
```

- [ ] **Step 4: Run to verify it passes** — `swift test --filter ThemeTests`. Expected: PASS (the new test + all existing `ThemeTests`). The `forwardContractTokens`/`bracesBalanced` tests must stay green.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowUI/Theme.swift Tests/SwiflowUITests/ThemeTests.swift
git commit -m "feat(swiflowui): accent hover/active derive from --sw-accent"
```

---

### Task 2: Promote the color pipeline into a native-only `SwiflowColor` library

**Files:**
- Move: `Tests/SwiflowUITests/Support/ContrastColor.swift` → `Sources/SwiflowColor/ContrastColor.swift`
- Modify: `Package.swift` (add the `SwiflowColor` target; add it to `SwiflowUITests` deps)
- Modify: `Tests/SwiflowUITests/ContrastColorTests.swift` and `Tests/SwiflowUITests/ThemeContrastTests.swift` (add `import SwiflowColor`)

- [ ] **Step 1: Move the file**
```bash
mkdir -p Sources/SwiflowColor
git mv Tests/SwiflowUITests/Support/ContrastColor.swift Sources/SwiflowColor/ContrastColor.swift
```

- [ ] **Step 2: Make the used API `public`** — In `Sources/SwiflowColor/ContrastColor.swift`, add `public` to exactly these declarations (leave `gammaToLinear`, `clampGamut`, `okLCHToOKLab` internal — they're only used inside the module):

- `struct LinRGB` → `public struct LinRGB`; its `var r, g, b` → `public var r, g, b`; `var luminance` → `public var luminance`; `static let black`/`white` → `public static let …`
- `struct OKLab` → `public struct OKLab`; its members → `public var L, a, b`
- `struct OKLCH` → `public struct OKLCH`; its members → `public var L, C, H`
- `enum Color` → `public enum Color`
- `static func hex`, `wcagContrast`, `linRGBToOKLab`, `okLabToLinRGB`, `okLabToOKLCH`, `mixOKLab`, `oklchFrom`, `contrastColor` → prefix each with `public`

- [ ] **Step 3: Add the target + dependency in `Package.swift`** — Add this target to the `targets:` array (place it right before the `SwiflowUI` target):

```swift
        // Native-only color pipeline (OKLab/OKLCH, WCAG, color-mix, oklch-from,
        // contrast-color) + the accent palette generator. Used by SwiflowCLI's
        // `theme` command and by SwiflowUI's contrast tests. NEVER a dependency
        // of the wasm SwiflowUI library — no color math ships in a wasm bundle.
        .target(
            name: "SwiflowColor",
            path: "Sources/SwiflowColor",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
```

And add `"SwiflowColor"` to the `SwiflowUITests` test target's `dependencies` (which is currently `["SwiflowUI", "Swiflow"]` → `["SwiflowUI", "Swiflow", "SwiflowColor"]`).

- [ ] **Step 4: Re-point the test imports** — At the top of BOTH `Tests/SwiflowUITests/ContrastColorTests.swift` and `Tests/SwiflowUITests/ThemeContrastTests.swift`, add the import line (alongside the existing `import Testing` / `@testable import SwiflowUI`):

```swift
import SwiflowColor
```

(`ContrastColorTests.swift` keeps `@testable import SwiflowUI` too — its `CSSValueParsingTests` suite reads the sheet. `CSSValueParsing.swift` is unchanged and stays in the test target.)

- [ ] **Step 5: Verify the M8 proofs still pass through the moved module**

Run: `swift test --filter "ContrastColor|ThemeContrast|CSSValueParsing"`
Expected: PASS — the 23 M8 tests, now compiling `Color`/`LinRGB` from `SwiflowColor`. If a "cannot find 'Color' in scope" appears, a `public` annotation from Step 2 was missed or the import wasn't added. If a stale-cache error appears, `swift package clean` and retry.

- [ ] **Step 6: Commit**
```bash
git add Package.swift Sources/SwiflowColor/ContrastColor.swift Tests/SwiflowUITests/ContrastColorTests.swift Tests/SwiflowUITests/ThemeContrastTests.swift
git commit -m "refactor(swiflowui): promote color pipeline into native-only SwiflowColor lib"
```

---

### Task 3: `darkAccent(from:)` + hex output in `SwiflowColor`

**Files:**
- Modify: `Sources/SwiflowColor/ContrastColor.swift` (append)
- Create: `Tests/SwiflowColorTests/DarkAccentTests.swift`
- Modify: `Package.swift` (add the `SwiflowColorTests` target)

- [ ] **Step 1: Add the test target in `Package.swift`** — Add to `targets:` (after the `SwiflowColor` target):

```swift
        .testTarget(
            name: "SwiflowColorTests",
            dependencies: ["SwiflowColor"],
            path: "Tests/SwiflowColorTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
```

- [ ] **Step 2: Write the failing test** — Create `Tests/SwiflowColorTests/DarkAccentTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiflowColor

@Suite("DarkAccent")
struct DarkAccentTests {
    @Test("darkAccent lightens and slightly desaturates the seed, preserving hue")
    func derivesLighterDarkArm() {
        let seed = "#3b82f6"
        let darkHex = Color.darkAccent(from: seed)
        let seedLCH = Color.okLabToOKLCH(Color.linRGBToOKLab(Color.hex(seed)))
        let darkLCH = Color.okLabToOKLCH(Color.linRGBToOKLab(Color.hex(darkHex)))
        // Lighter (clamped into the dark-mode band), less chroma, same hue.
        #expect(darkLCH.L > seedLCH.L)
        #expect(darkLCH.L >= 0.68 && darkLCH.L <= 0.76)
        #expect(darkLCH.C < seedLCH.C)
        #expect(abs(darkLCH.H - seedLCH.H) < 0.02)
        // Higher luminance than the seed (reads on a dark surface).
        #expect(Color.hex(darkHex).luminance > Color.hex(seed).luminance)
    }

    @Test("darkAccent returns a well-formed #rrggbb")
    func wellFormedHex() {
        let h = Color.darkAccent(from: "#7c3aed")
        #expect(h.count == 7 && h.hasPrefix("#"))
        #expect(h.dropFirst().allSatisfy { "0123456789abcdef".contains($0) })
    }
}
```

- [ ] **Step 3: Run to verify it fails** — `swift test --filter DarkAccentTests`. Expected: FAIL — `darkAccent` / `hexString` undefined.

- [ ] **Step 4: Implement** — Append to `Sources/SwiflowColor/ContrastColor.swift`:

```swift
extension Color {
    /// Linear channel → sRGB gamma-encoded (inverse of `gammaToLinear`).
    static func linearToGamma(_ c: Double) -> Double {
        c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055
    }
    /// Linear-light sRGB → "#rrggbb" (gamut-clamped, 8-bit).
    public static func hexString(_ c: LinRGB) -> String {
        func channel(_ v: Double) -> Int { Int((min(max(linearToGamma(v), 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", channel(c.r), channel(c.g), channel(c.b))
    }
    /// Derive a dark-mode accent from a light-mode seed: raise OKLCH lightness into the
    /// dark-mode band and modestly reduce chroma, preserving hue. Roughly reproduces the
    /// shipped #3b82f6 → #60a5fa pairing. Constants tunable; validation is the safety net.
    public static func darkAccent(from hex: String) -> String {
        let lch = okLabToOKLCH(linRGBToOKLab(Color.hex(hex)))
        let darkL = min(max(lch.L + 0.10, 0.68), 0.76)
        let darkC = lch.C * 0.78
        let lin = clampGamut(okLabToLinRGB(okLCHToOKLab(OKLCH(L: darkL, C: darkC, H: lch.H))))
        return hexString(lin)
    }
}
```

- [ ] **Step 5: Run to verify it passes** — `swift test --filter DarkAccentTests`. Expected: PASS (2 tests).

- [ ] **Step 6: Commit**
```bash
git add Package.swift Sources/SwiflowColor/ContrastColor.swift Tests/SwiflowColorTests/DarkAccentTests.swift
git commit -m "feat(swiflowcolor): darkAccent(from:) + hexString"
```

---

### Task 4: Family validation + the `accentThemeCSS` generator

**Files:**
- Modify: `Sources/SwiflowColor/ContrastColor.swift` (append)
- Create: `Tests/SwiflowColorTests/AccentThemeTests.swift`

- [ ] **Step 1: Write the failing test** — Create `Tests/SwiflowColorTests/AccentThemeTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiflowColor

@Suite("AccentTheme")
struct AccentThemeTests {
    @Test("A good brand color validates clean and emits a light-dark --sw-accent")
    func goodSeedEmitsCSS() throws {
        let css = try Color.accentThemeCSS(primaryHex: "#3b82f6")
        #expect(css.contains("--sw-accent: light-dark(#3b82f6, #"))
        #expect(css.contains(":root"))
    }

    @Test("3-digit hex and missing # are normalized")
    func normalizesHex() throws {
        let css = try Color.accentThemeCSS(primaryHex: "3b82f6")
        #expect(css.contains("--sw-accent: light-dark(#3b82f6,"))
    }

    @Test("A washed-out seed fails validation with a specific diagnostic")
    func badSeedThrows() {
        // A light yellow: ~1.07:1 as accent text/links on white — below the 3:1 UI bar.
        #expect(throws: Color.PaletteError.self) {
            _ = try Color.accentThemeCSS(primaryHex: "#fde047")
        }
    }

    @Test("Invalid hex throws invalidHex")
    func invalidHexThrows() {
        #expect(throws: Color.PaletteError.self) {
            _ = try Color.accentThemeCSS(primaryHex: "nope")
        }
    }

    @Test("validateAccentFamily returns failures naming token + mode")
    func validationNamesFailures() {
        let fails = Color.validateAccentFamily(lightAccentHex: "#fde047",
                                               darkAccentHex: Color.darkAccent(from: "#fde047"))
        #expect(!fails.isEmpty)
        #expect(fails.contains { $0.token.contains("as text") })
        #expect(fails.allSatisfy { !$0.token.isEmpty && $0.ratio < $0.target })
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter AccentThemeTests`. Expected: FAIL — `accentThemeCSS`, `validateAccentFamily`, `PaletteError`, `PaletteFailure` undefined.

- [ ] **Step 3: Implement** — Append to `Sources/SwiflowColor/ContrastColor.swift`:

```swift
extension Color {
    /// One WCAG shortfall for a generated token, in one color scheme.
    public struct PaletteFailure: Equatable, CustomStringConvertible {
        public let token: String
        public let mode: String        // "light" | "dark"
        public let ratio: Double
        public let target: Double
        public var description: String {
            String(format: "%@ (%@): %.2f:1 < %.1f:1 required", token, mode, ratio, target)
        }
    }

    public enum PaletteError: Error, CustomStringConvertible {
        case invalidHex(String)
        case contrastFailures([PaletteFailure])
        public var description: String {
            switch self {
            case .invalidHex(let s):
                return "invalid --primary hex: \(s) (expected #rgb or #rrggbb)"
            case .contrastFailures(let fs):
                return "brand color fails WCAG for the derived accent family:\n  "
                    + fs.map(\.description).joined(separator: "\n  ")
            }
        }
    }

    /// Validate "#rgb"/"#rrggbb" and normalize to lowercase "#rrggbb".
    static func normalizeHex(_ raw: String) throws -> String {
        let h = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        let ok = h.allSatisfy { "0123456789abcdefABCDEF".contains($0) }
        guard ok, h.count == 3 || h.count == 6 else { throw PaletteError.invalidHex(raw) }
        let full = h.count == 3 ? h.map { "\($0)\($0)" }.joined() : h
        return "#" + full.lowercased()
    }

    // The shipped contract these tokens must satisfy (mirrors Theme.swift):
    private static let surfaceLight = "#ffffff", surfaceDark = "#1a1a1a"
    private static let tintWeight = 0.15
    // -strong lightnesses: (normal 4.5 → light/dark), (more-contrast 7 → light/dark)
    private static let strongAA: (Double, Double) = (0.40, 0.80)
    private static let strongAAA: (Double, Double) = (0.30, 0.88)
    private static let textFallbackDark = "#0b1220"

    /// Recompute the accent-derived tokens (-strong at 4.5 + 7, -text) for the given
    /// light/dark accents and return every WCAG shortfall.
    public static func validateAccentFamily(lightAccentHex: String, darkAccentHex: String) -> [PaletteFailure] {
        var out: [PaletteFailure] = []
        let modes: [(String, String, String, Double, Double)] = [
            // mode, accentHex, surfaceHex, strongL(AA), strongL(AAA)
            ("light", lightAccentHex, surfaceLight, strongAA.0, strongAAA.0),
            ("dark",  darkAccentHex,  surfaceDark,  strongAA.1, strongAAA.1),
        ]
        for (mode, accentHex, surfaceHex, lAA, lAAA) in modes {
            let accent = hex(accentHex)
            let tint = mixOKLab(accent, hex(surfaceHex), weightBase: tintWeight)
            // --sw-accent used as TEXT (ghost buttons, links) on the surface. UI/large-text
            // bar (3:1): catches washed-out brand colors while allowing conventional
            // blue-on-white links (the default #3b82f6 is 3.68:1).
            let rAccentText = wcagContrast(accent, hex(surfaceHex))
            if rAccentText < 3.0 { out.append(.init(token: "--sw-accent (as text/links)", mode: mode, ratio: rAccentText, target: 3.0)) }
            // -strong on the tint: 4.5 normal, 7 under prefers-contrast: more.
            let rAA = wcagContrast(oklchFrom(accent, lightness: lAA), tint)
            if rAA < 4.5 { out.append(.init(token: "--sw-accent-strong", mode: mode, ratio: rAA, target: 4.5)) }
            let rAAA = wcagContrast(oklchFrom(accent, lightness: lAAA), tint)
            if rAAA < 7.0 { out.append(.init(token: "--sw-accent-strong (more-contrast)", mode: mode, ratio: rAAA, target: 7.0)) }
            // -text on the solid accent: contrast-color result AND the dark fallback.
            let rText = wcagContrast(contrastColor(against: accent), accent)
            if rText < 4.5 { out.append(.init(token: "--sw-accent-text", mode: mode, ratio: rText, target: 4.5)) }
            let rFallback = wcagContrast(hex(textFallbackDark), accent)
            if rFallback < 4.5 { out.append(.init(token: "--sw-accent-text fallback", mode: mode, ratio: rFallback, target: 4.5)) }
        }
        return out
    }

    /// Full generator: normalize the seed, derive the dark accent, validate the family,
    /// and return the override CSS. Throws `PaletteError` on a bad hex or any shortfall.
    public static func accentThemeCSS(primaryHex: String) throws -> String {
        let light = try normalizeHex(primaryHex)
        let dark = darkAccent(from: light)
        let failures = validateAccentFamily(lightAccentHex: light, darkAccentHex: dark)
        guard failures.isEmpty else { throw PaletteError.contrastFailures(failures) }
        return """
        /* Generated by `swiflow theme --primary \(light)`. Include after SwiflowUI's styles.
           Re-points --sw-accent; hover/active/text/strong derive from it automatically. */
        :root {
          --sw-accent: light-dark(\(light), \(dark));
        }
        """
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test --filter AccentThemeTests`. Expected: PASS (5 tests). `#fde047` fails the `--sw-accent (as text/links)` 3:1 check (~1.07:1 on white); `#3b82f6` passes (3.68:1 ≥ 3.0). The robust `-strong`/`-text` checks rarely trip — the accent-as-text check is the one that catches washed-out brand colors.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowColor/ContrastColor.swift Tests/SwiflowColorTests/AccentThemeTests.swift
git commit -m "feat(swiflowcolor): accent family WCAG validation + accentThemeCSS generator"
```

---

### Task 5: The `swiflow theme` command

**Files:**
- Create: `Sources/SwiflowCLI/Commands/ThemeCommand.swift`
- Modify: `Sources/SwiflowCLI/Swiflow.swift` (register the subcommand)
- Modify: `Package.swift` (`SwiflowCLI` depends on `SwiflowColor`)
- Create: `Tests/SwiflowCLITests/ThemeCommandTests.swift`

- [ ] **Step 1: Add the dependency in `Package.swift`** — In the `SwiflowCLI` executable target's `dependencies`, add `"SwiflowColor"` (alongside the existing `ArgumentParser`/`Hummingbird`/`Crypto` products).

- [ ] **Step 2: Write the failing test** — Create `Tests/SwiflowCLITests/ThemeCommandTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiflowCLI

@Suite("ThemeCommand")
struct ThemeCommandTests {
    @Test("--primary with a good color writes the override to --out and exits zero")
    func writesFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sw-theme-\(UUID().uuidString).css")
        defer { try? FileManager.default.removeItem(at: tmp) }
        var cmd = try ThemeCommand.parse(["--primary", "#3b82f6", "--out", tmp.path])
        try cmd.run()
        let css = try String(contentsOf: tmp, encoding: .utf8)
        #expect(css.contains("--sw-accent: light-dark(#3b82f6, #"))
    }

    @Test("a washed-out --primary makes run() throw (nonzero exit)")
    func badColorThrows() throws {
        var cmd = try ThemeCommand.parse(["--primary", "#fde047"])
        #expect(throws: (any Error).self) { try cmd.run() }
    }

    @Test("missing --primary is a parse error")
    func missingPrimary() {
        #expect(throws: (any Error).self) { _ = try ThemeCommand.parse([]) }
    }
}
```

- [ ] **Step 3: Run to verify it fails** — `swift test --filter ThemeCommandTests`. Expected: FAIL — `ThemeCommand` undefined.

- [ ] **Step 4: Implement the command** — Create `Sources/SwiflowCLI/Commands/ThemeCommand.swift`:

```swift
// Sources/SwiflowCLI/Commands/ThemeCommand.swift
//
// `swiflow theme --primary "#hex"` — derive a contrast-validated --sw-accent
// override from a brand color and emit it (stdout, or --out file). The whole
// accent family (hover/active/text/strong) derives from --sw-accent in
// SwiflowUI's base stylesheet, so the override re-points one token.

import ArgumentParser
import Foundation
import SwiflowColor

struct ThemeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "theme",
        abstract: "Generate a contrast-validated --sw-accent override from a brand color."
    )

    @Option(name: .customLong("primary"),
            help: "Brand color (light-mode accent), as #rgb or #rrggbb.")
    var primary: String

    @Option(name: .customLong("out"),
            help: "Write the CSS to this file. Defaults to stdout.")
    var out: String?

    func run() throws {
        let css = try Color.accentThemeCSS(primaryHex: primary)
        if let out {
            try css.write(toFile: out, atomically: true, encoding: .utf8)
        } else {
            print(css)
        }
    }
}
```

- [ ] **Step 5: Register the subcommand** — In `Sources/SwiflowCLI/Swiflow.swift`, add `ThemeCommand.self` to the `subcommands:` array:

```swift
        subcommands: [InitCommand.self, BuildCommand.self, DevCommand.self, DoctorCommand.self, ThemeCommand.self],
```

- [ ] **Step 6: Run to verify it passes** — `swift test --filter ThemeCommandTests`. Expected: PASS (3 tests). (`ArgumentParser`'s `run()` rethrows `PaletteError`, which the binary surfaces as a nonzero exit with the diagnostic — the test asserts the throw.)

- [ ] **Step 7: Commit**
```bash
git add Package.swift Sources/SwiflowCLI/Commands/ThemeCommand.swift Sources/SwiflowCLI/Swiflow.swift Tests/SwiflowCLITests/ThemeCommandTests.swift
git commit -m "feat(cli): swiflow theme — contrast-validated accent palette generator"
```

---

## Final verification (after all tasks)

- [ ] Full suite: `swift test` → all green (incl. the migrated M8 proofs and the new `SwiflowColor`/CLI tests).
- [ ] No color math in wasm: `SwiflowColor` is absent from `SwiflowUI`'s dependency closure — confirm `SwiflowUI`'s target in `Package.swift` does **not** list `SwiflowColor`.
- [ ] End-to-end the CLI: `swift build -c release --product swiflow && .build/release/swiflow theme --primary "#7c3aed"` prints a `:root { --sw-accent: light-dark(#7c3aed, #…); }` block; `… theme --primary "#fde047"` prints a WCAG diagnostic and exits nonzero (`echo $?` → 1).
- [ ] Eyeball P1: `.build/release/swiflow build --path examples/SwiflowUIDemo` then serve — default button hover/active still look right (subtle shift acceptable); pipe a generated theme into the demo's `<head>` to confirm a one-token re-skin cascades. (CI skips example builds — do this locally; revert the demo's stamped `swiflow-service-worker.js`/driver afterward, don't commit them.)
- [ ] Dispatch the final whole-branch code reviewer.

## Notes for the implementer

- **`SwiflowColor` is host/native only** — no `JavaScriptKit`, no `#if canImport`. It builds for the macOS host and is used by the CLI + tests. It must never enter `SwiflowUI`'s deps.
- **Don't re-tune the M8 contract by accident.** The `strongAA`/`strongAAA`/surface/tint constants in `validateAccentFamily` mirror the values shipped in `Theme.swift` (PR #66). If `Theme.swift`'s `-strong` lightnesses ever change, update these in lockstep (they're the generator's copy of the contract).
- **`Color` is a generic name** but namespaced by the `SwiflowColor` module; the CLI and tests qualify it as `Color.…` after `import SwiflowColor`. No SwiftUI in these targets, so no collision.
- **The dark-accent constants** (`+0.10`, `0.68…0.76`, `×0.78`) are tunable; `validateAccentFamily` is the guardrail, so a tweak that breaks contrast fails a test loudly.
