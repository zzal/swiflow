# SwiflowUI `--sw-warning` / `--sw-info` Status Tokens Design

> **Date:** 2026-06-26 · **Status:** approved, ready for implementation plan
> **Milestone:** M8 follow-up — introduces the two missing status tokens so the status set is
> complete (danger/success/**warning**/**info**), then bundles their generator seeds.
> **Unblocks:** the `--warning`/`--info` generator seeds deferred in the status-seeds PR (#71).

## Problem

SwiflowUI ships only two semantic status tokens — `--sw-danger` (red) and `--sw-success`
(green). The component layer already gestures at a fuller set but can't deliver it: `Toast` has
an `info` variant whose `.sw-toast--info` rule **doesn't exist**, so an info toast falls through
to the default neutral border; and there is no `warning` level anywhere (no token, no component
variant). A product can't render an amber "warning" toast/badge or a distinct "info" accent
without hand-authoring CSS. The status-seeds generator (#71) likewise can't offer `--warning`/
`--info` because the tokens they'd point at don't exist.

## Goal

Introduce `--sw-warning` and `--sw-info` into SwiflowUI's base sheet with the same rigor as
danger/success (default + `-strong` derivation + `prefers-contrast: more` + P3), wire them into
`Badge` and `Toast`, and extend `swiflow theme` with validated `--warning`/`--info` seeds.

## Decisions baked in (from brainstorming)

1. **`--sw-info` is an accent alias by default**, not a distinct shipped hue: `--sw-info:
   var(--sw-accent)`. Out of the box "info" renders in the brand color and tracks any
   `--primary`/accent override (including the accent's P3 upgrade). It remains an **independent,
   overridable token**: an app `:root` override or a `--info <hex>` generator seed makes it
   diverge from the accent.
2. **`--sw-warning` is a new amber**, full four-layer treatment. Shipped default
   `light-dark(#b45309, #fbbf24)` (amber-700 / amber-400) — chosen for contrast headroom
   (#b45309 = 5.02:1 on white as a border; amber-500 #f59e0b at 2.15:1 was rejected).
3. **Bundle both generator seeds** (`--warning`, `--info`) in this PR.
4. **Components touched: `Badge` + `Toast` only.** Other status usages (FieldChrome errors,
   Dropdown/Autocomplete) are danger-specific and unchanged.
5. Warning/info **stay polite** in Toast (`isAssertive` remains danger-only).

## Non-goals

- **No distinct info hue.** Info aliases the accent (decision 1); a separate sky/cyan default was
  considered and rejected.
- **No new components or new status usages.** Only Badge + Toast gain variants.
- **No change to danger/success.** Their token lines and component rules are untouched.
- **Still deferred:** APCA, p3 upgrade for a *generated* accent/status color, promoting
  `SwiflowColor` to a public (shipping) generator.

## Token design (`Sources/SwiflowUI/Theme.swift`)

Mirror the existing danger/success lines in each of the four layers. **Info gets no P3 raw line**
(it inherits the accent's via `var(--sw-accent)`); warning gets the full set.

### 1. `:root` defaults (after the `--sw-success` line)
```css
--sw-warning: light-dark(#b45309, #fbbf24);
--sw-info: var(--sw-accent);
```

### 2. base `-strong` (after the `--sw-success-strong` pair — literal fallback then `oklch(from …)`)
```css
--sw-warning-strong: light-dark(#92400e, #fbbf24);
--sw-warning-strong: light-dark(oklch(from var(--sw-warning) 0.40 c h), oklch(from var(--sw-warning) 0.80 c h));
--sw-info-strong: var(--sw-accent-strong);
--sw-info-strong: light-dark(oklch(from var(--sw-info) 0.40 c h), oklch(from var(--sw-info) 0.80 c h));
```
The literal first line is the pre-`oklch(from)` fallback (warning → amber-800/amber-400; info →
the accent's strong, correct for the alias default). The second line is the derived value that
also tracks a seeded raw token.

### 3. `prefers-contrast: more` (after the danger/success more-contrast strong overrides)
```css
--sw-warning-strong: light-dark(oklch(from var(--sw-warning) 0.30 c h), oklch(from var(--sw-warning) 0.88 c h));
--sw-info-strong: light-dark(oklch(from var(--sw-info) 0.30 c h), oklch(from var(--sw-info) 0.88 c h));
```

### 4. `@media (color-gamut: p3)` raw (after the `--sw-success` P3 line) — **warning only**
```css
--sw-warning: light-dark(color(display-p3 0.68 0.33 0.04), color(display-p3 0.98 0.75 0.14));
```
(display-p3 values approximate #b45309 / #fbbf24; the implementer tunes them to stay within the
amber family. No `--sw-info` P3 line — it resolves through `var(--sw-accent)`, which already has
one.)

## Component changes

### `Sources/SwiflowUI/Badge.swift`
`BadgeVariant` (`neutral, accent, danger, success`) → add `info, warning` (cases +
`modifierClass`). CSS (mirroring `.sw-badge--success`):
```css
.sw-badge--info    { background-color: color-mix(in oklab, var(--sw-info) 15%, var(--sw-surface)); color: var(--sw-info-strong); }
.sw-badge--warning { background-color: color-mix(in oklab, var(--sw-warning) 15%, var(--sw-surface)); color: var(--sw-warning-strong); }
```
`.info` is visually identical to the existing `.accent` until `--sw-info` is overridden — accepted.

### `Sources/SwiflowUI/Toast.swift`
`ToastVariant` (`info, success, danger`) → add `warning`. `info` already exists; add the missing
`.sw-toast--info` rule plus the new warning rule (mirroring `.sw-toast--success`):
```css
.sw-toast--info    { border-inline-start-color: var(--sw-info); }
.sw-toast--warning { border-inline-start-color: var(--sw-warning); }
```
`isAssertive` is unchanged (only `danger` is assertive).

## Generator seeds (`SwiflowColor` + `ThemeCommand`)

Extend `accentThemeCSS` with `warningHex:`/`infoHex:` (default `nil`), mirroring the
`dangerHex:`/`successHex:` mechanism from #71. Each provided seed is normalized, dark-derived via
`darkAccent(from:)`, validated, and emitted as a raw `--sw-…: light-dark(…)` line.

- **Validation:** `validateStatusFamily(name:lightHex:darkHex:rawBar:)` with **rawBar 3.0** for
  both warning and info (both are border/tint colors — Toast border, Badge tint — never raw text),
  and the derived `-strong` at ≥ 4.5 / 7. (Same profile as success in #71.)
- **Emit order in `:root`:** accent → danger → success → **warning → info** → neutrals.
- **CLI flags:** `swiflow theme … --warning <hex> --info <hex>`, both optional.
- **Backward compatible:** no `--warning`/`--info` → output byte-for-byte unchanged from #71
  (regression-guarded). The header command-echo lists only the flags supplied.

```
swiflow theme --primary "#7c3aed" --danger "#e11d48" --success "#059669" --warning "#d97706" --info "#0ea5e9" --neutrals
```

## Validation contract (what must hold)

- The **shipped** `--sw-warning` default `light-dark(#b45309, #fbbf24)` passes
  `validateStatusFamily(rawBar: 3.0)` (raw ≥ 3:1 on surface + `-strong` ≥ 4.5/7), both modes — a
  `SwiflowColorTests` guard asserts this so a future default tweak can't ship an inaccessible amber.
- A seeded `--warning`/`--info` that misses its bar fails the build with a per-token diagnostic
  (folds into `PaletteError.contrastFailures`).
- `--sw-info` default validation is **not** the generator's job (it's `var(--sw-accent)`; the
  accent is validated on its own).

## Components & boundaries

| Unit | Change | New? |
|------|--------|------|
| `Theme.swift` `baseStyleSheet` | `--sw-warning` (4 layers) + `--sw-info` (3 layers, no P3) | extended |
| `Badge.swift` | `info`/`warning` variants + CSS | extended |
| `Toast.swift` | `warning` variant + `.sw-toast--info`/`--warning` rules | extended |
| `accentThemeCSS(… warningHex:infoHex:)` | emit + validate the two seeds | extended |
| `ThemeCommand` | `--warning`/`--info` flags | extended |
| `examples/SwiflowUIDemo` | gallery: warning/info badges + toasts | extended |
| `EmbeddedTemplates.swift` | regen (demo is an embedded template) | regen |

## Testing

- **`ThemeTests` (SwiflowUI):** `baseStyleSheet` contains `--sw-warning`, `--sw-info`,
  `--sw-warning-strong`, `--sw-info-strong`, the warning P3 line, and the `@layer swiflow.base`
  wrapper still balances braces. Assert `--sw-info: var(--sw-accent)` is present (alias) and there
  is **no** `--sw-info:` P3 line.
- **Badge/Toast unit tests:** `Badge("x", variant: .warning)` emits `sw-badge--warning`;
  `.info` emits `sw-badge--info`; a `.warning` toast emits `sw-toast--warning`; the stylesheet
  includes the four new rules.
- **`SwiflowColorTests`:** shipped warning default passes `validateStatusFamily(rawBar: 3.0)`;
  `accentThemeCSS(primaryHex:…, warningHex: "#d97706", infoHex: "#0ea5e9")` contains `--sw-warning`
  and `--sw-info` in the right order; no-seed output is byte-for-byte unchanged; a washed
  warning/info throws.
- **`SwiflowCLITests`:** `theme … --warning … --info …` writes both tokens; without them, neither
  appears.
- **Playwright (local; CI skips example builds):** a rendered warning `Badge` resolves a non-empty
  `background-color` derived from the amber token (distinct from the success badge), and a warning
  `Toast` shows the amber border. Re-run `theming.spec.ts` to confirm the base-sheet additions
  didn't break the media-feature flips.
- **Demo eyeball:** the gallery shows danger/success/**warning**/**info** badges + toasts, readable
  in light + dark.

## Verification

`swift test` green; build the demo locally (`swiflow build --path examples/SwiflowUIDemo`) and
serve it ([[ci-skips-example-builds]]); run the Playwright suite locally with a freshly built
release CLI ([[run-e2e-locally-before-push]], [[no-subagent-playwright]] — run e2e inline,
detached, after killing leftovers). Regenerate `EmbeddedTemplates.swift` and commit it
([[ci-swift-6.3.2]] freshness gate). Update the theming guide + roadmap.

## Decisions resolved during brainstorming

1. **Info identity** → alias the accent (`--sw-info: var(--sw-accent)`), independently overridable;
   a distinct sky/cyan default was rejected.
2. **Seeds** → bundle both `--warning` and `--info` (the latter lets info diverge from the accent).
3. **Badge `.info`** → added despite cloning `.accent` by default (symmetry with Toast levels).
4. **Warning default** → amber-700 `#b45309` light / amber-400 `#fbbf24` dark, for contrast
   headroom over amber-600 `#d97706` (3.19:1).
5. **Scope** → Badge + Toast only; warning/info polite in Toast.
