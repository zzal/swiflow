# SwiflowUI `--sw-warning` / `--sw-info` Tokens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--sw-warning` (new amber) and `--sw-info` (accent alias) status tokens to SwiflowUI's base sheet, wire them into `Badge`/`Toast`, and add validated `--warning`/`--info` seeds to `swiflow theme`.

**Architecture:** `--sw-warning` gets the full four-layer treatment danger/success have (`:root` default, `-strong` literal-fallback + `oklch(from …)` derivation, `prefers-contrast: more`, P3). `--sw-info` is `var(--sw-accent)` (alias; 3 layers, no P3 — it inherits the accent's). `Badge` gains `info`/`warning` variants, `Toast` gains `warning` + the currently-missing `.sw-toast--info` rule. The generator threads two more optional seeds through `accentThemeCSS`, reusing `validateStatusFamily` at the 3:1 raw bar (both are border/tint colors).

**Tech Stack:** Swift 6, Swift Testing (`@Suite`/`@Test`/`#expect`), swift-argument-parser, native-only `SwiflowColor`, Playwright, the `swiflow` CLI.

**Spec:** [`docs/superpowers/specs/2026-06-26-swiflowui-warning-info-tokens-design.md`](../specs/2026-06-26-swiflowui-warning-info-tokens-design.md)

**Branch:** `feat/swiflowui-warning-info-tokens` (already created off `origin/main`, which includes the #71 status-seeds work; the spec is committed there).

---

## File Structure

| File | Change |
|------|--------|
| `Sources/SwiflowUI/Theme.swift` | `--sw-warning` (4 layers) + `--sw-info` (3 layers, no P3) in `baseStyleSheet` |
| `Tests/SwiflowUITests/ThemeTests.swift` | assert the new tokens across layers; extend the forward-contract list |
| `Sources/SwiflowUI/Badge.swift` | `BadgeVariant.info`/`.warning` + two CSS rules |
| `Sources/SwiflowUI/Toast.swift` | `ToastVariant.warning` + `.sw-toast--info`/`--warning` rules |
| `Tests/SwiflowUITests/FeedbackTests.swift` | Badge `.info`/`.warning` variant + stylesheet assertions |
| `Tests/SwiflowUITests/ToastTests.swift` | Toast `.warning` variant + politeness |
| `Sources/SwiflowColor/ContrastColor.swift` | `accentThemeCSS` gains `warningHex:`/`infoHex:` |
| `Tests/SwiflowColorTests/AccentThemeTests.swift` | emit/order/byte-compat; shipped-warning-default guard |
| `Sources/SwiflowCLI/Commands/ThemeCommand.swift` | `--warning`/`--info` flags |
| `Tests/SwiflowCLITests/ThemeCommandTests.swift` | flag wiring |
| `examples/SwiflowUIDemo/Sources/App/App.swift` | gallery: warning/info badges + toasts |
| `Sources/SwiflowCLI/EmbeddedTemplates.swift` | regen (demo is an embedded template) |
| `Tests/playwright/theming.spec.ts` | a warning Badge renders the amber token |
| `docs/guides/swiflowui-theming.md`, `docs/future-work/swiflowui-1.0-roadmap.md` | docs |

**Swift Testing filter gotcha:** `swift test --filter` matches **type** names (e.g. `ThemeTests`), never the `@Suite` string. "0 tests in 0 suites" means the filter matched nothing, not a pass.

**Reference — current danger/success lines in `Theme.swift` `baseStyleSheet` (mirror these exactly):**
- `:root` (after line ~76): `--sw-danger: light-dark(#dc2626, #f87171);` / `--sw-success: light-dark(#16a34a, #4ade80);`
- base `-strong` (after ~87): the literal-fallback line then the `oklch(from var(--sw-X) 0.40 c h / 0.80 c h)` line, for danger and success.
- `prefers-contrast: more` (after ~128): `--sw-X-strong: light-dark(oklch(from var(--sw-X) 0.30 c h), oklch(from var(--sw-X) 0.88 c h));`
- P3 (after ~155): `--sw-success: light-dark(color(display-p3 …), color(display-p3 …));`

The whole `baseStyleSheet` body is wrapped in `@layer swiflow.base { … }` — keep all additions inside it (they are, since they sit among the existing token lines).

---

### Task 1: `--sw-warning` / `--sw-info` base-sheet tokens

**Files:**
- Modify: `Sources/SwiflowUI/Theme.swift`
- Modify: `Tests/SwiflowUITests/ThemeTests.swift`

- [ ] **Step 1: Write the failing tests** — In `Tests/SwiflowUITests/ThemeTests.swift`, add a `@Test` inside `struct ThemeTests` (before its closing `}`), and extend the forward-contract token list.

  (a) Add this test:
```swift
    @Test("warning/info status tokens are present across the right layers") func warningInfoTokens() {
        let css = sheet
        // :root defaults — warning is a literal amber; info aliases the accent.
        #expect(css.contains("--sw-warning: light-dark(#b45309, #fbbf24)"))
        #expect(css.contains("--sw-info: var(--sw-accent)"))
        // -strong derivations exist for both.
        #expect(css.contains("--sw-warning-strong: light-dark(oklch(from var(--sw-warning) 0.40 c h)"))
        #expect(css.contains("--sw-info-strong: light-dark(oklch(from var(--sw-info) 0.40 c h)"))
        // more-contrast pushes both strong tokens to the 0.30/0.88 band.
        #expect(css.contains("--sw-warning-strong: light-dark(oklch(from var(--sw-warning) 0.30 c h)"))
        #expect(css.contains("--sw-info-strong: light-dark(oklch(from var(--sw-info) 0.30 c h)"))
        // warning has its own P3 raw line; info does NOT (it inherits the accent's via var()).
        #expect(css.contains("--sw-warning: light-dark(color(display-p3"))
        #expect(!css.contains("--sw-info: light-dark(color(display-p3"))
        // wrapping kept braces balanced.
        #expect(css.filter { $0 == "{" }.count == css.filter { $0 == "}" }.count)
    }
```

  (b) In `forwardContractTokens()`, add `"--sw-warning"`, `"--sw-info"`, `"--sw-warning-strong"`, `"--sw-info-strong"` to the token array (any position).

- [ ] **Step 2: Run to verify it fails** — `swift test --filter ThemeTests`
Expected: FAIL — `warningInfoTokens` and `forwardContractTokens` fail (tokens not in the sheet yet).

- [ ] **Step 3: Implement** — In `Sources/SwiflowUI/Theme.swift`, make four edits inside `baseStyleSheet`:

  (a) After `          --sw-success: light-dark(#16a34a, #4ade80);` add:
```
          --sw-warning: light-dark(#b45309, #fbbf24);
          --sw-info: var(--sw-accent);
```

  (b) After the success `-strong` derived line `          --sw-success-strong: light-dark(oklch(from var(--sw-success) 0.40 c h), oklch(from var(--sw-success) 0.80 c h));` add:
```
          --sw-warning-strong: light-dark(#92400e, #fbbf24);
          --sw-warning-strong: light-dark(oklch(from var(--sw-warning) 0.40 c h), oklch(from var(--sw-warning) 0.80 c h));
          --sw-info-strong: var(--sw-accent-strong);
          --sw-info-strong: light-dark(oklch(from var(--sw-info) 0.40 c h), oklch(from var(--sw-info) 0.80 c h));
```

  (c) In the `@media (prefers-contrast: more)` block, after `            --sw-success-strong: light-dark(oklch(from var(--sw-success) 0.30 c h), oklch(from var(--sw-success) 0.88 c h));` add:
```
            --sw-warning-strong: light-dark(oklch(from var(--sw-warning) 0.30 c h), oklch(from var(--sw-warning) 0.88 c h));
            --sw-info-strong: light-dark(oklch(from var(--sw-info) 0.30 c h), oklch(from var(--sw-info) 0.88 c h));
```

  (d) In the `@media (color-gamut: p3)` `:root`, after `              --sw-success: light-dark(color(display-p3 0.15 0.63 0.32), color(display-p3 0.42 0.86 0.55));` add (warning only — info inherits the accent's P3):
```
              --sw-warning: light-dark(color(display-p3 0.68 0.33 0.04), color(display-p3 0.98 0.75 0.14));
```

- [ ] **Step 4: Run to verify it passes** — `swift test --filter ThemeTests`
Expected: PASS — `warningInfoTokens`, `forwardContractTokens`, and all existing ThemeTests (`mediaLayersEmitted`, `overridesComeAfterBase`, the braces/contrast checks) stay green.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowUI/Theme.swift Tests/SwiflowUITests/ThemeTests.swift
git commit -m "feat(swiflowui): add --sw-warning (amber) and --sw-info (accent alias) tokens"
```

---

### Task 2: `Badge` info/warning variants

**Files:**
- Modify: `Sources/SwiflowUI/Badge.swift`
- Modify: `Tests/SwiflowUITests/FeedbackTests.swift` (the `@Suite("Badge")`)

- [ ] **Step 1: Write the failing tests** — In `Tests/SwiflowUITests/FeedbackTests.swift`, add to the `@Suite("Badge")` struct (before its closing `}`):
```swift
    @Test("info and warning variants map to their modifier classes") func infoWarningVariants() {
        #expect(el(Badge("i", variant: .info))!.attributes["class"] == "sw-badge sw-badge--info")
        #expect(el(Badge("w", variant: .warning))!.attributes["class"] == "sw-badge sw-badge--warning")
    }

    @Test("info/warning stylesheet rules use the matching token tint + -strong text") func infoWarningStylesheet() {
        _ = Badge("x")  // installs the sheet
        let sheet = badgeStyleSheet.cssString(scopeClass: "")
        #expect(sheet.contains(".sw-badge--info"))
        #expect(sheet.contains("var(--sw-info) 15%"))
        #expect(sheet.contains("color: var(--sw-info-strong)"))
        #expect(sheet.contains(".sw-badge--warning"))
        #expect(sheet.contains("var(--sw-warning) 15%"))
        #expect(sheet.contains("color: var(--sw-warning-strong)"))
    }
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter FeedbackTests`
Expected: FAIL to compile — `BadgeVariant` has no `.info`/`.warning` cases.

- [ ] **Step 3: Implement** — In `Sources/SwiflowUI/Badge.swift`:

  (a) Replace the enum body:
```swift
public enum BadgeVariant: Equatable {
    case neutral, accent, danger, success, info, warning
    var modifierClass: String {
        switch self {
        case .neutral: return "neutral"
        case .accent:  return "accent"
        case .danger:  return "danger"
        case .success: return "success"
        case .info:    return "info"
        case .warning: return "warning"
        }
    }
}
```

  (b) In `badgeStyleSheet`, after the `.sw-badge--success { … }` line, add:
```
    .sw-badge--info    { background-color: color-mix(in oklab, var(--sw-info) 15%, var(--sw-surface)); color: var(--sw-info-strong); }
    .sw-badge--warning { background-color: color-mix(in oklab, var(--sw-warning) 15%, var(--sw-surface)); color: var(--sw-warning-strong); }
```

- [ ] **Step 4: Run to verify it passes** — `swift test --filter FeedbackTests`
Expected: PASS — the 2 new tests + all existing Spinner/ProgressView/Card/Badge tests stay green.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowUI/Badge.swift Tests/SwiflowUITests/FeedbackTests.swift
git commit -m "feat(swiflowui): Badge info/warning variants"
```

---

### Task 3: `Toast` warning variant + info rule

**Files:**
- Modify: `Sources/SwiflowUI/Toast.swift`
- Modify: `Tests/SwiflowUITests/ToastTests.swift`

- [ ] **Step 1: Write the failing tests** — In `Tests/SwiflowUITests/ToastTests.swift`, add inside the suite (before its closing `}`):
```swift
    @Test("warning variant lowers to sw-toast--warning and is polite") func warningVariant() {
        let warn = el(building { ToastView(item: ToastItem("Careful", variant: .warning), onDismiss: {}).body })!
        #expect(allText(warn).contains("Careful"))
        #expect(firstWithClass(warn, "sw-toast--warning") != nil)
        #expect(ToastVariant.warning.isAssertive == false)   // warning is polite, only danger is assertive
    }

    @Test("stylesheet has explicit info + warning border rules") func infoWarningRules() {
        _ = building { ToastView(item: ToastItem("x"), onDismiss: {}).body }  // installs the sheet
        let sheet = toastStyleSheet.cssString(scopeClass: "")
        #expect(sheet.contains(".sw-toast--info"))
        #expect(sheet.contains("border-inline-start-color: var(--sw-info)"))
        #expect(sheet.contains(".sw-toast--warning"))
        #expect(sheet.contains("border-inline-start-color: var(--sw-warning)"))
    }
```
Note: the Toast stylesheet constant is `toastStyleSheet` (confirmed at `Toast.swift:172`); `ToastTests.swift:143` already calls `toastStyleSheet.cssString(scopeClass: "")`. The `building`/`el`/`allText`/`firstWithClass` helpers already exist at the top of `ToastTests.swift`.

- [ ] **Step 2: Run to verify it fails** — `swift test --filter ToastTests`
Expected: FAIL to compile — `ToastVariant` has no `.warning` case.

- [ ] **Step 3: Implement** — In `Sources/SwiflowUI/Toast.swift`:

  (a) Replace the enum (keep the doc comment above it; update it to mention warning/info tokens exist now):
```swift
public enum ToastVariant: Equatable {
    case info, success, danger, warning
    var modifierClass: String {
        switch self {
        case .info:    return "info"
        case .success: return "success"
        case .danger:  return "danger"
        case .warning: return "warning"
        }
    }
    /// Danger interrupts (role=alert + aria-live=assertive); info/success/warning are polite.
    var isAssertive: Bool { self == .danger }
}
```

  (b) In the stylesheet, replace the two existing status rules:
```
    .sw-toast--success { border-inline-start-color: var(--sw-success); }
    .sw-toast--danger  { border-inline-start-color: var(--sw-danger); }
```
  with (adding explicit info + warning):
```
    .sw-toast--info    { border-inline-start-color: var(--sw-info); }
    .sw-toast--success { border-inline-start-color: var(--sw-success); }
    .sw-toast--danger  { border-inline-start-color: var(--sw-danger); }
    .sw-toast--warning { border-inline-start-color: var(--sw-warning); }
```
(The default `border-inline-start: 4px solid var(--sw-accent)` stays as the base; `.sw-toast--info` now makes the info border explicit via `--sw-info`, which equals the accent by default.)

- [ ] **Step 4: Run to verify it passes** — `swift test --filter ToastTests`
Expected: PASS — the 2 new tests + existing Toast tests (`itemIdentity`, `variantPoliteness`, etc.) stay green.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowUI/Toast.swift Tests/SwiflowUITests/ToastTests.swift
git commit -m "feat(swiflowui): Toast warning variant + explicit info border rule"
```

---

### Task 4: Generator seeds (`accentThemeCSS` warning/info)

**Files:**
- Modify: `Sources/SwiflowColor/ContrastColor.swift` (the `accentThemeCSS` function)
- Modify: `Tests/SwiflowColorTests/AccentThemeTests.swift`

- [ ] **Step 1: Write the failing tests** — add inside `struct AccentThemeTests`:
```swift
    @Test("Shipped warning default passes the status validator (raw 3:1 + strong 4.5/7)") func shippedWarningAccessible() {
        // The base-sheet default is hand-authored light-dark(#b45309, #fbbf24) — guard it stays accessible.
        #expect(Color.validateStatusFamily(name: "--sw-warning",
                                           lightHex: "#b45309", darkHex: "#fbbf24",
                                           rawBar: 3.0).isEmpty)
    }

    @Test("warning/info seeds emit raw lines in order accent→danger→success→warning→info") func warningInfoEmit() {
        let css = try Color.accentThemeCSS(primaryHex: "#7c3aed",
                                           dangerHex: "#e11d48", successHex: "#059669",
                                           warningHex: "#d97706", infoHex: "#0ea5e9")
        for t in ["--sw-danger:", "--sw-success:", "--sw-warning:", "--sw-info:"] {
            #expect(css.contains(t))
        }
        let i = { (s: String) in css.range(of: s)!.lowerBound }
        #expect(i("--sw-accent:") < i("--sw-danger:"))
        #expect(i("--sw-danger:") < i("--sw-success:"))
        #expect(i("--sw-success:") < i("--sw-warning:"))
        #expect(i("--sw-warning:") < i("--sw-info:"))
    }

    @Test("No warning/info seeds is byte-for-byte the prior output") func noWarningInfoUnchanged() throws {
        let a = try Color.accentThemeCSS(primaryHex: "#3b82f6", dangerHex: "#e11d48")
        let b = try Color.accentThemeCSS(primaryHex: "#3b82f6", dangerHex: "#e11d48",
                                         warningHex: nil, infoHex: nil)
        #expect(a == b)
        #expect(!a.contains("--sw-warning"))
        #expect(!a.contains("--sw-info"))
    }

    @Test("A washed warning seed throws") func badWarningThrows() {
        #expect(throws: Color.PaletteError.self) {
            // amber-500 #f59e0b is 2.15:1 on white — below the 3:1 border bar.
            _ = try Color.accentThemeCSS(primaryHex: "#3b82f6", warningHex: "#f59e0b")
        }
    }
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter AccentThemeTests`
Expected: FAIL to compile — `accentThemeCSS` has no `warningHex:`/`infoHex:` params.

- [ ] **Step 3: Implement** — In `Sources/SwiflowColor/ContrastColor.swift`, two edits to `accentThemeCSS`:

  (a) Add the two params to the signature (between `successHex:` and `includeNeutrals:`):
```swift
    public static func accentThemeCSS(primaryHex: String,
                                      dangerHex: String? = nil,
                                      successHex: String? = nil,
                                      warningHex: String? = nil,
                                      infoHex: String? = nil,
                                      includeNeutrals: Bool = false) throws -> String {
```

  (b) Immediately after the existing `if let successHex { … }` block, insert:
```swift
        if let warningHex {
            let wl = try normalizeHex(warningHex)
            let wd = darkAccent(from: wl)
            failures += validateStatusFamily(name: "--sw-warning", lightHex: wl, darkHex: wd, rawBar: 3.0)
            statusLines.append("  --sw-warning: light-dark(\(wl), \(wd));")
            flagEcho += " --warning \(wl)"
        }
        if let infoHex {
            let il = try normalizeHex(infoHex)
            let id = darkAccent(from: il)
            failures += validateStatusFamily(name: "--sw-info", lightHex: il, darkHex: id, rawBar: 3.0)
            statusLines.append("  --sw-info: light-dark(\(il), \(id));")
            flagEcho += " --info \(il)"
        }
```
(The `statusLines`/`flagEcho`/`failures` vars and both `:root`-assembly paths already consume them — no further change. Order is correct because warning/info append after success.)

- [ ] **Step 4: Run to verify it passes** — `swift test --filter AccentThemeTests`
Expected: PASS — the 4 new tests + all existing AccentThemeTests (incl. the #71 danger/success and byte-compat tests) stay green. If `shippedWarningAccessible` FAILS, STOP and report — the shipped amber default isn't accessible and the spec's default hex must change (escalate, don't loosen).

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowColor/ContrastColor.swift Tests/SwiflowColorTests/AccentThemeTests.swift
git commit -m "feat(swiflowcolor): accentThemeCSS emits validated --warning/--info seeds"
```

---

### Task 5: `--warning` / `--info` CLI flags

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/ThemeCommand.swift`
- Modify: `Tests/SwiflowCLITests/ThemeCommandTests.swift`

- [ ] **Step 1: Write the failing tests** — add inside `struct ThemeCommandTests`:
```swift
    @Test("--warning/--info write validated overrides to --out") func warningInfoFlags() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sw-theme-\(UUID().uuidString).css")
        defer { try? FileManager.default.removeItem(at: tmp) }
        var cmd = try ThemeCommand.parse([
            "--primary", "#7c3aed", "--warning", "#d97706", "--info", "#0ea5e9", "--out", tmp.path,
        ])
        try cmd.run()
        let css = try String(contentsOf: tmp, encoding: .utf8)
        #expect(css.contains("--sw-warning: light-dark(#d97706, #"))
        #expect(css.contains("--sw-info: light-dark(#0ea5e9, #"))
    }

    @Test("Without --warning/--info neither token is emitted") func noWarningInfoFlags() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sw-theme-\(UUID().uuidString).css")
        defer { try? FileManager.default.removeItem(at: tmp) }
        var cmd = try ThemeCommand.parse(["--primary", "#7c3aed", "--out", tmp.path])
        try cmd.run()
        let css = try String(contentsOf: tmp, encoding: .utf8)
        #expect(!css.contains("--sw-warning"))
        #expect(!css.contains("--sw-info"))
    }
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter ThemeCommandTests`
Expected: FAIL — unknown options `--warning`/`--info`.

- [ ] **Step 3: Implement** — In `Sources/SwiflowCLI/Commands/ThemeCommand.swift`:

  (a) After the `@Option … var success: String?` declaration, add:
```swift
    @Option(name: .customLong("warning"),
            help: "Brand warning color (light-mode), as #rgb or #rrggbb.")
    var warning: String?

    @Option(name: .customLong("info"),
            help: "Brand info color (light-mode); defaults to the accent if unset.")
    var info: String?
```

  (b) Update the `accentThemeCSS` call in `run()` to thread them through:
```swift
        let css = try Color.accentThemeCSS(primaryHex: primary,
                                           dangerHex: danger,
                                           successHex: success,
                                           warningHex: warning,
                                           infoHex: info,
                                           includeNeutrals: neutrals)
```

- [ ] **Step 4: Run to verify it passes** — `swift test --filter ThemeCommandTests`
Expected: PASS — 2 new + existing flag tests green.

- [ ] **Step 5: Commit**
```bash
git add Sources/SwiflowCLI/Commands/ThemeCommand.swift Tests/SwiflowCLITests/ThemeCommandTests.swift
git commit -m "feat(cli): swiflow theme --warning/--info flags"
```

---

### Task 6: Demo wiring + EmbeddedTemplates regen

**Files:**
- Modify: `examples/SwiflowUIDemo/Sources/App/App.swift`
- Modify: `Sources/SwiflowCLI/EmbeddedTemplates.swift` (regen)

- [ ] **Step 1: Add warning/info badges** — In `examples/SwiflowUIDemo/Sources/App/App.swift`, find the badge cluster (the `Card(variant: .outlined)` row with `Badge("Error", variant: .danger)` / `Badge("Done", variant: .success)` / `Badge("Muted")`). Add two badges to that `HStack` immediately after `Badge("Done", variant: .success)`:
```swift
                        Badge("Warn", variant: .warning)
                        Badge("Info", variant: .info)
```

- [ ] **Step 2: Add a warning toast button** — find the toast trigger buttons (`Button("Toast: success", …)`, `Button("Toast: info", …)`, `Button("Toast: error", …)`). After the `Toast: info` button add:
```swift
                Button("Toast: warning", variant: .ghost) { self.toasts.append(ToastItem("Low disk space", variant: .warning)) }
```
(The `Toast: info` button already exists and now resolves the explicit `.sw-toast--info` rule.)

- [ ] **Step 3: Regenerate embedded templates** (SwiflowUIDemo is an embedded `swiflow init` template; a CI freshness gate asserts `EmbeddedTemplates.swift` is current):

Run: `swift scripts/embed-templates.swift`
Expected: `wrote …/EmbeddedTemplates.swift`; `git status` shows `Sources/SwiflowCLI/EmbeddedTemplates.swift` modified.

- [ ] **Step 4: Verify freshness + the demo builds** — Run: `swift test --filter TemplateEmbedderTests`
Expected: PASS. Then build the demo (CI skips example builds, so this is local-only):
Run: `swift build -c release --product swiflow && .build/release/swiflow build --path examples/SwiflowUIDemo`
Expected: `build complete.`

- [ ] **Step 5: Eyeball (manual, local)** — serve the demo and confirm the badge row shows danger/success/**warning** (amber)/**info** badges and the new "Toast: warning" button shows an amber-bordered toast, readable in light + dark. Note: the build stamps `swiflow-service-worker.js`/driver — `git checkout --` those after; keep only `App.swift` + `EmbeddedTemplates.swift`.

- [ ] **Step 6: Commit**
```bash
git add examples/SwiflowUIDemo/Sources/App/App.swift Sources/SwiflowCLI/EmbeddedTemplates.swift
git commit -m "docs(demo): show warning/info badges + a warning toast"
```

---

### Task 7: Playwright — warning Badge renders the amber token

**Files:**
- Modify: `Tests/playwright/theming.spec.ts`

- [ ] **Step 1: Write the test** — Add inside the existing `test.describe(...)` block in `Tests/playwright/theming.spec.ts` (it has `gotoMounted(page)` and `getByText`/`getByRole` helpers used by sibling tests):
```ts
  test("a warning Badge renders a non-empty amber background distinct from success", async ({ page }) => {
    await gotoMounted(page);
    const warnBg = await page.locator(".sw-badge--warning").first()
      .evaluate((el) => getComputedStyle(el).backgroundColor);
    const okBg = await page.locator(".sw-badge--success").first()
      .evaluate((el) => getComputedStyle(el).backgroundColor);
    // resolves to a real color (not transparent / empty) and is not the success tint
    expect(warnBg).toMatch(/^rgb/);
    expect(warnBg).not.toBe("rgba(0, 0, 0, 0)");
    expect(warnBg).not.toBe(okBg);
  });
```

- [ ] **Step 2: Build the release CLI first** (the e2e harness reuses the binary; a stale one scaffolds the old demo without the warning badge):
Run: `swift build -c release --product swiflow`
Expected: `Build of product 'swiflow' complete!`

- [ ] **Step 3: Run the spec INLINE, detached, after killing leftovers** (per [[no-subagent-playwright]] / [[run-e2e-locally-before-push]] — never delegate e2e to a subagent; kill stale servers + free port 3000 first):
```bash
pkill -9 -f playwright; pkill -9 -f swiflow-dev; pkill -9 -f "http.server"; sleep 1
rm -f Tests/playwright/.e2e-cache/*/.lock 2>/dev/null
cd Tests/playwright && npx playwright test theming.spec.ts
```
Expected: PASS — the new warning-badge test + the existing media-feature/override tests (confirming the base-sheet additions didn't break the token flips).

- [ ] **Step 4: Commit**
```bash
git add Tests/playwright/theming.spec.ts
git commit -m "test(e2e): warning Badge renders the amber token"
```

---

### Task 8: Docs — theming guide + roadmap

**Files:**
- Modify: `docs/guides/swiflowui-theming.md`
- Modify: `docs/future-work/swiflowui-1.0-roadmap.md`

- [ ] **Step 1: Document the new tokens + flags** — In `docs/guides/swiflowui-theming.md`, find the `### Generating a theme from brand colors` section (added in #71) and its flag bullet list. Add two bullets after the `--success` bullet:
```markdown
- `--warning "#d97706"` — set the brand warning color (amber; validated as a UI/border color, ≥ 3:1).
- `--info "#0ea5e9"` — set the brand info color (defaults to the accent if unset; validated ≥ 3:1).
```
Then, in `## The token contract` (or wherever the status tokens are listed), add a one-line note:
```markdown
> Status tokens: `--sw-danger`, `--sw-success`, `--sw-warning` (amber), and `--sw-info`
> (aliases `--sw-accent` by default). Each has a `-strong` text variant for badges/labels.
```

- [ ] **Step 2: Update the roadmap** — In `docs/future-work/swiflowui-1.0-roadmap.md`, in the M8 deferral list, replace the `--warning`/`--info` deferral clause. Find the line beginning `**Deferred from M8 to a later pass:** \`--warning\`/\`--info\` seeds` and replace its `--warning`/`--info` clause with a ✅ bullet above the deferred paragraph:
```markdown
- **✅ Warning/info status tokens + seeds (this PR)** — `--sw-warning` (amber, full 4-layer
  treatment) and `--sw-info` (accent alias, independently overridable) added to the base sheet and
  wired into `Badge`/`Toast`; `swiflow theme` gains validated `--warning`/`--info` seeds.
```
And edit the deferred paragraph so it no longer lists `--warning`/`--info` (leaving APCA, p3-for-generated-color, and public `SwiflowColor`).

- [ ] **Step 3: Verify docs-only** — Run: `git diff --stat docs/`
Expected: only the two doc files modified.

- [ ] **Step 4: Commit**
```bash
git add docs/guides/swiflowui-theming.md docs/future-work/swiflowui-1.0-roadmap.md
git commit -m "docs(theme): document --warning/--info tokens + seeds; mark shipped"
```

---

## Final verification (after all tasks)

- [ ] `swift test` → all green (ThemeTests, FeedbackTests, ToastTests, AccentThemeTests, ThemeCommandTests, TemplateEmbedderTests + full suite).
- [ ] `cd Tests/playwright && npx playwright test theming.spec.ts` → green, with a freshly built release CLI.
- [ ] `git status` clean except intended files — `EmbeddedTemplates.swift` IS committed; no stray stamped SW/driver artifacts.
- [ ] `git log --oneline origin/main..HEAD` → the spec + plan commits + the eight task commits.
- [ ] Dispatch the final code reviewer subagent over the whole branch.

## Notes for the implementer

- **Demo touches `examples/` → `EmbeddedTemplates.swift` MUST be regenerated and committed**, or CI's freshness gate fails ([[ci-swift-6.3.2]] gotcha; the lesson from PR #68).
- **Playwright is local-only and inline** — CI skips example builds + the WASM e2e gate ([[ci-skips-example-builds]]); never delegate the e2e run to a subagent ([[no-subagent-playwright]]); rebuild the release CLI before each run ([[run-e2e-locally-before-push]]).
- **`--sw-info` is `var(--sw-accent)` by default** — Badge `.info` looks identical to `.accent` until an app overrides `--sw-info` or passes `--info`. That's intended, not a bug.
- **`SwiflowColor` stays native-only** — never import it under `Sources/SwiflowUI`.
- **Byte-compat** — the `noWarningInfoUnchanged` test guards that supplying no warning/info seed leaves the #71 output untouched.
