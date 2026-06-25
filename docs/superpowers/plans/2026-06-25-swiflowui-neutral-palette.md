# SwiflowUI Neutral / Full-Palette Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `swiflow theme` with an opt-in `--neutrals` that derives the six neutral tokens, tinted toward the accent hue and contrast-proven, with a `prefers-contrast: more` layer.

**Architecture:** New `SwiflowColor` functions derive a low-chroma OKLCH neutral ramp at fixed lightness targets using the accent's hue, emit it as hex, and validate readable text on every surface. `accentThemeCSS` gains an `includeNeutrals` parameter that appends the neutral `:root` declarations + a `prefers-contrast: more` block; `ThemeCommand` gains a `--neutrals` flag. All native-only (CLI + tests); no wasm color math; accent-only output is unchanged.

**Tech Stack:** Swift 6 (language mode v6), Swift Testing, swift-argument-parser. `SwiflowColor`'s existing OKLCH pipeline (`Color.hex`/`okLabToOKLCH`/`linRGBToOKLab`/`wcagContrast`/`hexString`, internal `okLCHToOKLab`/`okLabToLinRGB`/`clampGamut`, `OKLCH`, `PaletteFailure`, `PaletteError`, `normalizeHex`, `darkAccent`, `validateAccentFamily`, `accentThemeCSS`).

**Spec:** [`docs/superpowers/specs/2026-06-25-swiflowui-neutral-palette-design.md`](../specs/2026-06-25-swiflowui-neutral-palette-design.md)

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Sources/SwiflowColor/ContrastColor.swift` (modify) | `TokenPair`, `neutralPalette`, `neutralContrastMore`, `validateNeutrals`, `accentThemeCSS(…, includeNeutrals:)` |
| `Tests/SwiflowColorTests/NeutralPaletteTests.swift` (new) | tests for the ramp + validation |
| `Tests/SwiflowColorTests/AccentThemeTests.swift` (modify) | tests for the `includeNeutrals` assembly |
| `Sources/SwiflowCLI/Commands/ThemeCommand.swift` (modify) | `--neutrals` flag |
| `Tests/SwiflowCLITests/ThemeCommandTests.swift` (modify) | CLI flag tests |

Filter gotcha: `swift test --filter` matches TYPE names — use `--filter NeutralPaletteTests` etc., never trust "0 tests in 0 suites".

---

### Task 1: `neutralPalette` + `neutralContrastMore` (the tinted ramp)

**Files:**
- Modify: `Sources/SwiflowColor/ContrastColor.swift` (append)
- Create: `Tests/SwiflowColorTests/NeutralPaletteTests.swift`

- [ ] **Step 1: Write the failing test** — Create `Tests/SwiflowColorTests/NeutralPaletteTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiflowColor

@Suite("NeutralPalette")
struct NeutralPaletteTests {
    @Test("Derives the six tokens in order, well-formed, with the right light/dark direction")
    func sixTokens() {
        let p = Color.neutralPalette(accentHex: "#7c3aed")
        #expect(p.map(\.name) == ["--sw-bg", "--sw-surface", "--sw-surface-2",
                                  "--sw-text", "--sw-text-muted", "--sw-border"])
        for t in p {
            for h in [t.light, t.dark] {
                #expect(h.count == 7 && h.hasPrefix("#"))
            }
        }
        let surface = p.first { $0.name == "--sw-surface" }!
        let text = p.first { $0.name == "--sw-text" }!
        #expect(Color.hex(surface.light).luminance > 0.8)   // light surface is bright
        #expect(Color.hex(text.light).luminance < 0.1)      // light-mode text is dark
        #expect(Color.hex(surface.dark).luminance < 0.1)    // dark surface is dark
        #expect(Color.hex(text.dark).luminance > 0.8)       // dark-mode text is bright
    }

    @Test("Neutrals carry an accent tint (a mid token is not pure gray)")
    func tinted() {
        let border = Color.neutralPalette(accentHex: "#7c3aed").first { $0.name == "--sw-border" }!
        let c = Color.hex(border.light)
        #expect(!(c.r == c.g && c.g == c.b))   // channels differ → tinted, not pure gray
    }

    @Test("neutralContrastMore overrides text/text-muted/border at higher contrast")
    func moreContrast() {
        let m = Color.neutralContrastMore(accentHex: "#7c3aed")
        #expect(m.map(\.name) == ["--sw-text", "--sw-text-muted", "--sw-border"])
        // more-contrast light text is darker than the base light text.
        let baseText = Color.neutralPalette(accentHex: "#7c3aed").first { $0.name == "--sw-text" }!
        let moreText = m.first { $0.name == "--sw-text" }!
        #expect(Color.hex(moreText.light).luminance <= Color.hex(baseText.light).luminance)
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter NeutralPaletteTests`. Expected: FAIL — `neutralPalette`/`neutralContrastMore`/`TokenPair` undefined.

- [ ] **Step 3: Implement** — Append to `Sources/SwiflowColor/ContrastColor.swift`:

```swift
extension Color {
    /// A derived token as `(name, lightHex, darkHex)`. Ordered arrays keep emitted CSS
    /// deterministic (a dict would not).
    public typealias TokenPair = (name: String, light: String, dark: String)

    // Faint accent cast — small enough to read as gray, large enough to survive 8-bit hex.
    private static let neutralTintChroma = 0.01
    // (token, L_light, L_dark) — lightness targets lifted from the shipped defaults; the muted
    // light target (0.46) is pinned so secondary text clears AA on the near-white page bg.
    private static let neutralRamp: [(String, Double, Double)] = [
        ("--sw-bg",         0.97, 0.15),
        ("--sw-surface",    1.00, 0.20),
        ("--sw-surface-2",  0.96, 0.24),
        ("--sw-text",       0.18, 0.96),
        ("--sw-text-muted", 0.46, 0.72),
        ("--sw-border",     0.92, 0.30),
    ]
    // prefers-contrast: more overrides (text/text-muted/border pushed toward the extremes).
    private static let neutralRampMore: [(String, Double, Double)] = [
        ("--sw-text",       0.10, 0.99),
        ("--sw-text-muted", 0.25, 0.90),
        ("--sw-border",     0.10, 0.99),
    ]

    /// OKLCH(L, C, H) → gamut-clamped "#rrggbb".
    private static func oklchHex(_ L: Double, _ C: Double, _ H: Double) -> String {
        hexString(clampGamut(okLabToLinRGB(okLCHToOKLab(OKLCH(L: L, C: C, H: H)))))
    }

    private static func ramp(_ rows: [(String, Double, Double)], accentHex: String) -> [TokenPair] {
        let hue = okLabToOKLCH(linRGBToOKLab(hex(accentHex))).H
        return rows.map { (name, ll, ld) in
            (name: name, light: oklchHex(ll, neutralTintChroma, hue), dark: oklchHex(ld, neutralTintChroma, hue))
        }
    }

    /// The six neutral tokens, tinted to the accent hue, as light/dark hex pairs (ordered).
    public static func neutralPalette(accentHex: String) -> [TokenPair] { ramp(neutralRamp, accentHex: accentHex) }

    /// The text/text-muted/border overrides for `@media (prefers-contrast: more)`.
    public static func neutralContrastMore(accentHex: String) -> [TokenPair] { ramp(neutralRampMore, accentHex: accentHex) }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test --filter NeutralPaletteTests`. Expected: PASS (3 tests). If `tinted` fails (channels equal), `neutralTintChroma` is too small for that lightness — nudge it up toward 0.014.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowColor/ContrastColor.swift Tests/SwiflowColorTests/NeutralPaletteTests.swift
git commit -m "feat(swiflowcolor): neutralPalette — accent-tinted OKLCH neutral ramp"
```

---

### Task 2: `validateNeutrals`

**Files:**
- Modify: `Sources/SwiflowColor/ContrastColor.swift` (append)
- Modify: `Tests/SwiflowColorTests/NeutralPaletteTests.swift` (append a suite)

- [ ] **Step 1: Write the failing test** — Append to `Tests/SwiflowColorTests/NeutralPaletteTests.swift`:

```swift
@Suite("ValidateNeutrals")
struct ValidateNeutralsTests {
    @Test("Default-derived neutrals clear AA for normal accents")
    func passesForNormalAccents() {
        for accent in ["#3b82f6", "#7c3aed", "#16a34a", "#dc2626"] {
            let fails = Color.validateNeutrals(Color.neutralPalette(accentHex: accent))
            #expect(fails.isEmpty, "neutrals for \(accent) should be AA, got \(fails)")
        }
    }

    @Test("Text too light against the surface fails with a per-mode diagnostic")
    func failsWhenTextTooLight() {
        // Contrived: light-mode text is near-white on a white surface → ~1:1.
        let bad: [Color.TokenPair] = [
            ("--sw-bg", "#ffffff", "#000000"),
            ("--sw-surface", "#ffffff", "#000000"),
            ("--sw-text", "#eeeeee", "#111111"),
            ("--sw-text-muted", "#dddddd", "#222222"),
        ]
        let fails = Color.validateNeutrals(bad)
        #expect(!fails.isEmpty)
        #expect(fails.contains { $0.token.contains("--sw-text") && $0.mode == "light" })
        #expect(fails.allSatisfy { $0.ratio < $0.target })
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter ValidateNeutralsTests`. Expected: FAIL — `validateNeutrals` undefined.

- [ ] **Step 3: Implement** — Append to `Sources/SwiflowColor/ContrastColor.swift`:

```swift
extension Color {
    /// WCAG check on a neutral palette: body and secondary text must clear 4.5 on both the
    /// card surface and the page background, in both schemes. (Border is intentionally not
    /// gated — see the spec.) Returns every shortfall.
    public static func validateNeutrals(_ palette: [TokenPair]) -> [PaletteFailure] {
        func find(_ n: String) -> (light: String, dark: String)? {
            palette.first { $0.name == n }.map { ($0.light, $0.dark) }
        }
        guard let surface = find("--sw-surface"), let bg = find("--sw-bg"),
              let text = find("--sw-text"), let muted = find("--sw-text-muted") else { return [] }
        var out: [PaletteFailure] = []
        let checks: [(String, (light: String, dark: String), (light: String, dark: String))] = [
            ("--sw-text on --sw-surface",       text,  surface),
            ("--sw-text on --sw-bg",            text,  bg),
            ("--sw-text-muted on --sw-surface", muted, surface),
            ("--sw-text-muted on --sw-bg",      muted, bg),
        ]
        for (label, fg, bgc) in checks {
            for (mode, f, b) in [("light", fg.light, bgc.light), ("dark", fg.dark, bgc.dark)] {
                let r = wcagContrast(hex(f), hex(b))
                if r < 4.5 { out.append(.init(token: label, mode: mode, ratio: r, target: 4.5)) }
            }
        }
        return out
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test --filter ValidateNeutralsTests`. Expected: PASS (2 tests). If `passesForNormalAccents` fails on a `--sw-text-muted on --sw-bg` shortfall, the muted light target is too light — lower `neutralRamp`'s `--sw-text-muted` light value (Task 1) from 0.46 toward 0.43 until all four accents pass, then re-run.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowColor/ContrastColor.swift Tests/SwiflowColorTests/NeutralPaletteTests.swift
git commit -m "feat(swiflowcolor): validateNeutrals — AA text-on-surface/bg guard"
```

---

### Task 3: `accentThemeCSS(…, includeNeutrals:)`

**Files:**
- Modify: `Sources/SwiflowColor/ContrastColor.swift` (replace `accentThemeCSS`)
- Modify: `Tests/SwiflowColorTests/AccentThemeTests.swift` (append tests)

- [ ] **Step 1: Write the failing test** — Append to `struct AccentThemeTests` in `Tests/SwiflowColorTests/AccentThemeTests.swift`:

```swift
    @Test("includeNeutrals: false is byte-for-byte the accent-only output (no neutral tokens)")
    func accentOnlyUnchanged() throws {
        let a = try Color.accentThemeCSS(primaryHex: "#3b82f6")
        let b = try Color.accentThemeCSS(primaryHex: "#3b82f6", includeNeutrals: false)
        #expect(a == b)
        #expect(!a.contains("--sw-surface"))
        #expect(!a.contains("@media"))
    }

    @Test("includeNeutrals: true emits the neutral ramp and a prefers-contrast block")
    func fullPaletteEmitted() throws {
        let css = try Color.accentThemeCSS(primaryHex: "#7c3aed", includeNeutrals: true)
        #expect(css.contains("--sw-accent: light-dark(#7c3aed, #"))
        #expect(css.contains("--sw-surface: light-dark(#"))
        #expect(css.contains("--sw-text: light-dark(#"))
        #expect(css.contains("--sw-border: light-dark(#"))
        #expect(css.contains("@media (prefers-contrast: more)"))
        #expect(css.contains("--neutrals"))   // header mentions the flag
    }
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter AccentThemeTests`. Expected: FAIL — `accentThemeCSS` has no `includeNeutrals:` parameter.

- [ ] **Step 3: Implement** — Replace the existing `accentThemeCSS` function in `Sources/SwiflowColor/ContrastColor.swift` with:

```swift
    /// Full generator: normalize the seed, derive the dark accent, validate, and return the
    /// override CSS. With `includeNeutrals`, also derives the accent-tinted neutral ramp + a
    /// prefers-contrast: more block (and folds neutral failures into the thrown error). The
    /// `includeNeutrals: false` output is byte-for-byte the original accent-only block.
    public static func accentThemeCSS(primaryHex: String, includeNeutrals: Bool = false) throws -> String {
        let light = try normalizeHex(primaryHex)
        let dark = darkAccent(from: light)
        var failures = validateAccentFamily(lightAccentHex: light, darkAccentHex: dark)

        if !includeNeutrals {
            guard failures.isEmpty else { throw PaletteError.contrastFailures(failures) }
            return """
            /* Generated by `swiflow theme --primary \(light)`. Include after SwiflowUI's styles.
               Re-points --sw-accent; hover/active/text/strong derive from it automatically. */
            :root {
              --sw-accent: light-dark(\(light), \(dark));
            }
            """
        }

        let neutrals = neutralPalette(accentHex: light)
        failures += validateNeutrals(neutrals)
        guard failures.isEmpty else { throw PaletteError.contrastFailures(failures) }

        let rootLines = (["  --sw-accent: light-dark(\(light), \(dark));"]
            + neutrals.map { "  \($0.name): light-dark(\($0.light), \($0.dark));" })
            .joined(separator: "\n")
        let moreLines = neutralContrastMore(accentHex: light)
            .map { "    \($0.name): light-dark(\($0.light), \($0.dark));" }
            .joined(separator: "\n")
        return """
        /* Generated by `swiflow theme --primary \(light) --neutrals`. Include after SwiflowUI's styles.
           Re-points --sw-accent (family cascades) + the accent-tinted neutral ramp. */
        :root {
        \(rootLines)
        }
        @media (prefers-contrast: more) {
          :root {
        \(moreLines)
          }
        }
        """
    }
```

- [ ] **Step 4: Run to verify it passes** — `swift test --filter AccentThemeTests`. Expected: PASS (all AccentThemeTests, including the prior accent-only ones and the 2 new). The `accentOnlyUnchanged` test guarantees the no-flag output didn't drift.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowColor/ContrastColor.swift Tests/SwiflowColorTests/AccentThemeTests.swift
git commit -m "feat(swiflowcolor): accentThemeCSS includeNeutrals — full palette + more-contrast"
```

---

### Task 4: `--neutrals` flag on the `theme` command

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/ThemeCommand.swift`
- Modify: `Tests/SwiflowCLITests/ThemeCommandTests.swift` (append tests)

- [ ] **Step 1: Write the failing test** — Append to `struct ThemeCommandTests` in `Tests/SwiflowCLITests/ThemeCommandTests.swift`:

```swift
    @Test("--neutrals writes the full palette (neutral tokens + prefers-contrast block)")
    func neutralsFlagWritesFullPalette() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sw-theme-\(UUID().uuidString).css")
        defer { try? FileManager.default.removeItem(at: tmp) }
        var cmd = try ThemeCommand.parse(["--primary", "#7c3aed", "--neutrals", "--out", tmp.path])
        try cmd.run()
        let css = try String(contentsOf: tmp, encoding: .utf8)
        #expect(css.contains("--sw-surface: light-dark(#"))
        #expect(css.contains("@media (prefers-contrast: more)"))
    }

    @Test("Without --neutrals the output stays accent-only")
    func noNeutralsByDefault() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sw-theme-\(UUID().uuidString).css")
        defer { try? FileManager.default.removeItem(at: tmp) }
        var cmd = try ThemeCommand.parse(["--primary", "#7c3aed", "--out", tmp.path])
        try cmd.run()
        let css = try String(contentsOf: tmp, encoding: .utf8)
        #expect(!css.contains("--sw-surface"))
    }
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter ThemeCommandTests`. Expected: FAIL — `--neutrals` is an unknown flag (`parse` throws), so `neutralsFlagWritesFullPalette` fails.

- [ ] **Step 3: Implement** — In `Sources/SwiflowCLI/Commands/ThemeCommand.swift`, add the flag (after the `out` option) and pass it through. The full updated struct body:

```swift
    @Option(name: .customLong("primary"),
            help: "Brand color (light-mode accent), as #rgb or #rrggbb.")
    var primary: String

    @Option(name: .customLong("out"),
            help: "Write the CSS to this file. Defaults to stdout.")
    var out: String?

    @Flag(name: .customLong("neutrals"),
          help: "Also derive the neutral ramp (surfaces/text/border), tinted to the accent.")
    var neutrals = false

    func run() throws {
        let css = try Color.accentThemeCSS(primaryHex: primary, includeNeutrals: neutrals)
        if let out {
            try css.write(toFile: out, atomically: true, encoding: .utf8)
        } else {
            print(css)
        }
    }
```

- [ ] **Step 4: Run to verify it passes** — `swift test --filter ThemeCommandTests`. Expected: PASS (the prior 3 + 2 new).

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowCLI/Commands/ThemeCommand.swift Tests/SwiflowCLITests/ThemeCommandTests.swift
git commit -m "feat(cli): swiflow theme --neutrals — emit the full accent-tinted palette"
```

---

## Final verification (after all tasks)

- [ ] Full suite: `swift test` → all green (the accent-only path is unchanged; new neutral/CLI tests pass).
- [ ] **End-to-end the CLI:** `swift build -c release --product swiflow && .build/release/swiflow theme --primary "#7c3aed" --neutrals` prints accent + the six neutral tokens + a `@media (prefers-contrast: more)` block, exit 0; `… --primary "#fde047" --neutrals` still exits nonzero (the accent-as-text check fires before neutrals matter).
- [ ] **Demo eyeball** (CI skips example builds): generate `… --primary "#7c3aed" --neutrals --out theme.css`, include it in `examples/SwiflowUIDemo`'s `<head>`, build + serve, and confirm surfaces/text/borders carry a faint violet tint while body and muted text stay readable in light and dark. (Revert any stamped `swiflow-service-worker.js`/driver afterward; do NOT commit a demo `index.html`/theme change unless you also regen `EmbeddedTemplates.swift` — SwiflowUIDemo is an embedded template.)
- [ ] Dispatch the final code reviewer.

## Notes for the implementer

- **`examples/` is untouched by this feature** — the generator only emits CLI output. (If you add a themed file to `SwiflowUIDemo` for the eyeball, that IS an `examples/` change and needs `swift scripts/embed-templates.swift` + committing `EmbeddedTemplates.swift`, per the CI freshness gate — but the eyeball is a local check, not part of the PR.)
- **Hex output, not `oklch()`** — neutrals emit `light-dark(#…, #…)` like the accent, for output consistency. The tint survives 8-bit at these lightnesses (e.g. a faint `#e9e6ef`), and `validateNeutrals` reads the *emitted hex*, so what's validated == what renders.
- **The more-contrast block is load-bearing**, not cosmetic: without it, the generated `:root` (included after the base sheet) would clobber the base sheet's `prefers-contrast: more` text/border boost.
- **Don't change the accent-only output** — the `accentOnlyUnchanged` test pins it byte-for-byte.
