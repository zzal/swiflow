# SwiflowUI p3/OKLCH Wide-Gamut Generator Upgrade Design

> **Date:** 2026-06-26 · **Status:** approved, ready for implementation plan
> **Milestone:** M8 follow-up — the **p3-for-generated-color** item deferred since PR #67.
> **Builds on:** the status-seed generator (#71) + warning/info tokens (#72).

## Problem

`swiflow theme` emits every generated color as an sRGB hex (`light-dark(#hex, #hex)`). The
hand-authored base-sheet defaults, by contrast, ship a `@media (color-gamut: p3)` block with
richer `color(display-p3 …)` values — so a *default* SwiflowUI app looks more vivid on a P3
display than a *generated* theme does. A generated accent/status color is capped at the sRGB
gamut even on hardware that can show more.

## Goal

Upgrade the generator so accent and status colors render at the **display-P3 gamut edge** on
capable displays, with the exact sRGB hex as the fallback elsewhere — using a single `oklch()`
declaration (no `@media` needed). "Better color definition" via OKLCH, and a real wide-gamut
upgrade (not just a syntax change).

## Decisions (from brainstorming)

1. **Boost chroma to the display-P3 gamut edge** at each seed's exact OKLCH lightness + hue.
   L and H are unchanged, so luminance/hue (and therefore WCAG contrast) are preserved — only
   chroma widens, and only on P3 hardware. (A faithful re-expression was rejected: re-stating an
   sRGB hex as `oklch()` renders identically on P3 — zero gamut gain.)
2. **Progressive double-declaration, as the new default.** For accent + each status token emit the
   hex line, then an `oklch()` line that wins where `oklch()` is supported (Baseline 2023). No
   `--p3` flag. No `@media` block — `oklch()` adapts to the display's gamut natively.
3. **Neutrals excluded.** The near-gray ramp (chroma ≈ 0.01) gains nothing from P3; it stays
   hex-only.
4. **Regenerate the demo `theme.css`** in this PR so the shipped demo demonstrates the p3 output.

## Non-goals

- **No `ThemeCommand` flag** — p3/oklch output is the default (decision 2).
- **No base-sheet or component change.** `Theme.swift`'s hand-authored `color(display-p3 …)`
  blocks stay (they cover the no-generator default theme). Components are untouched.
- **No change to validation thresholds or which colors are gated.** Validation still runs on the
  sRGB hex (see below).
- **Still deferred:** APCA; promoting `SwiflowColor` to a public (shipping) generator.

## Color math (new `SwiflowColor` surface, native-only)

The pipeline already has OKLab ↔ linear-sRGB ↔ OKLCH. Two facts it relies on: `okLabToLinRGB`
returns **raw, unclamped** linear-sRGB (so a P3-only color produces out-of-[0,1] sRGB values we
can re-project), and `okLabToOKLCH` returns **H in radians** (CSS needs degrees).

New pieces:

- **`linRGBToLinP3(_ c: LinRGB) -> LinRGB`** — the standard linear-sRGB → linear-Display-P3
  transform. Both spaces are D65, so it is a single 3×3 matrix (no chromatic adaptation):
  ```
  [ 0.82246197  0.17753803  0.0        ]
  [ 0.03319420  0.96680580  0.0        ]
  [ 0.01708263  0.07239744  0.91051993 ]
  ```
  (Coefficients are the implementer's to verify against a reference; the in-gamut tests pin
  correctness, not the literal matrix.)
- **`inP3Gamut(_ lab: OKLab) -> Bool`** — `okLabToLinRGB(lab)` → `linRGBToLinP3` → all channels in
  `[0, 1]` (small epsilon tolerance).
- **`p3MaxChroma(L:H:) -> Double`** — binary-search the largest chroma whose `OKLCH(L, C, H)` is
  still `inP3Gamut`, starting above the sRGB-clamped chroma. ~20 iterations to sub-0.001 precision.
- **`p3OKLCHString(fromHex:) -> String`** — hex → `OKLCH` → replace chroma with `p3MaxChroma(L:H:)`
  → format `"oklch(<L> <C> <Hdeg>)"`. H converted radians→degrees (normalized to `0…360`),
  rounded (e.g. L/C to 4 decimals, H to 2). The boosted chroma must be **≥** the seed's sRGB
  chroma (it can only widen), asserted by tests.

## Generator change (`accentThemeCSS`)

For accent and each provided status seed, emit a **second** declaration immediately after the hex
line, wrapping both light and dark arms in `p3OKLCHString`:

```css
:root {
  --sw-accent: light-dark(#7c3aed, #9f7bff);
  --sw-accent: light-dark(oklch(0.5106 0.2914 290.34), oklch(0.6979 0.1641 287.71));
  /* …danger/success/warning/info each get the same hex + oklch pair… */
  --sw-bg: light-dark(#f5f4fb, #0b0a0f);          /* neutrals: hex only */
  …
}
```

(Numbers illustrative; tests pin that chroma widened and the string is well-formed, not exact
values.) The `@media (prefers-contrast: more)` neutral block (from `--neutrals`) is unchanged.

## Validation

**Unchanged.** `validateAccentFamily`/`validateStatusFamily` continue to run on the sRGB hex — the
oklch line shares the same OKLCH L and H, so its luminance (≈ contrast) is preserved by
construction; the boosted chroma is a progressive enhancement on top of the validated, shipped
fallback. No new validation, no threshold change.

## Backward compatibility

- The hex line is still emitted, so `contains("--sw-accent: light-dark(#…")` assertions hold.
- The existing byte-compat tests compare two generator calls with the same args (`a == b`); both
  produce the new output, so they still pass. Any test pinning an *exact full string* of the old
  output must be updated to include the oklch line (the implementer greps for these).

## Demo

Regenerate `examples/SwiflowUIDemo/theme.css` with the same command it was created with
(`swiflow theme --primary "#7c3aed" --neutrals`) so it now carries the oklch accent line, then
regenerate `EmbeddedTemplates.swift` (the demo is an embedded template; CI freshness gate).

## Components & boundaries

| Unit | Change | New? |
|------|--------|------|
| `Color.linRGBToLinP3` + `inP3Gamut` | sRGB→P3 projection + gamut test | new |
| `Color.p3MaxChroma(L:H:)` | gamut-edge chroma search | new |
| `Color.p3OKLCHString(fromHex:)` | hex → boosted `oklch()` string | new |
| `Color.accentThemeCSS` | emit the oklch line for accent + status (not neutrals) | extended |
| `examples/SwiflowUIDemo/theme.css` + `EmbeddedTemplates.swift` | regen | regen |
| `docs/guides/swiflowui-theming.md`, roadmap | document the p3/oklch default | docs |

`SwiflowColor` stays native-only (no dependency added to the wasm `SwiflowUI`).

## Testing

- **`SwiflowColorTests`:**
  - `linRGBToLinP3`/`inP3Gamut`: a saturated sRGB color is inside P3; a chroma boosted past the P3
    edge is outside.
  - `p3MaxChroma("#7c3aed")` returns a chroma **strictly greater** than the seed's sRGB OKLCH
    chroma, and the boosted `OKLCH` is `inP3Gamut` while a hair more chroma is not.
  - `p3OKLCHString("#7c3aed")` matches `oklch(<num> <num> <num>)`, H in `0…360` degrees.
  - `accentThemeCSS(primaryHex: "#7c3aed")` now contains **both** `--sw-accent: light-dark(#7c3aed,`
    and a following `--sw-accent: light-dark(oklch(`. With status seeds, each status token gets its
    own oklch line. **Neutrals do not** get an oklch line (`--sw-bg:` appears once, hex only).
  - Contrast preserved: the boosted accent's OKLCH L equals the seed's L (so `validateAccentFamily`
    still passes for a known-good seed).
- **`SwiflowCLITests`:** `theme --primary "#7c3aed" --out <tmp>` writes a file containing an
  `oklch(` accent line.
- **Playwright (local; CI skips examples):** a generated oklch accent override resolves to a real
  `rgb`/`color()` in the browser (probe on a throwaway element), confirming the oklch line parses
  and applies.
- **Demo eyeball:** regenerated demo still re-skins correctly (the hex fallback and oklch agree on
  an sRGB display).

## Verification

`swift test` green; Playwright theming spec green with a freshly built release CLI
([[run-e2e-locally-before-push]], inline per [[no-subagent-playwright]]); regenerate the demo
`theme.css` + `EmbeddedTemplates.swift` and commit ([[ci-swift-6.3.2]] freshness gate); build the
demo locally ([[ci-skips-example-builds]]). Update the guide + mark the roadmap item shipped.

## Decisions resolved during brainstorming

1. **Boost** → to the display-P3 gamut edge (max vividness, L/H preserved). Moderate-cap and
   faithful-re-express were rejected (the latter is a visual no-op).
2. **Form** → progressive double-declaration (hex then `oklch()`), as the **default** output; no
   `--p3` flag, no `@media` block.
3. **Scope** → accent + status seeds only; neutrals stay hex (grays gain nothing from P3).
4. **Demo** → regenerate `theme.css` in this PR.
5. **Validation** → unchanged; runs on the sRGB hex (boosted oklch shares L/H → contrast holds).
