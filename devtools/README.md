# Swiflow DevTools (Chrome Panel, MVP)

A Chrome DevTools panel for inspecting a running Swiflow app's component
tree and `@State` live.

**Status:** Phase 19 MVP — read-only tree + state inspector. DOM
overlay, `@State` editing, and perf graphs are planned for later
phases (19c, 19d, 19b respectively).

---

## Install (sideload)

1. Clone the Swiflow repo.
2. Open Chrome and navigate to `chrome://extensions`.
3. Enable **Developer mode** (toggle at the top right).
4. Click **Load unpacked** and select this `devtools/` directory.
5. Confirm "Swiflow DevTools" appears in the extensions list with no
   errors.

The extension activates whenever Chrome DevTools is open. To use it:

1. Open a Swiflow app running in dev mode (e.g.
   `cd examples/MiniRouter && swiflow dev`).
2. Open Chrome DevTools (⌥⌘I on macOS, Ctrl-Shift-I elsewhere).
3. Click the **Swiflow** tab in the DevTools tab bar (it may be hidden
   behind the » overflow menu — drag tabs to reorder).
4. Click ↻ Refresh to load the component tree.

When the inspected page navigates, the panel auto-refreshes.

---

## What it shows

- **Tree pane (left):** every mounted component in document order,
  with depth-indented rows. The `[body→]` suffix marks a component
  whose body is another component anchor (vs. an HTML element or
  text leaf).
- **State pane (right):** click a row to see its `@State` field
  values. The DevAPI surfaces only JSON-friendly primitives
  (Bool / String / Int / Double / null); other types are filtered
  out at the source.
- **Footer:** `Selector: #app | Renders: 12 | LastPatch: 4 |
  LastRenderMs: 1.23` for the selector containing the selected
  component (or the first mounted root when nothing is selected).
- **Error region:** appears at the top in red if `window.__swiflow`
  is missing (non-Swiflow page, or production build with
  `SWIFLOW_DEV` unset) or if a page-side exception occurs.
- **Live indicator (footer, left edge):** a small dot. **Green**: the panel is polling the inspected app and last poll succeeded. **Grey**: panel is paused (you're viewing a different DevTools tab). **Red**: polling failed (no Swiflow runtime, page navigated away, etc) — the manual ↻ Refresh button still works in this state and will surface the actual error.

Multi-root apps render one section per mounted selector with a bold
header.

---

## Limitations (MVP)

- **No state-change row highlight.** When a `@State` value changes between polls, the panel re-renders the row but doesn't visually flash it. A nice-to-have for a follow-up.
- **No `@State` editing.** The panel is read-only.
- **No DOM overlay / component picker.** You can't click a DOM
  element to find its owning component.
- **Chrome only.** Firefox and Safari support are not planned for the
  MVP.

---

## Manual smoke checklist

After sideloading, walk through this once to confirm everything works:

1. [ ] Open `chrome://extensions`, confirm "Swiflow DevTools" loaded
   with no errors.
2. [ ] Start a dev server: `cd examples/MiniRouter && swiflow dev`
   (port 3001).
3. [ ] Open `http://127.0.0.1:3001` in Chrome, open DevTools, switch
   to the **Swiflow** tab.
4. [ ] Click ↻ Refresh. Confirm a tree of rows appears, root
   component at top.
5. [ ] Click the root component. Confirm the state pane shows its
   `@State` fields (or "No @State on this component." if it has
   none).
6. [ ] Footer shows the selector and perf numbers.
7. [ ] Navigate to `about:blank`. Confirm the panel auto-refreshes
   and shows "No Swiflow runtime detected on this page ..." in
   the red error region.
8. [ ] Navigate back to the demo. Confirm the error clears and the
   tree reappears.

---

## Troubleshooting

**"Swiflow" tab doesn't appear in DevTools.**
Close and reopen DevTools (Cmd-W in DevTools to close, ⌥⌘I to
reopen). Chrome only registers extension panels when DevTools opens.

**Panel shows "No Swiflow runtime detected" but the app is running.**
The app may be running a release build. `window.__swiflow` is only
attached in dev mode (gated on `window.SWIFLOW_DEV`). Run
`swiflow dev` (not a static-served release build).

**Tree pane is empty after Refresh.**
Check the panel's own console: right-click in the panel area →
**Inspect**. Look for messages prefixed `[Swiflow DevTools]`.
