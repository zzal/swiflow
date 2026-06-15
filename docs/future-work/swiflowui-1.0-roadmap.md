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
- **M6 — Overlays:** `Toast` (Popover + queue) first, then `Alert`/`Prompt` (`<dialog>`);
  these read `--sw-duration`/`--sw-overlay-bg`, so reduced-motion/transparency just work.
  Optionally land the small `EventInfo`-target-identity enabler here for click-outside.
- **M7 — 1.0 cut:** theming polish (token audit, dark-mode + media-feature pass), expand
  `examples/SwiflowUIDemo` into a component gallery, README/styling-guide docs, version tag.

## Deferred to 1.1+ (explicitly out of 1.0)

Custom portal/overlay-root host; `Menu`/`Dropdown`; `Tooltip`; full ARIA hardening pass
(beyond native-leaning baseline); `DataTable`/virtualized `List`; richer element-model work
(`CustomEvent` detail payloads, non-reconciled escape hatch — roadmap #2); edge-specific
padding (`.padding(.lg, .horizontal)`).

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
