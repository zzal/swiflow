// Panel core — browser-agnostic DevTools panel logic (rendering, polling,
// errors, build stamp). Shared verbatim by the Chrome and Safari extensions.
//
// The panel never talks to the inspected page directly. A browser-specific
// datasource.js (loaded just before this script in panel.html) defines the
// global SWIFLOW_DATA_SOURCE — an object with async tree(), state(path) and
// perf() methods — and this core consumes it. Chrome's datasource.js uses
// chrome.devtools.inspectedWindow.eval; Safari's uses a messaging bridge
// (eval natively crashes Safari's Web Inspector).

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

// Build stamp — proves which panel bundle is actually live. Safari and Web
// Inspector cache extension code aggressively, so during development a blank
// stamp means you're still running stale cached code (do a clean rebuild +
// reopen Web Inspector). Reads the version from the loaded manifest.
(() => {
  const tag = document.getElementById("build-tag");
  const manifest = chrome.runtime && chrome.runtime.getManifest && chrome.runtime.getManifest();
  if (tag && manifest) tag.textContent = "v" + manifest.version;
})();

// The data source is the browser-specific transport, provided by datasource.js
// (loaded before this file). See the SWIFLOW_DATA_SOURCE contract above.
const dataSource = globalThis.SWIFLOW_DATA_SOURCE;

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

if (!dataSource) {
  // datasource.js failed to load or didn't define the contract. Without it
  // nothing works, so surface it loudly rather than failing per-call later.
  showError("Internal error: no data source loaded (datasource.js missing or failed).");
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

const footer = document.getElementById("footer-stats");

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
  const separatorElm = document.createElement("div");
  separatorElm.textContent = '|';
  separatorElm.style.opacity = 0.5;

  const selectorElm = document.createElement("div");
  selectorElm.textContent = `Selector: ${selector}`;
  footer.appendChild(selectorElm);

  const rendersElm = document.createElement("div");
  rendersElm.textContent = `Renders: ${entry.renders}`;
  footer.appendChild(separatorElm.cloneNode(true));
  footer.appendChild(rendersElm);

  const lastPatchElm = document.createElement("div");
  lastPatchElm.textContent = `LastPatch: ${entry.lastPatchCount}`;
  footer.appendChild(separatorElm.cloneNode(true));
  footer.appendChild(lastPatchElm);

  // Round to 1 decimal but drop a trailing ".0". Safari clamps performance.now()
  // to whole milliseconds, so its render times are integers — show "6", not "6.0"
  // (Chrome's finer timer still shows e.g. "6.2").
  const renderMs = Math.round(entry.lastRenderMs * 10) / 10;
  const lastRenderTimeElm = document.createElement("div");
  lastRenderTimeElm.textContent = `LastRenderMs: ${renderMs}`;
  footer.appendChild(separatorElm);
  footer.appendChild(lastRenderTimeElm);
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
    // A fully successful refresh means the panel is healthy — clear any stale
    // error (e.g. a transient one surfaced mid-reload). Persistent errors stay,
    // because a failing fetch throws before reaching here.
    clearError();
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
  // Reset for the new page and flag a reconnect so the running poll re-renders
  // once the new page's runtime is ready — even if the render count coincides.
  // The Refresh click does an immediate pull; if it races the page teardown and
  // surfaces a transient error, the next successful poll clears it (refreshAll).
  selectedPath = null;
  lastPerfSignature = null;
  pollLive = false;
  clearState();
  document.getElementById("refresh-btn").click();
});

// ── Live polling (Phase 19b) ──────────────────────────────────────────────────
//
// Polls __swiflow.perf() every POLL_INTERVAL_MS while the panel is visible.
// On a change in any selector's `renders` count, runs refreshAll(). Poll-time
// errors are silent — they only paint the live indicator red. Visibility
// gating is driven externally by devtools.js calling swiflowStart/swiflowStop.

// Live-poll cadence. The header slider picks one of these stops (indices 0..4).
const POLL_INTERVALS = [250, 500, 750, 1000, 2000];
let pollIntervalMs = POLL_INTERVALS[0];
const liveIndicator = document.getElementById("live-indicator");

let pollHandle = null;
let lastPerfSignature = null;
let pollLive = false; // did the previous poll succeed? (drives reconnect detection)

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
    // Reconnect detection: a poll that succeeds right after a failure means the
    // runtime went away and came back — i.e. the page reloaded. Force a full
    // refresh even if the render count happens to match, and even in browsers
    // where devtools.network.onNavigated never fires (Safari). This is what
    // makes the panel re-live a reloaded app on its own, in both browsers.
    const reconnected = !pollLive;
    pollLive = true;
    setLiveIndicator("green", "Live");
    const signature = computePerfSignature(perf);
    if (reconnected || signature !== lastPerfSignature) {
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
    pollLive = false;
    setLiveIndicator("red", `Connection lost: ${err.message}`);
    // Next successful tick will be treated as a reconnect and force a refresh.
  }
}

window.swiflowStart = () => {
  if (pollHandle !== null) return; // already running
  setLiveIndicator("green", "Live");
  // Kick an immediate refresh so onShown doesn't wait 250ms to populate.
  // lastPerfSignature stays null here; the immediate poll will detect
  // "different" and run refreshAll on the first tick.
  pollHandle = setInterval(pollTick, pollIntervalMs);
  pollTick();  // immediate first poll
};

window.swiflowStop = () => {
  if (pollHandle === null) return;
  clearInterval(pollHandle);
  pollHandle = null;
  pollLive = false; // re-showing the panel counts as a reconnect → forces a fresh pull
  setLiveIndicator("grey", "Paused (panel hidden)");
};

// ── Poll-interval control (header slider) ──────────────────────────────────
// Maps the 5-stop slider to POLL_INTERVALS and applies the choice live: updates
// the label, restarts the running timer at the new cadence, and remembers the
// pick across reloads via localStorage.
const POLL_STORAGE_KEY = "swiflow.pollIntervalMs";
const pollSlider = document.getElementById("poll-slider");
const pollLabel = document.getElementById("poll-label");

function applyPollIndex(index, persist) {
  pollIntervalMs = POLL_INTERVALS[index] != null ? POLL_INTERVALS[index] : POLL_INTERVALS[0];
  if (pollLabel) pollLabel.textContent = `${pollIntervalMs} ms`;
  if (pollSlider) pollSlider.value = String(index);
  // Restart the timer immediately if polling is live, so the new cadence
  // takes effect without waiting for the current interval to elapse.
  if (pollHandle !== null) {
    clearInterval(pollHandle);
    pollHandle = setInterval(pollTick, pollIntervalMs);
  }
  if (persist) {
    try { localStorage.setItem(POLL_STORAGE_KEY, String(pollIntervalMs)); } catch (_) {}
  }
}

// Restore the saved cadence (default 250 ms) before polling starts below.
(() => {
  let saved = POLL_INTERVALS[0];
  try { saved = parseInt(localStorage.getItem(POLL_STORAGE_KEY), 10) || saved; } catch (_) {}
  const idx = POLL_INTERVALS.indexOf(saved);
  applyPollIndex(idx >= 0 ? idx : 0, false);
})();

if (pollSlider) {
  pollSlider.addEventListener("input", () => applyPollIndex(parseInt(pollSlider.value, 10), true));
}

// Drive polling from the panel's OWN visibility instead of devtools.js's
// panel.onShown. Safari doesn't reliably fire onShown or expose the panel
// window to the devtools_page, so the onShown→swiflowStart hook never ran —
// the live dot stayed grey and @State never auto-updated. visibilitychange
// fires in the panel page when its DevTools tab is shown/hidden; if a browser
// never fires it we simply keep polling, which is harmless.
function syncPollingToVisibility() {
  if (document.visibilityState === "hidden") {
    swiflowStop();
  } else {
    swiflowStart();
  }
}
document.addEventListener("visibilitychange", syncPollingToVisibility);
syncPollingToVisibility(); // panel is visible on load → start immediately
