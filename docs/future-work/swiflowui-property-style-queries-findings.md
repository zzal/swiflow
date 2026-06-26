# SwiflowUI `@property` + style-query spike — Findings

> Spike from `docs/superpowers/specs/2026-06-26-swiflowui-property-style-queries-design.md`.
> Source: Una Kravets, ["Modern CSS Theming"](https://una.im/modern-css-theming) (una.im, 2026).
> Date: 2026-06-26.

## Shipped

### Scalar `@property` registration

Spacing scale, `--sw-radius`/`-sm`, `--sw-border-width`, `--sw-focus-ring-width`,
`--sw-duration`, `--sw-disabled-opacity` are registered (`syntax`/`inherits: true`/
`initial-value`), so they are **type-validated** and **animatable**. The block sits outside
`@layer swiflow.base` (the at-rule is layer-agnostic). Visual no-op. Proven live by a Playwright
probe: a registered `<length>` rejects an invalid override (`--sw-border-width: banana` → stays
the inherited `1px`); an unregistered property would echo `"banana"`.

Immediate payoff already available: `--sw-border-width` / `--sw-focus-ring-width` thicken under
`prefers-contrast: more`, and a component naming `transition: border-width var(--sw-duration)`
now gets a smooth thicken instead of a snap.

### Color-token registration — **SHIPPED**

The surface/text/accent/status/`-strong`/border/focus-ring tokens are registered as `<color>`
(`inherits: true`, light-arm-hex `initial-value` — `light-dark()` is not a valid
computation-independent `initial-value`, so the light hex is the bottom-of-cascade floor).
`--sw-shadow`/`--sw-overlay-bg`/`--sw-backdrop` are excluded (not plain `<color>`).

The decision gate (ship only if the literal→`oklch(from …)` progressive fallback survives
registration) **passed on all four checks**:

1. **Emitted-CSS unit test** — both declarations (literal line + `oklch(from …)` line) are still
   physically present for a sample token; `progressiveEnhancementPairsEmitted` and `bracesBalanced`
   stay green (37 ThemeTests pass).
2. **Host build** — `swift build` exit 0.
3. **Demo build** — `swiflow build --path examples/SwiflowUIDemo` exit 0; registration is a build
   no-op.
4. **Runtime probe** — a registered `<color>` resolves to a real color and an invalid override
   falls to the *inherited* `:root` value (not garbage, not the `initial-value`). The pre-existing
   "app `:root` `--sw-accent` override wins over the base sheet" test **still passes**, confirming
   registration did not disturb the unlayered-beats-layered override mechanism.

Why the fallback is safe: an `oklch(from …)` value a browser can't understand is rejected at
**parse time**, *before* registered-syntax (computed-value-time) validation runs — so the literal
declaration earlier in the cascade still wins on pre-Baseline engines exactly as it did before
registration. Registration adds computed-value validation; it does not change parse-time grammar
handling.

## `@container style()` — investigation only, **DEFER**

**Pipeline survival: trivially yes.** SwiflowUI injects component CSS as a *raw string* at runtime
(via `installControlSheet` / the JS driver) — there is **no CSS-level minifier or transform** in
our build. A throwaway `@container badge style(--sw-detector: white)` block (with `contrast-color()`
as the light/dark-surface detector, behind `@supports`) appeared **byte-for-byte** in the built
`App.wasm`. So *any* modern CSS feature reaches the browser verbatim; our toolchain never gates CSS
syntax. The only adoption gate is **browser support**, not the pipeline.

**Recommendation: DEFER.** Rationale:

- `@container style()` queries on custom properties have **no Firefox support** as of 2026, so the
  pattern can only ever be a progressive enhancement layered *over* a cross-engine fallback.
- That cross-engine fallback already exists and works: the `-strong` tokens solve tint-text
  readability in every engine today. Adopting style queries now adds per-component `@supports`
  duplication for a cosmetic gain on two of three engines.
- The prerequisite is now in place: `@property` registration (shipped above) is what a future
  style-query / `contrast-color()`-detector pass would build on. Revisit if/when Firefox ships
  `style()` queries, or if an app need arises that `-strong` genuinely can't serve (e.g. text on a
  fully arbitrary app-supplied surface color).

`-strong` remains the shipped tint-text mechanism. No component behavior changed in this spike.

## Browser baseline (2026)

| Feature | Chrome | Safari | Firefox |
|---------|--------|--------|---------|
| `@property` registration | ✅ | ✅ | ✅ |
| `light-dark()` / relative color syntax | ✅ | ✅ | ✅ |
| `@container style()` (custom properties) | ✅ | ✅ | ❌ |
| `contrast-color()` | ✅ | ✅ | ⚠️ partial |
| `@function` (custom CSS functions) | ⚠️ 139+ | ❌ | ❌ |
