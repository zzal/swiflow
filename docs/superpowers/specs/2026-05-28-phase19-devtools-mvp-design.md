# Phase 19 — Component DevTools (Chrome panel, MVP)

**Status:** Approved
**Date:** 2026-05-28
**Predecessor:** Phase 9 (`docs/superpowers/specs/2026-05-20-swiflow-phase9-devtools-design.md`) shipped the `window.__swiflow` console API surface; this phase builds the GUI on top.

## Goal

A Chrome DevTools panel that shows the live component tree of any Swiflow
app, with click-to-inspect `@State` per node. Read-only. Built entirely
on the existing `window.__swiflow` API from Phase 9 — zero Swift-side
changes.

## Scope

**In:**
- A Chrome MV3 extension at `devtools/` in the repo
- A "Swiflow" panel in Chrome DevTools showing the parsed component tree
- Click-to-inspect: selecting a tree node shows its `@State` in a side pane
- Manual refresh button + auto-refresh on tab navigation
- Multi-root support (one tree section per mounted selector)
- Sideload distribution (chrome://extensions → Load unpacked from `devtools/`)
- A `devtools/README.md` with sideload instructions
- A short Playwright smoke test verifying the `__swiflow.tree()` and
  `__swiflow.state(path)` contract the panel depends on

**Explicitly out (deferred to later phases or not pursued):**
- DOM overlay / component picker (Phase 19c)
- `@State` editing (Phase 19d, would require new Swift-side mutation APIs)
- Render perf graph / sparkline (numbers still surface in footer; no charting)
- Auto-poll every N ms (manual refresh only; trivial to add later)
- Event-driven push from Swiflow's render loop (Phase 19b — needs Swift change)
- Firefox / Safari support
- Chrome Web Store publication (defer until 1.0)
- Time-travel / record-replay

## Architecture

### File layout

```
devtools/
├── manifest.json    MV3 manifest, declares devtools_page
├── devtools.html    Loaded by Chrome; runs devtools.js
├── devtools.js      Registers the "Swiflow" panel via chrome.devtools.panels.create
├── panel.html       Panel UI shell (split-pane HTML + CSS)
├── panel.js         Panel logic: DataSource, tree renderer, state pane, refresh
└── README.md        Sideload instructions
```

No build step. Vanilla JS / HTML / CSS. The panel is small enough that
framework overhead would dominate.

### Data flow

The panel runs in a Chrome extension context isolated from the inspected
page. The only bridge is `chrome.devtools.inspectedWindow.eval(...)` —
a Chrome-provided DevTools API that runs a small JS expression in the
inspected page's context and returns the result.

> **Note on the API name:** `chrome.devtools.inspectedWindow.eval` is a
> Chrome extension API, distinct from JavaScript's global `eval()`. It
> only accepts a string expression to evaluate against the inspected
> page; it does not introduce arbitrary-code-execution risk into the
> panel itself. There is no alternative for cross-context inspection
> from a DevTools panel — every Chrome DevTools extension (React,
> Vue, Redux, etc.) uses this same API.

Flow:

```
Panel UI  →  DataSource method  →  chrome.devtools.inspectedWindow.eval(
                                       "window.__swiflow.tree()"
                                    )
                                            ↓
                                    serialized JSON returns
                                            ↓
                                    Panel parses → renders tree
```

Click a tree node → `inspectedWindow.eval("window.__swiflow.state('1.0.2')")`
→ state pane updates.

### `DataSource` interface

The panel UI talks to a `DataSource` abstraction. Defined once in
`panel.js`; one implementation in MVP:

```js
class DataSource {
  async tree()        // returns { selector: treeString } | null
  async state(path)   // returns { fieldName: value } | null
  async perf()        // returns { selector: { renders, lastPatchCount, lastRenderMs } } | null
}
```

MVP impl: `InspectedWindowDataSource` — wraps every call in
`chrome.devtools.inspectedWindow.eval()`. The interface exists from day
one specifically so a future `EventBridgeDataSource` (Phase 19b) can
swap in without touching the panel UI. **This is the only
forward-looking concession in the design.** Every other piece is YAGNI'd
to MVP scope.

### Error envelope

`chrome.devtools.inspectedWindow.eval` swallows page-side exceptions
silently and returns `null` for non-JSON-serializable values. Wrap every
call site in an inline envelope (evaluated in the page context):

```js
const expr = `
  (() => {
    try {
      if (!window.__swiflow) return { ok: false, error: "no __swiflow global" };
      return { ok: true, value: window.__swiflow.tree() };
    } catch (e) {
      return { ok: false, error: String(e) };
    }
  })()
`;
chrome.devtools.inspectedWindow.eval(expr, (result, exception) => {
  if (exception) { /* show in panel error region */ return; }
  if (!result.ok) { /* show result.error in panel error region */ return; }
  /* use result.value */
});
```

A single error region at the top of the panel surfaces these. No silent
failures.

### Panel layout

Vertical split-pane:

```
┌──────────────────────────────────────────────────┐
│ [↻ Refresh]                                       │  ← header (~32px)
├──────────────────────────────────────────────────┤
│ (error region — hidden when empty)                │
├──────────────────────────────────────────────────┤
│ ┌─────────────────────┬──────────────────────┐  │
│ │ Tree                │ State                │  │
│ │                     │                      │  │
│ │ ▾ App ""            │ count: 0             │  │  ← split content
│ │   ▾ Sidebar ""      │ name: "alice"        │  │
│ │     · NavItem "0"   │                      │  │
│ │   ▾ MainArea "1"    │                      │  │
│ │     · Counter "1.0" │                      │  │
│ │     · Counter "1.1" │                      │  │
│ │                     │                      │  │
│ └─────────────────────┴──────────────────────┘  │
│ Selector: #app | Renders: 12 | LastPatch: 4     │  ← footer (~24px)
└──────────────────────────────────────────────────┘
```

- **Tree**: parsed from `__swiflow.tree()` indented string. Each
  non-`[body→]` line becomes a clickable row. Expand/collapse via the
  ▾/▸ glyph. Selection state highlighted.
- **State**: shows the `state(path)` object for the selected node as a
  simple key:value list. The DevAPI already filters to JSON-friendly
  primitives (Bool / String / Int / Double / null per
  `DevAPI.encodeStateForDisplay`), so the panel just renders what it
  receives — no further coercion or nested-object handling needed.
- **Footer**: shows the `perf()` summary for the **selector containing
  the currently-selected tree node**. When no node is selected, shows
  the first selector returned by `perf()` (insertion order matches the
  multi-root render order).

### Multi-root handling

`__swiflow.tree()` returns `{ selector: treeString, ... }`. The panel
renders one collapsible group per selector key. Single-root apps omit
the group header entirely — the tree renders flat without a
redundant `#app ▾` wrapper.

### Refresh behavior

- **Manual**: ↻ button at top fires all three queries (`tree()`,
  `state(selectedPath)`, `perf()`) and re-renders.
- **Auto-refresh on navigation**: panel listens to
  `chrome.devtools.network.onNavigated` and triggers a fresh fetch.
- **No polling**: confirmed out of scope for MVP.

## Detection / installation

The panel is registered unconditionally by `devtools.js` when the
extension is loaded. If `window.__swiflow` is absent in the inspected
page (non-Swiflow site, or `SWIFLOW_DEV` not set), the error region
shows "No Swiflow runtime detected on this page" and the tree/state
panes show empty states. This matches the React DevTools "this page
doesn't appear to be using React" pattern.

## Testing

- **No automated tests for the panel UI.** Chrome extension UI testing
  is high-friction (puppeteer-managed Chrome with `--load-extension`
  flag, headed mode for devtools panels, brittle selectors). The panel
  surface is tiny enough that the cost-benefit doesn't justify it for
  MVP. Re-evaluate at Phase 19b when push-based updates and editing
  arrive.
- **Manual smoke checklist** in `devtools/README.md`: sideload, open
  `examples/RouterDemo`, open DevTools → Swiflow panel, click tree
  nodes, verify state shows for components with `@State`, verify error
  region shows when navigating to a non-Swiflow page.
- **Playwright contract test** in `Tests/playwright/devtools-api.spec.ts`:
  open one of the example apps, evaluate
  `window.__swiflow.tree()` / `.state("")` / `.perf()` directly from
  the page, assert each returns the documented shape. This protects
  the API contract the panel depends on; if a future Swift change
  breaks the tree-string format, this test fails loudly.
- **Tree-string format pinning test** in
  `Tests/SwiflowTests/Reactivity/`: a Swift unit test that exercises
  `DevAPIFormatter.treeString` against a known mount tree and asserts
  the exact string output. Catches format drift at the source.

## Risks & Mitigations

- **Tree string format is unstable.** Panel parses
  `__swiflow.tree()`'s indented string. Format change → panel breaks
  silently.
  **Mitigation:** Pin the format with a Swift unit test (above) and
  the Playwright contract test (above). Two layers; one fails fast,
  one catches integration drift.

- **`chrome.devtools.inspectedWindow.eval` quirks.** Silently
  swallows exceptions, returns `null` for non-serializable values.
  **Mitigation:** Inline error envelope (architecture section above).

- **MV3 lifecycle.** Service workers can be torn down mid-session;
  devtools pages cannot. Since the MVP only uses
  `chrome.devtools.*` APIs (no background service worker), this
  risk is N/A for MVP. Becomes relevant in Phase 19b when push
  messaging is introduced.

- **Bundle size / unrelated coupling.** No risk. Vanilla JS, no
  dependencies, no shared code with Swiflow itself. The extension is
  fully decoupled from the Swift codebase; it only depends on the
  documented `window.__swiflow` API surface.

## Files Created / Modified

| File | Status | Purpose |
|---|---|---|
| `devtools/manifest.json` | new | MV3 extension manifest |
| `devtools/devtools.html` | new | Chrome devtools_page entry |
| `devtools/devtools.js` | new | Registers Swiflow panel |
| `devtools/panel.html` | new | Panel UI shell |
| `devtools/panel.js` | new | Panel logic (DataSource + render) |
| `devtools/README.md` | new | Sideload + smoke-test instructions |
| `Tests/playwright/devtools-api.spec.ts` | new | Contract test for `__swiflow.tree/state/perf` |
| `Tests/SwiflowTests/Reactivity/DevAPIFormatterTests.swift` | new | Pins tree-string format |
| `CHANGELOG.md` | modified | Phase 19 entry |
| `README.md` | modified | Mention DevTools panel in dev tooling section |

No production Swift code changes. No JS driver changes. No patch
protocol changes.

## Success Criteria

1. Sideloading `devtools/` in Chrome creates a "Swiflow" tab in DevTools.
2. Opening that tab on a running Swiflow app (e.g., `examples/RouterDemo`)
   shows the component tree.
3. Clicking a component with `@State` shows its current state values.
4. Refresh button updates both panes.
5. Opening the panel on a non-Swiflow page shows a clear "no Swiflow
   detected" message.
6. Multi-root apps render one tree section per selector.
7. The two new tests (Playwright contract + Swift format pin) pass.

## Out-of-MVP Roadmap (informational)

These exist so future phases can pick them up without re-brainstorming
the foundation:

- **Phase 19b**: Event-driven push updates. Add a Swift-side render
  event dispatch; introduce a content-script bridge; swap the panel's
  `DataSource` to `EventBridgeDataSource`.
- **Phase 19c**: DOM overlay + component picker. Hover a DOM element
  in the inspected page → highlight + reveal in tree.
- **Phase 19d**: `@State` editing. Add a Swift-side mutation API
  (`__swiflow.setState(path, field, value)`); add editable inputs
  in the state pane.
- **Phase 19e**: Chrome Web Store publication. Triggered by hitting 1.0.
