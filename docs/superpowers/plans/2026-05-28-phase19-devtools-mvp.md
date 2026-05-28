# Phase 19 — Component DevTools (Chrome Panel, MVP) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Chrome DevTools panel that shows a Swiflow app's live component tree with click-to-inspect `@State` per node. Read-only, vanilla JS, sideloaded from `devtools/`.

**Architecture:** Chrome MV3 extension registers a "Swiflow" devtools panel. Panel calls `chrome.devtools.inspectedWindow.eval` to invoke the existing `window.__swiflow` API in the inspected page (built in Phase 9). Panel UI talks to a `DataSource` abstraction so a future event-driven impl can swap in without UI changes.

**Tech Stack:** Vanilla HTML / CSS / JS in `devtools/`. No build step. Tests: swift-testing (pins `DevAPIFormatter.treeString` output format) + Playwright (contract test against `__swiflow` API on the Counter example).

**Spec:** `docs/superpowers/specs/2026-05-28-phase19-devtools-mvp-design.md` (commit `5ffb2fc`)

> **Note on the Chrome API used:** `chrome.devtools.inspectedWindow.eval` is a Chrome extension API for running a string expression against the inspected page from a DevTools panel context. It is distinct from JavaScript's global `eval()` and is the only supported way for any Chrome DevTools panel (React, Vue, Redux, etc.) to read page state. The plan calls it out explicitly because the panel code uses it for every page-side read.

---

## File Structure

| File | Responsibility | Status |
|---|---|---|
| `Tests/SwiflowTests/Reactivity/DevAPIFormatterTests.swift` | Pin `DevAPIFormatter.treeString` output format | new |
| `Tests/playwright/devtools-api.spec.ts` | Contract: `__swiflow.tree/state/perf` returns documented shapes | new |
| `devtools/manifest.json` | MV3 manifest declaring the devtools_page | new |
| `devtools/devtools.html` | Chrome devtools_page entry HTML | new |
| `devtools/devtools.js` | Registers the Swiflow panel via `chrome.devtools.panels.create` | new |
| `devtools/panel.html` | Panel UI shell (HTML + inline CSS) | new |
| `devtools/panel.js` | Panel logic: DataSource, tree renderer, state pane, refresh | new |
| `devtools/README.md` | Sideload + manual smoke checklist | new |
| `CHANGELOG.md` | Phase 19 entry | modify |
| `README.md` | Mention DevTools panel in dev tooling section | modify |

Each `devtools/*` file is small and focused. `panel.js` is the biggest — built across Tasks 5–8 in additive layers so each commit is self-contained and reviewable.

---

## Task 1: Pin the tree-string format with a Swift unit test

**Files:**
- Test: `Tests/SwiflowTests/Reactivity/DevAPIFormatterTests.swift` (new)

This test goes FIRST. The panel depends on a stable indented-string format; this test fails loudly if anyone changes `DevAPIFormatter.treeString` without intending to.

- [ ] **Step 1: Write the test file**

Create `Tests/SwiflowTests/Reactivity/DevAPIFormatterTests.swift`:

```swift
// Tests/SwiflowTests/Reactivity/DevAPIFormatterTests.swift
//
// Pins the exact output format of DevAPIFormatter.treeString. The Phase 19
// devtools panel parses this string to render the component tree, so any
// silent change to the format would break the panel without any test
// catching it on the Swift side. If you NEED to change the format, update
// this test deliberately and bump the panel's parser in lock-step.

import Testing
@testable import Swiflow

@Suite("DevAPIFormatter.treeString output format is pinned for the Phase 19 panel parser")
@MainActor
struct DevAPIFormatterTreeStringTests {

    final class Leaf: Component {
        var body: VNode { .text("leaf") }
    }

    final class Mid: Component {
        var body: VNode { embed { Leaf() } }
    }

    final class Root: Component {
        var body: VNode { embed { Mid() } }
    }

    @Test("3-deep nested tree produces the canonical indented format with [body→] markers")
    func threeDeepCanonicalFormat() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v = VNode.component(.init(Root.self) { Root() })
        let result = diff(mounted: nil, next: v, handles: handles, handlers: handlers)

        let out = DevAPIFormatter.treeString(from: result.newMountTree)

        // Format invariants the panel parser depends on:
        //   - one line per component anchor
        //   - "  " (two spaces) of indent per depth level
        //   - shortName + space + "\"<path>\""
        //   - " [body→]" suffix when the component's body is another component anchor
        //   - lines separated by "\n"
        let expected = """
            Root "" [body→]
              Mid "" [body→]
                Leaf ""
            """
        #expect(out == expected)
    }

    @Test("element with two child components renders both at the parent's depth with indexed paths")
    func elementWithComponentChildren() {
        final class Item: Component {
            var body: VNode { .text("item") }
        }
        final class Container: Component {
            var body: VNode {
                .element(ElementData(tag: "div", children: [
                    .component(.init(Item.self) { Item() }),
                    .component(.init(Item.self) { Item() }),
                ]))
            }
        }

        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v = VNode.component(.init(Container.self) { Container() })
        let result = diff(mounted: nil, next: v, handles: handles, handlers: handlers)

        let out = DevAPIFormatter.treeString(from: result.newMountTree)

        let expected = """
            Container "" [body→]
              Item "0"
              Item "1"
            """
        #expect(out == expected)
    }

    @Test("lines are joined with newline, not CRLF; no trailing newline")
    func lineEndingsAreUnixAndNoTrailingNewline() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v = VNode.component(.init(Root.self) { Root() })
        let result = diff(mounted: nil, next: v, handles: handles, handlers: handlers)

        let out = DevAPIFormatter.treeString(from: result.newMountTree)

        #expect(!out.contains("\r"), "format must be LF, never CRLF")
        #expect(!out.hasSuffix("\n"), "no trailing newline")
        #expect(out.contains("\n"), "multi-line output uses '\\n' as separator")
    }
}
```

- [ ] **Step 2: Run the test to confirm it passes against current implementation**

Run: `swift test --filter DevAPIFormatterTreeStringTests`
Expected: PASS (3 tests). If `threeDeepCanonicalFormat` fails with a diff showing different `[body→]` placement or different indentation, the format has drifted from what the spec documented — update the expected string to match observed output AFTER confirming with the team that the format change was intentional, then bump the panel parser in lock-step in Task 5.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiflowTests/Reactivity/DevAPIFormatterTests.swift
git commit -m "$(cat <<'EOF'
test(devtools): pin DevAPIFormatter.treeString output format

The Phase 19 devtools panel parses the indented string returned by
__swiflow.tree() (which calls DevAPIFormatter.treeString). Any silent
change to the format would break the panel without any test catching
it on the Swift side. Three tests pin: 3-deep nesting + [body→]
markers, element-with-component-children indexed paths, line endings
(LF, no trailing newline).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Playwright contract test for `__swiflow` API shape

**Files:**
- Test: `Tests/playwright/devtools-api.spec.ts` (new)

Verifies `window.__swiflow.tree() / state(path) / perf()` return the shapes the panel depends on. Runs against the existing Counter demo on port 3000 (already configured in `playwright.config.ts`).

- [ ] **Step 1: Write the test file**

Create `Tests/playwright/devtools-api.spec.ts`:

```ts
// Tests/playwright/devtools-api.spec.ts
//
// Contract test for the window.__swiflow API surface that Phase 19's
// devtools panel depends on. Runs against the Counter dev server on
// port 3000 (configured in playwright.config.ts). If any of these
// assertions break, the panel parser must be updated in lock-step.

import { test, expect } from "@playwright/test";

test.describe("__swiflow API contract (devtools panel dependency)", () => {
  test.use({ baseURL: "http://127.0.0.1:3000" });

  test("window.__swiflow exists with tree, state, perf, handlers functions in dev mode", async ({ page }) => {
    await page.goto("/");
    // Wait for the app to mount (Counter heading is the established readiness signal).
    await expect(page.getByRole("heading", { name: "Hello, Swiflow!" })).toBeVisible();

    const apiShape = await page.evaluate(() => ({
      hasNamespace: typeof (window as any).__swiflow === "object",
      hasTree: typeof (window as any).__swiflow?.tree === "function",
      hasState: typeof (window as any).__swiflow?.state === "function",
      hasPerf: typeof (window as any).__swiflow?.perf === "function",
      hasHandlers: typeof (window as any).__swiflow?.handlers === "function",
    }));

    expect(apiShape).toEqual({
      hasNamespace: true,
      hasTree: true,
      hasState: true,
      hasPerf: true,
      hasHandlers: true,
    });
  });

  test("tree() returns object keyed by selector with indented string values", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByRole("heading", { name: "Hello, Swiflow!" })).toBeVisible();

    const tree = await page.evaluate(() => (window as any).__swiflow.tree());

    expect(typeof tree).toBe("object");
    const selectors = Object.keys(tree);
    expect(selectors.length).toBeGreaterThan(0);

    for (const sel of selectors) {
      expect(typeof tree[sel]).toBe("string");
      expect(tree[sel].length).toBeGreaterThan(0);
      // Spot-check the canonical line shape: TypeName "path" maybe-followed-by " [body→]".
      const firstLine = tree[sel].split("\n")[0];
      expect(firstLine).toMatch(/^\S+ "[^"]*"( \[body→\])?$/);
    }
  });

  test("perf() returns object keyed by selector with renders / lastPatchCount / lastRenderMs numbers", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByRole("heading", { name: "Hello, Swiflow!" })).toBeVisible();

    const perf = await page.evaluate(() => (window as any).__swiflow.perf());

    expect(typeof perf).toBe("object");
    for (const sel of Object.keys(perf)) {
      expect(typeof perf[sel].renders).toBe("number");
      expect(typeof perf[sel].lastPatchCount).toBe("number");
      expect(typeof perf[sel].lastRenderMs).toBe("number");
    }
  });

  test("state(path) returns @State object for the root component path; null for unknown path", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByRole("heading", { name: "Hello, Swiflow!" })).toBeVisible();

    // The Counter demo's root component holds the count @State. Path "" hits the root.
    const rootState = await page.evaluate(() => (window as any).__swiflow.state(""));
    expect(rootState).not.toBeNull();
    expect(typeof rootState).toBe("object");
    // Counter's @State field is named `count`. If the example renames it,
    // bump the expected name — the SHAPE (object keyed by field name with
    // primitive value) is what matters.
    expect(rootState).toHaveProperty("count");
    expect(typeof rootState.count).toBe("number");

    const unknownState = await page.evaluate(() => (window as any).__swiflow.state("999.999.999"));
    expect(unknownState).toBeNull();
  });
});
```

- [ ] **Step 2: Run the test against the Counter dev server**

The default `playwright.config.ts` spins up the Counter dev server on port 3000 automatically. Run from `Tests/playwright`:

```bash
cd Tests/playwright
npx playwright test devtools-api.spec.ts
```

Expected: 4 tests PASS.

If `state("")` fails on the `count` property assertion, inspect the demo's actual state field name with `page.evaluate(() => (window as any).__swiflow.state(""))` and update the assertion to match. The exact name is not load-bearing for the panel — only the shape (object keyed by field name with primitive value).

- [ ] **Step 3: Commit**

```bash
git add Tests/playwright/devtools-api.spec.ts
git commit -m "$(cat <<'EOF'
test(devtools): playwright contract test for __swiflow API shape

Verifies window.__swiflow.tree() / state() / perf() / handlers()
exist as functions and return the shapes the Phase 19 devtools
panel depends on. Runs against the Counter dev server on port 3000
(configured in playwright.config.ts).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Chrome extension scaffold (manifest + devtools_page + empty panel)

**Files:**
- Create: `devtools/manifest.json`
- Create: `devtools/devtools.html`
- Create: `devtools/devtools.js`
- Create: `devtools/panel.html`
- Create: `devtools/panel.js`

Lands a minimum-viable extension that, when sideloaded, creates a "Swiflow" tab in Chrome DevTools showing a placeholder panel. No data flow yet. Verifies the manifest, panel registration, and file layout before any UI logic depends on them.

- [ ] **Step 1: Write the manifest**

Create `devtools/manifest.json`:

```json
{
  "manifest_version": 3,
  "name": "Swiflow DevTools",
  "version": "0.1.0",
  "description": "Inspect Swiflow (Swift WASM) component trees and @State live in Chrome DevTools.",
  "minimum_chrome_version": "108",
  "devtools_page": "devtools.html"
}
```

- [ ] **Step 2: Write the devtools_page entry HTML**

Create `devtools/devtools.html`:

```html
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>Swiflow DevTools</title>
  </head>
  <body>
    <script src="devtools.js"></script>
  </body>
</html>
```

- [ ] **Step 3: Write the panel registrar**

Create `devtools/devtools.js`:

```js
// Registers the "Swiflow" panel in Chrome DevTools. This file runs in
// the devtools_page context — separate from the panel's own context.
// chrome.devtools.panels.create returns the panel handle but we don't
// currently need to attach any cross-context listeners here; all data
// flow happens inside panel.js via the chrome.devtools.inspectedWindow API.
chrome.devtools.panels.create(
  "Swiflow",
  null,                // no icon path for MVP
  "panel.html",
  () => {
    // Panel created. Nothing to do here yet.
  }
);
```

- [ ] **Step 4: Write the panel HTML shell**

Create `devtools/panel.html`:

```html
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>Swiflow Panel</title>
    <style>
      :root {
        --bg: #1e1e1e;
        --fg: #d4d4d4;
        --accent: #4ec9b0;
        --error-bg: #5a1d1d;
        --error-fg: #ffb4b4;
        --row-hover: #2a2d2e;
        --row-selected: #094771;
        --border: #333;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        font-size: 12px;
      }
      html, body {
        margin: 0;
        padding: 0;
        height: 100%;
        background: var(--bg);
        color: var(--fg);
      }
      body {
        display: flex;
        flex-direction: column;
      }
      header {
        padding: 6px 10px;
        border-bottom: 1px solid var(--border);
      }
      #error-region {
        padding: 8px 10px;
        background: var(--error-bg);
        color: var(--error-fg);
        border-bottom: 1px solid var(--border);
      }
      #error-region[hidden] { display: none; }
      main {
        flex: 1;
        display: flex;
        min-height: 0;
      }
      #tree-pane, #state-pane {
        overflow: auto;
        padding: 8px;
      }
      #tree-pane {
        flex: 1;
        border-right: 1px solid var(--border);
      }
      #state-pane {
        width: 40%;
        min-width: 200px;
      }
      footer {
        padding: 4px 10px;
        border-top: 1px solid var(--border);
        font-size: 11px;
        color: #888;
      }
      .tree-row {
        white-space: pre;
        cursor: pointer;
        padding: 1px 4px;
      }
      .tree-row:hover { background: var(--row-hover); }
      .tree-row.selected { background: var(--row-selected); }
      .state-key { color: var(--accent); }
      .state-value { color: var(--fg); }
      .empty-state {
        padding: 20px;
        text-align: center;
        color: #666;
      }
    </style>
  </head>
  <body>
    <header>
      <button id="refresh-btn">↻ Refresh</button>
    </header>
    <div id="error-region" hidden></div>
    <main>
      <div id="tree-pane">
        <div class="empty-state">Click ↻ Refresh to load the component tree.</div>
      </div>
      <div id="state-pane">
        <div class="empty-state">Select a component to view its @State.</div>
      </div>
    </main>
    <footer id="footer"></footer>
    <script src="panel.js"></script>
  </body>
</html>
```

- [ ] **Step 5: Write the placeholder panel.js**

Create `devtools/panel.js`:

```js
// Phase 19 panel logic. Currently a placeholder; Tasks 4–7 layer in
// the DataSource, tree renderer, state pane, refresh wiring, and
// error handling.

document.getElementById("refresh-btn").addEventListener("click", () => {
  // No-op for now. Task 4 wires this up.
  console.log("[Swiflow DevTools] Refresh clicked (not yet wired)");
});
```

- [ ] **Step 6: Smoke-test the sideload**

Manual step — there's no automated harness for Chrome extension loading.

1. Open Chrome and navigate to `chrome://extensions`.
2. Enable "Developer mode" (toggle at top right).
3. Click "Load unpacked" and select the `devtools/` directory.
4. Open any web page.
5. Open DevTools (Cmd-Opt-I).
6. Confirm a "Swiflow" tab appears in the DevTools tab bar.
7. Click it. Confirm the panel layout renders with the ↻ Refresh button and the two empty-state messages.

If the panel doesn't appear, check `chrome://extensions` for load errors and fix them before continuing.

- [ ] **Step 7: Commit**

```bash
git add devtools/manifest.json devtools/devtools.html devtools/devtools.js devtools/panel.html devtools/panel.js
git commit -m "$(cat <<'EOF'
feat(devtools): Chrome MV3 extension scaffold (panel registration + UI shell)

Phase 19 Task 3: minimum-viable Chrome devtools extension that, when
sideloaded from devtools/, registers a "Swiflow" tab in DevTools and
renders an empty panel shell. No data flow yet — Tasks 4–7 layer in
the DataSource, tree renderer, state pane, and refresh wiring.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `DataSource` abstraction + `InspectedWindowDataSource` impl

**Files:**
- Modify: `devtools/panel.js`

Lands the abstraction layer the panel UI talks to. Wires the refresh button to log fetched data; no rendering yet (Task 5).

- [ ] **Step 1: Replace `devtools/panel.js` with the DataSource + wired refresh**

Replace the entire contents of `devtools/panel.js`:

```js
// Phase 19 panel logic.
//
// The panel runs in a Chrome extension context isolated from the
// inspected page. The bridge is the chrome.devtools.inspectedWindow API,
// which runs a string expression in the inspected page's context and
// returns the JSON-serialized result.
//
// All page-side calls go through DataSource so a future event-driven
// impl (Phase 19b) can swap in without touching the rendering layer.

/**
 * Abstract source of devtools data. Methods resolve to documented
 * shapes or null on failure. Errors are surfaced via the returned
 * Promise rejecting with an Error whose .message is suitable for
 * display in the panel's error region.
 */
class DataSource {
  async tree()      { throw new Error("not implemented"); }
  async state(path) { throw new Error("not implemented"); }
  async perf()      { throw new Error("not implemented"); }
}

/**
 * MVP implementation: queries window.__swiflow.* in the inspected
 * page via the chrome.devtools.inspectedWindow API and returns the
 * JSON-serialized result. Wraps every call in an inline envelope so
 * page-side exceptions surface instead of being silently swallowed.
 */
class InspectedWindowDataSource extends DataSource {
  async tree()      { return this._call("window.__swiflow.tree()"); }
  async state(path) { return this._call(`window.__swiflow.state(${JSON.stringify(path)})`); }
  async perf()      { return this._call("window.__swiflow.perf()"); }

  _call(expr) {
    // Inline envelope: page-side try/catch produces { ok, value, error }.
    // Without this, the underlying chrome.devtools.inspectedWindow API
    // silently returns null on page exceptions and on non-JSON-serializable
    // values.
    const wrapped = `
      (() => {
        try {
          if (!window.__swiflow) {
            return { ok: false, error: "No Swiflow runtime detected on this page (window.__swiflow is undefined). Make sure the app is running in dev mode." };
          }
          return { ok: true, value: ${expr} };
        } catch (e) {
          return { ok: false, error: String(e && e.message ? e.message : e) };
        }
      })()
    `;
    return new Promise((resolve, reject) => {
      chrome.devtools.inspectedWindow.eval(wrapped, (result, exception) => {
        if (exception) {
          reject(new Error(String(exception.value || exception.description || exception)));
          return;
        }
        if (!result || !result.ok) {
          reject(new Error((result && result.error) || "Unknown page-side error"));
          return;
        }
        resolve(result.value);
      });
    });
  }
}

const dataSource = new InspectedWindowDataSource();

// Wire the refresh button. Task 5 replaces the console.log with real rendering.
document.getElementById("refresh-btn").addEventListener("click", async () => {
  try {
    const tree = await dataSource.tree();
    console.log("[Swiflow DevTools] tree:", tree);
    const perf = await dataSource.perf();
    console.log("[Swiflow DevTools] perf:", perf);
  } catch (err) {
    console.error("[Swiflow DevTools]", err.message);
  }
});
```

- [ ] **Step 2: Reload the extension and smoke-test**

1. Open `chrome://extensions`. Find "Swiflow DevTools". Click the reload icon (⟳).
2. Open one of the example apps (e.g., `examples/RouterDemo` running on port 3001, or the Counter on 3000) in another tab.
3. Open DevTools on that tab. Click the Swiflow panel.
4. Click ↻ Refresh.
5. Open the panel's own DevTools: right-click in the panel area → "Inspect" (this opens DevTools on the DevTools page). Switch to the Console tab.
6. Confirm two log lines: `[Swiflow DevTools] tree: { ... }` and `[Swiflow DevTools] perf: { ... }`.
7. Navigate the inspected tab to `about:blank` and click Refresh again. Confirm an error log: `[Swiflow DevTools] No Swiflow runtime detected on this page ...`.

- [ ] **Step 3: Commit**

```bash
git add devtools/panel.js
git commit -m "$(cat <<'EOF'
feat(devtools): DataSource abstraction + InspectedWindowDataSource impl

Phase 19 Task 4: wraps the chrome.devtools.inspectedWindow API with
an inline error envelope so page-side exceptions and "no __swiflow"
cases surface as rejected Promises instead of silently returning
null. Refresh button now logs tree/perf data to the panel's own
console. Tree/state rendering lands in Task 5.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Tree renderer with click selection

**Files:**
- Modify: `devtools/panel.js`

Parses the indented string returned by `tree()` into clickable rows. Click selects a row (visual highlight + records the selected path). Per-selector grouping deferred to Task 7.

- [ ] **Step 1: Add the tree parser + renderer to `devtools/panel.js`**

After the `const dataSource = new InspectedWindowDataSource();` line, but BEFORE the existing `refresh-btn` listener, insert:

```js
// ── Tree parsing ──────────────────────────────────────────────────────────────
//
// __swiflow.tree() returns { selector: "indented\nstring", ... }. Each
// non-empty line in the indented string represents one component anchor.
// Format pinned by DevAPIFormatterTreeStringTests:
//   "  " * depth + TypeName + " " + "\"<path>\"" + (" [body→]" if present)
//
// Parser returns an array of { depth, typeName, path, hasBody } records
// in document order. The panel renderer walks the array; each record
// becomes one clickable row.

function parseTreeString(s) {
  if (!s) return [];
  const rows = [];
  for (const line of s.split("\n")) {
    if (line.length === 0) continue;
    let i = 0;
    while (line.startsWith("  ", i)) i += 2;
    const depth = i / 2;
    const body = line.slice(i);
    const hasBody = body.endsWith(" [body→]");
    const trimmed = hasBody ? body.slice(0, -" [body→]".length) : body;
    const m = trimmed.match(/^(\S+) "([^"]*)"$/);
    if (!m) continue;
    rows.push({ depth, typeName: m[1], path: m[2], hasBody });
  }
  return rows;
}

// ── Tree rendering ────────────────────────────────────────────────────────────

const treePane = document.getElementById("tree-pane");

// Currently-selected row's path, or null. Used by the state pane (Task 6)
// and the refresh handler to re-fetch state for the same selection.
let selectedPath = null;

function renderTree(treeData) {
  treePane.replaceChildren();
  if (!treeData || Object.keys(treeData).length === 0) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = "No mounted roots.";
    treePane.appendChild(empty);
    return;
  }

  const selectors = Object.keys(treeData);
  const showSelectorHeaders = selectors.length > 1;

  for (const selector of selectors) {
    let rowsContainer = treePane;
    if (showSelectorHeaders) {
      // Collapsible group per selector. The ▾/▸ glyph toggles a wrapper
      // div containing this selector's rows.
      const header = document.createElement("div");
      header.style.fontWeight = "bold";
      header.style.padding = "4px 0";
      header.style.cursor = "pointer";
      header.style.userSelect = "none";
      let collapsed = false;
      const updateLabel = () => {
        header.textContent = `${collapsed ? "▸" : "▾"} ${selector}`;
      };
      updateLabel();
      const group = document.createElement("div");
      header.addEventListener("click", () => {
        collapsed = !collapsed;
        group.hidden = collapsed;
        updateLabel();
      });
      treePane.appendChild(header);
      treePane.appendChild(group);
      rowsContainer = group;
    }
    for (const row of parseTreeString(treeData[selector])) {
      const el = document.createElement("div");
      el.className = "tree-row";
      el.dataset.path = row.path;
      el.dataset.selector = selector;
      el.style.paddingLeft = `${row.depth * 16 + 4}px`;
      el.textContent = `${row.typeName} "${row.path}"${row.hasBody ? " [body→]" : ""}`;
      if (row.path === selectedPath) {
        el.classList.add("selected");
      }
      el.addEventListener("click", () => {
        for (const prev of treePane.querySelectorAll(".tree-row.selected")) {
          prev.classList.remove("selected");
        }
        el.classList.add("selected");
        selectedPath = row.path;
        // Task 6 wires state-pane refresh here.
      });
      rowsContainer.appendChild(el);
    }
  }
}
```

Then UPDATE the existing refresh-btn handler to call `renderTree`:

```js
document.getElementById("refresh-btn").addEventListener("click", async () => {
  try {
    const tree = await dataSource.tree();
    renderTree(tree);
  } catch (err) {
    console.error("[Swiflow DevTools]", err.message);
  }
});
```

(Remove the old `console.log` and `perf` lines — the perf surface comes back in Task 6.)

- [ ] **Step 2: Reload + smoke-test**

1. Reload the extension at `chrome://extensions`.
2. Open the Counter demo at http://127.0.0.1:3000 with DevTools → Swiflow panel.
3. Click ↻ Refresh.
4. Confirm the tree pane shows rows like `App "" [body→]`, indented children below.
5. Click a row. Confirm it gets a blue selection highlight.
6. Click a different row. Confirm the previous selection clears.

- [ ] **Step 3: Commit**

```bash
git add devtools/panel.js
git commit -m "$(cat <<'EOF'
feat(devtools): tree parser + clickable row rendering

Phase 19 Task 5: parses the indented string from __swiflow.tree()
into a flat array of {depth, typeName, path, hasBody} records and
renders them as clickable, indented rows in the tree pane. Click
selects a row (visual highlight + records the path for the state
pane in Task 6). Multi-root apps render one collapsible group per
selector with a ▾/▸ toggle; single-root apps render flat with no
selector header.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: State pane + footer (perf summary)

**Files:**
- Modify: `devtools/panel.js`

Selecting a row fetches its `@State` via `state(path)` and renders the key:value list. Footer shows `perf()` for the selected row's selector.

- [ ] **Step 1: Add the state pane renderer + footer renderer**

In `devtools/panel.js`, after the `function renderTree` block, insert:

```js
// ── State pane ────────────────────────────────────────────────────────────────

const statePane = document.getElementById("state-pane");

function renderState(stateObj) {
  statePane.replaceChildren();
  if (stateObj === null || stateObj === undefined) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = "No @State on this component.";
    statePane.appendChild(empty);
    return;
  }
  const entries = Object.entries(stateObj);
  if (entries.length === 0) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = "No @State on this component.";
    statePane.appendChild(empty);
    return;
  }
  for (const [key, value] of entries) {
    const row = document.createElement("div");
    row.style.padding = "2px 4px";
    const k = document.createElement("span");
    k.className = "state-key";
    k.textContent = `${key}: `;
    const v = document.createElement("span");
    v.className = "state-value";
    v.textContent = JSON.stringify(value);
    row.appendChild(k);
    row.appendChild(v);
    statePane.appendChild(row);
  }
}

function clearState() {
  statePane.replaceChildren();
  const empty = document.createElement("div");
  empty.className = "empty-state";
  empty.textContent = "Select a component to view its @State.";
  statePane.appendChild(empty);
}

// ── Footer (perf summary) ─────────────────────────────────────────────────────

const footer = document.getElementById("footer");

function renderFooter(perfData, activeSelector) {
  footer.replaceChildren();
  if (!perfData || Object.keys(perfData).length === 0) {
    footer.textContent = "";
    return;
  }
  // Spec: show perf for the selector containing the currently-selected
  // tree node. When no node is selected, show the first selector
  // returned by perf() (insertion order matches multi-root render order).
  const selector = activeSelector || Object.keys(perfData)[0];
  const entry = perfData[selector];
  if (!entry) {
    footer.textContent = "";
    return;
  }
  footer.textContent =
    `Selector: ${selector} | Renders: ${entry.renders} ` +
    `| LastPatch: ${entry.lastPatchCount} | LastRenderMs: ${entry.lastRenderMs.toFixed(2)}`;
}
```

- [ ] **Step 2: Wire row click to fetch and render state**

Replace the existing `el.addEventListener("click", () => { ... })` block in `renderTree` with:

```js
      el.addEventListener("click", async () => {
        for (const prev of treePane.querySelectorAll(".tree-row.selected")) {
          prev.classList.remove("selected");
        }
        el.classList.add("selected");
        selectedPath = row.path;
        const selector = el.dataset.selector;
        try {
          const state = await dataSource.state(row.path);
          renderState(state);
          const perf = await dataSource.perf();
          renderFooter(perf, selector);
        } catch (err) {
          console.error("[Swiflow DevTools]", err.message);
        }
      });
```

(`showError` is added in Task 7; for this task, `console.error` is the placeholder.)

- [ ] **Step 3: Update the refresh handler to also render footer**

Replace the existing refresh-btn click handler with:

```js
document.getElementById("refresh-btn").addEventListener("click", async () => {
  try {
    const tree = await dataSource.tree();
    renderTree(tree);
    const perf = await dataSource.perf();
    renderFooter(perf, null);
    if (selectedPath !== null) {
      const state = await dataSource.state(selectedPath);
      renderState(state);
    } else {
      clearState();
    }
  } catch (err) {
    console.error("[Swiflow DevTools]", err.message);
  }
});
```

- [ ] **Step 4: Reload + smoke-test**

1. Reload the extension.
2. Open the Counter demo → Swiflow panel.
3. Click ↻ Refresh. Confirm tree appears AND footer shows e.g. `Selector: #app | Renders: 1 | LastPatch: ... | LastRenderMs: ...`.
4. Click the root component row. Confirm the state pane shows `count: 0` (or similar).
5. Click ↻ Refresh again. Confirm state pane still shows count for the still-selected row.
6. Click a row with no `@State` (e.g., a leaf with no fields). Confirm state pane shows "No @State on this component."

- [ ] **Step 5: Commit**

```bash
git add devtools/panel.js
git commit -m "$(cat <<'EOF'
feat(devtools): state pane + perf footer

Phase 19 Task 6: selecting a tree row fetches __swiflow.state(path)
and renders the @State fields as a key:value list. Footer shows
__swiflow.perf() data for the selector containing the selected row
(falls back to the first selector when nothing is selected).
Refresh button now re-fetches all three: tree, state (if a row is
selected), perf.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Error region + auto-refresh on navigation

**Files:**
- Modify: `devtools/panel.js`

Surfaces errors in the top error region (replacing the temporary `console.error` calls) and re-fetches automatically when the inspected page navigates.

- [ ] **Step 1: Add the error region wiring**

In `devtools/panel.js`, near the top (after the `const dataSource = new InspectedWindowDataSource();` line), insert:

```js
// ── Error region ──────────────────────────────────────────────────────────────

const errorRegion = document.getElementById("error-region");

function showError(message) {
  errorRegion.textContent = message;
  errorRegion.hidden = false;
}

function clearError() {
  errorRegion.textContent = "";
  errorRegion.hidden = true;
}
```

- [ ] **Step 2: Replace `console.error` calls with `showError`**

Find ALL `console.error("[Swiflow DevTools]", err.message);` lines in the file and replace them with `showError(err.message);`. There are two: one in the refresh-btn handler and one in the row click handler.

Then add `clearError();` at the START of the refresh-btn handler (before `try`) and at the start of the row click handler (before `try`):

```js
document.getElementById("refresh-btn").addEventListener("click", async () => {
  clearError();
  try {
    // ... existing body ...
```

```js
      el.addEventListener("click", async () => {
        // selection update
        for (const prev of treePane.querySelectorAll(".tree-row.selected")) {
          prev.classList.remove("selected");
        }
        el.classList.add("selected");
        selectedPath = row.path;
        clearError();
        const selector = el.dataset.selector;
        try {
          // ... existing fetch + render code ...
```

- [ ] **Step 3: Add auto-refresh on navigation**

At the end of `devtools/panel.js`, append:

```js
// ── Auto-refresh on navigation ────────────────────────────────────────────────
//
// Re-fetch when the inspected page navigates. Without this, the panel
// shows stale data from the previous URL. Selection is cleared because
// the previous path may not exist in the new tree.
chrome.devtools.network.onNavigated.addListener(() => {
  selectedPath = null;
  clearState();
  document.getElementById("refresh-btn").click();
});
```

- [ ] **Step 4: Reload + smoke-test**

1. Reload the extension.
2. Open the Counter demo → Swiflow panel. Click ↻ Refresh. Tree appears.
3. In the inspected tab, navigate to `about:blank`. Confirm the panel automatically re-fetches and shows "No Swiflow runtime detected on this page (window.__swiflow is undefined). Make sure the app is running in dev mode." in the red error region at the top.
4. Navigate back to the Counter. Confirm the error clears and the tree reappears.
5. Trigger an error manually: in the inspected tab's console, run `window.__swiflow = null`. Click ↻ Refresh in the panel. Confirm the same error appears.
6. Restore: navigate to the Counter again or reload it. Confirm error clears.

- [ ] **Step 5: Commit**

```bash
git add devtools/panel.js
git commit -m "$(cat <<'EOF'
feat(devtools): error region + auto-refresh on page navigation

Phase 19 Task 7: errors from page-side queries (missing __swiflow,
runtime exceptions) now surface in the top error region instead of
being lost to the panel's own console. Auto-refresh fires on
chrome.devtools.network.onNavigated so the panel stays in sync
with the inspected page; selection clears on navigation because
the previous path may not exist in the new tree.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: devtools/README.md (sideload + smoke checklist)

**Files:**
- Create: `devtools/README.md`

User-facing documentation for sideloading the extension and verifying it works.

- [ ] **Step 1: Write the README**

Create `devtools/README.md`:

```markdown
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
   `cd examples/RouterDemo && swiflow dev`).
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

Multi-root apps render one section per mounted selector with a bold
header.

---

## Limitations (MVP)

- **No automatic polling.** Click ↻ Refresh to update after a
  `@State` change. Auto-refresh fires only on full page navigation.
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
2. [ ] Start a dev server: `cd examples/RouterDemo && swiflow dev`
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
```

- [ ] **Step 2: Commit**

```bash
git add devtools/README.md
git commit -m "$(cat <<'EOF'
docs(devtools): sideload instructions + manual smoke checklist

Phase 19 Task 8: user-facing README at devtools/README.md covering
installation, what the panel shows, MVP limitations, an
8-step smoke checklist, and troubleshooting for the two most likely
gotchas (panel tab not appearing, "no runtime" on a release build).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Project README + CHANGELOG

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add a DevTools mention to the project README**

In `README.md`, find the section that mentions dev tooling (search with `grep -n "DevTools\|dev tooling\|devtools" README.md`). If a section exists, add the line at the end of it. If no such section exists, add this block above the existing "Examples" or "Quick start" section:

```markdown
### Chrome DevTools panel

A read-only Chrome DevTools extension at [`devtools/`](devtools/) shows
the live component tree and `@State` of any Swiflow app running in dev
mode. Sideload via `chrome://extensions` → **Load unpacked** →
select `devtools/`. See [`devtools/README.md`](devtools/README.md) for
the full smoke checklist.
```

- [ ] **Step 2: Add the Phase 19 entry to CHANGELOG.md**

Insert a new `##` section ABOVE the current topmost entry (which is
`## [Phase 18] — onChange for nested components` per the most recent
push). The new entry:

```markdown
## [Phase 19] — Component DevTools (Chrome panel, MVP)

### Added
- Chrome DevTools extension at `devtools/` — sideload via `chrome://extensions` → Load unpacked. Adds a "Swiflow" tab in DevTools that shows the live component tree and `@State` of any Swiflow app running in dev mode. Read-only MVP; DOM overlay, `@State` editing, perf graphs, and Web Store publication are explicitly deferred to later phases (19b/c/d/e). See `devtools/README.md` for usage.

### Tests
- New Swift unit test `DevAPIFormatterTreeStringTests` pins the exact output format of `DevAPIFormatter.treeString` — the indented string the panel parses. Format drift now fails Swift tests at the source.
- New Playwright contract test `devtools-api.spec.ts` asserts the shape of `window.__swiflow.tree() / state() / perf() / handlers()` on the Counter demo. Catches integration drift in the API surface the panel depends on.

### Internals
- No production Swift code changes. No JS driver changes. No patch protocol changes. The extension consumes the `window.__swiflow` API surface shipped by Phase 9 as-is.
```

- [ ] **Step 3: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs(phase19): mention DevTools panel in README + CHANGELOG entry

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Final verification (after all tasks)

- [ ] `swift test --filter DevAPIFormatterTreeStringTests` — 3/3 pass
- [ ] `cd Tests/playwright && npx playwright test devtools-api.spec.ts` — 4/4 pass
- [ ] `swift test` — full suite still green
- [ ] Walk through the 8-step smoke checklist in `devtools/README.md` end-to-end against a live Swiflow app

If any smoke-checklist step fails, file it under the corresponding task's section and revisit before declaring Phase 19 complete.
