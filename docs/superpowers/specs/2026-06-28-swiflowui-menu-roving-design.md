# SwiflowUI roving `role=menu` for Dropdown — Design

> **Date:** 2026-06-28 · **Status:** approved, ready for implementation plan
> **Milestone:** the **`Menu`** item from the SwiflowUI 1.1+ deferred list — realized as a
> keyboard-roving upgrade to the existing `Dropdown` (not a separate component).
> **Prior art:** `Dropdown` (native Popover API + anchor positioning) and `Autocomplete`
> (`.on(.keydown)` roving + imperative focus-by-id, `#if canImport(JavaScriptKit)`-guarded).

## Problem

`Dropdown` ships as "a dropdown of actions" built on the native Popover API: click/Enter/Space
open it, Esc/click-outside dismiss it, each item is a `<button popovertargetaction="hide">` that
runs an action and closes. Its own doc notes it is **not a strict ARIA menu** — there is no
arrow-key roving and no `role=menu`/`menuitem` semantics. The 1.1+ roadmap lists `Menu` for exactly
this gap.

The originally-assumed blocker — an `EventInfo.key` enabler — **already exists and is in
production**: `EventInfo.key` is marshaled end-to-end (JS driver → `DispatcherBridge` → `EventInfo`)
and `Autocomplete` already uses `.on(.keydown) { e in … e.key … }`. So this is **pure component
work** with no framework change.

## Goal

Upgrade `Dropdown` to a proper WAI-ARIA **menu** with keyboard roving — `role=menu`/`menuitem`,
arrow-key navigation with **roving tabindex** (real DOM focus on each item), Home/End, and
focus-into-menu on open — while keeping the native Popover API for open/dismiss/focus-return.
Existing `Dropdown`/`DropdownItem` call sites keep working unchanged; they gain keyboard support
for free.

## Decisions (from brainstorming)

1. **Enhance `Dropdown`** (make it a roving menu); do NOT add a separate `Menu` component or
   deprecate `Dropdown`.
2. **Roving tabindex** (APG-canonical for menus) — real focus on each menuitem; NOT
   `aria-activedescendant` (that's the combobox pattern, correctly used by `Autocomplete`, which is
   left untouched).
3. **Actions menu — no value binding.** `role=menu` is for commands, not form values. Form value
   selection stays with `Select` (native) and `Autocomplete` (combobox), which already expose
   `Binding<String>`.
4. **No core/framework changes** — `EventInfo.key` already exists; the popover `toggle` is reachable
   via `.custom("toggle")` but isn't needed (see focus-on-open below).

## Mechanism

`DropdownMenu` stays a `@Component` (still only to pin the stable `menuID`). **No `@State` is
added** — with roving tabindex, **DOM focus is the source of truth**. The native Popover API keeps
handling open (trigger click/Enter/Space), dismiss (Esc, click-outside), and focus-return-to-trigger.

- **Roles / ARIA:** the popover container gains `role="menu"`; the trigger's `aria-haspopup`
  changes from `"true"` to `"menu"`; each item gains `role="menuitem"`.
- **Roving tabindex:** every item gets `tabindex="-1"` and a stable `id` (`<menuID>-item-<n>`).
  Focus is moved programmatically; Tab does not stop on individual items.
- **Focus-into-menu on open (native, no JS):** the **first enabled item gets the `autofocus`
  attribute**. The Popover API's show-focusing-steps focus the `autofocus` element when the popover
  opens — so focus lands on the first item on open with zero JS, regardless of how it opened.
- **Roving keys** — each enabled item carries a keydown handler (capturing the ordered list of
  enabled item ids + its own position) that imperatively `.focus()`es the target item by id
  (`JSObject.global.document.getElementById(id).object?.focus()`, `#if canImport(JavaScriptKit)`-
  guarded exactly like `Autocomplete`; a no-op on host):
  - `ArrowDown` / `ArrowUp` → next / previous enabled item, **wrapping** (APG menu style).
  - `Home` / `End` → first / last enabled item.
  - `Tab` → close the menu (`hidePopover` on the menu element).
  - `Enter` / `Space` → **native** `<button>` activation (runs the item's action) + the existing
    `popovertargetaction="hide"` closes the menu. (No custom handling.)
  - `Escape` → **native** popover light-dismiss, which returns focus to the trigger. (No custom
    handling.)
- **Disabled items:** `DropdownItem(disabled:)` already renders a native `disabled` `<button>`
  (not focusable). Disabled items are **excluded from the roving order** and never receive
  `autofocus`. (Keeping native `disabled` rather than `aria-disabled`-focusable is a deliberate
  scope choice — see non-goals.)

## Where the wiring lives

`DropdownItem` stays a simple `<button>` + action + close — unchanged API. The **menu does the
roving assembly in `DropdownMenu.body`**, because only it knows item order/count. After building the
item nodes (via the existing `items()` builder + `DropdownAmbient`), it post-processes them:

1. Identify the **enabled menu items**: `.element` nodes whose `class` contains
   `sw-dropdown__item` and whose attributes do **not** include `disabled`. (Dividers / non-item
   nodes are passed through untouched.)
2. For each item node (enabled and disabled alike) inject `role="menuitem"`, `tabindex="-1"`, and a
   stable `id` via the same `ElementData.attributes` mutation helper `Tooltip` used.
3. On the **first enabled** item, also inject `autofocus`.
4. On each **enabled** item, attach the keydown roving handler via `.on(.keydown)` (capturing the
   enabled-id list + this item's index).

This centralizes all menu/roving logic in `DropdownMenu` and leaves `DropdownItem` (and its public
API) unchanged.

## Impact / compatibility

- **`Autocomplete` is untouched** — separate file, separate (combobox / `aria-activedescendant`)
  pattern, correct as-is.
- Existing `Dropdown` / `DropdownItem` usage is unchanged; the only observable differences are added
  ARIA + keyboard behavior. No public API change.
- The stale `Dropdown` doc comment ("a dropdown of actions, not a strict ARIA menu … needs an
  `EventInfo.key` enabler") is rewritten to describe the roving menu.

## Components & boundaries

| Unit | Change |
|------|--------|
| `DropdownMenu.body` (in `Dropdown.swift`) | inject `role=menu`/`menuitem`, `tabindex=-1`, ids, `autofocus`, keydown roving; `aria-haspopup="menu"` |
| roving keydown helper (file-local) | compute next/prev/first/last enabled id; imperative `.focus()` (`#if canImport(JavaScriptKit)`) |
| attribute-injection helper | add `role`/`tabindex`/`id`/`autofocus` to an item `.element` (mirror `Tooltip`'s helper) |
| `DropdownItem` | unchanged public API (menu injects the menu semantics) |

All in `Sources/SwiflowUI/Dropdown.swift`. No core/framework change; SwiflowUI stays as-is.

## Testing

- **Unit (`Tests/SwiflowUITests/DropdownTests.swift`):** assert the container has `role="menu"`;
  the trigger has `aria-haspopup="menu"`; every item has `role="menuitem"` + `tabindex="-1"` + an
  `id`; the first enabled item has `autofocus`; a disabled item is present but excluded from
  `autofocus`/roving; each enabled item carries a `keydown` handler. (Actual focus *movement* is
  imperative DOM → browser-only, covered by e2e.)
- **Playwright (local; run via the existing dropdown/`router` config or `counter` config to avoid
  the `.e2e-cache/sw` SourceKit-LSP scaffold race; build the release CLI first):** open the menu →
  focus lands on the first item; ArrowDown/Up move focus and **wrap**; Home/End jump to ends;
  Escape closes and returns focus to the trigger; Enter activates an item and closes.
- **Host `swift build` + `swift test`**, plus a demo build eyeball
  (`swiflow build --path examples/SwiflowUIDemo`).

## Non-goals

- **No separate `Menu` component**, no `Dropdown` deprecation.
- **No value binding** — actions menu only; values → `Select` / `Autocomplete`.
- **No submenus, no typeahead** (type-a-letter jump), **no horizontal menubar**, no
  `menuitemcheckbox` / `menuitemradio`.
- **No `aria-disabled`-focusable disabled items** — disabled items keep native `disabled` and are
  skipped (a future enhancement could make them focusable-but-inert).
- **No core/framework changes** (`EventInfo.key`, `Event` cases all already sufficient).

## Decisions resolved during brainstorming

1. **Relationship** → enhance `Dropdown` into a roving menu (new-component and deprecate-Dropdown
   rejected).
2. **Focus model** → roving tabindex (APG-canonical); `Autocomplete` keeps `aria-activedescendant`
   (correct for combobox) and is untouched.
3. **Not a form control** → no value getter/setter; `role=menu` is for actions. Forms use
   `Select`/`Autocomplete`.
4. **Focus-on-open** → native `autofocus` on the first item (no toggle handler, no `@State`).
5. **No framework work** → the assumed `EventInfo.key` enabler already ships.
