// Phase 19 panel logic.
//
// The panel runs in a Chrome extension context isolated from the
// inspected page. The bridge is the chrome.devtools.inspectedWindow API,
// which runs a string expression in the inspected page's context and
// returns the JSON-serialized result.
//
// All page-side calls go through DataSource so a future event-driven
// impl (Phase 19b) can swap in without touching the rendering layer.

// ── OS color-scheme detection ─────────────────────────────────────────────────
//
// The bundled Chromium tokens (design_system_tokens.css) trigger their
// dark variants via the `theme-with-dark-background` class on <html>,
// not via @media (prefers-color-scheme). Without that class the file's
// :root block stays in light mode regardless of OS preference. This
// IIFE adds the class when the OS prefers dark and listens for changes
// so the panel re-themes live if the user toggles their OS theme.
// Runs as early as possible (top of the only external script the panel
// loads); MV3 CSP forbids inline <script> so an HTML-level pre-paint
// hook isn't available — a brief FOUC of light theme on cold load is
// acceptable.
(() => {
  const html = document.documentElement;
  const mq = matchMedia("(prefers-color-scheme: dark)");
  const apply = () => html.classList.toggle("theme-with-dark-background", mq.matches);
  apply();
  mq.addEventListener("change", apply);
})();

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
    // Cross-browser eval dispatch. Chrome's devtools.inspectedWindow.eval is
    // callback-only — eval(expr, (result, exceptionInfo) => …) — while Safari
    // and Firefox implement the WebExtensions promise form — eval(expr)
    // resolving to [result, exceptionInfo]. Critically, Safari NATIVELY CRASHES
    // Web Inspector when handed Chrome's callback form, so we must not pass a
    // callback there. `browser` is defined in Safari/Firefox but not Chrome,
    // which lets us pick the right calling convention. (typeof guards against
    // a ReferenceError where `browser` is undeclared.)
    const inspected = chrome.devtools.inspectedWindow;
    return new Promise((resolve, reject) => {
      const settle = (result, exception) => {
        if (exception) {
          reject(new Error(String(exception.value || exception.description || exception.code || exception)));
          return;
        }
        if (!result || !result.ok) {
          reject(new Error((result && result.error) || "Unknown page-side error"));
          return;
        }
        resolve(result.value);
      };
      if (typeof browser !== "undefined" && browser.devtools) {
        // Promise form (Safari/Firefox): resolves to [result, exceptionInfo].
        inspected.eval(wrapped).then(
          (pair) => settle(pair && pair[0], pair && pair[1]),
          (err) => reject(err instanceof Error ? err : new Error(String(err)))
        );
      } else {
        // Callback form (Chrome).
        inspected.eval(wrapped, settle);
      }
    });
  }
}

const dataSource = new InspectedWindowDataSource();

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
      el.addEventListener("click", async () => {
        for (const prev of treePane.querySelectorAll(".tree-row.selected")) {
          prev.classList.remove("selected");
        }
        el.classList.add("selected");
        selectedPath = row.path;
        clearError();
        // `selector` is the closed-over loop variable from the enclosing
        // `for (const selector of selectors)`. const + for...of give each
        // iteration its own binding, so this closure captures the right one.
        try {
          const state = await dataSource.state(row.path);
          renderState(state);
          const perf = await dataSource.perf();
          renderFooter(perf, selector);
        } catch (err) {
          showError(err.message);
        }
      });
      rowsContainer.appendChild(el);
    }
  }
}

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
  // Sort alphabetically by field name. __swiflow.state() returns an object
  // whose key order reflects the Swift-side dictionary iteration order,
  // which isn't stable across renders. Without this sort, the field rows
  // shuffle between refreshes — distracting, and makes value-change
  // spotting harder.
  const entries = Object.entries(stateObj).sort(([a], [b]) => a.localeCompare(b));
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

// ── Refresh ───────────────────────────────────────────────────────────────────
//
// Single source of truth for "re-fetch everything and re-render". Called
// by the ↻ Refresh button (user-driven), the navigation handler, and the
// poll loop. `surfaceErrors` controls whether failures bubble to the
// error region (true for user-initiated, false for poll-driven).

async function refreshAll(surfaceErrors) {
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
    if (surfaceErrors) {
      showError(err.message);
    }
    throw err;
  }
}

document.getElementById("refresh-btn").addEventListener("click", async () => {
  clearError();
  try {
    await refreshAll(true);
  } catch (_) {
    // Error already surfaced via showError inside refreshAll.
  }
});

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

// ── Live polling (Phase 19b) ──────────────────────────────────────────────────
//
// Polls __swiflow.perf() every POLL_INTERVAL_MS while the panel is visible.
// On a change in any selector's `renders` count, runs refreshAll(). Poll-time
// errors are silent — they only paint the live indicator red. Visibility
// gating is driven externally by devtools.js calling swiflowStart/swiflowStop.

const POLL_INTERVAL_MS = 250;
const liveIndicator = document.getElementById("live-indicator");

let pollHandle = null;
let lastPerfSignature = null;

function setLiveIndicator(state, tooltip) {
  liveIndicator.classList.remove(
    "live-indicator--green",
    "live-indicator--grey",
    "live-indicator--red"
  );
  liveIndicator.classList.add(`live-indicator--${state}`);
  liveIndicator.title = tooltip;
}

function computePerfSignature(perf) {
  if (!perf) return "";
  const keys = Object.keys(perf).sort();
  const compact = {};
  for (const k of keys) compact[k] = perf[k].renders;
  return JSON.stringify(compact);
}

async function pollTick() {
  try {
    const perf = await dataSource.perf();
    setLiveIndicator("green", "Live");
    const signature = computePerfSignature(perf);
    if (signature !== lastPerfSignature) {
      lastPerfSignature = signature;
      // refreshAll(false): poll-driven, suppress error-region surfacing.
      // If the refresh itself fails, swallow — pollTick's own catch
      // (below) covers it on the next tick.
      try {
        await refreshAll(false);
      } catch (_) {
        // Silent — handled by the outer catch on the next poll.
      }
    }
  } catch (err) {
    setLiveIndicator("red", `Connection lost: ${err.message}`);
    // Preserve lastPerfSignature: when polling recovers, the next
    // successful tick will see whatever state moved during the outage
    // and trigger a single recovery refresh.
  }
}

window.swiflowStart = () => {
  if (pollHandle !== null) return; // already running
  setLiveIndicator("green", "Live");
  // Kick an immediate refresh so onShown doesn't wait 250ms to populate.
  // lastPerfSignature stays null here; the immediate poll will detect
  // "different" and run refreshAll on the first tick.
  pollHandle = setInterval(pollTick, POLL_INTERVAL_MS);
  pollTick();  // immediate first poll
};

window.swiflowStop = () => {
  if (pollHandle === null) return;
  clearInterval(pollHandle);
  pollHandle = null;
  setLiveIndicator("grey", "Paused (panel hidden)");
};
