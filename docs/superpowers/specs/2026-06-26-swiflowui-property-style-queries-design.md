# SwiflowUI `@property` registration + style-query spike — Design

> **Date:** 2026-06-26 · **Status:** approved, ready for implementation plan
> **Milestone:** M9 (1.1) — *Modern CSS theming primitives* (roadmap candidate).
> **Origin:** Una Kravets, ["Modern CSS Theming"](https://una.im/modern-css-theming) (2026).
> **Builds on:** the M8 contrast/`-strong` token system (#66) and the media-feature-first
> base sheet (`Sources/SwiflowUI/Theme.swift`).

## Problem

The article splits theming into **macro** (page-level `light-dark()`) and **micro**
(per-component palette derivation in CSS), and surfaces three primitives we don't yet use:
`@property` registration, `@container style()` queries, and `contrast-color()`. Two of its
techniques we already ship (`light-dark()`; relative color syntax for `-strong`/p3). Of the
rest, `@property` registration is a cross-engine-safe, immediately useful win, and
`@container style()` is a *potential* standards-based replacement for the `-strong` soft-tint
workaround — but it has **no Firefox support** as of 2026, so it cannot replace a mechanism
that must work in every engine.

This spike lands the safe half and *investigates* the rest without disturbing the proven
`-strong` system.

## Goal

1. **Ship** `@property` registration for the `--sw-*` tokens where it is unambiguously safe,
   making those tokens **typed** (validated) and **animatable** (transitionable).
2. **Investigate** whether color tokens can also be registered without breaking the existing
   progressive double-declaration fallback; ship color registration only if proven safe.
3. **Investigate** `@container style()` end-to-end in our dev/build/wasm pipeline as a
   throwaway proof-of-concept, and record an adopt/defer recommendation. Ship nothing from
   this part.

The `-strong` tint-text mechanism (`Theme.swift` lines 79–93) is **unchanged**. No component's
shipped behavior changes.

## The critical engineering risk (drives the scope split)

`baseStyleSheet` relies on a **progressive double-declaration** pattern for derived colors:
a literal fallback first, then an `oklch(from …)` / `contrast-color()` line, e.g.

```css
--sw-accent-hover: light-dark(#2563eb, #7cb0fb);
--sw-accent-hover: light-dark(oklch(from var(--sw-accent) calc(l - 0.08) c h), …);
```

This works today because a browser that cannot parse `oklch(from …)` rejects that declaration
**at parse time**, so the literal declaration remains the cascaded value.

Registering a custom property (`@property … { syntax: "<color>"; … }`) adds **computed-value-time**
validation on top of parse-time grammar. The open question this spike must answer empirically:

> When a registered `<color>` property receives an `oklch(from …)` value the browser can't
> parse, does the literal fallback still win (parse-time rejection, as today), or does the
> token fall to the `@property` `initial-value` instead — silently regressing pre-Baseline
> browsers?

Expectation (to be **verified, not assumed**): parse-time grammar rejection happens *before*
registered-syntax validation, so the literal fallback should still win. But this is exactly the
kind of cascade subtlety that bites silently, so it is gated behind a real test before any color
token is registered.

This risk is why the work splits into **always-safe scalars** (ship) vs. **colors** (ship only
if proven).

## Work units

### Unit A — Register the scalar (non-color) tokens · **ships**

These tokens are single-declaration (no fallback chain), so registration carries none of the
risk above. Register with `inherits: true` (every `--sw-*` token is set at `:root` and read by
descendants) and the current value as `initial-value`:

| Token(s) | `syntax` | `initial-value` |
|----------|----------|-----------------|
| `--sw-space-xs/sm/md/lg/xl` | `<length>` | `0.25rem` / `0.5rem` / `0.75rem` / `1.25rem` / `2rem` |
| `--sw-radius-sm`, `--sw-radius` | `<length>` | `4px` / `8px` |
| `--sw-border-width` | `<length>` | `1px` |
| `--sw-focus-ring-width` | `<length>` | `2px` |
| `--sw-duration` | `<time>` | `150ms` |
| `--sw-disabled-opacity` | `<number>` | `0.5` |

Concrete payoff:
- **Type safety** — an app override with a bad unit is caught/ignored rather than poisoning the
  cascade.
- **Animatable** — registered `<length>`/`<time>` tokens interpolate. The immediate example:
  `--sw-border-width` (and `--sw-focus-ring-width`) thicken under `prefers-contrast: more`; once
  registered, a component naming `transition: border-width var(--sw-duration)` gets a smooth
  thickening instead of a snap. (No component is *required* to add such a transition in this
  spike; registration just makes it possible.)

`@property` rules are emitted **outside** the `@layer swiflow.base { … }` wrapper (the at-rule is
layer-agnostic; placing it outside keeps intent clear). The `initial-value` sits below every
cascade origin, so app `:root` overrides — including the unlayered-beats-layered mechanism the
base sheet depends on — still win.

### Unit B — Color-token registration · **investigate, conditional ship**

Determine the fallback-chain behavior from the risk section above:

1. **Host build + reasoning:** register the color tokens as `<color>` (`inherits: true`,
   literal `initial-value`) in a working copy and confirm a modern build renders identically.
2. **Fallback probe:** in Playwright, force the second (derived) declaration to a value the
   engine treats as invalid and assert the token still resolves to the **literal**, not the
   `initial-value`. (A registered token falling to `initial-value` here is the regression
   signal.)

**Decision gate:**
- **If the literal fallback is proven intact** → ship color registration too (unlocks
  animatable color tokens + the `@property` prerequisite for any future style-query work).
- **If it falls to `initial-value`** → do **not** register colors; document the exact failure
  mode in the findings and leave color registration deferred. Unit A still ships.

Color tokens in scope *if* this passes: `--sw-bg`, `--sw-surface`, `--sw-surface-2`,
`--sw-text`, `--sw-text-muted`, the accent family, the status tokens, the `-strong` family,
`--sw-border`, `--sw-focus-ring`. (`--sw-shadow`, `--sw-overlay-bg`, `--sw-backdrop` are *not*
plain `<color>` — they're shadow/length/filter values — and are out of scope for registration.)

### Unit C — `@container style()` proof-of-concept · **never ships**

A throwaway demo proving the mechanism survives our toolchain end-to-end:

- Add a scratch tinted variant (e.g. a Badge styled via `@container style(--detector: …)` with
  `contrast-color()` as the light/dark-surface detector, the article's pattern) **behind an
  `@supports`** guard so non-supporting engines keep `-strong`.
- Build it locally through `swiflow build` (dev **and** release/minified CSS path) and confirm:
  the `@container`/`style()`/`contrast-color()` syntax passes through our CSS emission and the
  minifier intact, renders on a supporting engine, and falls back cleanly elsewhere.
- **Revert the scratch code before merge.** Its only output is the findings entry.

Findings to record: does it work in dev + minified build; what adopting it for real micro-theming
would cost (per-component CSS, `@supports` fallback duplication, the Firefox gap); and an
explicit **adopt / defer** recommendation. `-strong` remains the shipped text mechanism
regardless.

## Files

| File | Change | Ships? |
|------|--------|--------|
| `Sources/SwiflowUI/Theme.swift` | Add the `@property` block to `baseStyleSheet` (scalars always; colors iff Unit B passes), before the `@layer swiflow.base {` line | ✅ |
| `Tests/SwiflowUITests/ThemeTests.swift` | Assert each registered `@property` rule is emitted with the correct `syntax` / `inherits` / `initial-value` | ✅ |
| `Tests/playwright/theming.spec.ts` | Probe: a registered scalar resolves to its typed computed value; **if** Unit B ships, a probe that the literal fallback still wins under an invalid derived value | ✅ (cond.) |
| `docs/future-work/swiflowui-property-style-queries-findings.md` | Findings doc: Unit B verdict + mechanism, Unit C verdict + recommendation, browser-baseline table | ✅ |
| `docs/future-work/swiflowui-1.0-roadmap.md` | Update the M9 entry: `@property` shipped; record color + style-query verdicts | ✅ |
| scratch Badge/demo for Unit C | Built locally, **reverted before merge** | ❌ |

`SwiflowUI` stays wasm-only; no native dependency added. No `SwiflowColor` change (this is pure
CSS-side work).

## Testing & verification

- **Host build** (`swift build`) — CI skips examples, so this is the authoritative check for
  token/CSS regressions.
- **Unit (durable contract):** emitted-CSS assertions for the `@property` rules in `ThemeTests`.
- **Playwright (local):** the scalar-resolves probe, plus the fallback-intact probe if colors
  ship. Build the release CLI first ([[run-e2e-locally-before-push]]); run inline/detached after
  killing leftovers ([[no-subagent-playwright]]).
- **Demo eyeball:** `swiflow build --path examples/SwiflowUIDemo` ([[ci-skips-example-builds]])
  renders identically — registration must be visually a no-op.
- **Embed freshness:** the shipped diff must not touch `examples/` (the Unit C scratch is
  reverted), so the `TemplateEmbedder` freshness gate stays green; verify a clean `git status`
  for `examples/` before merge ([[ci-swift-6.3.2]]).

## Non-goals

- No change to `-strong`, to Badge's shipped behavior, or to any component's text mechanism.
- No broader `contrast-color()` adoption; no `@function` (Chrome-139-only per the article).
- No shipping of the `@container style()` layer (Unit C is investigation only).

## Decisions resolved during brainstorming

1. **End-state** → investigate, ship the low-risk part (`@property` registration), findings doc
   for the rest. (Full Badge conversion and pure-throwaway were rejected.)
2. **Tint-text mechanism** → keep `-strong`; style queries do **not** take over picking tint
   text in this spike.
3. **Style-query half** → a non-shipped proof-of-concept that validates the mechanism in our
   pipeline and yields an adopt/defer recommendation. (Dropping it entirely was rejected — the
   M9 roadmap item promised the investigation.)
4. **Color registration** → conditional: ship only if the progressive double-declaration
   fallback is proven intact under registration; otherwise defer with the failure documented.
