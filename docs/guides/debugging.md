# Debugging Swiflow Apps in the Browser

`swiflow dev` embeds DWARF debug symbols in every `App.wasm` build
(`--debug-info-format dwarf` is passed automatically). This enables the
Chrome C/C++ DevTools Extension to map WASM addresses back to Swift source
file and line numbers.

---

## 1. What you get by default

Every `swiflow dev` build:

- Passes `--debug-info-format dwarf` to `swift package js`.
- Embeds DWARF symbols directly in `App.wasm` — no extra flags or steps.
- Injects `window.SWIFLOW_DEV = true` via the dev server's served HTML, which
  activates the error overlay and RAF error shim in the JS driver.

`swiflow build` (release) strips debug info for a smaller bundle. Never serve a
dev build in production.

---

## 2. Install the Chrome C/C++ DevTools Extension

The extension reads DWARF from the WASM binary and translates addresses to
source locations inside Chrome DevTools.

1. Install from: **<https://goo.gle/wasm-debugging-extension>**
2. Reload DevTools (`F12` or `Cmd+Option+I`) after installing — DWARF support
   activates automatically.

This is a one-time setup per browser profile.

---

## 3. Reading the error overlay

When a render error occurs (a WASM→JS call fails during the RAF render loop),
the JS driver catches it and shows a full-viewport red overlay:

- **Title:** `⚠ Swiflow render error — WASM execution stopped`
- **Body:** the raw error stack trace. With the extension installed, WASM
  addresses resolve to `Renderer.swift:148`-style references.
- **Link:** direct link to the extension install page.
- **Dismiss button:** removes the overlay from the DOM. The app remains frozen
  — the RAF render loop has died and `@State` changes will no longer reach the
  DOM. **Reload the page** to recover.

The same error is also emitted to `console.error` so it appears in the DevTools
Console tab alongside the source-resolved stack trace.

### Compile-error overlay (dev loop)

There is a second, distinct overlay: when a save triggers a rebuild that FAILS
to compile, `swiflow dev` pushes the compiler diagnostics to the browser as a
dismissable overlay (Vite-style), anchored at the first `error:` line. The
page keeps rendering the last-good build behind it, and the overlay clears
itself on the next successful hot-swap. Unlike the render-error overlay above,
nothing has crashed — fix the code and save.

---

## 4. Setting breakpoints in Swift source

Once the extension is installed:

1. Open DevTools → **Sources** tab.
2. In the file tree on the left, expand the `wasm://` entry (or a local file
   path entry if the extension resolved the source root).
3. Your `.swift` source files appear listed by path. Open the file you want.
4. Click a line number to set a breakpoint.
5. The next time that line executes — during an event handler or a render
   triggered by `@State` — DevTools pauses execution and shows local variables
   in the Scope panel.

> **Tip:** Swift variables are represented as their underlying WASM values.
> Integers and booleans are readable directly. Strings appear as WASM memory
> pointers — inspect them via the Memory Inspector panel (right-click a value
> in the Scope panel → "Reveal in Memory Inspector").

---

## 5. Dev build vs release build

| | `swiflow dev` | `swiflow build` |
|---|---|---|
| DWARF symbols | ✅ embedded | ❌ stripped |
| Error overlay | ✅ active | ❌ absent |
| Extension stack traces | ✅ Swift file:line | ❌ WASM addresses only |
| Bundle size | Larger | Smaller |
| Use in production | ❌ Never | ✅ Yes |

---

## 6. Firefox

The DWARF extension is Chrome-only. Firefox's built-in WASM debugger shows the
WAT (WebAssembly Text Format) disassembly rather than Swift source. For
Swift-level source debugging, use Chrome.
