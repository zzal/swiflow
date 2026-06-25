# SwiflowUI Neutral / Full-Palette Generation Design

> **Date:** 2026-06-25 · **Status:** approved, ready for implementation plan
> **Milestone:** First **M8 deferral** — extends the palette generator (M8 part 2, PR #67)
> from accent-only to a full accent-tinted neutral palette.
> **Origin:** the [Reshaped evaluation](../../future-work/swiflowui-reshaped-evaluation.md)
> steal-list #2/#3 (full palette + OKLCH); recorded as deferred in the M8 roadmap entry.

## Problem

`swiflow theme --primary "#hex"` (PR #67) emits only `--sw-accent`; the six neutral tokens
(`--sw-bg`, `--sw-surface`, `--sw-surface-2`, `--sw-text`, `--sw-text-muted`, `--sw-border`) stay
the hand-authored defaults. Those defaults are near-gray and contrast-correct, so a generated
theme's surfaces/text **don't pick up the brand** — a violet-accented app still sits on
pure-gray chrome, which reads as disconnected. Mature systems (Radix, Reshaped) tint their
neutrals subtly toward the brand hue for cohesion while keeping text readable.

## Goal

Extend the generator with an opt-in `--neutrals` that derives the full neutral ramp from the
`--primary` seed — near-grays **tinted toward the accent hue**, light + dark, **contrast-proven**
(readable body/secondary text on every surface) — and emits them alongside the accent, including
a `prefers-contrast: more` layer so the accessibility boost the base sheet provides is preserved.

## Non-goals

- **Not always-on.** `--neutrals` is opt-in; `swiflow theme --primary X` stays accent-only
  (backward compatible with PR #67).
- **No `--tint` knob (v1).** The tint is a single tunable chroma constant in `SwiflowColor`, not
  a CLI option.
- **`--danger`/`--success` seeds, APCA, and a public (shipping) `SwiflowColor`** remain deferred.
- **No runtime color math.** Still a build-time CLI; the wasm stays lean.
- **Border contrast not gated** (see Validation) and surface/bg separation not validated.

## CLI surface

```
swiflow theme --primary "#7c3aed" --neutrals [--out path]
```
- `--neutrals` (flag, default false): also derive and emit the neutral ramp. Without it, output is
  exactly today's accent-only block.

## Architecture

Build on the existing `SwiflowColor` pipeline (`Color.hex`/`oklchFrom`/`okLabToOKLCH`/
`wcagContrast`/`hexString`) and the `swiflow theme` command. New `SwiflowColor` surface:

- `neutralPalette(accentHex:) -> [String: (light: String, dark: String)]` — the six neutral
  tokens as light/dark hex pairs, tinted to the accent hue.
- `validateNeutrals(_:) -> [PaletteFailure]` — WCAG checks on the derived neutrals.
- `accentThemeCSS(primaryHex:includeNeutrals:)` gains the `includeNeutrals` parameter (default
  `false`); when true it appends the neutral `:root` declarations and a
  `prefers-contrast: more` block, and folds neutral failures into the thrown `PaletteError`.

`SwiflowColor` stays native-only (CLI + tests); no dependency added to the wasm `SwiflowUI`.

## Algorithm — fixed lightness ramp × accent hue × small chroma

Each neutral token has a fixed `(L_light, L_dark)` OKLCH-lightness target, lifted from today's
defaults (the implementer reads them back from the current hex values; approximate targets):

| Token | L_light | L_dark | role |
|-------|:-------:|:------:|------|
| `--sw-bg` | 0.97 | 0.15 | page/canvas |
| `--sw-surface` | 1.00 | 0.20 | cards (lift off bg) |
| `--sw-surface-2` | 0.96 | 0.24 | subtle fills |
| `--sw-text` | 0.18 | 0.96 | body text |
| `--sw-text-muted` | 0.50 | 0.72 | secondary text |
| `--sw-border` | 0.92 | 0.30 | hairline separators |

Each token = `OKLCH(L, tintChroma, accentHue)` → gamut-clamp → `#rrggbb`, where `tintChroma` is a
single small constant (≈0.006–0.01, **tunable; validation is the safety net**) so neutrals read
as grays with a faint accent cast. `accentHue` = the OKLCH hue of the normalized `--primary`. The
`L_text`/`L_muted` targets are confirmed (or nudged) by validation to clear 4.5 on the surfaces.

## Validation

`validateNeutrals` asserts, in both light and dark modes:

- `--sw-text` on `--sw-surface` ≥ **4.5** (AA body text on cards)
- `--sw-text` on `--sw-bg` ≥ **4.5** (body text on the page)
- `--sw-text-muted` on `--sw-surface` ≥ **4.5** (AA secondary text)
- `--sw-text-muted` on `--sw-bg` ≥ **4.5**

These pass by construction (we control the lightnesses); the checks are the regression guard —
a tuning change that drops readable text below AA fails the build with a per-token diagnostic
(reusing `PaletteFailure`). **Border is intentionally not gated**: a hairline border is ~1.2:1
against its surface; gating at the 3:1 non-text bar would force heavy borders against the design
intent. The accessible-border need is met by the `prefers-contrast: more` layer below.

## `prefers-contrast: more` layer (required)

The base sheet (`Theme.swift`) re-points `--sw-text`/`--sw-text-muted`/`--sw-border` under
`@media (prefers-contrast: more)`. The generated theme CSS is included **after** the base sheet,
so a plain generated `:root` would override (clobber) that block under more-contrast — losing the
boost. Therefore, when `--neutrals` is set, the generator **also emits a
`@media (prefers-contrast: more) { :root { … } }` block** that re-points the neutral text/border
to high-contrast tinted values (text → near-black/white at the accent hue, heavier/darker
border). This mirrors how M8's `-strong` handles more-contrast (PR #66).

## Output shape

```css
/* Generated by `swiflow theme --primary #7c3aed --neutrals`. Include after SwiflowUI's styles. */
:root {
  --sw-accent: light-dark(#7c3aed, #9f7bff);
  --sw-bg: light-dark(#fdfcff, #100e13);
  --sw-surface: light-dark(#ffffff, #1a181d);
  --sw-surface-2: light-dark(#f6f4fa, #242128);
  --sw-text: light-dark(#16131a, #f6f4f8);
  --sw-text-muted: light-dark(#5c5866, #a8a2b2);
  --sw-border: light-dark(#e9e6ef, #332f3a);
}
@media (prefers-contrast: more) {
  :root {
    --sw-text: light-dark(#0a0810, #ffffff);
    --sw-text-muted: light-dark(#1c1922, #e8e4ee);
    --sw-border: light-dark(#0a0810, #ffffff);
  }
}
```

(Hex values above are illustrative — the implementer's `neutralPalette` produces the real ones;
the contrast tests pin correctness, not the exact hexes.) Accent-only output (no `--neutrals`) is
byte-for-byte unchanged from PR #67.

## Components & boundaries

| Unit | Responsibility | New? |
|------|----------------|------|
| `Color.neutralPalette(accentHex:)` | six neutral tokens as tinted light/dark hex pairs | new (`SwiflowColor`) |
| `Color.validateNeutrals(_:)` | WCAG checks on text/text-muted over surface+bg | new (`SwiflowColor`) |
| `Color.accentThemeCSS(primaryHex:includeNeutrals:)` | assemble accent (+ optional neutrals + more-contrast) CSS | extended |
| `ThemeCommand` | `--neutrals` flag → pass `includeNeutrals: true` | extended |

## Testing

- **`SwiflowColorTests`:**
  - `neutralPalette("#7c3aed")` — each token's light/dark OKLCH hue ≈ the accent hue, chroma is
    small (> 0 and below a low cap), and lightness ≈ the target band; output is well-formed
    `#rrggbb`.
  - `validateNeutrals` returns empty for the default-derived palette of a normal accent
    (`#3b82f6`, `#7c3aed`), and returns a `text`/`text-muted` failure for a contrived palette
    whose text lightness is forced too close to the surface (assert the guard actually fires).
  - `accentThemeCSS(primaryHex: "#7c3aed", includeNeutrals: true)` contains `--sw-surface:`,
    `--sw-text:`, and a `@media (prefers-contrast: more)` block; with `includeNeutrals: false`
    it contains none of the neutral tokens (accent-only unchanged).
- **CLI (`SwiflowCLITests`):** `theme --primary "#7c3aed" --neutrals --out <tmp>` writes a file
  containing `--sw-surface` and the more-contrast block, exit 0; without `--neutrals` the file has
  no `--sw-surface`.
- **Demo eyeball** (CI skips example builds): regenerate a themed demo with `--neutrals`, serve,
  confirm surfaces/text/borders carry the faint accent tint and body text stays readable in light
  and dark.

## Verification

`swift test` green (the new `SwiflowColor`/CLI tests); the accent-only path is unchanged.
`examples/` is untouched (no `EmbeddedTemplates.swift` regen — the generator is CLI-only output,
not an example edit).

## Decisions resolved during brainstorming

1. **Neutral model** → **accent-tinted neutrals** (low-chroma grays following the accent hue) —
   pure gray was rejected as ~equal to today's defaults; a separate `--neutral` seed deferred.
2. **Opt-in** → `--neutrals` flag; accent-only stays the default output.
3. **Border** → not contrast-gated (subtle by design); the `prefers-contrast: more` layer carries
   the accessible-border requirement.
