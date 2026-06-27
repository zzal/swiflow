# SwiflowUI `Tooltip` component — Design

> **Date:** 2026-06-27 · **Status:** approved, ready for implementation plan
> **Milestone:** the **`Tooltip`** component from the SwiflowUI 1.1+ deferred list.
> **Prior art:** `Dropdown` (Popover API + anchor positioning, lifecycle-free) and the
> stateless control seam (`installControlSheet`, Button / form controls).

## Problem

SwiflowUI has no tooltip primitive. Apps either hand-roll one or fall back to the native `title`
attribute (unstyleable, slow, no touch/keyboard control). A tooltip is a small, descriptive
overlay revealed on hover/focus of a trigger.

The defining constraint: the **Popover API triggers on click** (`popovertarget`), not hover, so a
hover/focus tooltip with top-layer rendering would require JS show/hide handlers — departing from
the library's native-first, lifecycle-free ethos. We deliberately choose a **CSS-only** mechanism
instead, accepting its two limitations (no top layer, no Escape-dismiss) in exchange for zero JS,
full cross-engine support, and the CSS-first house style.

## Goal

A `Tooltip` free function that wraps a trigger and shows a token-styled, `role="tooltip"` bubble on
hover and keyboard focus, positioned around the trigger, with `aria-describedby` wiring — pure CSS,
no JS, no `@Component`.

## Decisions (from brainstorming)

1. **CSS-only** reveal (`:hover` / `:focus-within`). (JS-driven Popover and native `title` rejected.)
2. **Stateless free function** + `installControlSheet` (the Button / form-control seam), not a
   `@Component` — there is no open-state to persist; the bubble id and its `aria-describedby` are
   emitted together each render, so id regeneration is harmless.
3. **Wrapper API** — CSS-only reveal requires the bubble to be a DOM sibling of the hovered trigger.
4. **Plain absolute positioning** relative to the wrapper (not CSS anchor positioning) — works in
   every engine including Firefox; CSS-only can't reach the top layer anyway.

## API

```swift
@MainActor
public func Tooltip(
    _ text: String,
    placement: TooltipPlacement = .top,
    _ attributes: Attribute...,      // merge onto the WRAPPER
    content: () -> VNode             // the trigger
) -> VNode

public enum TooltipPlacement: Equatable { case top, bottom, leading, trailing }
```

Usage:

```swift
Tooltip("Delete permanently") { Button("Delete", variant: .danger) { delete() } }
Tooltip("Filter results", placement: .bottom) { iconButton() }
```

Rendered structure:

```html
<span class="sw-tooltip-wrap">                                  <!-- position: relative; display: inline-block -->
  <button … aria-describedby="sw-tip-N">Delete</button>          <!-- caller's trigger; aria injected -->
  <span class="sw-tooltip sw-tooltip--top" role="tooltip" id="sw-tip-N">Delete permanently</span>
</span>
```

Caller `Attribute…`/`.class` merge onto the wrapper (so the wrapped trigger's layout can be tuned).

## Mechanism

- **Reveal:** `.sw-tooltip` is hidden by default (`opacity: 0; visibility: hidden`) and shown by
  `.sw-tooltip-wrap:hover .sw-tooltip, .sw-tooltip-wrap:focus-within .sw-tooltip`. `:focus-within`
  covers keyboard focus of the trigger; `:hover` is on the **wrapper**, so moving the pointer onto
  the bubble keeps it open (WCAG 1.4.13 **hoverable**).
- **Positioning:** wrapper is `position: relative; display: inline-block`; the bubble is
  `position: absolute`, placed per `TooltipPlacement` with logical offsets so `.leading`/`.trailing`
  flip under RTL:
  - `.top` → `bottom: 100%; left: 50%; transform: translateX(-50%)`
  - `.bottom` → `top: 100%; left: 50%; transform: translateX(-50%)`
  - `.leading` → `inset-inline-end: 100%; top: 50%; transform: translateY(-50%)`
  - `.trailing` → `inset-inline-start: 100%; top: 50%; transform: translateY(-50%)`
- **`aria-describedby` injection:** an internal helper adds `aria-describedby="<tipID>"` to the
  trigger when it is a single `.element` VNode. If the child is not a single element (e.g. a
  component anchor or text), the visual tooltip still works and the bubble keeps `role="tooltip"`,
  but the explicit link is skipped — documented. The bubble (referenced by `aria-describedby`) is
  announced on focus even while visually hidden — the standard SR pattern.

## Styling (tokens only)

`.sw-tooltip` reads `--sw-*` tokens, consistent with the Dropdown menu / overlay surfaces:
`--sw-surface` background, `--sw-text` color, `1px solid --sw-border`, `--sw-radius`, `--sw-shadow`,
`font-size: 0.8125rem`, `--sw-space-xs`/`--sw-space-sm` padding, `max-width: 16rem` with normal
wrapping, a high `z-index`. A CSS arrow via `::after` (border-triangle) tinted to `--sw-surface`.
Reveal transitions `opacity`/`visibility` on `var(--sw-duration) var(--sw-ease)` with a short
show-delay (~120ms) to avoid flicker on pass-through; `prefers-reduced-motion` already collapses
`--sw-duration` to `0s` via the token, so no per-component motion branch.

## Accessibility — and the accepted limitation

- `role="tooltip"` + `aria-describedby`; revealed on **hover and keyboard focus**; **hoverable**.
- **Dismissable (Escape) is NOT supported** — CSS has no key handling, so WCAG 1.4.13's
  *dismissable* criterion is not met. This is the explicit cost of the CSS-only mechanism. It is
  documented prominently in the component guide and flagged in the roadmap as the trigger for a
  future JS-driven variant. Every other part of 1.4.13 (hoverable, persistent) is satisfied.
- Disabled triggers don't fire hover/focus reliably — documented; no special handling.

## Components & boundaries

| Unit | Responsibility | New? |
|------|----------------|------|
| `Tooltip(_:placement:_:content:)` | wrapper free function | new |
| `TooltipPlacement` | `.top`/`.bottom`/`.leading`/`.trailing` → modifier class | new |
| `tooltipStyleSheet` | global `.sw-tooltip*` token-only sheet (via `installControlSheet`) | new |
| aria-describedby injection helper | add `aria-describedby` to a single-element trigger | new (file-local) |

All in one focused file `Sources/SwiflowUI/Tooltip.swift` (matching Badge/Spinner). No `@Component`,
no JS, no core-framework change.

## Testing

- **Unit (`Tests/SwiflowUITests/TooltipTests.swift`):** the emitted `tooltipStyleSheet` contains
  `.sw-tooltip`, `role`-bearing markup, the `:hover` and `:focus-within` reveal selectors, and the
  four `.sw-tooltip--<placement>` rules; a render-level test that the wrapped trigger node carries
  `aria-describedby` equal to the bubble's `id`, and that the bubble has `role="tooltip"`.
- **Demo:** add a `Tooltip` example to the SwiflowUIDemo gallery.
- **Playwright (local, run via `playwright.counter.config.ts` to avoid the `.e2e-cache/sw`
  SourceKit-LSP scaffold race):** focusing the trigger reveals the bubble; hovering reveals it;
  `aria-describedby` matches the bubble `id`. Kept light — behavior is static CSS.
- **Demo build** (`swiflow build --path examples/SwiflowUIDemo`) and host `swift build` /
  `swift test` green.

## Non-goals

- **No Escape-dismiss / no top-layer** (CSS-only limitations, accepted).
- **No interactive/rich bubble content** — text label only; interactive content → use
  `Dropdown`/Popover.
- **No JS, no `@Component`, no configurable delay** beyond the fixed CSS show-delay.
- **No anchor positioning** — plain absolute relative to the wrapper.

## Decisions resolved during brainstorming

1. **Mechanism** → CSS-only `:hover`/`:focus-within` (JS-popover and `title` rejected).
2. **Seam** → stateless free function + `installControlSheet`.
3. **API** → wrapper (`Tooltip("text") { trigger }`) — forced by CSS-only's DOM-sibling requirement.
4. **Positioning** → plain absolute relative to a `position: relative` wrapper; logical offsets for
   RTL; four placements, default `.top`.
5. **A11y limitation** → no Escape-dismiss; documented + roadmap-flagged.
