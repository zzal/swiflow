# Swiflow Phase 13b — Browser Debugging Story

## Goal

Give a Swiflow developer two things when something goes wrong in the browser:

1. **An immediate, visible signal** — a red error overlay (+ `console.error`) that names the problem and explains the app is frozen, rather than a silent DOM freeze.
2. **Swift source locations in stack traces** — via the Chrome C/C++ DevTools Extension reading the DWARF already embedded in `App.wasm` by `swiflow dev`.

No Swift changes. No new build flags. The DWARF embedding (`--debug-info-format dwarf`) is already in place. This phase is entirely in the JS driver and documentation.

---

## Section 1 — Architecture

### What already exists

- `swiflow dev` passes `--debug-info-format dwarf` to `swift package js` → DWARF debug symbols are embedded in every dev-mode `App.wasm`.
- The driver already gates dev-mode behaviour on `window.SWIFLOW_DEV`.
- `js-driver/swiflow-driver.js` is the single source of truth; `Sources/SwiflowCLI/EmbeddedDriver.swift` is the embedded mirror (must stay bit-for-bit identical).

### What this phase adds

All changes live inside the existing `if (window.SWIFLOW_DEV)` block in `swiflow-driver.js`, executed before `connect()`. Three additions, in order:

| # | Addition | Purpose |
|---|---|---|
| 1 | Extension guidance `console.log` | Tells the developer to install the Chrome extension on first page load |
| 2 | `window.__swiflowDevError(e)` function | Renders `console.error` + overlay when a WASM error is caught |
| 3 | `requestAnimationFrame` shim | Wraps every RAF callback in try/catch; calls `__swiflowDevError` on failure |

Production builds (`window.SWIFLOW_DEV` absent or falsy) are completely unaffected.

---

## Section 2 — JS Driver Changes

### 2a. Extension guidance log

Printed once at page load, before `connect()`:

```js
console.log(
  "[swiflow dev] For Swift source locations in stack traces,\n" +
  "install the Chrome C/C++ DevTools Extension:\n" +
  "  https://goo.gle/wasm-debugging-extension\n" +
  "Then: DevTools → Settings → Experiments → enable \"WebAssembly Debugging: Enable DWARF support\""
);
```

### 2b. `window.__swiflowDevError(e)`

Called by the RAF shim whenever a WASM render error escapes. Two effects:

**Console** — emits a `console.error` with a clear header so the developer knows the app is frozen, followed by the raw error stack. When the Chrome extension is installed the WASM addresses in the stack become `Renderer.swift:148`-style references.

```js
console.error(
  "[swiflow] render error — WASM execution stopped.\n" +
  "Reload the page to recover.\n\n" +
  (e && e.stack ? e.stack : String(e))
);
```

**Overlay** — injects a full-viewport div over the page:

- Dark translucent background (`rgba(0,0,0,0.85)`), monospace font.
- Red bold title: `⚠ Swiflow render error — WASM execution stopped`.
- The error stack (pre-formatted).
- A line: `"Install the Chrome C/C++ DevTools Extension to see Swift file:line above."` followed by the extension link as an `<a>` tag.
- A dismiss button labelled `"Dismiss (app is frozen — reload to continue)"` that removes the overlay from the DOM.
- If `__swiflowDevError` is called again (e.g. multiple RAF ticks before the user acts), the existing overlay is replaced, not stacked.

```js
window.__swiflowDevError = function(e) {
  console.error(
    "[swiflow] render error — WASM execution stopped.\n" +
    "Reload the page to recover.\n\n" +
    (e && e.stack ? e.stack : String(e))
  );

  var existing = document.getElementById("__swiflow-error-overlay");
  if (existing) existing.remove();

  var overlay = document.createElement("div");
  overlay.id = "__swiflow-error-overlay";
  overlay.style.cssText =
    "position:fixed;inset:0;z-index:999999;background:rgba(0,0,0,0.85);" +
    "color:#fff;font-family:monospace;font-size:14px;padding:24px;" +
    "overflow:auto;white-space:pre-wrap;word-break:break-word;";

  var title = document.createElement("div");
  title.style.cssText =
    "font-size:18px;font-weight:bold;margin-bottom:16px;color:#ff6b6b;";
  title.textContent = "⚠ Swiflow render error — WASM execution stopped";

  var msg = document.createElement("pre");
  msg.style.cssText = "margin:0 0 16px;";
  msg.textContent = e && e.stack ? e.stack : String(e);

  var hint = document.createElement("div");
  hint.style.cssText = "color:#aaa;font-size:12px;margin-bottom:4px;";
  hint.textContent =
    "Install the Chrome C/C++ DevTools Extension to see Swift file:line in the stack above:";

  var link = document.createElement("a");
  link.href = "https://goo.gle/wasm-debugging-extension";
  link.target = "_blank";
  link.style.cssText = "color:#4dabf7;font-size:12px;display:block;margin-bottom:16px;";
  link.textContent = "https://goo.gle/wasm-debugging-extension";

  var dismiss = document.createElement("button");
  dismiss.style.cssText =
    "padding:8px 16px;background:#444;color:#fff;border:none;" +
    "cursor:pointer;font-size:14px;border-radius:4px;";
  dismiss.textContent = "Dismiss (app is frozen — reload to continue)";
  dismiss.onclick = function() { overlay.remove(); };

  overlay.appendChild(title);
  overlay.appendChild(msg);
  overlay.appendChild(hint);
  overlay.appendChild(link);
  overlay.appendChild(dismiss);
  document.body.appendChild(overlay);
};
```

### 2c. `requestAnimationFrame` shim

Installed immediately after `__swiflowDevError` is defined, before `connect()`. Wraps the global `requestAnimationFrame` so every RAF callback — including SwiftWasm's render loop — runs inside a try/catch:

```js
var _raf = window.requestAnimationFrame.bind(window);
window.requestAnimationFrame = function(cb) {
  return _raf(function(t) {
    try { cb(t); }
    catch(e) { window.__swiflowDevError(e); }
  });
};
```

`window.requestAnimationFrame.bind(window)` preserves the `this` binding before the patch (consistent with the `performance.now()` fix already shipped in Phase 13b's hotfix commit).

The shim runs inside the driver IIFE, before the WASM module is imported, so SwiftWasm's `scheduleRAFIfNeeded()` sees the patched version. Callbacks from other JS on the page (if any) also get the try/catch wrapper, which is acceptable in a dev-only code path.

### 2d. Updated `if (window.SWIFLOW_DEV)` block structure

```js
if (window.SWIFLOW_DEV) {
  // 1. Extension guidance
  console.log(/* ... */);

  // 2. Error handler
  window.__swiflowDevError = function(e) { /* ... */ };

  // 3. RAF shim
  var _raf = window.requestAnimationFrame.bind(window);
  window.requestAnimationFrame = function(cb) { /* ... */ };

  // 4. WebSocket reconnect loop (existing — unchanged)
  let reconnectDelay = 250;
  const maxDelay = 5000;
  function connect() { /* ... */ }
  connect();
}
```

### 2e. EmbeddedDriver sync

Every change to `js-driver/swiflow-driver.js` is mirrored verbatim in `Sources/SwiflowCLI/EmbeddedDriver.swift` (the `javascriptSource` static string). The existing test `"Init writes the embedded driver verbatim to swiflow-driver.js"` enforces this and will fail if they diverge.

---

## Section 3 — Documentation

### New file: `docs/guides/debugging.md`

Six sections:

**1. What `swiflow dev` gives you by default**
Every dev build passes `--debug-info-format dwarf`, embedding DWARF debug symbols in `App.wasm`. No extra flags needed. Release builds (`swiflow build`) strip debug info for smaller bundles.

**2. Installing the Chrome C/C++ DevTools Extension**
Link to `https://goo.gle/wasm-debugging-extension`. After installing: DevTools → Settings (⚙) → Experiments → enable "WebAssembly Debugging: Enable DWARF support" → reload DevTools. One-time setup per browser profile.

**3. Reading the error overlay**
When a render error occurs, a red overlay appears. The app is frozen — the RAF render loop has died and `@State` changes will no longer reach the DOM. The dismiss button hides the overlay but does not recover the app; reload is required. The stack trace in the overlay shows WASM addresses without the extension; with it, addresses resolve to Swift file:line references.

**4. Setting breakpoints**
DevTools → Sources → open the file tree on the left → look for your `.swift` source files (they appear under a `wasm://` or file-path entry once the extension resolves them). Click a line number to set a breakpoint. Execution pauses in Swift source on the next render or event handler call.

**5. Dev vs release**
`swiflow dev` → DWARF embedded → full debugger support, larger `.wasm`.
`swiflow build` → no debug info → smaller bundle, WASM-address-only traces.
Never serve a dev build in production.

**6. Firefox note**
The DWARF extension is Chrome-only. Firefox's WASM debugger shows the WAT (WebAssembly text format) disassembly rather than Swift source. For Swift-level debugging, use Chrome.

### README update

One line added under the "Dev server" section:
```
See [docs/guides/debugging.md](docs/guides/debugging.md) for Chrome debugger + Swift source breakpoints.
```

---

## Section 4 — File Map

| File | Change |
|---|---|
| `js-driver/swiflow-driver.js` | Add extension log, `__swiflowDevError`, RAF shim inside `if (window.SWIFLOW_DEV)` |
| `Sources/SwiflowCLI/EmbeddedDriver.swift` | Mirror the driver changes verbatim |
| `docs/guides/debugging.md` | New file — six-section debugging guide |
| `README.md` | One-line link to debugging guide under dev-server section |

No changes to `Package.swift`, Swift sources, or build flags.

---

## Section 5 — Testing

The existing end-to-end test `"swiflow init + swiflow dev serves the page and reloads on file change"` validates the dev server pipeline. No new automated tests are required for this phase: the overlay and RAF shim are visual/runtime behaviour that only activates on a thrown exception, which doesn't arise in the headless test harness.

Manual verification steps:
1. `swiflow init demo && cd demo && swiflow dev`
2. Introduce a deliberate error (e.g. temporarily revert the `performance.now()` fix)
3. Confirm the console guidance log appears at page load
4. Confirm the red overlay appears after the first click (when the RAF fires)
5. Confirm the dismiss button works
6. Confirm installing the Chrome extension causes the stack trace to show Swift file:line references

---

## Section 6 — Design Decisions

| Question | Decision |
|---|---|
| Where to catch WASM errors | RAF shim in JS driver — catches the exact failure mode (async render loop), zero Swift changes |
| Overlay vs console-only | Both — overlay is visible without DevTools open; console entry is where the extension translates addresses |
| Overlay dismiss behaviour | Dismisses overlay; app stays frozen; reload is the explicit recovery path |
| Production impact | None — all new code is gated on `window.SWIFLOW_DEV` |
| `requestAnimationFrame` patch scope | Intentionally global — dev mode only, acceptable tradeoff; catches future WASM RAF errors automatically |
| Firefox | Documented as unsupported for Swift-level debugging; no code changes for Firefox |
| New Swift changes | None — DWARF already embedded, error surfacing is pure JS |
