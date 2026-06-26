# `@property` registration + style-query spike — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Register the safe `--sw-*` tokens with `@property` (typed + animatable), conditionally register color tokens behind an empirical fallback proof, and investigate `@container style()` as a non-shipped proof-of-concept — all without touching the `-strong` tint-text mechanism.

**Architecture:** All shipped change is additive CSS in one raw string (`SwiflowUI.baseStyleSheet`, `Sources/SwiflowUI/Theme.swift`). `@property` at-rules go *outside* the `@layer swiflow.base { … }` wrapper (the at-rule is layer-agnostic). Verification is layered: emitted-CSS unit tests (durable contract) + a host build (CI skips examples) + local Playwright probes against the counter demo + a demo eyeball. The style-query work is a throwaway, reverted before merge.

**Tech Stack:** Swift (SwiflowUI module), Swift Testing (`@Suite`/`@Test`/`#expect`), Playwright (`Tests/playwright/theming.spec.ts`, runs against the counter/HelloWorld demo on `:3000`).

---

## Context every task needs

- **Spec:** `docs/superpowers/specs/2026-06-26-swiflowui-property-style-queries-design.md`.
- **The file under change:** `Sources/SwiflowUI/Theme.swift`. The token contract is one raw multiline string inside `baseStyleSheet` (lines ~37–170). The string begins:
  ```
          raw("""
          @layer swiflow.base {
          :root {
            color-scheme: light dark;
            ...
  ```
  Swift strips the 8-space delimiter indentation, so in the *emitted* CSS `@layer swiflow.base {` has zero leading spaces. **Keep the 8-space source indentation** on every line you add inside the `"""` so the output stays clean.
- **The `-strong` mechanism is OUT OF SCOPE.** Do not edit lines 79–93 or any component's text color. This spike must be a visual no-op.
- **Test runner:** `swift test --filter ThemeTests` runs the SwiflowUI theme suite. `swift build` (host) is the authoritative compile check because CI skips example builds.
- **Playwright protocol (memories [[run-e2e-locally-before-push]], [[no-subagent-playwright]]):** ALWAYS `swift build -c release --product swiflow` first (the harness reuses the binary by size+mtime stamp; a stale binary scaffolds the old demo). Run inline/detached, never via a subagent, after killing leftovers on the ports.

---

## Task 1: Register scalar (non-color) tokens — Unit A (ships)

**Files:**
- Modify: `Sources/SwiflowUI/Theme.swift` (insert before `@layer swiflow.base {`)
- Test: `Tests/SwiflowUITests/ThemeTests.swift`

- [ ] **Step 1: Write the failing unit test**

Add this `@Test` inside `struct ThemeTests` in `Tests/SwiflowUITests/ThemeTests.swift` (after the existing `forwardContractTokens` test):

```swift
@Test("Scalar tokens are registered with @property (typed + animatable)") func scalarPropertyRegistration() {
    let css = sheet
    // The @property block must be emitted OUTSIDE @layer swiflow.base (layer-agnostic at-rule).
    #expect(css.contains("@property --sw-border-width"))
    #expect(css.contains("@property --sw-duration"))
    #expect(css.contains("@property --sw-radius"))
    #expect(css.contains("@property --sw-disabled-opacity"))
    // Each registration carries syntax + inherits + initial-value.
    #expect(css.contains(#"@property --sw-border-width { syntax: "<length>"; inherits: true; initial-value: 1px; }"#))
    #expect(css.contains(#"@property --sw-duration { syntax: "<time>"; inherits: true; initial-value: 150ms; }"#))
    #expect(css.contains(#"@property --sw-disabled-opacity { syntax: "<number>"; inherits: true; initial-value: 0.5; }"#))
    // The block precedes the cascade layer in source order.
    let propIdx = css.range(of: "@property --sw-space-xs")!.lowerBound
    let layerIdx = css.range(of: "@layer swiflow.base")!.lowerBound
    #expect(propIdx < layerIdx)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ThemeTests/scalarPropertyRegistration`
Expected: FAIL — the `@property` strings are not yet emitted (`#expect` failures on `contains`).

- [ ] **Step 3: Add the `@property` block to `baseStyleSheet`**

In `Sources/SwiflowUI/Theme.swift`, find the opening of the raw string:

```swift
        raw("""
        @layer swiflow.base {
```

Replace it with (note: 8-space source indentation preserved; blank-line + comment for readers):

```swift
        raw("""
        /* Register the scalar tokens so they are TYPE-VALIDATED and ANIMATABLE.
           @property is layer-agnostic, so these sit outside @layer swiflow.base.
           initial-value is the bottom-of-cascade fallback only — :root below always
           sets each token, and unlayered app overrides still win. */
        @property --sw-space-xs { syntax: "<length>"; inherits: true; initial-value: 0.25rem; }
        @property --sw-space-sm { syntax: "<length>"; inherits: true; initial-value: 0.5rem; }
        @property --sw-space-md { syntax: "<length>"; inherits: true; initial-value: 0.75rem; }
        @property --sw-space-lg { syntax: "<length>"; inherits: true; initial-value: 1.25rem; }
        @property --sw-space-xl { syntax: "<length>"; inherits: true; initial-value: 2rem; }
        @property --sw-radius-sm { syntax: "<length>"; inherits: true; initial-value: 4px; }
        @property --sw-radius { syntax: "<length>"; inherits: true; initial-value: 8px; }
        @property --sw-border-width { syntax: "<length>"; inherits: true; initial-value: 1px; }
        @property --sw-focus-ring-width { syntax: "<length>"; inherits: true; initial-value: 2px; }
        @property --sw-duration { syntax: "<time>"; inherits: true; initial-value: 150ms; }
        @property --sw-disabled-opacity { syntax: "<number>"; inherits: true; initial-value: 0.5; }

        @layer swiflow.base {
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter ThemeTests`
Expected: PASS — `scalarPropertyRegistration` green, and all pre-existing ThemeTests still green (the additions don't alter any existing assertion).

- [ ] **Step 5: Host build (authoritative — CI skips examples)**

Run: `swift build`
Expected: exit 0, no warnings about the changed file.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowUI/Theme.swift Tests/SwiflowUITests/ThemeTests.swift
git commit -m "feat(swiflowui): register scalar --sw-* tokens with @property

Typed + animatable spacing/radius/border-width/focus-ring-width/duration/opacity
tokens. @property emitted outside @layer swiflow.base (layer-agnostic). Visual
no-op; -strong untouched.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Runtime proof that scalar registration is active — Unit A (ships)

**Files:**
- Test: `Tests/playwright/theming.spec.ts`

- [ ] **Step 1: Add the registration probe**

Append this test inside the `test.describe("SwiflowUI theming responds to media features", … )` block in `Tests/playwright/theming.spec.ts` (after the warning/info test):

```ts
test("registered scalar tokens reject invalid values (proves @property is live)", async ({ page }) => {
  // A registered <length> property rejects an invalid value at computed-value time,
  // so the element keeps the inherited :root value (1px). An UNregistered custom
  // property would instead echo the raw "banana" string. Reading getComputedStyle
  // (not .style) is what surfaces the registration.
  await gotoMounted(page);
  const resolved = await page.evaluate(() => {
    const el = document.createElement("span");
    document.body.appendChild(el);
    el.style.setProperty("--sw-border-width", "banana");
    const v = getComputedStyle(el).getPropertyValue("--sw-border-width").trim();
    el.remove();
    return v;
  });
  expect(resolved).toBe("1px"); // invalid value rejected → inherited, not "banana"
});
```

- [ ] **Step 2: Build the release CLI (required before Playwright)**

Run: `swift build -c release --product swiflow`
Expected: exit 0. This refreshes the binary stamp so the harness re-scaffolds with the registered tokens.

- [ ] **Step 3: Kill any leftover dev servers, then run the spec inline**

```bash
lsof -ti:3000,3001,3002,3003 | xargs kill -9 2>/dev/null; \
cd Tests/playwright && npx playwright test theming.spec.ts --project=chromium
```
Expected: all theming tests PASS, including `registered scalar tokens reject invalid values`. (Cold WASM build can take ~3 min on first run.)

- [ ] **Step 4: Commit**

```bash
git add Tests/playwright/theming.spec.ts
git commit -m "test(e2e): probe that @property scalar registration is live

A registered <length> rejects an invalid override (keeps inherited 1px); an
unregistered custom prop would echo the raw string.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Color-token registration — Unit B (conditional ship, decision gate)

**Files:**
- Modify: `Sources/SwiflowUI/Theme.swift`
- Test: `Tests/SwiflowUITests/ThemeTests.swift`, `Tests/playwright/theming.spec.ts`

**Gate:** ship color registration only if Steps 4–7 are all clean. If any shows a regression, execute Step 8 (revert + document defer) instead of Step 9.

- [ ] **Step 1: Write the failing unit test (double-declaration must survive)**

Add to `struct ThemeTests` in `Tests/SwiflowUITests/ThemeTests.swift`:

```swift
@Test("Color tokens are registered AND keep their literal→oklch double-declaration") func colorPropertyRegistration() {
    let css = sheet
    #expect(css.contains(#"@property --sw-accent { syntax: "<color>"; inherits: true; initial-value: #3b82f6; }"#))
    #expect(css.contains(#"@property --sw-bg { syntax: "<color>"; inherits: true; initial-value: #f6f7f9; }"#))
    // The progressive fallback MUST stay physically present: literal line first,
    // oklch(from …) line second. Registration must not collapse it.
    #expect(css.contains("--sw-accent-hover: light-dark(#"))
    #expect(css.contains("--sw-accent-hover: light-dark(oklch(from var(--sw-accent)"))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ThemeTests/colorPropertyRegistration`
Expected: FAIL — color `@property` rules not yet emitted.

- [ ] **Step 3: Add the color `@property` rules**

In `Sources/SwiflowUI/Theme.swift`, find the `@property --sw-disabled-opacity` line added in Task 1 and insert the color block immediately after it (before the blank line and `@layer swiflow.base {`). **`initial-value` for a `<color>` must be a plain, computation-independent color — `light-dark()` is NOT allowed there, so use the light-arm hex** (it is only the bottom-of-cascade fallback, never hit while `:root` sets the token):

```swift
        @property --sw-disabled-opacity { syntax: "<number>"; inherits: true; initial-value: 0.5; }
        /* Color tokens registered as <color>. initial-value must be computation-independent
           (no light-dark()/var()/relative color) — the light-arm hex is the fallback floor.
           The literal→oklch(from) double-declarations in :root are unaffected: an unsupported
           oklch(from …) is rejected at PARSE time (before registered-syntax validation), so the
           literal still wins on pre-Baseline engines exactly as before registration. */
        @property --sw-bg { syntax: "<color>"; inherits: true; initial-value: #f6f7f9; }
        @property --sw-surface { syntax: "<color>"; inherits: true; initial-value: #ffffff; }
        @property --sw-surface-2 { syntax: "<color>"; inherits: true; initial-value: #f3f4f6; }
        @property --sw-text { syntax: "<color>"; inherits: true; initial-value: #111111; }
        @property --sw-text-muted { syntax: "<color>"; inherits: true; initial-value: #5b616b; }
        @property --sw-accent { syntax: "<color>"; inherits: true; initial-value: #3b82f6; }
        @property --sw-accent-hover { syntax: "<color>"; inherits: true; initial-value: #2563eb; }
        @property --sw-accent-active { syntax: "<color>"; inherits: true; initial-value: #1d4ed8; }
        @property --sw-accent-text { syntax: "<color>"; inherits: true; initial-value: #0b1220; }
        @property --sw-danger { syntax: "<color>"; inherits: true; initial-value: #dc2626; }
        @property --sw-success { syntax: "<color>"; inherits: true; initial-value: #16a34a; }
        @property --sw-warning { syntax: "<color>"; inherits: true; initial-value: #b45309; }
        @property --sw-info { syntax: "<color>"; inherits: true; initial-value: #3b82f6; }
        @property --sw-accent-strong { syntax: "<color>"; inherits: true; initial-value: #1d4ed8; }
        @property --sw-danger-strong { syntax: "<color>"; inherits: true; initial-value: #b91c1c; }
        @property --sw-success-strong { syntax: "<color>"; inherits: true; initial-value: #15803d; }
        @property --sw-warning-strong { syntax: "<color>"; inherits: true; initial-value: #92400e; }
        @property --sw-info-strong { syntax: "<color>"; inherits: true; initial-value: #1d4ed8; }
        @property --sw-border { syntax: "<color>"; inherits: true; initial-value: #e5e7eb; }
        @property --sw-focus-ring { syntax: "<color>"; inherits: true; initial-value: #3b82f6; }
```

> NOTE: `--sw-shadow`, `--sw-overlay-bg`, `--sw-backdrop` are deliberately **excluded** — they are shadow/length/filter values, not plain `<color>`.

- [ ] **Step 4: Run unit tests — both-declarations-present gate**

Run: `swift test --filter ThemeTests`
Expected: PASS — `colorPropertyRegistration` green (proves the literal AND oklch lines both still emit) and every pre-existing ThemeTests/ThemeContrastTests assertion green.

- [ ] **Step 5: Host build gate**

Run: `swift build`
Expected: exit 0.

- [ ] **Step 6: Demo-eyeball gate (registration must be a visual no-op)**

Run: `swift build -c release --product swiflow && .build/release/swiflow build --path examples/SwiflowUIDemo`
Then open `examples/SwiflowUIDemo/dist/index.html` (or serve it) and confirm the gallery — badges, buttons, surfaces — renders **identically** to before (compare against a quick `git stash`-ed screenshot if unsure).
Expected: no visual difference; build exits 0.

- [ ] **Step 7: Runtime gate — registered color is active and harmless**

Add to `Tests/playwright/theming.spec.ts` (inside the same describe block):

```ts
test("registered color tokens are active and harmless (Unit B gate)", async ({ page }) => {
  // A registered <color> resolves normally AND rejects an invalid override (the element
  // inherits the :root value rather than echoing garbage) — proving registration is live
  // without changing any rendered color. An unregistered prop would echo "not-a-color".
  await gotoMounted(page);
  const r = await page.evaluate(() => {
    const accent = getComputedStyle(document.documentElement).getPropertyValue("--sw-accent").trim();
    const el = document.createElement("span");
    document.body.appendChild(el);
    el.style.setProperty("--sw-accent", "not-a-color");
    const overridden = getComputedStyle(el).getPropertyValue("--sw-accent").trim();
    el.remove();
    return { accent, overridden };
  });
  expect(r.accent).not.toBe("");          // base sheet resolves to a real color
  expect(r.overridden).toBe(r.accent);    // invalid override rejected → inherited, not "not-a-color"
});
```

Run (CLI already release-built in Step 6):
```bash
lsof -ti:3000,3001,3002,3003 | xargs kill -9 2>/dev/null; \
cd Tests/playwright && npx playwright test theming.spec.ts --project=chromium
```
Expected: all theming tests PASS, including the Unit B gate.

- [ ] **Step 8: IF any gate (Steps 4–7) regressed — revert color registration + record defer**

Only if a gate failed:
```bash
git checkout Sources/SwiflowUI/Theme.swift   # drop the color @property block
# remove colorPropertyRegistration from ThemeTests.swift and the Unit B gate test
#   from theming.spec.ts (Task 1/2 changes stay)
```
Note the exact failure (which gate, observed vs expected) verbatim — it becomes the "color registration: DEFERRED" entry in Task 5's findings doc. Then skip Step 9 and proceed to Task 4.

- [ ] **Step 9: IF all gates clean — commit color registration**

```bash
git add Sources/SwiflowUI/Theme.swift Tests/SwiflowUITests/ThemeTests.swift Tests/playwright/theming.spec.ts
git commit -m "feat(swiflowui): register color --sw-* tokens with @property

<color>-typed tokens; literal→oklch(from) double-declaration verified intact
(parse-time fallback unaffected by registration). Visual no-op confirmed by
host build + demo eyeball + runtime probe.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: `@container style()` proof-of-concept — Unit C (NON-SHIPPED, reverted)

**Goal:** Prove the `@container style()` + `contrast-color()` micro-theming pattern survives our dev + minified-build pipeline, then **revert all code**. The only durable output is findings text for Task 5. Do **not** commit any code from this task.

**Files (all reverted before the task ends):**
- Temporarily modify: `Sources/SwiflowUI/Badge.swift`

- [ ] **Step 1: Add a throwaway style-query block to the Badge sheet**

In `Sources/SwiflowUI/Badge.swift`, inside `badgeStyleSheet`'s `raw("""…""")`, append this block before the closing `"""` (it sets a detector token and branches text via a style query, behind `@supports` so non-supporting engines keep the shipped `-strong` rules above):

```css
/* SPIKE — NON-SHIPPED proof-of-concept. Revert before merge. */
@supports (container-type: normal) and (color: contrast-color(red)) {
  .sw-badge--accent {
    --sw-detector: contrast-color(color-mix(in oklab, var(--sw-accent) 15%, var(--sw-surface)));
    container-name: badge;
    container-type: normal;
  }
  @container badge style(--sw-detector: white) {
    .sw-badge--accent { outline: 2px dashed magenta; } /* visible marker that the branch fired */
  }
}
```

- [ ] **Step 2: Build dev + release and confirm the syntax survives our pipeline**

```bash
swift build -c release --product swiflow
.build/release/swiflow build --path examples/SwiflowUIDemo
grep -o "@container badge style" examples/SwiflowUIDemo/dist/assets/*.css || echo "NOT FOUND in minified output"
```
Record: does `@container … style(…)` survive minification (FOUND vs NOT FOUND)? Does `.build/release/swiflow dev --path examples/SwiflowUIDemo` serve it without a CSS parse error in the browser console? Does the magenta marker render on a supporting engine (Chrome) and is it absent (clean fallback to `-strong`) when you toggle `@supports` off by editing the condition?

- [ ] **Step 3: Capture findings, then REVERT**

Write down (for Task 5): pipeline-survival (dev + minified), render result, and an explicit **adopt / defer** recommendation weighing the Firefox `style()` gap, the per-component `@supports` duplication cost, and that `-strong` already solves the readability problem cross-engine.

Then revert every change from this task:
```bash
git checkout Sources/SwiflowUI/Badge.swift
git status   # MUST show Badge.swift unmodified; no Unit C code is committed
```
Expected: `git status` clean for `Badge.swift`. **Do not commit anything in this task.**

---

## Task 5: Findings doc + roadmap update (ships)

**Files:**
- Create: `docs/future-work/swiflowui-property-style-queries-findings.md`
- Modify: `docs/future-work/swiflowui-1.0-roadmap.md`

- [ ] **Step 1: Write the findings doc**

Create `docs/future-work/swiflowui-property-style-queries-findings.md` with this content, filling the bracketed verdicts from Task 3 (Step 8/9 outcome) and Task 4 (Step 3 notes):

```markdown
# SwiflowUI `@property` + style-query spike — Findings

> Spike from `docs/superpowers/specs/2026-06-26-swiflowui-property-style-queries-design.md`.
> Source: Una Kravets, "Modern CSS Theming" (una.im, 2026).

## Shipped

- **Scalar `@property` registration** — spacing, radii, border/focus widths, duration,
  opacity are now type-validated and animatable. Visual no-op; proven live by a Playwright
  invalid-override probe.

## Color-token registration — [SHIPPED | DEFERRED]

[If SHIPPED:] Color tokens registered as `<color>` with light-arm-hex initial-values. The
literal→`oklch(from …)` double-declaration is preserved — an unsupported relative-color value
is rejected at **parse time**, before registered-syntax validation, so pre-Baseline engines
still fall back to the literal exactly as before registration. Verified by: emitted-CSS
both-declarations test, host build, demo eyeball (no visual change), and a runtime probe
(invalid override falls to the inherited value, not garbage).

[If DEFERRED:] Not registered. Observed regression: [exact gate + observed-vs-expected from
Task 3 Step 8]. The scalar registration ships regardless.

## `@container style()` — investigation only, [ADOPT | DEFER]

Pipeline survival (dev + minified `swiflow build`): [FOUND/parsed cleanly | issue]. Render on a
supporting engine: [magenta marker fired | …]. Fallback on `@supports`-off: [clean `-strong`].

Recommendation: **[ADOPT later | DEFER]**. Rationale: `@container style()` on custom properties
has **no Firefox support** as of 2026, so it can only ever be a progressive enhancement layered
over `-strong` — which already solves tint-text readability in every engine. Adopting it now adds
per-component `@supports` duplication for a cosmetic gain on two of three engines. `@property`
registration (shipped) is the prerequisite already in place if/when we revisit.

## Browser baseline (2026)

| Feature | Chrome | Safari | Firefox |
|---------|--------|--------|---------|
| `@property` registration | ✅ | ✅ | ✅ |
| `light-dark()` / relative color | ✅ | ✅ | ✅ |
| `@container style()` (custom props) | ✅ | ✅ | ❌ |
| `contrast-color()` | ✅ | ✅ | ⚠️ partial |
| `@function` | ⚠️ 139+ | ❌ | ❌ |
```

- [ ] **Step 2: Update the M9 roadmap entry**

In `docs/future-work/swiflowui-1.0-roadmap.md`, edit the `### M9 (1.1) — Modern CSS theming primitives — candidate` section: change the `@property` bullet to mark it shipped and link the findings, and record the two verdicts. Replace the `@property` bullet and append a results line:

```markdown
- **✅ `@property` registration (this spike)** — scalar `--sw-*` tokens registered (typed +
  animatable); color tokens [registered | deferred, see findings]. Full results +
  `@container style()` adopt/defer call in
  [`swiflowui-property-style-queries-findings.md`](swiflowui-property-style-queries-findings.md).
```

(Leave the `@container style()` and `contrast-color()` bullets as candidates; the findings doc now carries their verdict.)

- [ ] **Step 3: Final verification**

```bash
swift test --filter ThemeTests
swift build
git status --short examples/   # MUST be empty — no example/embed churn (Unit C reverted)
```
Expected: ThemeTests green; build exit 0; `examples/` clean (so the `TemplateEmbedder` freshness gate stays green).

- [ ] **Step 4: Commit**

```bash
git add docs/future-work/swiflowui-property-style-queries-findings.md docs/future-work/swiflowui-1.0-roadmap.md
git commit -m "docs(swiflowui): @property/style-query spike findings + M9 roadmap update

Records the shipped scalar (and color, if applicable) @property registration, and
the @container style() adopt/defer recommendation (Firefox-unsupported → defer;
-strong stays the cross-engine tint-text mechanism).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final review (after all tasks)

Dispatch a final code-review subagent over the whole branch diff (`git diff origin/main`), then open the PR. The shipped diff must be: `Theme.swift` (`@property` block), `ThemeTests.swift` (1–2 new tests), `theming.spec.ts` (1–2 new probes), the findings doc, and the roadmap edit — and **nothing** under `examples/` or `Sources/SwiflowUI/Badge.swift`.
