# SwiflowUI Base-Token Cascade Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wrap SwiflowUI's base token sheet in `@layer swiflow.base` so app/generated `:root` overrides win the cascade, then prove it in the browser and wire a generated palette into the demo.

**Architecture:** One `Theme.swift` edit wraps `baseStyleSheet`'s emitted CSS in `@layer swiflow.base { … }`. Because any unlayered rule beats any layered rule regardless of source order, a static (unlayered) `:root { --sw-accent }` override — in `index.html` or a generated `theme.css` — now beats the runtime-appended base sheet. The generator, `Theme` component, and component sheets are unchanged (all already unlayered). Verified by a Playwright cascade test (unit tests can't see the cascade) + the existing media-feature specs.

**Tech Stack:** Swift 6, Swift Testing, Playwright (`@playwright/test`), the `swiflow` CLI. Branch: `feat/swiflowui-neutral-palette` (folded in).

**Spec:** [`docs/superpowers/specs/2026-06-25-swiflowui-base-layer-cascade-design.md`](../specs/2026-06-25-swiflowui-base-layer-cascade-design.md)

---

## File Structure

| File | Change |
|------|--------|
| `Sources/SwiflowUI/Theme.swift` | wrap `baseStyleSheet` raw CSS in `@layer swiflow.base { … }` |
| `Tests/SwiflowUITests/ThemeTests.swift` | assert `@layer swiflow.base` is emitted (+ braces stay balanced) |
| `docs/guides/swiflowui-theming.md` | one line: overrides win via `@layer swiflow.base` |
| `Tests/playwright/theming.spec.ts` | a static `:root` override wins over the base sheet (route-rewrite) |
| `examples/SwiflowUIDemo/theme.css` (new) + `index.html` | wire a `--neutrals` palette as the visual proof |
| `Sources/SwiflowCLI/EmbeddedTemplates.swift` | regen (SwiflowUIDemo is an embedded template) |

Swift Testing filter gotcha: `swift test --filter` matches TYPE names (`ThemeTests`), never trust "0 tests in 0 suites".

---

### Task 1: Wrap base tokens in `@layer swiflow.base`

**Files:**
- Modify: `Sources/SwiflowUI/Theme.swift` (the `baseStyleSheet` raw string)
- Modify: `Tests/SwiflowUITests/ThemeTests.swift` (add one `@Test`)
- Modify: `docs/guides/swiflowui-theming.md` (one note)

- [ ] **Step 1: Write the failing test** — Add inside `struct ThemeTests` (before its closing brace):

```swift
    @Test("Base tokens live in @layer swiflow.base so unlayered app overrides win")
    func baseTokensAreLayered() {
        let css = sheet
        #expect(css.contains("@layer swiflow.base"))
        // tokens + a media layer are still present (now inside the layer)
        #expect(css.contains("--sw-accent"))
        #expect(css.contains("@media (prefers-contrast: more)"))
        // wrapping kept braces balanced
        #expect(css.filter { $0 == "{" }.count == css.filter { $0 == "}" }.count)
    }
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter ThemeTests`. Expected: the new test FAILS (no `@layer swiflow.base` yet).

- [ ] **Step 3: Implement** — In `Sources/SwiflowUI/Theme.swift`, wrap the entire `raw("""…""")` body in a layer. Two edits:

  (a) Find the opening:
```
        raw("""
        :root {
```
  and replace with:
```
        raw("""
        @layer swiflow.base {
        :root {
```

  (b) Add the layer's closing brace as the LAST line before the `"""` that ends the raw string. Find the end of the sheet — the final lines are the close of the `color-gamut` block followed by the closing `"""`:
```
        }
        """)
```
  and replace with:
```
        }
        }
        """)
```
  (This adds exactly one `}` to close `@layer swiflow.base`. If the exact whitespace before `""")` differs, match the real file: the goal is one extra `}` immediately before the closing `"""`.)

- [ ] **Step 4: Run to verify it passes** — `swift test --filter ThemeTests`. Expected: PASS — the new test **and** all existing `ThemeTests` (`baseSheetContainsRootTokens`, `overridesComeAfterBase`, `bracesBalanced`, `mediaLayersEmitted`, `progressiveEnhancementPairsEmitted`, etc.) stay green. If `bracesBalanced` fails, the closing `}` was miscounted — re-check edit (b) added exactly one.

- [ ] **Step 5: Document it** — In `docs/guides/swiflowui-theming.md`, under "Re-skinning via tokens" (the section showing a `:root` override), add this note:

```markdown
> Your `:root` overrides win because SwiflowUI's base tokens ship in `@layer swiflow.base`
> — any unlayered rule (your `index.html`, a `swiflow theme` `theme.css`, the `Theme`
> component) beats a layer regardless of source order, so the override applies even though
> the base sheet is injected at runtime.
```

- [ ] **Step 6: Commit**
```bash
git add Sources/SwiflowUI/Theme.swift Tests/SwiflowUITests/ThemeTests.swift docs/guides/swiflowui-theming.md
git commit -m "fix(swiflowui): wrap base tokens in @layer swiflow.base so app overrides win"
```

---

### Task 2: Playwright proof — an app `:root` override wins

**Files:**
- Modify: `Tests/playwright/theming.spec.ts` (add one test inside the existing `test.describe`)

- [ ] **Step 1: Write the test** — Add inside the `test.describe("SwiflowUI theming responds to media features", …)` block in `Tests/playwright/theming.spec.ts`:

```ts
  test("an app :root --sw-accent override (in <head>) wins over the base sheet", async ({ page }) => {
    // Inject a static override into the INITIAL HTML <head> — i.e. parsed before the
    // runtime-appended base sheet. It only wins if base tokens are in @layer swiflow.base
    // (unlayered beats layered regardless of source order). Use rgb() so the computed
    // value is unambiguous and scheme-independent (no light-dark()).
    await page.route("**/*", async (route) => {
      if (route.request().resourceType() !== "document") return route.continue();
      const res = await route.fetch();
      const html = (await res.text()).replace(
        "</head>",
        "<style>:root { --sw-accent: rgb(225, 29, 72) }</style></head>"
      );
      await route.fulfill({ response: res, body: html });
    });
    await gotoMounted(page);
    const bg = await page.getByRole("button", { name: "Increment" })
      .evaluate((el) => getComputedStyle(el).backgroundColor);
    expect(bg).toBe("rgb(225, 29, 72)");
  });
```

- [ ] **Step 2: Build the release CLI first** (the e2e harness reuses the binary — a stale one scaffolds the old example):

Run: `swift build -c release --product swiflow`
Expected: `Build of product 'swiflow' complete!`

- [ ] **Step 3: Run the theming spec** — Run: `cd Tests/playwright && npx playwright test theming.spec.ts`
Expected: PASS — the new override test **and** the existing media-feature tests (color-scheme flip, reduced-motion, contrast). The latter passing confirms the `@layer` wrap didn't break the `@media` token layers.

- [ ] **Step 4: Confirm the test is meaningful** (it must catch the bug it guards). Temporarily undo the fix and confirm the new test FAILS:

```bash
git stash push -- Sources/SwiflowUI/Theme.swift
swift build -c release --product swiflow
cd Tests/playwright && npx playwright test theming.spec.ts -g "wins over the base sheet"   # expect FAIL (bg is the default blue)
cd - && git stash pop
swift build -c release --product swiflow   # restore the fix in the binary
```
Expected: FAILS while stashed (proving it catches the regression), PASSES after `git stash pop`.

- [ ] **Step 5: Commit**
```bash
git add Tests/playwright/theming.spec.ts
git commit -m "test(e2e): app :root token override wins over the @layer base sheet"
```

---

### Task 3: Wire the generated palette into the demo

**Files:**
- Create: `examples/SwiflowUIDemo/theme.css` (generated)
- Modify: `examples/SwiflowUIDemo/index.html` (link it)
- Modify: `Sources/SwiflowCLI/EmbeddedTemplates.swift` (regen)

- [ ] **Step 1: Generate the palette** — Run (release CLI is built from Task 2):
```bash
.build/release/swiflow theme --primary "#7c3aed" --neutrals --out examples/SwiflowUIDemo/theme.css
```
Expected: writes `theme.css` containing `:root { --sw-accent…; --sw-bg…; … }` + a `@media (prefers-contrast: more)` block. Confirm it exists and is non-empty.

- [ ] **Step 2: Link it in the demo** — In `examples/SwiflowUIDemo/index.html`, add this line inside `<head>`, immediately AFTER the existing `</style>` (so it's an unlayered override the base layer can't beat):

```html
    <link rel="stylesheet" href="theme.css" />
```

- [ ] **Step 3: Regenerate the embedded templates** (SwiflowUIDemo is an embedded `swiflow init` template — a CI freshness gate asserts `EmbeddedTemplates.swift` is current):

Run: `swift scripts/embed-templates.swift`
Expected: `wrote …/EmbeddedTemplates.swift`. `git status` shows `Sources/SwiflowCLI/EmbeddedTemplates.swift` modified (it now embeds `theme.css` + the `index.html` change).

- [ ] **Step 4: Verify freshness + build** — Run: `swift test --filter TemplateEmbedderTests`
Expected: PASS (the bit-for-bit `EmbeddedTemplates.swift` test is green after the regen).

Then build the demo to confirm it compiles and the static `theme.css` is served:
Run: `.build/release/swiflow build --path examples/SwiflowUIDemo`
Expected: `build complete.`

- [ ] **Step 5: Eyeball (manual, local — CI skips example builds)** — Serve and confirm the whole gallery re-skins violet (surfaces/text/borders carry the faint accent tint, buttons branded), readable in light + dark, proving the generated `theme.css` actually wins the cascade. Note: the build stamps `swiflow-service-worker.js`/driver — `git checkout --` those after; keep only `theme.css` + `index.html` + `EmbeddedTemplates.swift`.

- [ ] **Step 6: Commit**
```bash
git add examples/SwiflowUIDemo/theme.css examples/SwiflowUIDemo/index.html Sources/SwiflowCLI/EmbeddedTemplates.swift
git commit -m "docs(demo): wire a generated --neutrals palette into SwiflowUIDemo"
```

---

## Final verification (after all tasks)

- [ ] `swift test` → all green (the `@layer` unit assertion + `TemplateEmbedderTests` + everything else).
- [ ] `cd Tests/playwright && npx playwright test theming.spec.ts` → all green (override + media specs), with the release CLI freshly built.
- [ ] `git status` clean except the intended files (no stray stamped SW/driver artifacts committed).
- [ ] Dispatch the final code reviewer over the whole branch (this fix + the neutral-palette feature).

## Notes for the implementer

- **Only `baseStyleSheet` changes in shipping code** — do NOT touch the generator, `Theme`, the M8 contrast tokens, or any component sheet; they're already unlayered and keep winning.
- **The `@layer` ordering is automatic:** the reset layer is injected first (lowest), `swiflow.base` second; no explicit `@layer reset, swiflow.base;` statement is required (but it's harmless if you prefer to add one at the very top of the raw string).
- **Playwright is local-only** — CI skips example builds and the WASM e2e gate ([[run-e2e-locally-before-push]] / [[ci-skips-example-builds]]); rebuild the release CLI before each Playwright run.
- **The demo touches `examples/`** → `EmbeddedTemplates.swift` MUST be regenerated and committed, or CI's freshness gate fails (the lesson from PR #68).
