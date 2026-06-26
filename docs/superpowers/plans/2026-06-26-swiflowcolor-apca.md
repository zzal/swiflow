# APCA advisory in SwiflowColor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an advisory APCA (perceptual) contrast readout to `SwiflowColor` that appears in the `swiflow theme` generator's diagnostics *only when a seed already fails the WCAG gate* — WCAG 2.x stays the sole gate.

**Architecture:** One new pure function `Color.apcaContrast(textHex:bgHex:)` (clean-room APCA-W3 0.1.9), a tiny usage→Lc map, two new fields on the existing `PaletteFailure`, and a private `paletteFailure(...)` factory that the two validators call instead of `PaletteFailure.init` so every failure carries its APCA reading. No CSS, token, threshold, or CLI-flag change; a passing palette is byte-identical to today.

**Tech Stack:** Swift, Swift Testing (`@Suite`/`@Test`/`#expect`), `@testable import SwiflowColor`. All work is in one source file plus its tests; `SwiflowColor` is native-only (CLI + tests), never a wasm dependency.

---

## Context every task needs

- **Spec:** `docs/superpowers/specs/2026-06-26-swiflowcolor-apca-design.md`.
- **The file:** `Sources/SwiflowColor/ContrastColor.swift` — a test/CLI-only color pipeline. Relevant existing members on `enum Color`: `hex(_:) -> LinRGB` (sRGB→linear), `hexString(_ c: LinRGB) -> String` (linear→`#rrggbb`, 8-bit), `wcagContrast`, `contrastColor(against:)`, `oklchFrom(_:lightness:)`, `mixOKLab`, and the `PaletteFailure` struct + `validateAccentFamily` / `validateStatusFamily`. `Foundation` is already imported (so `pow`/`abs` are available).
- **APCA operates on sRGB-encoded values** via its own `^2.4` luminance model — *not* the linear pipeline. `apcaContrast` parses the hex sRGB channels directly. The validators hold colors as `LinRGB`, so they bridge to APCA via the existing `hexString(...)` (linear→8-bit-sRGB hex), i.e. APCA is measured on the actual rendered 8-bit color.
- **Run tests:** `swift test --filter SwiflowColorTests`. Authoritative compile: `swift build`.
- **Scope discipline:** do NOT change `accentThemeCSS`, the CLI, any WCAG threshold, or any CSS/token. The only behavior change is richer diagnostic text on an *already-failing* build.

---

## Task 1: `Color.apcaContrast(textHex:bgHex:)`

**Files:**
- Modify: `Sources/SwiflowColor/ContrastColor.swift`
- Test: `Tests/SwiflowColorTests/ApcaTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowColorTests/ApcaTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiflowColor

@Suite("APCA")
struct ApcaTests {
    // APCA-W3 reference Lc values (within rounding tolerance).
    @Test("Known APCA-W3 reference pairs") func referencePairs() {
        #expect(abs(Color.apcaContrast(textHex: "#000000", bgHex: "#ffffff") - 106.04) < 0.1)
        #expect(abs(Color.apcaContrast(textHex: "#ffffff", bgHex: "#000000") - -107.88) < 0.1)
        #expect(abs(Color.apcaContrast(textHex: "#888888", bgHex: "#ffffff") - 63.1) < 0.5)
    }

    @Test("Polarity flips sign when text/background swap") func polaritySign() {
        let darkOnLight = Color.apcaContrast(textHex: "#000000", bgHex: "#ffffff")
        let lightOnDark = Color.apcaContrast(textHex: "#ffffff", bgHex: "#000000")
        #expect(darkOnLight > 0)   // dark text on light bg → positive
        #expect(lightOnDark < 0)   // light text on dark bg → negative
    }

    @Test("Identical colors have ~zero contrast") func identicalIsZero() {
        #expect(Color.apcaContrast(textHex: "#7c3aed", bgHex: "#7c3aed") == 0)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ApcaTests`
Expected: FAIL — `apcaContrast` does not exist (compile error).

- [ ] **Step 3: Implement `apcaContrast`**

In `Sources/SwiflowColor/ContrastColor.swift`, add this inside `enum Color` (place it right after `wcagContrast`, keeping contrast functions together):

```swift
/// APCA-W3 (0.1.9) perceptual lightness contrast, **Lc**, for `textHex` on `bgHex`.
/// Returns a signed value (≈ −108…106); the sign encodes polarity (negative = light text
/// on a dark background), so callers compare `abs(lc)` to a target. ADVISORY ONLY — this is
/// not a gate; WCAG 2.x remains SwiflowColor's contrast gate. Clean-room reimplementation of
/// the published APCA-W3 constants (no vendored source). Inputs are sRGB-encoded hex, parsed
/// directly — APCA uses a simple `^2.4` luminance model, distinct from the WCAG linear pipeline.
public static func apcaContrast(textHex: String, bgHex: String) -> Double {
    // APCA-W3 0.1.9 constants.
    let mainTRC = 2.4
    let (rCo, gCo, bCo) = (0.2126, 0.7152, 0.0722)
    let (normBG, normTXT, revTXT, revBG) = (0.56, 0.57, 0.62, 0.65)
    let blkThrs = 0.022, blkClmp = 1.414
    let scale = 1.14, loOffset = 0.027, loClip = 0.1, deltaYmin = 0.0005

    func srgb(_ raw: String) -> (Double, Double, Double) {
        let h = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        func byte(_ i: Int) -> Double {
            let start = h.index(h.startIndex, offsetBy: i)
            let end = h.index(start, offsetBy: 2)
            return Double(Int(h[start..<end], radix: 16) ?? 0) / 255.0
        }
        return (byte(0), byte(2), byte(4))
    }
    // Screen luminance Ys with APCA's near-black soft clamp.
    func screenY(_ c: (Double, Double, Double)) -> Double {
        let y = rCo * pow(c.0, mainTRC) + gCo * pow(c.1, mainTRC) + bCo * pow(c.2, mainTRC)
        return y < blkThrs ? y + pow(blkThrs - y, blkClmp) : y
    }

    let yTxt = screenY(srgb(textHex))
    let yBg = screenY(srgb(bgHex))
    if abs(yBg - yTxt) < deltaYmin { return 0 }

    let sapc: Double, offset: Double
    if yBg > yTxt {                                   // normal: dark text on light bg
        sapc = (pow(yBg, normBG) - pow(yTxt, normTXT)) * scale
        if sapc < loClip { return 0 }
        offset = -loOffset
    } else {                                          // reverse: light text on dark bg
        sapc = (pow(yBg, revBG) - pow(yTxt, revTXT)) * scale
        if sapc > -loClip { return 0 }
        offset = loOffset
    }
    return (sapc + offset) * 100
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter ApcaTests`
Expected: PASS — all three tests green (the hand-verified references: 106.04 / −107.88 / 63.1).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowColor/ContrastColor.swift Tests/SwiflowColorTests/ApcaTests.swift
git commit -m "feat(swiflowcolor): APCA-W3 perceptual contrast (advisory)

Color.apcaContrast(textHex:bgHex:) — clean-room APCA-W3 0.1.9, signed Lc,
polarity-aware, sRGB-based. Advisory only; WCAG 2.x stays the gate.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `PaletteFailure` APCA fields + validator wiring

> This task changes `PaletteFailure`'s stored fields AND the two validators that construct it **together**, in one commit — adding the fields alone would break the validators' `.init` calls, so they must move as a unit to keep the build green.

**Files:**
- Modify: `Sources/SwiflowColor/ContrastColor.swift`
- Test: `Tests/SwiflowColorTests/ApcaTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `struct ApcaTests` in `Tests/SwiflowColorTests/ApcaTests.swift`:

```swift
@Test("recommendedLc maps text→75, non-text→45") func recommendedLcMapping() {
    #expect(Color.recommendedLc(isText: true) == 75)
    #expect(Color.recommendedLc(isText: false) == 45)
}

@Test("PaletteFailure.description appends the APCA clause after the WCAG part") func descriptionShowsApca() {
    let f = Color.PaletteFailure(token: "--x", mode: "light", ratio: 3.9, target: 4.5,
                                 apcaLc: 68, apcaTarget: 75)
    #expect(f.description.contains("3.90:1 < 4.5:1 required"))  // WCAG portion unchanged
    #expect(f.description.contains("APCA Lc 68"))
    #expect(f.description.contains("≥ 75 for text"))
}

@Test("A failing danger seed's diagnostic carries an APCA text target (75)") func dangerFailureCarriesApca() {
    // Washed-out rose: fails the 4.5 error-text bar → text usage → APCA target 75.
    let fails = Color.validateStatusFamily(name: "--sw-danger",
                                           lightHex: "#f1a9a9", darkHex: "#f1a9a9", rawBar: 4.5)
    let raw = fails.first { $0.token == "--sw-danger" && $0.mode == "light" }
    #expect(raw != nil)
    if let d = raw {
        #expect(d.apcaTarget == 75)
        #expect(abs(d.apcaLc) > 0)
        #expect(d.description.contains("required"))   // WCAG portion intact
        #expect(d.description.contains("APCA Lc"))
    }
}

@Test("A failing non-text success seed recommends the Lc 45 UI target") func successFailureTarget45() {
    // Too-light green: fails the 3:1 UI/border bar → non-text usage → APCA target 45.
    let fails = Color.validateStatusFamily(name: "--sw-success",
                                           lightHex: "#bfe9cb", darkHex: "#bfe9cb", rawBar: 3.0)
    let raw = fails.first { $0.token == "--sw-success" && $0.mode == "light" }
    #expect(raw?.apcaTarget == 45)
}

@Test("A clean palette still produces no failures (no output regression)") func cleanPaletteNoFailures() {
    #expect(Color.validateAccentFamily(lightAccentHex: "#3b82f6", darkAccentHex: "#60a5fa").isEmpty)
}
```

- [ ] **Step 2: Run to verify it fails / does not build**

Run: `swift test --filter SwiflowColorTests`
Expected: FAIL/no-build — `recommendedLc` undefined and `PaletteFailure` has no `apcaLc`/`apcaTarget`.

- [ ] **Step 3: Extend `PaletteFailure`, add `recommendedLc` and the `paletteFailure` factory**

In `Sources/SwiflowColor/ContrastColor.swift`, replace the existing `PaletteFailure` struct:

```swift
    /// One WCAG shortfall for a generated token, in one color scheme.
    public struct PaletteFailure: Equatable, Sendable, CustomStringConvertible {
        public let token: String
        public let mode: String        // "light" | "dark"
        public let ratio: Double
        public let target: Double
        public var description: String {
            String(format: "%@ (%@): %.2f:1 < %.1f:1 required", token, mode, ratio, target)
        }
    }
```

with:

```swift
    /// One WCAG shortfall for a generated token, in one color scheme. Carries an APCA
    /// (perceptual) reading as an advisory second opinion — see `apcaLc` / `apcaTarget`.
    public struct PaletteFailure: Equatable, Sendable, CustomStringConvertible {
        public let token: String
        public let mode: String        // "light" | "dark"
        public let ratio: Double
        public let target: Double
        /// Signed APCA Lc for this token's text/surface pairing (advisory; `abs` is compared).
        public let apcaLc: Double
        /// APCA's recommended Lc for this usage (75 text, 45 non-text). Guidance, never gated.
        public let apcaTarget: Double
        public var description: String {
            let wcag = String(format: "%@ (%@): %.2f:1 < %.1f:1 required", token, mode, ratio, target)
            let usage = apcaTarget >= 75 ? "text" : "non-text"
            let apca = String(format: " — APCA Lc %.0f (suggests ≥ %.0f for %@)",
                              abs(apcaLc), apcaTarget, usage)
            return wcag + apca
        }
    }

    /// APCA advisory target for a usage: fluent text 75, non-text/UI element 45. Guidance only.
    static func recommendedLc(isText: Bool) -> Double { isText ? 75 : 45 }

    /// Build a `PaletteFailure`, computing its advisory APCA reading from the same text/surface
    /// pair used for the WCAG ratio. APCA runs on the rendered 8-bit color (`hexString`).
    private static func paletteFailure(_ token: String, _ mode: String,
                                       ratio: Double, target: Double,
                                       text: LinRGB, bg: LinRGB, isText: Bool) -> PaletteFailure {
        PaletteFailure(token: token, mode: mode, ratio: ratio, target: target,
                       apcaLc: apcaContrast(textHex: hexString(text), bgHex: hexString(bg)),
                       apcaTarget: recommendedLc(isText: isText))
    }
```

- [ ] **Step 4: Update `validateAccentFamily`**

Replace the `for` loop body in `validateAccentFamily` with (lifts each text color to a local so it can be passed to `paletteFailure`; `--sw-accent`-as-text and every `-strong`/`-text` are text usages → `isText: true`; the `ratio` values are unchanged):

```swift
        for (mode, accentHex, surfaceHex, lAA, lAAA) in modes {
            let accent = hex(accentHex)
            let surface = hex(surfaceHex)
            let tint = mixOKLab(accent, surface, weightBase: tintWeight)
            // --sw-accent used as TEXT (ghost buttons, links) on the surface; UI/large-text bar (3:1).
            let rAccentText = wcagContrast(accent, surface)
            if rAccentText < 3.0 {
                out.append(paletteFailure("--sw-accent (as text/links)", mode,
                                          ratio: rAccentText, target: 3.0,
                                          text: accent, bg: surface, isText: true))
            }
            // -strong on the tint: 4.5 normal, 7 under prefers-contrast: more.
            let strongAA = oklchFrom(accent, lightness: lAA)
            let rAA = wcagContrast(strongAA, tint)
            if rAA < 4.5 {
                out.append(paletteFailure("--sw-accent-strong", mode, ratio: rAA, target: 4.5,
                                          text: strongAA, bg: tint, isText: true))
            }
            let strongAAA = oklchFrom(accent, lightness: lAAA)
            let rAAA = wcagContrast(strongAAA, tint)
            if rAAA < 7.0 {
                out.append(paletteFailure("--sw-accent-strong (more-contrast)", mode,
                                          ratio: rAAA, target: 7.0,
                                          text: strongAAA, bg: tint, isText: true))
            }
            // -text on the solid accent: the Baseline contrast-color() result.
            let textColor = contrastColor(against: accent)
            let rText = wcagContrast(textColor, accent)
            if rText < 4.5 {
                out.append(paletteFailure("--sw-accent-text", mode, ratio: rText, target: 4.5,
                                          text: textColor, bg: accent, isText: true))
            }
        }
```

- [ ] **Step 5: Update `validateStatusFamily`**

Add the `rawIsText` line just before its `for` loop, then replace the loop body:

```swift
        // danger's raw token renders as error text (bar 4.5 → APCA text); success/warning/info
        // are non-text UI colors (bar 3.0 → APCA non-text).
        let rawIsText = rawBar >= 4.5
        for (mode, seedHex, surfaceHex, lAA, lAAA) in modes {
            let seed = hex(seedHex)
            let surface = hex(surfaceHex)
            let tint = mixOKLab(seed, surface, weightBase: tintWeight)
            // RAW token used directly on the surface (error text / borders / tints).
            let rRaw = wcagContrast(seed, surface)
            if rRaw < rawBar {
                out.append(paletteFailure(name, mode, ratio: rRaw, target: rawBar,
                                          text: seed, bg: surface, isText: rawIsText))
            }
            // -strong on the tint: 4.5 normal, 7 under prefers-contrast: more (always text).
            let strongAA = oklchFrom(seed, lightness: lAA)
            let rAA = wcagContrast(strongAA, tint)
            if rAA < 4.5 {
                out.append(paletteFailure("\(name)-strong", mode, ratio: rAA, target: 4.5,
                                          text: strongAA, bg: tint, isText: true))
            }
            let strongAAA = oklchFrom(seed, lightness: lAAA)
            let rAAA = wcagContrast(strongAAA, tint)
            if rAAA < 7.0 {
                out.append(paletteFailure("\(name)-strong (more-contrast)", mode,
                                          ratio: rAAA, target: 7.0,
                                          text: strongAAA, bg: tint, isText: true))
            }
        }
```

- [ ] **Step 6: Run the full SwiflowColor suite + host build**

Run: `swift test --filter SwiflowColorTests && swift build`
Expected: PASS — the five new tests green, ALL pre-existing tests (`StatusSeedTests`, `AccentThemeTests`, `NeutralPaletteTests`, `DarkAccentTests`, `P3GamutTests`) still green (they assert on `token`/`mode`/`ratio`/`target`, unchanged), and `swift build` exit 0 (`accentThemeCSS`/CLI use `.description`, which still works).

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiflowColor/ContrastColor.swift Tests/SwiflowColorTests/ApcaTests.swift
git commit -m "feat(swiflowcolor): advisory APCA Lc on each WCAG failure

PaletteFailure gains apcaLc/apcaTarget (75 text / 45 non-text); both validators
route through a paletteFailure factory so a failing seed reports its APCA reading.
Passing palettes are byte-identical.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Docs note + roadmap mark shipped

**Files:**
- Modify: `docs/guides/swiflowui-theming.md`
- Modify: `docs/future-work/swiflowui-1.0-roadmap.md`

- [ ] **Step 1: Add a one-paragraph note to the theming guide**

In `docs/guides/swiflowui-theming.md`, find the "Generating a theme from brand colors" section (the paragraph ending "…fails the build with a per-token diagnostic rather than shipping an unreadable theme.") and add immediately after it:

```markdown
When a seed fails, its diagnostic also includes an **APCA** (perceptual) reading — e.g.
`APCA Lc 68 (suggests ≥ 75 for text)` — as a second opinion alongside the WCAG ratio. APCA is
advisory only: WCAG 2.x remains the gate, and a passing palette prints nothing extra.
```

- [ ] **Step 2: Mark the roadmap deferral shipped**

In `docs/future-work/swiflowui-1.0-roadmap.md`, find the M8 deferral line:

```markdown
**Deferred from M8 to a later pass:** APCA as an opt-in algorithm; promoting `SwiflowColor` into a
public (shipping) generator.
```

Replace it with:

```markdown
**Deferred from M8 to a later pass:** ~~APCA as an opt-in algorithm~~ — **shipped** as an advisory
APCA-W3 reading in failed-seed diagnostics (WCAG 2.x stays the gate); promoting `SwiflowColor` into
a public (shipping) generator remains deferred.
```

- [ ] **Step 3: Verify nothing regressed (sanity)**

Run: `swift test --filter SwiflowColorTests && swift build`
Expected: still green (docs-only change).

- [ ] **Step 4: Commit**

```bash
git add docs/guides/swiflowui-theming.md docs/future-work/swiflowui-1.0-roadmap.md
git commit -m "docs: note the advisory APCA reading; mark the M8 APCA deferral shipped

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final review (after all tasks)

Dispatch a code-review subagent over `git diff origin/main...HEAD`. The shipped diff must be exactly: `ContrastColor.swift` (apcaContrast + PaletteFailure fields/factory + the two validator bodies), `ApcaTests.swift` (new), the guide note, and the roadmap line — and **nothing** in `Sources/SwiflowUI/`, `examples/`, or any CSS/token. Then run a manual smoke: `swift run swiflow theme --primary "#3b82f6" --danger "#f1a9a9"` and confirm the danger diagnostic shows an `APCA Lc … suggests ≥ 75` clause, while `--primary "#3b82f6"` alone prints a clean palette with no APCA text.
