# SwiflowUI Status-Color Seeds (`swiflow theme --danger/--success`) Design

> **Date:** 2026-06-26 · **Status:** approved, ready for implementation plan
> **Milestone:** Second **M8 deferral** — extends the palette generator (M8 part 2, PR #67;
> neutrals deferral PR #70) from accent-only to optional brand status colors.
> **Origin:** the [Reshaped evaluation](../../future-work/swiflowui-reshaped-evaluation.md)
> steal-list (semantic color seeds); recorded as deferred in the M8 roadmap entry.

## Problem

`swiflow theme --primary "#hex" [--neutrals]` re-points the brand accent (and, opt-in, the
accent-tinted neutral ramp), but the two semantic **status** tokens — `--sw-danger` and
`--sw-success` — stay the hand-authored red/green defaults. A product with a brand-specific
error red or success green (e.g. a rose `#e11d48` danger, an emerald `#10b981` success) has no
generator path to set them; they'd have to hand-author the `light-dark()` pair and guess at
contrast. Status colors are **fixed-hue semantic** colors (red means danger, green means
success) — unlike the accent they are NOT derived from the brand hue — so they need their own
opt-in seed inputs.

## Goal

Add two **opt-in** flags, `--danger <hex>` and `--success <hex>`, that each derive a
contrast-validated `light-dark()` override for the corresponding token (dark counterpart derived
the same way the accent's is), validated against **how each token is actually used**, and emit
them into the same generated `:root`. Omitting a flag leaves that token at its shipped default.

## Non-goals

- **Not always-on.** Both flags are opt-in; `swiflow theme --primary X` output is byte-for-byte
  unchanged (so is `--primary X --neutrals`).
- **No auto-derivation from the accent hue.** Status colors keep their own seed hues; we do not
  rotate the accent into red/green (rejected in brainstorming — weakens the semantic signal).
- **No `--warning`/`--info` seeds.** There are no `--sw-warning`/`--sw-info` tokens in the system;
  adding them is a separate, larger feature (new base-sheet tokens). Out of scope.
- **No new base-sheet or component change.** The base sheet already derives `-strong`
  (+ its `prefers-contrast: more` and P3 variants) from `var(--sw-danger)`/`var(--sw-success)`;
  overriding the raw token cascades automatically.
- **No demo / Playwright change.** Pure generator output, no base-sheet/component/cascade change;
  `swift test` fully covers it. (No release-CLI rebuild, no `examples/`/`EmbeddedTemplates.swift`
  regen — same as the neutral PR's generator half.) APCA, a public/shipping `SwiflowColor`, and
  a p3 upgrade for generated seeds remain deferred.
- **No runtime color math.** Still a build-time CLI; `SwiflowColor` stays native-only.

## CLI surface

```
swiflow theme --primary "#7c3aed" --danger "#e11d48" --success "#10b981" [--neutrals] [--out path]
```

- `--danger <hex>` (optional): brand danger/error color (light-mode), `#rgb` or `#rrggbb`.
- `--success <hex>` (optional): brand success color (light-mode), `#rgb` or `#rrggbb`.
- Both compose freely with `--neutrals` and with each other. `--primary` stays required.
- Omitting either flag → that token is **not** emitted (keeps the shipped default).

## Architecture

Build on the existing `SwiflowColor` pipeline and `swiflow theme`. The dark counterpart of each
seed is derived with the **same** `darkAccent(from:)` transform the accent uses (OKLCH L+0.10
clamped, C×0.78), so a status seed behaves exactly like the accent seed. The generator emits only
the **raw** token override:

```css
--sw-danger:  light-dark(<seed>, <darkSeed>);
--sw-success: light-dark(<seed>, <darkSeed>);
```

The base sheet (`Theme.swift`) already re-derives `--sw-danger-strong`/`--sw-success-strong`
(normal, `prefers-contrast: more`, and P3) from `var(--sw-danger)`/`var(--sw-success)` via
`oklch(from …)`. Because the generated `:root` is unlayered it wins the cascade over the
`@layer swiflow.base` definitions (and over the base sheet's `@media (color-gamut: p3)` raw
re-point — the seed wins on P3 displays too, the same accepted tradeoff as the accent/neutral
overrides). **Therefore the generator emits no extra `@media` block for status colors** (unlike
`--neutrals`, whose `:root` would have clobbered the base more-contrast text/border re-point).

### New `SwiflowColor` surface

- `accentThemeCSS(primaryHex:dangerHex:successHex:includeNeutrals:)` — extends the existing
  function with two optional hex parameters (default `nil`). When a seed is non-nil it is
  normalized, dark-derived, validated, and its `--sw-…: light-dark(…)` line is added to `:root`.
- `validateStatusFamily(name:lightHex:darkHex:rawBar:) -> [PaletteFailure]` — the generalized
  status validator (below), called once per provided seed (`rawBar` 4.5 for danger, 3.0 for
  success). Factored from `validateAccentFamily`'s shared machinery (`mixOKLab` tint,
  `oklchFrom`, the `strongAA`/`strongAAA` lightness constants, `surfaceLight`/`surfaceDark`,
  `tintWeight`), which it reuses rather than duplicates.

`SwiflowColor` stays native-only (CLI + tests); no dependency added to the wasm `SwiflowUI`.

## Validation — per-usage bars

Each status token is validated **against how it is actually rendered** (confirmed by auditing
component usage), in both light and dark modes:

| Check | Bar | Why |
|-------|:---:|-----|
| raw `--sw-danger` on surface | ≥ **4.5** | error message text + invalid-field legend (`FieldChrome`) render the raw color as text |
| raw `--sw-success` on surface | ≥ **3.0** | only borders/tints (`Toast` border, `Badge` `color-mix` background) — never text |
| `-strong` = `oklchFrom(seed, 0.40 light / 0.80 dark)` on the 15% tint | ≥ **4.5** | `-strong` is badge/dropdown text on the tinted surface |
| `-strong` = `oklchFrom(seed, 0.30 light / 0.88 dark)` on the 15% tint | ≥ **7** | the `prefers-contrast: more` boost |

Where the tint = `mixOKLab(seed, surface, weightBase: 0.15)` and surface =
`#ffffff` (light) / `#1a1a1a` (dark) — the exact constants `validateAccentFamily` already uses.
**No `-text`/`contrast-color` check** — there are no solid-fill status buttons (the accent's
`-text` check exists only for `Button`'s solid accent fill).

The asymmetric raw bar (danger 4.5, success 3.0) is deliberate and faithful to usage: the shipped
defaults `#dc2626` (danger, 4.83:1 on white) and `#16a34a` (success, 3.30:1 on white) **both
pass**, and the example seeds `#e11d48`/`#10b981` pass. A uniform 4.5 raw bar was rejected because
it would reject the framework's own default green and over-gate a token that is never text.

Failures fold into the existing `PaletteError.contrastFailures([PaletteFailure])` (the build
fails with a per-token, per-mode diagnostic naming the token, mode, actual ratio, and target).
`PaletteFailure.token` carries the real token name (e.g. `--sw-success-strong (more-contrast)`).

## Output shape

`--primary` + both status seeds (no `--neutrals`):

```css
/* Generated by `swiflow theme --primary #7c3aed --danger #e11d48 --success #10b981`.
   Include after SwiflowUI's styles. Re-points --sw-accent (family cascades) + status colors. */
:root {
  --sw-accent:  light-dark(#7c3aed, #9f7bff);
  --sw-danger:  light-dark(#e11d48, <derived>);
  --sw-success: light-dark(#10b981, <derived>);
}
```

(Dark hexes are illustrative — `darkAccent` produces the real ones; contrast tests pin
correctness, not exact hexes.) Ordering inside `:root`: **accent, then danger, then success,
then neutrals** (if `--neutrals`). When `--neutrals` is also set, the neutral lines and the
neutral `@media (prefers-contrast: more)` block append exactly as in PR #70 — status colors add
no media block of their own.

**Backward compatibility (regression-guarded):** with both status seeds `nil`, the output is
byte-for-byte the existing accent-only (PR #67) or accent+neutrals (PR #70) block. The generated
comment header echoes only the flags actually supplied.

## Components & boundaries

| Unit | Responsibility | New? |
|------|----------------|------|
| `Color.validateStatusFamily(name:lightHex:darkHex:rawBar:)` | raw (per-bar) + `-strong` (4.5/7) WCAG checks for one status token, light+dark | new (`SwiflowColor`) |
| `Color.accentThemeCSS(primaryHex:dangerHex:successHex:includeNeutrals:)` | assemble accent (+ optional danger/success/neutrals) CSS; validate each seed | extended |
| `ThemeCommand` | `--danger`/`--success` `@Option`s → pass through | extended |

## Testing

- **`SwiflowColorTests`:**
  - `validateStatusFamily("--sw-danger", light: "#e11d48", dark: <derived>, rawBar: 4.5)` and the
    success equivalent return **empty** for the example seeds and for the **shipped defaults**
    (`#dc2626` raw-bar 4.5, `#16a34a` raw-bar 3.0).
  - The danger raw bar **fires**: a contrived washed danger (e.g. a pale pink whose raw < 4.5 on
    white) returns a `--sw-danger` failure; a `-strong` failure fires for a seed whose derived
    `-strong` can't clear 4.5/7 on the tint. (Assert the guards actually fail, per the
    [[assertmacroexpansion-peer-divergence]] lesson — must-fire tests, not just must-pass.)
  - `accentThemeCSS(primaryHex: "#7c3aed", dangerHex: "#e11d48", successHex: "#10b981")` contains
    `--sw-danger:` and `--sw-success:` and **no** neutral tokens / no `@media` block; with both
    `nil` the output is **byte-for-byte** the existing accent-only string (golden test); with
    `dangerHex` set but `successHex` nil, only `--sw-danger` appears.
  - Composes with neutrals: `…dangerHex: "#e11d48", includeNeutrals: true` contains `--sw-danger`,
    `--sw-surface`, and the neutral `@media (prefers-contrast: more)` block.
  - A bad status hex throws `PaletteError.invalidHex`.
- **`SwiflowCLITests`:** `theme --primary "#7c3aed" --danger "#e11d48" --success "#10b981" --out
  <tmp>` writes a file containing `--sw-danger` and `--sw-success`, exit 0; without the flags the
  file has neither (accent-only unchanged). A contrast-failing seed exits non-zero with the
  per-token diagnostic.

## Verification

`swift test` green (new `SwiflowColor`/CLI tests; the accent-only and accent+neutrals paths are
unchanged — golden tests prove it). **No demo, Playwright, release-CLI rebuild, or
`EmbeddedTemplates.swift` regen** — the generator's output is CLI-only and touches no `examples/`
file and no shipping CSS. Dispatch the final code reviewer over the branch.

## Decisions resolved during brainstorming

1. **Seed model** → opt-in `--danger`/`--success` hex seeds (parallel to `--primary`); accent-only
   stays the default output. Auto-derivation from the accent hue was rejected (weakens semantics);
   "emit the defaults explicitly" was rejected (no value).
2. **Validation** → per-usage bars: raw danger ≥ 4.5 (it's error text), raw success ≥ 3.0
   (border/tint only), both `-strong` ≥ 4.5/7. A uniform 4.5 raw bar was rejected because it
   rejects the shipped default green (`#16a34a` = 3.30:1) and over-gates a never-text token.
3. **Scope** → danger + success only (the only existing status tokens); no warning/info.
4. **No media block for status** → unlike neutrals, the base sheet re-derives `-strong`
   (incl. more-contrast + P3) from the raw token, so overriding the raw token is sufficient.
5. **No demo/Playwright** → pure generator output, no cascade/base-sheet change; `swift test` is
   the complete gate.
