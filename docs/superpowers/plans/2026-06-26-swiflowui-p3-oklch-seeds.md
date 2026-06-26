# SwiflowUI p3/OKLCH Wide-Gamut Generator Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `swiflow theme` emit accent + status colors at the display-P3 gamut edge via a progressive `oklch()` declaration (hex fallback first), so generated themes render wide-gamut on capable displays.

**Architecture:** New native-only color math projects OKLab → linear-Display-P3 and binary-searches the in-P3 max chroma at a seed's exact L/H. The generator emits a second `--sw-X: light-dark(oklch(…), oklch(…))` line after each accent/status hex line (neutrals stay hex-only). Validation is unchanged (runs on the hex; oklch shares L/H → contrast preserved). Generator-only — no base-sheet/component/CLI-flag change.

**Tech Stack:** Swift 6, Swift Testing, native-only `SwiflowColor`, Playwright, the `swiflow` CLI.

**Spec:** [`docs/superpowers/specs/2026-06-26-swiflowui-p3-oklch-seeds-design.md`](../specs/2026-06-26-swiflowui-p3-oklch-seeds-design.md)

**Branch:** `feat/swiflowui-p3-oklch-seeds` (already created off `origin/main`; the spec + a roadmap update are committed there).

---

## File Structure

| File | Change |
|------|--------|
| `Sources/SwiflowColor/ContrastColor.swift` | add `linRGBToLinP3`, `inP3Gamut`, `p3MaxChroma`, `p3OKLCHString`; emit the oklch line in `accentThemeCSS` |
| `Tests/SwiflowColorTests/P3GamutTests.swift` (new) | unit tests for the P3 math |
| `Tests/SwiflowColorTests/AccentThemeTests.swift` | assert the oklch line is emitted (accent + status), neutrals stay hex |
| `Tests/SwiflowCLITests/ThemeCommandTests.swift` | smoke: written file has an `oklch(` accent line |
| `examples/SwiflowUIDemo/theme.css` (regen) + `Sources/SwiflowCLI/EmbeddedTemplates.swift` (regen) | demo carries the oklch output |
| `Tests/playwright/theming.spec.ts` | a generated oklch accent resolves in-browser |
| `docs/guides/swiflowui-theming.md`, `docs/future-work/swiflowui-1.0-roadmap.md` | docs |

**Reference — existing pipeline in `ContrastColor.swift` (reuse):**
- `struct LinRGB { var r,g,b: Double; var luminance }`, `struct OKLab { L,a,b }`, `struct OKLCH { L,C,H }` (**H in radians**)
- `static func hex(_ hex: String) -> LinRGB` (parses `#rrggbb`)
- `static func okLabToLinRGB(_ : OKLab) -> LinRGB` (**returns RAW, unclamped** linear-sRGB)
- `static func linRGBToOKLab(_:) -> OKLab`, `static func okLabToOKLCH(_:) -> OKLCH`, `static func okLCHToOKLab(_:) -> OKLab`
- `accentThemeCSS` builds `:root` from `"  --sw-accent: light-dark(\(light), \(dark));"` + `statusLines` (+ neutrals)

**Swift Testing filter gotcha:** `swift test --filter` matches **type** names (`P3GamutTests`), never the `@Suite` string.

---

### Task 1: P3 gamut color math

**Files:**
- Modify: `Sources/SwiflowColor/ContrastColor.swift` (add a new `extension Color { … }` near the other color-math extensions, e.g. after the `oklchFrom`/`darkAccent` extension)
- Create: `Tests/SwiflowColorTests/P3GamutTests.swift`

- [ ] **Step 1: Write the failing tests** — Create `Tests/SwiflowColorTests/P3GamutTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiflowColor

@Suite("P3Gamut")
struct P3GamutTests {
    @Test("a saturated sRGB color is inside the P3 gamut") func srgbInsideP3() {
        // Any in-sRGB color is in P3 (P3 ⊇ sRGB).
        for hex in ["#7c3aed", "#e11d48", "#16a34a", "#0284c7", "#b45309"] {
            #expect(Color.inP3Gamut(Color.linRGBToOKLab(Color.hex(hex))))
        }
    }

    @Test("chroma boosted past the P3 edge falls outside the gamut") func beyondEdgeOutside() {
        let lch = Color.okLabToOKLCH(Color.linRGBToOKLab(Color.hex("#7c3aed")))
        let edge = Color.p3MaxChroma(L: lch.L, H: lch.H)
        #expect(Color.inP3Gamut(Color.okLCHToOKLab(.init(L: lch.L, C: edge, H: lch.H))))
        // a hair past the edge is out of gamut
        #expect(!Color.inP3Gamut(Color.okLCHToOKLab(.init(L: lch.L, C: edge + 0.02, H: lch.H))))
    }

    @Test("P3 edge chroma is >= the seed's sRGB chroma (only widens)") func boostWidens() {
        for hex in ["#7c3aed", "#e11d48", "#0284c7"] {
            let lch = Color.okLabToOKLCH(Color.linRGBToOKLab(Color.hex(hex)))
            #expect(Color.p3MaxChroma(L: lch.L, H: lch.H) >= lch.C - 1e-9)
        }
        // for a vivid violet the P3 edge is strictly wider
        let v = Color.okLabToOKLCH(Color.linRGBToOKLab(Color.hex("#7c3aed")))
        #expect(Color.p3MaxChroma(L: v.L, H: v.H) > v.C + 1e-3)
    }

    @Test("p3OKLCHString is well-formed oklch() with hue in 0...360 degrees") func stringForm() {
        let s = Color.p3OKLCHString(fromHex: "#7c3aed")
        #expect(s.hasPrefix("oklch(") && s.hasSuffix(")"))
        // oklch(<L> <C> <Hdeg>)
        let nums = s.dropFirst(6).dropLast()
            .split(separator: " ").compactMap { Double($0) }
        #expect(nums.count == 3)
        #expect(nums[0] > 0 && nums[0] < 1)        // L in 0..1
        #expect(nums[2] >= 0 && nums[2] <= 360)     // H in degrees
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter P3GamutTests`
Expected: FAIL to compile — `linRGBToLinP3`/`inP3Gamut`/`p3MaxChroma`/`p3OKLCHString` don't exist.

- [ ] **Step 3: Implement** — Add this extension to `Sources/SwiflowColor/ContrastColor.swift`:

```swift
extension Color {
    /// Linear-sRGB → linear-Display-P3. Both are D65, so it is a single matrix (no chromatic
    /// adaptation). Used to test P3-gamut membership of an (out-of-sRGB) OKLab color.
    static func linRGBToLinP3(_ c: LinRGB) -> LinRGB {
        LinRGB(
            r: 0.82246197 * c.r + 0.17753803 * c.g + 0.0        * c.b,
            g: 0.03319420 * c.r + 0.96680580 * c.g + 0.0        * c.b,
            b: 0.01708263 * c.r + 0.07239744 * c.g + 0.91051993 * c.b)
    }

    /// Is this OKLab color representable in the Display-P3 gamut? (small epsilon tolerance)
    static func inP3Gamut(_ lab: OKLab) -> Bool {
        let p = linRGBToLinP3(okLabToLinRGB(lab))
        let eps = 1e-6
        return p.r >= -eps && p.r <= 1 + eps
            && p.g >= -eps && p.g <= 1 + eps
            && p.b >= -eps && p.b <= 1 + eps
    }

    /// Largest chroma whose OKLCH(L, C, H) stays inside Display-P3, via binary search.
    static func p3MaxChroma(L: Double, H: Double) -> Double {
        var lo = 0.0, hi = 0.5   // 0.5 is beyond any real-display chroma
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if inP3Gamut(okLCHToOKLab(OKLCH(L: L, C: mid, H: H))) { lo = mid } else { hi = mid }
        }
        return lo
    }

    /// A hex color re-expressed as `oklch(L C Hdeg)` with chroma pushed to the P3 gamut edge at
    /// its own L and H (same lightness/hue → same luminance/contrast; only chroma widens, and
    /// only on P3 displays). H is converted radians→degrees.
    public static func p3OKLCHString(fromHex hexStr: String) -> String {
        let lch = okLabToOKLCH(linRGBToOKLab(hex(hexStr)))
        let c = max(lch.C, p3MaxChroma(L: lch.L, H: lch.H))   // can only widen
        var deg = lch.H * 180 / .pi
        if deg < 0 { deg += 360 }
        func round(_ x: Double, _ scale: Double) -> Double { (x * scale).rounded() / scale }
        return "oklch(\(round(lch.L, 10000)) \(round(c, 10000)) \(round(deg, 100)))"
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `swift test --filter P3GamutTests`
Expected: PASS (4 tests). If `srgbInsideP3` fails, the matrix is wrong (an in-sRGB color must be in P3) — re-check the `linRGBToLinP3` coefficients against a reference.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowColor/ContrastColor.swift Tests/SwiflowColorTests/P3GamutTests.swift
git commit -m "feat(swiflowcolor): display-P3 gamut math + p3OKLCHString"
```

---

### Task 2: Generator emits the oklch line

**Files:**
- Modify: `Sources/SwiflowColor/ContrastColor.swift` (`accentThemeCSS`)
- Modify: `Tests/SwiflowColorTests/AccentThemeTests.swift`
- Modify: `Tests/SwiflowCLITests/ThemeCommandTests.swift`

- [ ] **Step 1: Write the failing tests** — In `Tests/SwiflowColorTests/AccentThemeTests.swift`, add inside `struct AccentThemeTests`:

```swift
    @Test("accent gets a progressive oklch() line after the hex line") func accentHasOklch() throws {
        let css = try Color.accentThemeCSS(primaryHex: "#7c3aed")
        #expect(css.contains("--sw-accent: light-dark(#7c3aed, #"))   // hex fallback still first
        #expect(css.contains("--sw-accent: light-dark(oklch("))        // oklch upgrade line
        // the oklch line comes AFTER the hex line for the same token
        let hexAt = css.range(of: "--sw-accent: light-dark(#")!.lowerBound
        let oklchAt = css.range(of: "--sw-accent: light-dark(oklch(")!.lowerBound
        #expect(hexAt < oklchAt)
    }

    @Test("each status seed also gets an oklch line; neutrals stay hex-only") func statusOklchNeutralsHex() throws {
        let css = try Color.accentThemeCSS(primaryHex: "#7c3aed",
                                           dangerHex: "#e11d48", includeNeutrals: true)
        #expect(css.contains("--sw-danger: light-dark(oklch("))
        // neutrals are near-gray: hex only, no oklch line
        #expect(css.contains("--sw-bg: light-dark(#"))
        #expect(!css.contains("--sw-bg: light-dark(oklch("))
    }

    @Test("contrast still validates (boosted oklch shares the hex's L/H)") func contrastPreserved() {
        // The accent family validator runs on the hex; a known-good seed still passes.
        #expect(Color.validateAccentFamily(lightAccentHex: "#7c3aed",
                                           darkAccentHex: Color.darkAccent(from: "#7c3aed")).isEmpty)
    }
```

Also in `Tests/SwiflowCLITests/ThemeCommandTests.swift`, add inside `struct ThemeCommandTests`:
```swift
    @Test("generated file carries a progressive oklch accent line") func fileHasOklch() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sw-theme-\(UUID().uuidString).css")
        defer { try? FileManager.default.removeItem(at: tmp) }
        var cmd = try ThemeCommand.parse(["--primary", "#7c3aed", "--out", tmp.path])
        try cmd.run()
        let css = try String(contentsOf: tmp, encoding: .utf8)
        #expect(css.contains("--sw-accent: light-dark(oklch("))
    }
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter AccentThemeTests`
Expected: FAIL — `accentHasOklch`/`statusOklchNeutralsHex` fail (no oklch line yet).

- [ ] **Step 3: Implement** — In `Sources/SwiflowColor/ContrastColor.swift`, inside `accentThemeCSS`:

  (a) Add a local helper at the top of the function body (right after `var flagEcho = ""`), which returns BOTH the hex line and the oklch line for a token:
```swift
        // Each accent/status token emits a hex fallback line + a progressive oklch() line whose
        // chroma is pushed to the P3 gamut edge (wider gamut on capable displays; same L/H).
        func tokenLines(_ name: String, _ lightHex: String, _ darkHex: String) -> [String] {
            ["  \(name): light-dark(\(lightHex), \(darkHex));",
             "  \(name): light-dark(\(p3OKLCHString(fromHex: lightHex)), \(p3OKLCHString(fromHex: darkHex)));"]
        }
```

  (b) Change each status block to append BOTH lines. Replace the four `statusLines.append("  --sw-X: light-dark(\(x), \(xd));")` calls with `statusLines += tokenLines(...)`. Concretely, for danger:
```swift
            statusLines += tokenLines("--sw-danger", dl, dd)
```
  and likewise `tokenLines("--sw-success", sl, sd)`, `tokenLines("--sw-warning", wl, wd)`, `tokenLines("--sw-info", il, id)` in their respective blocks (replacing only the `.append(...)` line; keep the `normalizeHex`/`darkAccent`/`validateStatusFamily`/`flagEcho` lines).

  (c) Replace the accent line in BOTH `:root` assembly paths. In the no-neutrals path:
```swift
            let rootBody = (tokenLines("--sw-accent", light, dark) + statusLines)
                .joined(separator: "\n")
```
  and in the neutrals path:
```swift
        let rootLines = (tokenLines("--sw-accent", light, dark)
            + statusLines
            + neutrals.map { "  \($0.name): light-dark(\($0.light), \($0.dark));" })
            .joined(separator: "\n")
```
  (Neutrals keep their single hex line — no `tokenLines`.)

- [ ] **Step 4: Run to verify it passes** — `swift test --filter AccentThemeTests` then `swift test --filter ThemeCommandTests`
Expected: PASS — the new tests AND all existing AccentThemeTests/ThemeCommandTests (the byte-compat self-comparisons `a == b` still hold; the `contains("#hex")` assertions still hold because the hex line is still first). If a pre-existing test pinned an *exact full* output string, update it to include the oklch line (grep `Tests/SwiflowColorTests` for `light-dark(#` triple-quoted blocks; there should be none — the byte-compat tests are `a == b` comparisons).

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowColor/ContrastColor.swift Tests/SwiflowColorTests/AccentThemeTests.swift Tests/SwiflowCLITests/ThemeCommandTests.swift
git commit -m "feat(swiflowcolor): emit progressive P3 oklch() line for accent + status"
```

---

### Task 3: Regenerate the demo theme.css

**Files:**
- Modify: `examples/SwiflowUIDemo/theme.css` (regen)
- Modify: `Sources/SwiflowCLI/EmbeddedTemplates.swift` (regen)

- [ ] **Step 1: Build the release CLI** (it must embed the new generator):
Run: `swift build -c release --product swiflow`
Expected: `Build of product 'swiflow' complete!`

- [ ] **Step 2: Regenerate theme.css with the original command** (the same one in its header comment):
```bash
.build/release/swiflow theme --primary "#7c3aed" --neutrals --out examples/SwiflowUIDemo/theme.css
```
Expected: the file now contains an `--sw-accent: light-dark(oklch(…` line after the hex line; neutrals remain hex-only. Confirm with: `grep -c "oklch(" examples/SwiflowUIDemo/theme.css` → ≥ 1.

- [ ] **Step 3: Regenerate embedded templates** (the demo is an embedded template; CI freshness gate):
Run: `swift scripts/embed-templates.swift`
Expected: `wrote …/EmbeddedTemplates.swift`; `git status` shows `theme.css` + `EmbeddedTemplates.swift` modified.

- [ ] **Step 4: Verify freshness** — Run: `swift test --filter TemplateEmbedderTests`
Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add examples/SwiflowUIDemo/theme.css Sources/SwiflowCLI/EmbeddedTemplates.swift
git commit -m "docs(demo): regenerate theme.css with progressive P3 oklch output"
```

---

### Task 4: Playwright — a generated oklch accent resolves in-browser

**Files:**
- Modify: `Tests/playwright/theming.spec.ts`

This proves the emitted `oklch()` line parses and applies (using the same route-rewrite trick the existing override test uses, but injecting an oklch override).

- [ ] **Step 1: Write the test** — Add inside the `test.describe(...)` block in `Tests/playwright/theming.spec.ts`:
```ts
  test("an oklch() accent override (the generator's P3 output) resolves and applies", async ({ page }) => {
    // Inject an oklch override like the generator now emits. It must parse and win, proving the
    // P3 progressive line is valid CSS the browser applies (resolved to the display's gamut).
    await page.route("**/*", async (route) => {
      if (route.request().resourceType() !== "document") return route.continue();
      const res = await route.fetch();
      const html = (await res.text()).replace(
        "</head>",
        "<style>:root { --sw-accent: oklch(0.55 0.25 145) }</style></head>"
      );
      await route.fulfill({ response: res, body: html });
    });
    await gotoMounted(page);
    const bg = await page.getByRole("button", { name: "Increment" })
      .evaluate((el) => getComputedStyle(el).backgroundColor);
    // a green-ish oklch — resolves to a real rgb/color(), not empty/transparent, and not the default blue
    expect(bg).toMatch(/^(rgb|color)/);
    expect(bg).not.toBe("rgba(0, 0, 0, 0)");
  });
```

- [ ] **Step 2: Build the release CLI first** (e2e harness reuses the binary):
Run: `swift build -c release --product swiflow`
Expected: `Build of product 'swiflow' complete!`

- [ ] **Step 3: Run the spec INLINE, detached, after killing leftovers** (per [[no-subagent-playwright]] / [[run-e2e-locally-before-push]]):
```bash
pkill -9 -f playwright; pkill -9 -f swiflow-dev; lsof -ti tcp:3000 | xargs kill -9 2>/dev/null; sleep 1
cd Tests/playwright && npx playwright test theming.spec.ts
```
Expected: PASS — the new oklch test + the existing media-feature/override/token tests.

- [ ] **Step 4: Commit**
```bash
git add Tests/playwright/theming.spec.ts
git commit -m "test(e2e): an oklch() accent override resolves in-browser"
```

---

### Task 5: Docs — guide + roadmap

**Files:**
- Modify: `docs/guides/swiflowui-theming.md`
- Modify: `docs/future-work/swiflowui-1.0-roadmap.md`

- [ ] **Step 1: Document the p3/oklch default** — In `docs/guides/swiflowui-theming.md`, in the `### Generating a theme from brand colors` section, after the flag bullet list (before or after the example fence), add:
```markdown
Generated accent/status colors ship a progressive `oklch()` line after their hex fallback, so they
render at the **display-P3 gamut edge** on capable screens (richer color; identical sRGB hex
fallback elsewhere). Lightness and hue are preserved, so contrast is unchanged. Neutrals stay
hex-only (grays gain nothing from a wider gamut).
```

- [ ] **Step 2: Mark the roadmap item shipped** — In `docs/future-work/swiflowui-1.0-roadmap.md`, replace the `**Next (in progress):** **p3 / wide-gamut upgrade…**` paragraph (added earlier on this branch) with a ✅ bullet appended to the M8 shipped list:
```markdown
- **✅ p3 / wide-gamut generated colors (this PR)** — `swiflow theme` emits accent + status colors
  with a progressive `oklch()` line (chroma pushed to the display-P3 gamut edge at the seed's L/H)
  after the sRGB hex fallback, so generated themes render wide-gamut on capable displays without an
  `@media` block. Neutrals stay hex-only; validation still runs on the hex (L/H preserved →
  contrast unchanged).
```
Leave the **Deferred** paragraph (APCA; public `SwiflowColor`) as-is.

- [ ] **Step 3: Verify docs-only** — Run: `git diff --stat docs/`
Expected: only the two doc files modified.

- [ ] **Step 4: Commit**
```bash
git add docs/guides/swiflowui-theming.md docs/future-work/swiflowui-1.0-roadmap.md
git commit -m "docs(theme): document the p3/oklch generated-color default; mark shipped"
```

---

## Final verification (after all tasks)

- [ ] `swift test` → all green (P3GamutTests, AccentThemeTests, ThemeCommandTests, TemplateEmbedderTests + full suite).
- [ ] `cd Tests/playwright && npx playwright test theming.spec.ts` → green, with a freshly built release CLI.
- [ ] `git status` clean except intended files — `theme.css` + `EmbeddedTemplates.swift` committed; **no stray stamped SW/driver artifacts** from any demo build (`git checkout --` them if a build dropped them).
- [ ] `git log --oneline origin/main..HEAD` → roadmap + spec + plan + the five task commits.
- [ ] Dispatch the final code reviewer over the whole branch.

## Notes for the implementer

- **Generator-only** — do NOT touch `Theme.swift`, components, or add a CLI flag. The base sheet's hand-authored `color(display-p3 …)` blocks stay (they cover the no-generator default theme).
- **`SwiflowColor` stays native-only** — never import it under `Sources/SwiflowUI`.
- **Contrast is preserved by construction** — the oklch line shares the hex's OKLCH L and H, so don't add new validation; the existing hex-based validators are correct.
- **Demo build drops stamped artifacts** — after any `swiflow build`, `git checkout --` the `swiflow-service-worker.js`/`swiflow-driver.js`/`swiflow-manifest.json` in the example dir; commit only `theme.css` + `EmbeddedTemplates.swift`.
- **Playwright is local + inline** — CI skips example builds ([[ci-skips-example-builds]]); never delegate the e2e run to a subagent ([[no-subagent-playwright]]); rebuild the release CLI before each run.
