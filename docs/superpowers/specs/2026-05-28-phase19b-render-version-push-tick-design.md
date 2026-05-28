# Phase 19b — Render-Version Push Tick

**Status:** Approved
**Date:** 2026-05-28
**Predecessor:** Phase 19a (`docs/superpowers/specs/2026-05-28-phase19-devtools-mvp-design.md`)
shipped the read-only DevTools panel. This phase makes it live.

> **Note on the Chrome API used:** `chrome.devtools.inspectedWindow.eval` is a
> Chrome extension API for running a string expression against the inspected
> page from a DevTools panel context. It is distinct from JavaScript's global
> `eval()` and is the only supported way for any Chrome DevTools panel
> (React, Vue, Redux, etc.) to read page state. Phase 19b polls this API at
> a low cadence; it does not introduce any new arbitrary-code-execution
> surface beyond what Phase 19a already used.

## Goal

Make the DevTools panel auto-update on every Swiflow render without
requiring the user to click ↻ Refresh. Achieve this with zero
production Swift code changes by reusing the existing
`__swiflow.perf().renders` counter as the render-version signal.

## Scope

**In:**
- Panel polls `__swiflow.perf()` every 250 ms while the DevTools tab
  containing the panel is visible.
- Compares per-selector `renders` counts to the last seen snapshot;
  any increase (or appearance of a new selector) triggers the existing
  refresh logic.
- Polling pauses when the panel is hidden, resumes when shown.
- Errors during polling are silent (no error-region spam).
- Manual ↻ Refresh button retained as fallback.
- A small "live" indicator in the footer so the user can see the
  panel is keeping itself up to date.

**Explicitly out:**
- Any Swift-side change. `Renderer.renderCount` already increments on
  every render (`Sources/SwiflowWeb/Renderer.swift:191`), and `DevAPI`
  already exposes it via `__swiflow.perf()[selector].renders`. Phase
  19b is panel-only.
- True zero-latency push (CustomEvent + content-script bridge). Phase
  19b's worst-case latency is ~250 ms which is invisible; the bridge
  approach would buy 200 ms in exchange for ~3× the code plus an MV3
  service-worker lifecycle to manage. Deferred unless real users
  complain about the latency.
- Pause/play UI for snapshotting state at a moment in time. The
  manual ↻ Refresh button already serves this need for the rare case
  where the user wants to inspect a frozen tree.
- "Highlight changed state on update" (flash a row on value change).
  Nice-to-have follow-up; this spec ships the plumbing, not the
  visual feedback.
- Connection-state UX improvements (friendlier "waiting for Swiflow"
  empty state, prod-build distinction, selection restore on reload).
  Listed as menu items earlier; they belong in their own phase
  (19e if pursued).

## Architecture

### Polling loop

The panel runs a `setInterval` with period `POLL_INTERVAL_MS = 250`.
Each tick:

1. Call `dataSource.perf()` (existing path — wraps the
   `chrome.devtools.inspectedWindow` API with the error envelope
   from Phase 19a).
2. On success, compute a stable signature of the per-selector render
   counts. The signature is `JSON.stringify` of an object that maps
   each selector to its `renders` integer, with keys sorted.
3. Compare to `lastPerfSignature`. If equal, do nothing — the cost is
   one cross-context query that returned ~50 bytes of JSON. Cheap.
4. If different, record the new signature and call the existing
   refresh logic (the same code path the ↻ Refresh button uses):
   re-fetch tree, re-fetch state for the selected row if any, render
   footer from the perf object we already have.

### Visibility gating

Polling is wasted when the user is on a different DevTools tab.
`chrome.devtools.panels.create()` (called in `devtools.js`) returns a
panel handle whose `.onShown` and `.onHidden` events fire when the
user switches in and out. Wire these:

- On `onShown`: start the interval, run an immediate refresh so the
  panel reflects current state without waiting 250 ms.
- On `onHidden`: clear the interval. Keep the last selection and last
  tree state in memory; next `onShown` will reconcile.

Without this, the panel polls forever from first open even if the
user never looks at the Swiflow tab again. With this, polling cost
maps directly to user attention.

### Change detection algorithm

The signature is `JSON.stringify({s1: r1, s2: r2, ...})` with keys
sorted alphabetically. This catches three change cases:

- Existing selector's `renders` incremented (re-render happened).
- New selector key appeared (`Swiflow.render(into:)` mounted a new root).
- Selector disappeared (`Swiflow.unmount(into:)` removed a root).

All three correctly trigger a refresh. Selector ordering across polls
is stable because we sort keys.

The first poll after `onShown` always triggers a refresh (the prior
signature is `null`), which is the intended behavior — that's how the
panel populates on first open.

### Error handling during polling

Poll-time `perf()` calls can fail for the same reasons manual ones
can: the page navigated to a non-Swiflow URL, `__swiflow` was nulled
out by user-typed `window.__swiflow = null` in the console, the page
crashed. At 250 ms cadence, surfacing every failure to the error
region would render the panel unusable.

Rule: **poll-driven errors are silent.** The catch in the poll loop
records the error to a debug field (`lastPollError`) and updates the
live indicator's color, but does not call `showError`. The
user-clicked ↻ Refresh path keeps its existing behavior — errors
there are user-triggered and worth surfacing prominently.

When a poll fails, the existing `lastPerfSignature` is preserved.
When polling recovers (next successful poll), the signature
comparison runs normally — if state moved during the outage, the
recovery will trigger one refresh and re-sync.

### Live indicator

A small dot at the left edge of the footer:

- **Green** when the last poll succeeded.
- **Grey** when the panel is hidden (paused).
- **Red** when the most recent poll failed.

Tooltip on hover gives the precise state ("Live — last update 80ms
ago" / "Paused (panel hidden)" / "Connection lost: <error>"). This
gives the user the "is the panel actually live?" feedback that an
auto-updating UI otherwise lacks.

## Files Modified

| File | Status | Change |
|---|---|---|
| `devtools/panel.js` | modify | Add poll loop, visibility wiring, signature comparison, silent poll-error handling, live indicator update |
| `devtools/devtools.js` | modify | Hook `panel.onShown` / `panel.onHidden` to start/stop polling in the panel context |
| `devtools/panel.html` | modify | Add the live-indicator dot to the footer (single element + CSS) |
| `devtools/README.md` | modify | Document the new auto-update behavior, remove "Click ↻ Refresh to update" from the limitations list |
| `CHANGELOG.md` | modify | Phase 19b entry |

No Swift changes. No `Sources/`, no `Tests/SwiflowTests/`, no
`Tests/playwright/`. The contract test from Phase 19a already
verifies that `__swiflow.perf()` returns the shape this design
depends on; if it ever drifts, that test fails first.

## Communication: panel.js ↔ devtools.js

`chrome.devtools.panels` lives in the devtools_page context, not the
panel context. `panel.onShown` / `panel.onHidden` listeners can only
be added in `devtools.js`. The handover pattern:

- `devtools.js` registers the panel as today, then in the panel
  callback adds `onShown` and `onHidden` listeners.
- `onShown` fires with the panel's `window` reference. devtools.js
  caches that ref and calls `win.swiflowStart()` on it. It also
  re-uses the cached ref on `onHidden` (which lacks a `win` arg)
  to call `win.swiflowStop()`.
- `panel.js` exposes `window.swiflowStart` and `window.swiflowStop`
  at module load. Start kicks off the interval and runs an immediate
  refresh; stop clears the interval and updates the live indicator
  to grey.

This is the only cross-context coordination required. The DataSource
abstraction stays untouched.

## Testing

- **Manual:** load the panel on the Counter demo, click the
  Increment button in the demo — confirm the panel updates count
  within ~250 ms without touching ↻ Refresh.
- **Manual:** switch DevTools to another tab (e.g., Elements) and
  back to Swiflow — confirm polling pauses then resumes; immediate
  refresh on resume.
- **Manual:** navigate the inspected page to `about:blank` — confirm
  the live indicator turns red and the panel does NOT spam the error
  region. Navigate back — confirm the indicator turns green and the
  tree refreshes.
- **No new automated tests.** The Phase 19a Playwright contract test
  already protects the `perf()` shape this design rides on; the
  panel polling logic is too coupled to Chrome extension lifecycle
  to test profitably without major harness work.

## Risks & Mitigations

- **Poll storms during high-frequency renders.** If the app renders
  at 60 fps (a long-running animation), every poll sees a different
  `renders` count and triggers a full refresh — which itself runs 3
  cross-context queries. At worst the panel does ~12 queries per
  second on top of the baseline 4 polls. The work is small (small
  JSON serializations) and the panel is not on the hot path of the
  app, so this is acceptable. If it becomes a problem in practice,
  add a min-interval between refreshes (`MIN_REFRESH_INTERVAL_MS = 100`).

- **Selection survives across refreshes — but DOES the right path
  survive?** When the tree shape changes (component added/removed
  mid-render), the previously selected `path` may no longer exist.
  The existing `dataSource.state(path)` returns `null` for unknown
  paths, and `renderState(null)` shows "No @State on this component."
  The visual feedback is correct; the user just sees their selection
  apparently empty out. Acceptable for this phase. A follow-up could
  clear the selection automatically when the path goes missing.

- **MV3 service worker.** This design uses zero background-script
  features (no `chrome.runtime.sendMessage`, no service worker).
  Entirely contained in the devtools_page + panel contexts, both of
  which are stable across MV3's tighter lifecycle.

## Success Criteria

1. Open the panel on the Counter demo. Click Increment in the demo
   tab. The panel's `count` value updates within 250 ms without
   touching ↻ Refresh.
2. Switch DevTools tabs away from Swiflow and back. Polling pauses
   then resumes; an immediate refresh fires on resume.
3. Navigate the inspected page to a non-Swiflow URL. The live
   indicator turns red but the error region stays empty.
4. Manual ↻ Refresh still works — clicking it during a poll outage
   surfaces the same error in the error region the way it did in 19a.
5. Live indicator accurately reflects state at all times (green
   during normal operation, grey when hidden, red on poll failure).

## Out-of-19b Roadmap (informational)

- **19c**: DOM overlay + component picker.
- **19d**: `@State` editing.
- **19e**: Connection-state UX (friendly waiting state, prod-build
  distinction, selection-restore on reload).
- **19f (maybe)**: True zero-latency CustomEvent push — if 250 ms
  polling latency ever becomes user-visible.
