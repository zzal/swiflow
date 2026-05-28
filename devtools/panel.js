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

document.getElementById("refresh-btn").addEventListener("click", async () => {
  try {
    const tree = await dataSource.tree();
    renderTree(tree);
  } catch (err) {
    console.error("[Swiflow DevTools]", err.message);
  }
});
