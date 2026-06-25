# SwiflowUI M8 — Contrast Tokens Design

> **Date:** 2026-06-25 · **Status:** approved, ready for implementation plan
> **Milestone:** SwiflowUI **M8 (1.1) — Token correctness & generation**
> (see [`docs/future-work/swiflowui-1.0-roadmap.md`](../../future-work/swiflowui-1.0-roadmap.md))
> **Origin:** the [Reshaped evaluation](../../future-work/swiflowui-reshaped-evaluation.md)
> — steal-list item #1 (on-background contrast tokens).

## Problem

SwiflowUI derives readable text from background tokens by **hand-guessing** the result:

- **Soft-tint text.** Badges/menu items put semantic-hue text on a *pale tint of the same
  hue* — `color-mix(in oklab, var(--sw-accent) 15%, var(--sw-surface))`. The base hue token is
  mid-tone in light mode and fails WCAG on that pale tint, so three hand-darkened tokens patch
  it: `--sw-accent-strong`, `--sw-danger-strong`, `--sw-success-strong`
  (`Sources/SwiflowUI/Theme.swift`). Consumers: `Badge` (accent/danger/success),
  `Autocomplete` (danger), `Dropdown` (danger).
- **Solid-fill text.** The primary `Button` puts text on a solid `--sw-accent` fill via
  `--sw-accent-text: light-dark(#ffffff, #0b1220)` — another hand-picked value.

Both are guesses tuned for the *shipped* palette. The moment an app overrides `--sw-accent`
(SwiflowUI's core re-skin promise), the guess can silently fail WCAG. There is no test that
proves even the defaults pass.

## Goal

Replace the hand-guessed text colors with **CSS that derives them from the background token at
render time** (so they survive app overrides and stay media-first — components keep reading one
`--sw-*` token), **plus a Swift test that proves the shipped defaults clear their contrast
target**. Best-effort correctness for arbitrary app hues; proven correctness for defaults.

## Non-goals (deferred to 1.1+)

- **APCA** algorithm — WCAG 2.x covers the documented failure; APCA is additive polish.
- **A generalized on-tint utility** for arbitrary tint backgrounds — no second tint pattern
  exists today (YAGNI); the 3 hues + canonical 15% tint are the only consumers.
- **Solid `danger`/`success` text tokens** — no solid danger/success fills exist in the
  component set yet (`Button` has no `.danger` variant). Add when a consumer appears.
- **A public palette generator** (Reshaped's `generateThemeColors` analog) — the Swift color
  module built here lives in the test target; promote it to shipping code only when a generator
  is actually built.
- **Component API changes** — every consumer already reads the relevant `--sw-*` token; this
  milestone only changes token *definitions* and adds tests.

## Design overview

Two parts, sharing one structure and one proof harness.

| | **Part A — soft-tint** | **Part B — solid-fill** |
|---|---|---|
| Token(s) | `--sw-accent-strong`, `--sw-danger-strong`, `--sw-success-strong` | `--sw-accent-text` |
| Consumers | `Badge`, `Autocomplete`, `Dropdown` | `Button` `.primary` (+ overlay buttons transitively) |
| Background | `color-mix(in oklab, var(--hue) 15%, var(--sw-surface))` | solid `var(--sw-accent)` |
| Derivation | `oklch(from var(--hue) L c h)` — same hue, pinned lightness | `contrast-color(var(--sw-accent))` — black or white |
| Browser support | Baseline 2024 | Baseline 2026 (Apr) |
| Target ratio | 4.5:1 normal · 7:1 under `prefers-contrast: more` | 4.5:1 |

**Shared structure — progressive enhancement.** Each token keeps its current hand-tuned literal
as the *first* declaration and gains the dynamic derivation as a *second*. A browser that can't
parse the dynamic value discards that declaration and keeps the literal. Both features are now
Baseline, so the fallback is cheap insurance for users on older browser versions, not
load-bearing.

## Part A — soft-tint `-strong` tokens

### Mechanism

The tint background is a `color-mix` of the hue into the surface; the readable text is the
*same hue* at a **fixed lightness** chosen to clear the target on that tint, regardless of the
source hue's own lightness. `light-dark()` selects the whole derived color per scheme (it is
color-only, so it wraps each `oklch(...)` rather than the L number):

```css
/* in baseStyleSheet :root — replaces the current single declaration */
/* static fallback — today's hand-tuned values, kept verbatim */
--sw-accent-strong: light-dark(#1d4ed8, #60a5fa);
/* dynamic — same hue, lightness pinned to clear 4.5:1 on the 15% tint */
--sw-accent-strong:  light-dark(oklch(from var(--sw-accent)  Lal c h), oklch(from var(--sw-accent)  Lad c h));
--sw-danger-strong:  light-dark(#b91c1c, #f87171);
--sw-danger-strong:  light-dark(oklch(from var(--sw-danger)  Ldl c h), oklch(from var(--sw-danger)  Ldd c h));
--sw-success-strong: light-dark(#15803d, #4ade80);
--sw-success-strong: light-dark(oklch(from var(--sw-success) Lsl c h), oklch(from var(--sw-success) Lsd c h));
```

### Higher-contrast layer

Under `prefers-contrast: more`, re-point the derivation to a darker/lighter L meeting 7:1.
Authored in a new block inside the existing `@media (prefers-contrast: more)` layer:

```css
@media (prefers-contrast: more) {
  :root {
    --sw-accent-strong:  light-dark(oklch(from var(--sw-accent)  Lal7 c h), oklch(from var(--sw-accent)  Lad7 c h));
    /* danger, success likewise */
  }
}
```

### The lightness constants

`Lal`/`Lad`/… are **starting points the test confirms or nudges** — the test is the source of
truth for whether they pass. Expected starting values: light-mode L ≈ `0.40` (4.5) / `0.30`
(7); dark-mode L ≈ `0.80` (4.5) / `0.88` (7). The implementer tunes them until
`ThemeContrastTests` is green, then writes the final numbers into the sheet.

### Stated limitation

Absolute-L pinning guarantees the ratio for **our three hues** (blue/red/green all read well at
L ≈ 0.40 in light mode). A custom app hue with unusual luminance (e.g. a pale yellow accent)
gets **best-effort readability, not a proof** — pure CSS cannot compute a contrast ratio
(`color-contrast()` is not shipped). This is the dynamic-vs-proven trade, made explicit. Part B
has no such gap.

## Part B — solid-fill `-text` token

`contrast-color(<color>)` returns **black or white** — whichever *maximizes* WCAG contrast with
the argument. On the default accent it picks **black in both modes** (light `#3b82f6`: black
5.70:1 vs white 3.68:1; dark `#60a5fa`: black 8.20:1 vs white 2.55:1):

```css
/* in baseStyleSheet :root */
--sw-accent-text: light-dark(#0b1220, #0b1220);     /* static fallback — dark both arms */
--sw-accent-text: contrast-color(var(--sw-accent)); /* dynamic */
```

`Button` `.primary` already reads `color: var(--sw-accent-text)` — no component change.

**This is a deliberate, visible restyle** (decided during brainstorming): the primary button's
**light-mode label changes from white to dark**. It fixes a latent failure — today's white on
`#3b82f6` is only **3.68:1**, below AA 4.5 for 16px/500 text — and makes the default
AA-correct. The static fallback's light arm therefore changes from `#ffffff` to `#0b1220` so
non-`contrast-color` browsers also pass; the dark arm (`#0b1220`) is unchanged.

**Caveat carried into the proof:** `contrast-color()` *maximizes*; it does not *guarantee* a
threshold. For a true mid-luminance background even the better of black/white can fall near or
below 4.5:1. For the accent solid this is safe (5.7/8.2:1), but the proof asserts it — for both
the `contrast-color` result and the static fallback — rather than assuming it.

## The Swift proof harness

Lives in the **test target only** (`Tests/SwiflowUITests/`); the shipped `SwiflowUI` module
gains **no color math** — the browser is the runtime engine, Swift only proves defaults.

### `Support/ContrastColor.swift`

A self-contained, dependency-free color pipeline (~200–300 LOC):

- sRGB-hex ↔ linear sRGB ↔ XYZ ↔ OKLab/OKLCH conversions.
- `colorMix(_:_:weight:in: .oklab)` — replicates the tint background.
- `oklch(from:lightness:)` — replicates the text derivation (keep C, H; replace L);
  gamut-clamp the result to sRGB before luminance.
- `contrastColor(against:)` — returns black or white by max WCAG contrast (replicates Part B).
- `wcagContrastRatio(_:_:)` — `(Llite + 0.05) / (Ldark + 0.05)` on linear-luminance.

### `ThemeContrastTests.swift`

- **Single source of truth for defaults:** parse the base hex values of `--sw-accent`,
  `--sw-danger`, `--sw-success`, `--sw-surface`, and the `-strong`/`-text` fallbacks out of
  `SwiflowUI.baseStyleSheet.cssString(scopeClass: "")` (precedent: `ThemeTests` already
  inspects emitted CSS), so the test cannot drift from the sheet.
- **Part A:** for each hue ∈ {accent, danger, success}, each scheme ∈ {light, dark}, each
  target ∈ {4.5 normal, 7 more-contrast}: rebuild tint = `mix(15% hue, surface)`, text =
  `oklch(from hue, L, c, h)` using the L parsed from the dynamic declaration, assert
  `contrastRatio(text, tint) ≥ target`.
- **Part B:** for the default accent (light + dark): assert **both** the fallback literal
  (`#ffffff`/`#0b1220`) **and** the `contrastColor(against: accent)` result clear 4.5:1 on the
  solid accent.

## Files touched

- **Modify** `Sources/SwiflowUI/Theme.swift` — the `-strong` and `-text` token declarations in
  `baseStyleSheet` (`:root` + the `prefers-contrast: more` block). The only shipping change.
- **Extend** `Tests/SwiflowUITests/ThemeTests.swift` — assert the dynamic declarations are
  emitted (the static + dynamic pair is present for each token).
- **Create** `Tests/SwiflowUITests/Support/ContrastColor.swift` — the color pipeline.
- **Create** `Tests/SwiflowUITests/ThemeContrastTests.swift` — the proof.
- No changes to `Badge`, `Button`, `Autocomplete`, `Dropdown` — they already read the tokens.

## Verification

- `swift test` — the new `ContrastColor` pipeline has its own unit tests (known-color
  conversions, a hand-checked WCAG ratio), and `ThemeContrastTests` proves every default
  {hue × scheme × target} and the Part B solid-fill clear their ratio.
- Relative-color and `contrast-color()` are not cleanly emulable in Playwright, so runtime
  correctness rests on the static-fallback layer + the Swift proof rather than a browser pixel
  check. The existing `theming.spec.ts` continues to cover the media-feature token flips.
- No `examples/` changes; no embedded-driver/regen impact (SwiflowUI is a library target, not
  the CLI's embedded JS).

## Decisions resolved during brainstorming

1. **Contrast contract** → *Both* — dynamic CSS derivation (survives overrides) **and** a
   build-time Swift proof on the shipped defaults.
2. **Scope** → core WCAG 4.5:1 + the `prefers-contrast: more` 7:1 bump; APCA and a generalized
   utility deferred.
3. **`contrast-color()` fit** → folded in as **Part B** (both mechanisms now Baseline, so the
   support story is symmetric; shared proof harness). Part A ships first as its own sub-step.
4. **Primary-button restyle** → *Adopt the `contrast-color` result.* It picks black on the
   default accent in both modes, so the light-mode button label changes white→dark. Accepted as
   the AA-correct outcome (today's white-on-accent is 3.68:1); the static fallback's light arm
   moves to `#0b1220` to match. Alternatives considered and rejected: dropping Part B to keep
   white-on-blue; darkening `--sw-accent` to navy so white passes (changes the accent
   everywhere).
