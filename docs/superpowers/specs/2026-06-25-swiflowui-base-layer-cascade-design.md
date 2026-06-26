# SwiflowUI Base-Token Cascade Fix (`@layer swiflow.base`) Design

> **Date:** 2026-06-25 · **Status:** approved, ready for implementation plan
> **Rides with:** the neutral-palette PR (`feat/swiflowui-neutral-palette`) — folded in per the
> user's call, since the demo wiring for that feature depends on this fix.

## Problem

SwiflowUI's base **token** sheet (`SwiflowUI.baseStyleSheet`: the `:root { --sw-* }` block + the
five `@media` override layers) is injected **unlayered** and **appended** to `<head>` at runtime
(`CSSInjector.appendStyle` → `head.appendChild`, on first render). An app's documented override —
a `:root { --sw-accent: … }` in `index.html`'s `<head>` (or a linked `theme.css`, e.g. the output
of `swiflow theme`) — is parsed *earlier*. Both are unlayered `:root` (equal specificity), so
**later-in-source wins → the runtime base sheet beats the static override → the override does
nothing.**

This silently breaks two documented things:
- `docs/guides/swiflowui-theming.md`'s "override tokens in your own `:root`" mechanism.
- The `swiflow theme` generator's headline workflow — its emitted `:root` CSS, included the
  documented way, never takes effect.

(The reset is already `@layer reset` and correctly loses to everything; only the *tokens* are the
problem.)

## Goal

Make app/generated **unlayered** `:root` overrides reliably win over SwiflowUI's base tokens,
regardless of injection/source order, by putting the base tokens in a cascade **layer**. Then
wire a real generated `theme.css` into `SwiflowUIDemo` as the visual proof.

## The fix — `@layer swiflow.base`

Wrap `baseStyleSheet`'s entire emitted content in `@layer swiflow.base { … }` (the `:root` token
block **and** all five `@media` override blocks). Resulting cascade order:

```
@layer reset            (lowest — the reset)
@layer swiflow.base     (the tokens + their media overrides)
<unlayered>             (component .sw-* sheets, scopedStyles, AND app/theme.css :root overrides)
```

Because **any unlayered rule beats any layered rule regardless of source order or specificity**,
an app's unlayered `:root { --sw-accent: … }` now wins over `swiflow.base` even though the base
sheet is appended later. Layer order is established by first-appearance: the reset is injected
first (lowest), `swiflow.base` second — correct without an explicit `@layer` order statement, but
the implementation MAY emit a leading `@layer reset, swiflow.base;` declaration for clarity.

### Why this is the right layer to fix at

- **The generator needs no change** — it already emits *unlayered* `:root {…}` + `@media{:root{}}`,
  which now correctly win. (Same for the M8 `-strong`/contrast tokens and the `Theme` component —
  all unlayered, all still win.)
- **Components are unaffected** — they only *consume* `var(--sw-*)` (never define tokens), and
  their `.sw-*`/`scopedStyles` sheets are unlayered, so they keep beating the layer exactly as
  before; they read whatever token value wins the cascade.
- **The media-feature overrides keep working** — they sit in the same `swiflow.base` layer and
  re-point tokens relative to the base within it; an app/generated `@media` block (unlayered) still
  beats them, which is precisely what the generator's `prefers-contrast: more` block relies on.

## Non-goals

- No change to the generator's output, the `Theme` component, or any component sheet.
- Not introducing app-facing layer APIs or a multi-layer token architecture — one base layer.
- No change to the reset (`@layer reset` stays as-is).

## Components & boundaries

| Unit | Change |
|------|--------|
| `Sources/SwiflowUI/Theme.swift` | wrap the `baseStyleSheet` raw CSS in `@layer swiflow.base { … }` |
| `Tests/SwiflowUITests/ThemeTests.swift` | assert `@layer swiflow.base` is emitted; keep existing token/`@media`/brace assertions green |
| `Tests/playwright/theming.spec.ts` (or a sibling) | a static `:root` override wins over base; existing media-feature flips still pass |
| `examples/SwiflowUIDemo/index.html` + generated `theme.css` | wire a `--neutrals` palette as the visual proof |
| `Sources/SwiflowCLI/EmbeddedTemplates.swift` | regen (SwiflowUIDemo is an embedded template) |
| `docs/guides/swiflowui-theming.md` | one line noting overrides win via `@layer swiflow.base` |

## Testing

- **Unit (`ThemeTests`):** `baseStyleSheet.cssString(scopeClass: "")` contains `@layer swiflow.base`
  and still contains the tokens / `@media (prefers-contrast: more)` / balanced braces (the existing
  assertions must stay green; update only if a test pinned the sheet's exact opening).
- **Playwright (the load-bearing check — cascade isn't unit-testable):** in a fixture whose
  `<head>` has `<style>:root { --sw-accent: #e11d48 }</style>`, a rendered `Button`'s computed
  `background-color` resolves to that override (≈ `rgb(225, 29, 72)`), not the default blue; and a
  control page without the override stays default. Plus: re-run `theming.spec.ts` to confirm the
  `@layer` wrapping didn't break the `emulateMedia` token flips (dark/contrast/reduced-motion).
- **Demo:** `swiflow theme --primary "#7c3aed" --neutrals --out examples/SwiflowUIDemo/theme.css`,
  link it in that demo's `<head>`, build + serve, confirm the whole gallery re-skins violet
  (surfaces/text/borders tinted, buttons branded) with readable text in light + dark.

## Verification

`swift test` green; the Playwright override + media specs green (run locally — CI skips example
builds and the WASM e2e gate). After the demo wiring, `swift scripts/embed-templates.swift` +
commit `EmbeddedTemplates.swift` (CI freshness gate, since SwiflowUIDemo is embedded).

## Decisions resolved during brainstorming

1. **Fix location** → wrap the **base tokens** in `@layer swiflow.base` (not change the generator):
   one foundational fix repairs app overrides, the generator, the `Theme` component, and the M8
   tokens at once.
2. **Packaging** → folded into the neutral-palette PR (one PR), with the demo wiring as the proof.
3. **Verification** → Playwright is mandatory (a cascade change is not unit-testable); the unit
   test only confirms the `@layer` text is emitted.
