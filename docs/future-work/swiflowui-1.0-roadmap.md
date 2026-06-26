# SwiflowUI → 1.0 Roadmap

> Companion to [`roadmap.md`](roadmap.md) (Theme B3, "UI core components"). This document
> scopes the concrete component set, theming foundation, and milestone sequence for a 1.0
> SwiflowUI release.

## Why

SwiflowUI v0 shipped intentionally minimal — `VStack`/`HStack`, `.padding()`/`.gap()`, the
`Spacing`/`CrossAlign`/`MainAlign` token enums, and a `:root` base stylesheet
(`Sources/SwiflowUI/{Stack,Modifiers,Tokens,Theme}.swift`, ~270 LOC). Everything else apps
need today comes from **core Swiflow**: 28 raw HTML element factories, the modifier/event
system, two-way bindings (`.value`/`.checked`/`.selection`), `Ref`, `Form`/`Validator`, and
the `#css` macro.

The gap shows up as **hand-rolled UI in every real app**: the HelloWorld scaffold rolls its
own Toast, SignIn modal, and AboutPopover; MissionControl rolls every form field, inline
error text, list-row factories, and an `isFetching` spinner. A 1.0 SwiflowUI should retire
that hand-rolling with a small, consistent, ready-to-use component set — without abandoning
the CSS-first, token-driven philosophy of v0.

## Direction

- **Identity — Hybrid:** CSS-first layout/overlay primitives *plus* a small set of
  lightly-skinned, token-deferring controls that look decent out of the box but defer all
  visual choices to `--sw-*` tokens and `#css` overrides.
- **Overlays — Native-first:** build on `<dialog>` + the Popover API (the approach the
  scaffold already proves), not a custom portal host.
- **Scope — Comprehensive:** the core set *plus* all four stretch components.
- **A11y — Native-leaning baseline:** build on semantic elements so roles/keyboard/focus
  come for free; add ARIA only where we depart from native; document any gaps.
- **Theming — Media-feature-first:** the token layer is designed up front so app-wide visual
  behavior responds to CSS media features (`light-dark()`/`prefers-color-scheme`,
  `prefers-contrast`, `prefers-reduced-motion`, `prefers-reduced-transparency`,
  `color-gamut`). Components never branch on these — they read tokens, and media-query layers
  re-point the tokens.

**Outcome:** a credible, accessible SwiflowUI 1.0 that a freshly-scaffolded app can build a
real UI from without dropping to raw HTML for common patterns — shipped with no hard
framework blockers, a component gallery demo, and Playwright coverage.

---

## Theming foundation (designed up front)

The single load-bearing decision: **every color, space, radius, border, motion, and
transparency value a component renders reads a `--sw-*` token** — components never branch on
user/device preferences. Responsiveness to CSS media features is then expressed once, as
token-override layers in `baseStyleSheet` (`Sources/SwiflowUI/Theme.swift`), and every
component adapts for free. The core `CSSSheet` / `CSSEntry.group(prefix:, entries:)` case
already emits `@media` wrappers, so no new CSS machinery is needed.

Token layers (base values at `:root`; each media block overrides only the affected tokens):

| Media feature | Tokens it re-points | Effect |
|---------------|---------------------|--------|
| `light-dark()` / `prefers-color-scheme` | `--sw-surface`, `--sw-text`, `--sw-accent`, … | light/dark palettes (already in v0) |
| `prefers-contrast: more` | text/border/accent colors, `--sw-border-width` | stronger contrast, heavier borders |
| `prefers-reduced-motion: reduce` | `--sw-duration` → `0s`, `--sw-anim-play` → `paused` | transitions collapse & animations pause |
| `prefers-reduced-transparency: reduce` | `--sw-overlay-bg` opaque, `--sw-backdrop` → `none` | toasts & dialog backdrops become solid |
| `color-gamut: p3` | color tokens → `color(display-p3 …)` (sRGB fallback at `:root`) | richer color on capable displays |

Consequences for the component set: `Alert`/`Prompt`/`Toast` reference
`--sw-duration`/`--sw-overlay-bg`, so they honor reduced-motion / reduced-transparency with
zero per-component code; `Button`/`Card`/`Badge` re-skin entirely through these tokens. This
is why **M2 (theming foundation) precedes every skinned component.**

---

## The 1.0 component set

Conventions (consistent with the existing codebase):
- **Stateless components → free functions** returning `VNode` (matches `VStack`/`HStack`).
  This covers layout *and* the controls (Button, the M4 form controls): they wrap native
  elements + a `Binding` and hold no internal state, so native semantics (checkbox/radio/
  select keyboard + roving focus) come for free.
- **Only genuinely stateful components → `@Component` classes** (the overlays' queue/open
  state; matches `SwiflowRouter`'s `Link`).
- **Styling:** stateless controls inject a global, token-only `.sw-*` utility-class sheet once
  via `installControlSheet(id:_:)` (raw CSS — the classes are unscoped); `@Component`s use
  `scopedStyles` (auto-scoped to `.swiflow-<Type>`). Every color/space/radius reads a `--sw-*`
  var so apps re-skin via tokens or `#css` with no API change.
- **Data:** reuse existing `Binding<T>` two-way bindings (`Sources/Swiflow/DSL/EventModifiers.swift`)
  and `Form`/`Validator` (`Sources/Swiflow/Forms/Form.swift`) — no new state machinery.

| Component | Kind | Native basis | A11y notes | Framework dep |
|-----------|------|--------------|------------|---------------|
| `Grid` | free fn | `display:grid` | n/a | none |
| `Spacer` | free fn | flex-grow filler | n/a | none |
| `Divider` | free fn | `<hr>`/styled rule | `role=separator` (native `<hr>`) | none |
| `ZStack` | free fn | absolute/grid overlap | n/a | none |
| `Button` | free fn / modifier | `<button>` | native button semantics | none |
| `TextField` | free fn | `<label>`-wrapped `<input>` | implicit label assoc, `aria-invalid` + `role=alert` error | none |
| `Toggle` | free fn | `<input type=checkbox role=switch>` + track/thumb | a **switch** (immediate setting); `role=switch` | none |
| `Checkbox` | free fn | `<label>`-wrapped `<input type=checkbox>` | a **checkbox** (selection/confirmation); native semantics | none |
| `Select` | free fn | `<select>` | native listbox semantics | none |
| `RadioGroup` | free fn | `<input type=radio>` name-group | native roving focus (shared `name`) | none |
| `Spinner`/`ProgressView` | free fn | CSS animation / `<progress>` | `role=status`/`aria-busy` | none |
| `Card` | free fn | styled surface div | n/a | none |
| `Badge`/`Tag` | free fn | styled span | n/a | none |
| `Alert` | `@Component` | `<dialog>.showModal()` | top-layer+focus-trap+ESC free | none (click-outside ⇒ #4) |
| `Prompt` | `@Component` | `<dialog>` + form `method=dialog` | returns value via `close(value)` | none (click-outside ⇒ #4) |
| `Toast` | `@Component` | Popover API + queue | `role=status` live region | none |

**Native-first removes the 1.0 blockers.** `<dialog>.showModal()` provides top-layer
rendering, backdrop, focus trap, and ESC-to-close natively; dismissal uses ESC + explicit
buttons. Toast uses the Popover API + a small dismiss queue (the scaffold's `after()`
pattern). The only roadmap enabler that touches this set, **`EventInfo` target identity
(roadmap cross-cutting #4)**, is needed *only* for click-outside-to-dismiss polish — an
optional enhancement, not a gate. **Portal host (#3) is deferred entirely.**

---

## Milestones

Sequenced cheapest-first; the theming foundation (M2) lands before any skinned component so
its tokens — including the media-feature layers — are the contract every control reads. Each
milestone is independently shippable and gets its own brainstorm → plan → implement cycle.

**Status (2026-06-15): COMPLETE — M1–M7 shipped and merged.** The full component set
(M1–M6), the HelloWorld dogfood (#18), the docs (`docs/guides/swiflowui.md` /
`swiflowui-theming.md`), the theming-verification pass (emitted-CSS in `ThemeTests` +
runtime `emulateMedia` in `theming.spec.ts`, #20), and the milestone close-out
(CHANGELOG `[Unreleased]` entry) are all done.

No version tag was cut: the framework as a whole is pre-1.0 (0.1.x), so "SwiflowUI 1.0"
here is the **component-library milestone name**, recorded as a CHANGELOG entry under
`[Unreleased]` (stable for pre-1.0 usage) — NOT a project v1.0 release. Deferred items
below remain for 1.1+.

- **M1 — Layout primitives:** `Grid`, `Spacer`, `Divider`, `ZStack`. Pure CSS-first, no
  state, no deps. Finishes the v0 layout story. Extend `Tokens.swift` as needed.
- **M2 — Theming foundation:** the token taxonomy + the media-feature override layers
  (light-dark, `prefers-contrast`, `prefers-reduced-motion`, `prefers-reduced-transparency`,
  `color-gamut`) in `baseStyleSheet`, plus the token-only `scopedStyles` convention every
  skinned component follows. Load-bearing — see "Theming foundation" above.
- **M3 — Button + skinned-control pattern:** `Button` (variant/size via tokens) as the first
  consumer of M2, proving the re-skin-via-token and override story end to end.
- **M4 — Form controls:** `TextField`, `Toggle`, `Select`, `RadioGroup` — **stateless free
  functions** wrapping native elements + a `Binding`, plus a `Field`-integrated convenience
  that auto-wires error display + `aria-invalid` + blur→`markTouched`. Native elements give
  roving focus/keyboard for free. Retires the hand-rolled `SignIn`/MissionControl fields.
  (Done milestone-internally: `TextField` first to set the field-chrome pattern, then the rest.
  Chrome-factoring is deferred to the **Toggle** step — TextField's `.sw-field` uses a column
  layout that fits TextField/Select but NOT Toggle (label *beside* checkbox) or RadioGroup
  (`<fieldset>`/`<legend>`); extract a layout-neutral "label + error + aria" helper + shared
  input/error/size CSS once Toggle is the second consumer, rather than abstracting on one.
  DONE at Toggle: `FieldChrome.swift` (`controlInputAttributes`, `fieldErrorNode`, `formControlsSheet`).
  DONE at RadioGroup: the group/per-control split — `fieldGroupAttributes` puts group aria on the
  `<fieldset>`, per-option radios get a simple assembly + a derived `Binding<Bool>`. **M4 COMPLETE**:
  all four controls shipped (TextField/Toggle/Select/RadioGroup), each its own reviewed sub-step.)
- **M5 — Feedback & display:** `Spinner`/`ProgressView`, `Card`, `Badge`/`Tag`. Cheap,
  high-visibility; pairs `Spinner` with the `.task` async story.
- **M6 — Overlays:** `Toast`, `Alert`, `Prompt` — these read `--sw-duration`/`--sw-overlay-bg`,
  so reduced-motion/transparency just work. **M6 COMPLETE**: `Alert` (#15) + `Prompt` (#16,
  `<form method=dialog>` Enter-to-submit, shared `.sw-dialog` chrome) + `Toast` (#17, app-owned
  `[ToastItem]` queue, hover/focus pause). Built `Alert`/`Prompt` first (modal `<dialog>`),
  then `Toast` (fixed `ToastStack`, not the top layer). Click-outside still needs the deferred
  `EventInfo`-target enabler — dismissal is ESC + explicit controls.
- **M7 — 1.0 cut:** theming polish (token audit, dark-mode + media-feature pass), expand
  `examples/SwiflowUIDemo` into a component gallery, README/styling-guide docs, version tag.
  **DONE:** SwiflowUIDemo showcases every category (gallery); the HelloWorld **dogfood**
  (#18) retired its hand-rolled Toast/SignIn; **docs** shipped (`docs/guides/swiflowui.md` +
  `swiflowui-theming.md`, README updated); **theming-verification** (emitted-CSS in
  `ThemeTests` + runtime `emulateMedia` in `theming.spec.ts`, #20); **milestone close-out**
  recorded in `CHANGELOG.md` under `[Unreleased]`. No version tag — the framework is pre-1.0,
  so this is a component-library milestone, not a project v1.0 release.

## Deferred to 1.1+ (explicitly out of 1.0)

Custom portal/overlay-root host; `Menu`/`Dropdown`; `Tooltip`; full ARIA hardening pass
(beyond native-leaning baseline); `DataTable`/virtualized `List`; richer element-model work
(`CustomEvent` detail payloads, non-reconciled escape hatch — roadmap #2); edge-specific
padding (`.padding(.lg, .horizontal)`).

### M8 (1.1) — Token correctness & generation — ✅ SHIPPED (2026-06-25)

*Origin: evaluation of the [Reshaped](https://github.com/reshaped-ui/reshaped) design
system (MIT) against this roadmap, 2026-06-25 — full grid, scores, and sources in
[`swiflowui-reshaped-evaluation.md`](swiflowui-reshaped-evaluation.md). Reshaped's components mostly don't port
(React), but its **token layer** is architecturally convergent with our media-feature-first
stance — CSS custom properties, automatic dark mode in tokens, responsive resolved in CSS not
JS — and it solves a problem 1.0 left hand-rolled: deriving **correct** base token values.
M1–M7 shipped the media-feature **response** system (override layers re-point tokens), but
the base values were hand-authored in `Theme.swift`/`Tokens.swift`.*

**All three parts shipped** (recorded under CHANGELOG `[Unreleased]`, pre-1.0). Note: the
original "pure-token-layer, no component API" framing did **not** hold — the realized milestone
added the build-time `swiflow theme` CLI **and** a small `Theme` component. What actually shipped:

- **✅ Contrast tokens (PR #66)** — instead of *autogenerating* `-strong` tokens, the `-strong`
  and `-text` tokens **derive at render time** from `var(--sw-accent)` via
  `oklch(from … L c h)` (soft-tint text) and `contrast-color()` (solid-fill text), each over a
  progressive-enhancement literal fallback; proven WCAG (4.5, + 7 under `prefers-contrast: more`)
  by a **test-only** Swift pipeline (`Sources/SwiflowColor`). Structurally fixes the light-mode
  soft-tint failure **and** fixed a latent sub-AA primary button (white-on-accent was 3.68:1 →
  now contrast-color picks dark text). No color math ships in wasm; the browser is the engine.
- **✅ OKLCH palette generator (PR #67)** — a **build-time** `swiflow theme --primary "#hex"`
  CLI (not a runtime API — keeps color math out of wasm) that derives the dark-mode accent and
  **validates** the family against WCAG (accent-as-text ≥ 3:1 catches washed-out colors; fails
  the build with a diagnostic). Also made `--sw-accent-hover`/`-active` derive from
  `--sw-accent`, so re-pointing one token cascades the whole accent family. **Accent-only**;
  neutrals/semantics/full-palette, APCA, and p3-for-generated-accent deferred (see below).
- **✅ Scoped theme region (PR #68)** — a runtime `Theme(.accent("#7c3aed"), .radius("12px")) { … }`
  component (`Sources/SwiflowUI/ThemeScope.swift`) that scopes `--sw-*` overrides to a subtree
  as inline custom properties on a `display: contents` wrapper (zero layout impact). Ergonomic
  multi-token sugar over `.style()` — single-token subtree theming already works and cascades
  via the accent-family change above. Explicit values only (no runtime derivation).

- **✅ Neutral / full-palette generation (PR #70)** — opt-in `swiflow theme --primary X --neutrals`
  derives the accent-tinted neutral ramp (`--sw-bg`/`--sw-surface`/`--sw-text`/`--sw-border`) with
  contrast-proven text-on-surface, plus a `prefers-contrast: more` block. Also fixed the base-token
  cascade (`@layer swiflow.base`) so generated/app `:root` overrides reliably win.
- **✅ Status-color seeds (PR #71)** — opt-in `--danger`/`--success` seeds emit contrast-validated
  raw status overrides (per-usage bars: danger ≥ 4.5 as error text, success ≥ 3:1 as border/tint,
  derived `-strong` ≥ 4.5/7); compose with `--neutrals`. No base-sheet/component change — the base
  sheet re-derives `-strong`/more-contrast/P3 from the raw token.
- **✅ Warning/info status tokens + seeds (PR #72)** — added `--sw-warning` (amber, full 4-layer
  treatment) and `--sw-info` (aliases `--sw-accent`, independently overridable) to the base sheet,
  wired into `Badge`/`Toast` (incl. the previously-missing `.sw-toast--info` rule); `swiflow theme`
  gains validated `--warning`/`--info` seeds. **The status set is now complete**
  (danger/success/warning/info), so the generator covers every shipped token.

- **✅ p3 / wide-gamut generated colors (this PR)** — `swiflow theme` emits accent + status colors
  with a progressive `oklch()` line (chroma pushed to the display-P3 gamut edge at the seed's L/H)
  after the sRGB hex fallback, so generated themes render wide-gamut on capable displays without an
  `@media` block. Neutrals stay hex-only; validation still runs on the hex (L/H preserved →
  contrast unchanged).

**Deferred from M8 to a later pass:** APCA as an opt-in algorithm; promoting `SwiflowColor` into a
public (shipping) generator.

### M9 (1.1) — Modern CSS theming primitives — candidate

*Origin: evaluation of Una Kravets' ["Modern CSS Theming"](https://una.im/modern-css-theming)
(2026), which splits theming into **macro** (page-level `light-dark()`) and **micro**
(per-component palette derivation in CSS) and argues a component should receive only a brand
color and derive its background/text/elevation itself. That framing is convergent with our
"components read tokens, never branch" rule — the branching it proposes lives in CSS (style
queries), not component code. Two of its techniques we already ship; three are candidate
upgrades.*

**Already aligned (no work):** `light-dark()` driven by `color-scheme` is our token contract;
relative color syntax (`oklch(from var(--x) calc(l + …) c h)`) is already how `-strong` and the
p3/OKLCH generator (#73) derive. The article externally validates both bets.

Candidate items, ranked:

- **✅ `@property` registration for `--sw-*` tokens (SHIPPED — this spike)** — scalar tokens
  (spacing/radius/border-width/focus-ring-width/duration/opacity) **and** color tokens are
  registered (`syntax`/`inherits`/`initial-value`), so they are type-validated and animatable.
  Color registration shipped after a 4-gate proof that the literal→`oklch(from)` progressive
  fallback survives registration (parse-time rejection precedes registered-syntax validation).
  This is also the prerequisite for any future style-query work. Full results in
  [`swiflowui-property-style-queries-findings.md`](swiflowui-property-style-queries-findings.md).
- **`@container style()` queries — a standards-based "micro-theming" seam. → DEFER (this spike).**
  Lets *CSS* branch on a token value (e.g. a tinted surface picking readable text) without the
  *component* branching — inside our no-branch rule, and the proper standards fix for the
  soft-tint-contrast problem the `-strong` tokens work around ([[swiflowui-soft-tint-contrast]]).
  Spike verdict: our pipeline passes the syntax through verbatim (no CSS minifier), so the only
  blocker is **no Firefox support** as of 2026 — it can only be a progressive layer over the
  cross-engine `-strong`, which already works. Deferred; `@property` (shipped) is the groundwork.
  See findings.
- **`contrast-color()`** — *watch, gate behind `@supports`.* Auto-picks black/white for WCAG
  contrast at runtime; complements (does not replace) `SwiflowColor`'s build-time validation —
  we validate seeds at generate time, `contrast-color()` would handle arbitrary user backgrounds
  at runtime. Most useful as the *detector* inside a style query. We already use it for the
  solid-fill `-text` token (M8/#66); broader adoption is the deferred piece. Very new baseline.

**Rejected:** `@function` custom CSS functions (Chrome-139-only per the article) — too early for a
cross-engine library; relative color syntax gives the same elevation result at full Baseline.

### Reshaped evaluation — considered and rejected (with reasons)

Recorded so a future session doesn't re-litigate these:

- **Single flexible `View` primitive** (Reshaped collapses Stack/Box/Grid into one `View`
  with all-responsive props) — **rejected.** M1 deliberately shipped `VStack`/`HStack`/`Grid`/
  `ZStack`/`Spacer`/`Divider` as separate SwiftUI-idiom free functions because the audience is
  Swift developers who expect that mental model. Collapsing to one `View` is a breaking change
  against a shipped, audience-fit choice. Keep only the lesson: *lean on modifiers, not a new
  primitive per layout need.*
- **Headless/utilities package split** (`@reshaped/headless` + `@reshaped/utilities`) —
  **deferred as premature.** Revisit only if `Sources/SwiflowUI` outgrows its current
  footprint.
- **Polymorphic `Button`** (`href` auto-renders `<a>` vs `<button>`) — **lean reject.** Keeping
  `Button` and `SwiflowRouter`'s `Link` as separate types is cleaner than overloading one.
- **Per-component a11y regression tests** — **already covered** by the Verification section
  (a11y smoke + Playwright `emulateMedia`); optionally tighten to per-component assertions.
- **`--rs` token prefix discipline** — **already covered** by our `--sw-` prefix.

## Verification

- **Per component:** a focused entry in the expanded `examples/SwiflowUIDemo` gallery plus a
  Playwright spec under `Tests/playwright/`. Overlays get interaction specs (open/close, ESC,
  queue order, focus restore).
- **A11y smoke:** assert native roles/labels present, `aria-invalid` toggles on validation,
  Toast/Spinner expose live-region roles; keyboard path for `RadioGroup`.
- **Media features:** unit-test the `baseStyleSheet` output to assert each `@media` token
  layer is emitted; Playwright `page.emulateMedia({ colorScheme, reducedMotion, contrast,
  forcedColors })` to verify components actually respond (transitions disabled under
  reduced-motion, palette flips under dark, heavier borders under more-contrast).
  `prefers-reduced-transparency` and `color-gamut` aren't emulable in Playwright today, so
  they're covered by the emitted-CSS unit test plus a manual check.
- **Theming:** verify a token override (`--sw-accent`, radius) re-skins `Button`/`Card`
  without touching component code; dark-mode via `light-dark()` renders correctly.
- **Scaffold dogfood:** rewrite the HelloWorld template's hand-rolled Toast + SignIn modal to
  use the new components as the end-to-end acceptance that 1.0 actually retires hand-rolling.
- `swift test` + full Playwright suite green; component gallery builds via `swiflow build`.

## Non-goals

- This roadmap is a sequence of small specs, not one mega-PR.
- No new reactive/state machinery — everything composes from existing `Binding`, `Form`,
  `Ref`, `@Component`, `#css`, and the token system.
