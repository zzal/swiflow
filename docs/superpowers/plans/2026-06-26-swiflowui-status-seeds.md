# SwiflowUI Status-Color Seeds (`--danger`/`--success`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add opt-in `--danger <hex>` / `--success <hex>` flags to `swiflow theme` that emit contrast-validated `--sw-danger`/`--sw-success` overrides, composing with `--primary`/`--neutrals`.

**Architecture:** Two new optional params on `Color.accentThemeCSS` derive each status seed's dark counterpart with the existing `darkAccent(from:)` and emit a raw `--sw-…: light-dark(…)` line into the same `:root` (the base sheet re-derives `-strong`/more-contrast/P3 from the raw token, so no extra `@media` block). A generalized `validateStatusFamily` enforces per-usage WCAG bars (raw danger ≥4.5 as error text, raw success ≥3:1 as border/tint, both `-strong` ≥4.5/7). `ThemeCommand` gets two `@Option`s. Pure CLI output — no shipping CSS, component, demo, or `EmbeddedTemplates.swift` change.

**Tech Stack:** Swift 6, Swift Testing (`@Suite`/`@Test`/`#expect`), swift-argument-parser, the native-only `SwiflowColor` library.

**Spec:** [`docs/superpowers/specs/2026-06-26-swiflowui-status-seeds-design.md`](../specs/2026-06-26-swiflowui-status-seeds-design.md)

**Branch:** `feat/swiflowui-status-seeds` (already created off `origin/main`; the spec is committed there).

---

## File Structure

| File | Change |
|------|--------|
| `Sources/SwiflowColor/ContrastColor.swift` | add `validateStatusFamily(name:lightHex:darkHex:rawBar:)`; extend `accentThemeCSS` with `dangerHex:`/`successHex:` params |
| `Tests/SwiflowColorTests/StatusSeedTests.swift` (new) | unit tests for `validateStatusFamily` (must-pass for defaults/examples, must-fire for washed/over-bright seeds) |
| `Tests/SwiflowColorTests/AccentThemeTests.swift` | tests for the extended `accentThemeCSS` (emit, byte-compat, compose-with-neutrals) |
| `Sources/SwiflowCLI/Commands/ThemeCommand.swift` | add `--danger`/`--success` `@Option`s; pass through |
| `Tests/SwiflowCLITests/ThemeCommandTests.swift` | CLI flag wiring tests |
| `docs/guides/swiflowui-theming.md` | document the two generator flags |
| `docs/future-work/swiflowui-1.0-roadmap.md` | mark neutrals (PR #70) + status seeds shipped; add the warning/info follow-up |

**Swift Testing filter gotcha:** `swift test --filter` matches **type** names (e.g. `StatusSeedTests`), never the `@Suite` display string. Never trust "0 tests in 0 suites" — that means the filter matched nothing, not that tests passed.

**Reference — existing shared machinery in `ContrastColor.swift` (reuse, do not duplicate):**
- `static func hex(_:) -> LinRGB`, `static func wcagContrast(_ a: LinRGB, _ b: LinRGB) -> Double`
- `static func oklchFrom(_ source: LinRGB, lightness: Double) -> LinRGB`
- `static func mixOKLab(_ base: LinRGB, _ other: LinRGB, weightBase: Double) -> LinRGB`
- `static func darkAccent(from hex: String) -> String`, `static func normalizeHex(_:) throws -> String`
- `private static let surfaceLight = "#ffffff"`, `surfaceDark = "#1a1a1a"`, `tintWeight = 0.15`
- `private static let strongAA: (Double, Double) = (0.40, 0.80)`, `strongAAA: (Double, Double) = (0.30, 0.88)`
- `struct PaletteFailure { let token: String; let mode: String; let ratio: Double; let target: Double }`
- `enum PaletteError: Error { case invalidHex(String); case contrastFailures([PaletteFailure]) }`

---

### Task 1: `validateStatusFamily` in SwiflowColor

**Files:**
- Modify: `Sources/SwiflowColor/ContrastColor.swift` (insert a method immediately **after** `validateAccentFamily`'s closing `}` at line ~193, still inside the same `extension Color` — it sits between `validateAccentFamily` and `accentThemeCSS`)
- Create: `Tests/SwiflowColorTests/StatusSeedTests.swift`

- [ ] **Step 1: Write the failing tests** — Create `Tests/SwiflowColorTests/StatusSeedTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiflowColor

@Suite("StatusSeed")
struct StatusSeedTests {
    // Derive the dark arm the same way the generator does.
    private func dark(_ light: String) -> String { Color.darkAccent(from: light) }

    @Test("Shipped default danger/success seeds validate clean at their per-usage bars")
    func defaultsPass() {
        // #dc2626 raw on white = 4.83 (≥4.5 error-text bar); #16a34a raw = 3.30 (≥3.0 UI bar).
        // -strong derivations (L 0.40/0.80, 0.30/0.88) clear 4.5/7 with large margin for vivid hues.
        #expect(Color.validateStatusFamily(name: "--sw-danger",
                                           lightHex: "#dc2626", darkHex: dark("#dc2626"),
                                           rawBar: 4.5).isEmpty)
        #expect(Color.validateStatusFamily(name: "--sw-success",
                                           lightHex: "#16a34a", darkHex: dark("#16a34a"),
                                           rawBar: 3.0).isEmpty)
    }

    @Test("Example brand seeds (rose danger, emerald success) validate clean")
    func exampleSeedsPass() {
        #expect(Color.validateStatusFamily(name: "--sw-danger",
                                           lightHex: "#e11d48", darkHex: dark("#e11d48"),
                                           rawBar: 4.5).isEmpty)
        #expect(Color.validateStatusFamily(name: "--sw-success",
                                           lightHex: "#059669", darkHex: dark("#059669"),
                                           rawBar: 3.0).isEmpty)
    }

    @Test("A washed-out danger fails the raw 4.5 error-text bar, naming --sw-danger")
    func washedDangerFiresRawBar() {
        // #f5a3a3 light pink: ~2:1 on white, below the 4.5 raw error-text bar.
        let fails = Color.validateStatusFamily(name: "--sw-danger",
                                               lightHex: "#f5a3a3", darkHex: dark("#f5a3a3"),
                                               rawBar: 4.5)
        #expect(!fails.isEmpty)
        #expect(fails.contains { $0.token == "--sw-danger" && $0.mode == "light" })
        #expect(fails.allSatisfy { $0.ratio < $0.target })
    }

    @Test("A too-light success fails the raw 3:1 UI bar, naming --sw-success")
    func lightSuccessFiresRawBar() {
        // #86efac light green: ~1.5:1 on white, below the 3.0 raw UI/border bar. (The -strong
        // bar is not a useful must-fire fixture: oklchFrom forces L to 0.40/0.80, so a
        // dark-on-pale -strong always clears contrast — the RAW bar is the binding constraint.)
        let fails = Color.validateStatusFamily(name: "--sw-success",
                                               lightHex: "#86efac", darkHex: dark("#86efac"),
                                               rawBar: 3.0)
        #expect(fails.contains { $0.token == "--sw-success" && $0.mode == "light" })
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter StatusSeedTests`
Expected: FAIL to compile — `validateStatusFamily` does not exist yet (`type 'Color' has no member 'validateStatusFamily'`).

- [ ] **Step 3: Implement** — In `Sources/SwiflowColor/ContrastColor.swift`, add this method immediately **after** the closing `}` of `validateAccentFamily` (it returns at line ~192; insert before the `}` that closes the enclosing `extension Color`):

```swift
    /// Validate one fixed-hue status token (danger/success) against how it is actually used:
    /// the RAW token on the surface at `rawBar` (danger renders as error text → pass 4.5;
    /// success is borders/tints only → pass 3.0), and the base-sheet-derived `-strong`
    /// (L 0.40/0.80 normal, 0.30/0.88 more-contrast) on the 15% tint at 4.5 / 7. No `-text`
    /// check — there are no solid-fill status buttons. Mirrors `validateAccentFamily`'s machinery.
    public static func validateStatusFamily(name: String,
                                            lightHex: String,
                                            darkHex: String,
                                            rawBar: Double) -> [PaletteFailure] {
        var out: [PaletteFailure] = []
        let modes: [(String, String, String, Double, Double)] = [
            ("light", lightHex, surfaceLight, strongAA.0, strongAAA.0),
            ("dark",  darkHex,  surfaceDark,  strongAA.1, strongAAA.1),
        ]
        for (mode, seedHex, surfaceHex, lAA, lAAA) in modes {
            let seed = hex(seedHex)
            let surface = hex(surfaceHex)
            let tint = mixOKLab(seed, surface, weightBase: tintWeight)
            // RAW token used directly on the surface (error text / borders / tints).
            let rRaw = wcagContrast(seed, surface)
            if rRaw < rawBar { out.append(.init(token: name, mode: mode, ratio: rRaw, target: rawBar)) }
            // -strong on the tint: 4.5 normal, 7 under prefers-contrast: more.
            let rAA = wcagContrast(oklchFrom(seed, lightness: lAA), tint)
            if rAA < 4.5 { out.append(.init(token: "\(name)-strong", mode: mode, ratio: rAA, target: 4.5)) }
            let rAAA = wcagContrast(oklchFrom(seed, lightness: lAAA), tint)
            if rAAA < 7.0 { out.append(.init(token: "\(name)-strong (more-contrast)", mode: mode, ratio: rAAA, target: 7.0)) }
        }
        return out
    }
```

- [ ] **Step 4: Run to verify it passes** — `swift test --filter StatusSeedTests`
Expected: PASS (4 tests). If `defaultsPass` or `exampleSeedsPass` FAILS, STOP and report the failing token/ratio — it would mean a bar is too strict for vivid status colors (a design issue to escalate, not a code bug). If a must-fire test (`washedDangerFiresRawBar`/`lightSuccessFiresRawBar`) does NOT fail as expected, pick a more extreme (lighter) fixture hex so the raw bar genuinely fires.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowColor/ContrastColor.swift Tests/SwiflowColorTests/StatusSeedTests.swift
git commit -m "feat(swiflowcolor): validateStatusFamily for danger/success seeds"
```

---

### Task 2: Extend `accentThemeCSS` with status seeds

**Files:**
- Modify: `Sources/SwiflowColor/ContrastColor.swift` (replace the whole `accentThemeCSS` function body, currently at lines ~199–237)
- Modify: `Tests/SwiflowColorTests/AccentThemeTests.swift` (add `@Test`s inside `struct AccentThemeTests`)

- [ ] **Step 1: Write the failing tests** — Add these inside `struct AccentThemeTests` in `Tests/SwiflowColorTests/AccentThemeTests.swift` (before its closing `}`):

```swift
    @Test("Status seeds emit raw --sw-danger/--sw-success lines, no neutral tokens, no @media")
    func statusSeedsEmit() throws {
        let css = try Color.accentThemeCSS(primaryHex: "#7c3aed",
                                           dangerHex: "#e11d48", successHex: "#059669")
        #expect(css.contains("--sw-accent: light-dark(#7c3aed, #"))
        #expect(css.contains("--sw-danger: light-dark(#e11d48, #"))
        #expect(css.contains("--sw-success: light-dark(#059669, #"))
        #expect(!css.contains("--sw-surface"))   // no neutrals
        #expect(!css.contains("@media"))          // status colors need no media block
        // ordering: accent, then danger, then success
        let iAccent = css.range(of: "--sw-accent:")!.lowerBound
        let iDanger = css.range(of: "--sw-danger:")!.lowerBound
        let iSuccess = css.range(of: "--sw-success:")!.lowerBound
        #expect(iAccent < iDanger && iDanger < iSuccess)
    }

    @Test("Only the supplied status flag is emitted")
    func oneStatusSeedOnly() throws {
        let css = try Color.accentThemeCSS(primaryHex: "#3b82f6", dangerHex: "#e11d48")
        #expect(css.contains("--sw-danger: light-dark(#e11d48, #"))
        #expect(!css.contains("--sw-success"))
    }

    @Test("No status seeds is byte-for-byte the accent-only output")
    func noStatusSeedsUnchanged() throws {
        let a = try Color.accentThemeCSS(primaryHex: "#3b82f6")
        let b = try Color.accentThemeCSS(primaryHex: "#3b82f6", dangerHex: nil, successHex: nil)
        #expect(a == b)
        #expect(!a.contains("--sw-danger"))
    }

    @Test("No status seeds is byte-for-byte the accent+neutrals output")
    func noStatusSeedsUnchangedWithNeutrals() throws {
        let a = try Color.accentThemeCSS(primaryHex: "#7c3aed", includeNeutrals: true)
        let b = try Color.accentThemeCSS(primaryHex: "#7c3aed",
                                         dangerHex: nil, successHex: nil, includeNeutrals: true)
        #expect(a == b)
    }

    @Test("Status seeds compose with --neutrals (status lines + neutral ramp + media block)")
    func statusComposesWithNeutrals() throws {
        let css = try Color.accentThemeCSS(primaryHex: "#7c3aed",
                                           dangerHex: "#e11d48", includeNeutrals: true)
        #expect(css.contains("--sw-danger: light-dark(#e11d48, #"))
        #expect(css.contains("--sw-surface: light-dark(#"))
        #expect(css.contains("@media (prefers-contrast: more)"))
        // danger appears before the neutral ramp
        #expect(css.range(of: "--sw-danger:")!.lowerBound < css.range(of: "--sw-surface:")!.lowerBound)
    }

    @Test("A contrast-failing status seed throws PaletteError")
    func badStatusSeedThrows() {
        #expect(throws: Color.PaletteError.self) {
            // pale pink danger: raw < 4.5 on white
            _ = try Color.accentThemeCSS(primaryHex: "#3b82f6", dangerHex: "#f5a3a3")
        }
    }

    @Test("An invalid status hex throws invalidHex")
    func invalidStatusHexThrows() {
        #expect(throws: Color.PaletteError.self) {
            _ = try Color.accentThemeCSS(primaryHex: "#3b82f6", successHex: "nope")
        }
    }
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter AccentThemeTests`
Expected: FAIL to compile — `accentThemeCSS` has no `dangerHex:`/`successHex:` parameters yet.

- [ ] **Step 3: Implement** — In `Sources/SwiflowColor/ContrastColor.swift`, replace the **entire** `accentThemeCSS` function (from its `///` doc comment through its closing `}`) with this. The byte-compat guarantee holds because `statusLines` is empty and `flagEcho` is `""` when both seeds are `nil`, leaving both existing output strings identical:

```swift
    /// Full generator: normalize the seed, derive the dark accent, validate, and return the
    /// override CSS. Optional `dangerHex`/`successHex` add contrast-validated raw status
    /// overrides (their dark arms derived like the accent; the base sheet re-derives `-strong`,
    /// more-contrast, and P3 from the raw token). With `includeNeutrals`, also derives the
    /// accent-tinted neutral ramp + a prefers-contrast: more block. With no status seeds and
    /// `includeNeutrals: false`, the output is byte-for-byte the original accent-only block.
    public static func accentThemeCSS(primaryHex: String,
                                      dangerHex: String? = nil,
                                      successHex: String? = nil,
                                      includeNeutrals: Bool = false) throws -> String {
        let light = try normalizeHex(primaryHex)
        let dark = darkAccent(from: light)
        var failures = validateAccentFamily(lightAccentHex: light, darkAccentHex: dark)

        // Optional status seeds: normalize, dark-derive, validate, emit a raw line. Each appends
        // its flag to the header's command echo so the generated comment is reproducible.
        var statusLines: [String] = []
        var flagEcho = ""
        if let dangerHex {
            let dl = try normalizeHex(dangerHex)
            let dd = darkAccent(from: dl)
            failures += validateStatusFamily(name: "--sw-danger", lightHex: dl, darkHex: dd, rawBar: 4.5)
            statusLines.append("  --sw-danger: light-dark(\(dl), \(dd));")
            flagEcho += " --danger \(dl)"
        }
        if let successHex {
            let sl = try normalizeHex(successHex)
            let sd = darkAccent(from: sl)
            failures += validateStatusFamily(name: "--sw-success", lightHex: sl, darkHex: sd, rawBar: 3.0)
            statusLines.append("  --sw-success: light-dark(\(sl), \(sd));")
            flagEcho += " --success \(sl)"
        }

        if !includeNeutrals {
            guard failures.isEmpty else { throw PaletteError.contrastFailures(failures) }
            let rootBody = (["  --sw-accent: light-dark(\(light), \(dark));"] + statusLines)
                .joined(separator: "\n")
            return """
            /* Generated by `swiflow theme --primary \(light)\(flagEcho)`. Include after SwiflowUI's styles.
               Re-points --sw-accent; hover/active/text/strong derive from it automatically. */
            :root {
            \(rootBody)
            }
            """ + "\n"
        }

        let neutrals = neutralPalette(accentHex: light)
        failures += validateNeutrals(neutrals)
        guard failures.isEmpty else { throw PaletteError.contrastFailures(failures) }

        let rootLines = (["  --sw-accent: light-dark(\(light), \(dark));"]
            + statusLines
            + neutrals.map { "  \($0.name): light-dark(\($0.light), \($0.dark));" })
            .joined(separator: "\n")
        let moreLines = neutralContrastMore(accentHex: light)
            .map { "    \($0.name): light-dark(\($0.light), \($0.dark));" }
            .joined(separator: "\n")
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

- [ ] **Step 4: Run to verify it passes** — `swift test --filter AccentThemeTests`
Expected: PASS — the 7 new tests **and** all pre-existing `AccentThemeTests` (`goodSeedEmitsCSS`, `normalizesHex`, `accentOnlyUnchanged`, `fullPaletteEmitted`, etc.) stay green. The two byte-compat tests (`noStatusSeedsUnchanged*`) confirm the refactor didn't shift a single byte of the existing outputs.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowColor/ContrastColor.swift Tests/SwiflowColorTests/AccentThemeTests.swift
git commit -m "feat(swiflowcolor): accentThemeCSS emits validated --danger/--success seeds"
```

---

### Task 3: `--danger`/`--success` CLI flags

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/ThemeCommand.swift`
- Modify: `Tests/SwiflowCLITests/ThemeCommandTests.swift`

- [ ] **Step 1: Write the failing tests** — Add inside `struct ThemeCommandTests` in `Tests/SwiflowCLITests/ThemeCommandTests.swift` (before its closing `}`):

```swift
    @Test("--danger/--success write validated status overrides to --out")
    func statusFlagsWriteFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sw-theme-\(UUID().uuidString).css")
        defer { try? FileManager.default.removeItem(at: tmp) }
        var cmd = try ThemeCommand.parse([
            "--primary", "#7c3aed", "--danger", "#e11d48", "--success", "#059669",
            "--out", tmp.path,
        ])
        try cmd.run()
        let css = try String(contentsOf: tmp, encoding: .utf8)
        #expect(css.contains("--sw-danger: light-dark(#e11d48, #"))
        #expect(css.contains("--sw-success: light-dark(#059669, #"))
    }

    @Test("Without status flags the output has no status overrides")
    func noStatusFlagsByDefault() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sw-theme-\(UUID().uuidString).css")
        defer { try? FileManager.default.removeItem(at: tmp) }
        var cmd = try ThemeCommand.parse(["--primary", "#7c3aed", "--out", tmp.path])
        try cmd.run()
        let css = try String(contentsOf: tmp, encoding: .utf8)
        #expect(!css.contains("--sw-danger"))
        #expect(!css.contains("--sw-success"))
    }

    @Test("A contrast-failing --danger makes run() throw")
    func badDangerThrows() throws {
        var cmd = try ThemeCommand.parse(["--primary", "#7c3aed", "--danger", "#f5a3a3"])
        #expect(throws: (any Error).self) { try cmd.run() }
    }
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter ThemeCommandTests`
Expected: FAIL to compile — `ThemeCommand` has no `--danger`/`--success` options, so `parse([… "--danger" …])` is an unknown-option error / the type has no such members.

- [ ] **Step 3: Implement** — In `Sources/SwiflowCLI/Commands/ThemeCommand.swift`, add the two options after the existing `neutrals` flag (after line 28), and pass them through in `run()`. Replace the `var neutrals = false` declaration block and the `run()` body:

  (a) After the `@Flag … var neutrals = false` declaration, add:

```swift
    @Option(name: .customLong("danger"),
            help: "Brand danger/error color (light-mode), as #rgb or #rrggbb.")
    var danger: String?

    @Option(name: .customLong("success"),
            help: "Brand success color (light-mode), as #rgb or #rrggbb.")
    var success: String?
```

  (b) Replace the `run()` body's `let css = …` line:

```swift
        let css = try Color.accentThemeCSS(primaryHex: primary,
                                           dangerHex: danger,
                                           successHex: success,
                                           includeNeutrals: neutrals)
```

- [ ] **Step 4: Run to verify it passes** — `swift test --filter ThemeCommandTests`
Expected: PASS — the 3 new tests **and** the existing ones (`writesFile`, `badColorThrows`, `missingPrimary`, `neutralsFlagWritesFullPalette`, `noNeutralsByDefault`) stay green.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowCLI/Commands/ThemeCommand.swift Tests/SwiflowCLITests/ThemeCommandTests.swift
git commit -m "feat(cli): swiflow theme --danger/--success status-seed flags"
```

---

### Task 4: Docs — theming guide + roadmap

**Files:**
- Modify: `docs/guides/swiflowui-theming.md`
- Modify: `docs/future-work/swiflowui-1.0-roadmap.md`

- [ ] **Step 1: Document the generator flags** — In `docs/guides/swiflowui-theming.md`, find the `## Re-skinning via tokens` section's `@layer swiflow.base` blockquote (the line beginning `> — any unlayered rule …`, ends `> the base sheet is injected at runtime.`). Immediately **after** that blockquote (insert a blank line then the text), add:

```markdown
### Generating a theme from brand colors

`swiflow theme --primary "#7c3aed"` derives a contrast-validated `--sw-accent` family and prints
a `:root` override (use `--out theme.css` to write a file, then link it after SwiflowUI's styles).
Add optional seeds:

- `--neutrals` — also derive the accent-tinted neutral ramp (surfaces/text/border).
- `--danger "#e11d48"` — set the brand danger/error color (validated as error text, ≥ 4.5:1).
- `--success "#059669"` — set the brand success color (validated as a UI/border color, ≥ 3:1).

```text
swiflow theme --primary "#7c3aed" --danger "#e11d48" --success "#059669" --neutrals --out theme.css
```

Each seed is WCAG-validated for the way that token is actually rendered; a color that can't meet
its bar fails the build with a per-token diagnostic rather than shipping an unreadable theme.
```

- [ ] **Step 2: Update the roadmap** — In `docs/future-work/swiflowui-1.0-roadmap.md`, replace the **"Deferred from M8 to a later pass:"** paragraph (the four lines starting `**Deferred from M8 to a later pass:**` and ending `… public (shipping) generator.`) with:

```markdown
- **✅ Neutral / full-palette generation (PR #70)** — opt-in `swiflow theme --primary X --neutrals`
  derives the accent-tinted neutral ramp (`--sw-bg`/`--sw-surface`/`--sw-text`/`--sw-border`) with
  contrast-proven text-on-surface, plus a `prefers-contrast: more` block. Also fixed the base-token
  cascade (`@layer swiflow.base`) so generated/app `:root` overrides reliably win.
- **✅ Status-color seeds (this PR)** — opt-in `--danger`/`--success` seeds emit contrast-validated
  raw status overrides (per-usage bars: danger ≥ 4.5 as error text, success ≥ 3:1 as border/tint,
  derived `-strong` ≥ 4.5/7); compose with `--neutrals`. No base-sheet/component change — the base
  sheet re-derives `-strong`/more-contrast/P3 from the raw token.

**Deferred from M8 to a later pass:** `--warning`/`--info` seeds (blocked on first introducing
`--sw-warning`/`--sw-info` as base-sheet tokens + component variants — neither exists today, and
`Toast`'s `info` variant has no dedicated token); APCA as an opt-in algorithm; p3 upgrade for a
generated accent/status color; promoting `SwiflowColor` into a public (shipping) generator.
```

- [ ] **Step 3: Verify the docs render** — Run: `git diff --stat docs/`
Expected: both files show as modified; no other files touched. (No code, no tests — docs only.)

- [ ] **Step 4: Commit**
```bash
git add docs/guides/swiflowui-theming.md docs/future-work/swiflowui-1.0-roadmap.md
git commit -m "docs(theme): document --danger/--success; mark neutrals + status seeds shipped"
```

---

## Final verification (after all tasks)

- [ ] `swift test` → all green (the new `StatusSeed`/`AccentTheme`/`ThemeCommand` tests + the full existing suite; ~1125+ tests). The byte-compat tests prove the accent-only and accent+neutrals outputs are unchanged.
- [ ] `git status` → clean except the intended files. **No `examples/` change, no `Sources/SwiflowCLI/EmbeddedTemplates.swift` change** (this is generator-only output — if either appears in `git status`, something is wrong; investigate before proceeding).
- [ ] `git log --oneline origin/main..HEAD` → the spec commit + the four task commits, in order.
- [ ] Dispatch the final code reviewer subagent over the whole branch.

## Notes for the implementer

- **No demo, Playwright, or release-CLI rebuild** — this is pure generator output with no shipping-CSS, component, or cascade change ([[run-e2e-locally-before-push]] does not apply; nothing an example or the browser exercises changed). `swift test` is the complete gate.
- **Byte-compat is load-bearing** — the two `noStatusSeedsUnchanged*` tests are the contract that the refactor of `accentThemeCSS` didn't perturb the existing PR #67 / PR #70 outputs. If either fails, the new code changed the no-seed output (likely a stray space in the header `flagEcho` or a `statusLines` join issue) — fix until byte-identical.
- **`SwiflowColor` stays native-only** — it is a dependency of `SwiflowCLI` and the test targets, **never** of the wasm `SwiflowUI`. Do not add an import of it anywhere under `Sources/SwiflowUI`.
- **Must-fire tests matter** — per [[assertmacroexpansion-peer-divergence]], a validation guard that never fires is worthless; the washed-danger and bright-success tests assert the bars actually reject bad input, not just accept good input.
