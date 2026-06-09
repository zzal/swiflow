# Swiflow DevTools (Safari Web Inspector, MVP)

A Safari Web Inspector panel for inspecting a running Swiflow app's
component tree and `@State` live. It shares the Chrome DevTools panel's
browser-agnostic **core** (`../chrome/`: UI, rendering, polling) and adds a
Safari-specific **encapsulation** for reading the page — because
`inspectedWindow.eval` crashes Safari's Web Inspector, Safari reads
`window.__swiflow` through a small messaging bridge instead. See
**Architecture** below.

**Requires:** macOS, **Safari 16.4+** (for the `devtools_page` API), and
**full Xcode.app** (the converter ships only with Xcode, not the Command
Line Tools).

---

## Architecture: shared core + per-browser encapsulation

The panel never touches the inspected page directly. A browser-specific
`datasource.js` (loaded before the core `panel.js`) defines a global
`SWIFLOW_DATA_SOURCE` with `tree()`, `state(path)`, `perf()`; the core just
calls it.

- **Common core** (authored in `../chrome/`, copied here by `build.sh`):
  `panel.html`, `panel.js`, `devtools.js`, `panel-icon.svg`, the CSS.
- **Chrome encapsulation** (`../chrome/datasource.js`): reads the page via
  `chrome.devtools.inspectedWindow.eval`.
- **Safari encapsulation** (this dir): `datasource.js` + a messaging bridge,
  because `inspectedWindow.eval` natively crashes Safari's Web Inspector
  (confirmed on Safari 26.5, even for a trivial `1 + 1`).

Safari's request hops down this chain, and the reply returns along it. Each hop
labels its own errors, so a failure message names the exact leg that broke:

```
panel datasource.js  --runtime-->  bridge-sw.js  --tabs-->
bridge-content.js  --postMessage-->  bridge-page.js (MAIN world)  ->  __swiflow
```

---

## Build & load (temporary / unsigned, for development)

Safari has no "Load unpacked" like Chrome. Even an unsigned extension must
be wrapped in a small app, built once in Xcode, and run.

1. Install Xcode.app, then point the toolchain at it:

   ```sh
   sudo xcode-select -s /Applications/Xcode.app
   ```

2. Assemble the extension and generate the Xcode project:

   ```sh
   cd devtools/safari
   ./build.sh
   ```

   `build.sh` copies the shared panel files from `../chrome` into
   `./extension`, then runs `safari-web-extension-converter` to create the
   wrapper project under `./xcode` (and opens it). On later runs it only
   re-syncs `./extension` and skips conversion so your signing survives —
   see "Keeping in sync" below.

3. In Xcode, for **both** targets (the app and the `... Extension` appex):
   **Signing & Capabilities → Signing Certificate → Sign to Run Locally**
   (leave Team set to None).

4. In Safari: **Settings → Advanced →** enable **Show features for web
   developers** (if not already), then **Develop → Allow Unsigned Extensions**.
   (This resets every time Safari relaunches — re-enable it after each launch
   during development.)

5. In Xcode, **Build & Run** (⌘R) the app. Then in Safari:
   **Settings → Extensions** and tick **Swiflow DevTools** to enable it.

---

## Use

1. Open a Swiflow app running in dev mode, e.g.:

   ```sh
   cd examples/MiniRouter && swiflow dev
   ```

2. Open Web Inspector (⌥⌘I).
3. Click the **Swiflow** tab in the Web Inspector tab bar.

The panel populates on its own and the **live dot** turns green — the tree and
`@State` track the app automatically (no need to click Refresh; the button is a
manual pull). The header **slider** sets the live-poll interval (250 ms → 2 s)
and your choice is remembered across reloads.

Everything the panel shows (tree pane, `@State` pane, footer, live indicator) is
documented in `../chrome/README.md` — the behavior is identical.

---

## Keeping in sync with the Chrome extension

- `../chrome/` is the single source of truth for the **core** (UI/logic).
  Edit core files there, never in `./extension`.
- Safari-specific files live **here**: `manifest.json`, `datasource.js`
  (messaging transport), and `bridge-sw.js` / `bridge-content.js` /
  `bridge-page.js`. If you bump `name`/`version` in `../chrome/manifest.json`,
  bump this `manifest.json` too.
- `./extension` and `./xcode` are build artifacts (gitignored). Don't edit
  files in `./extension` directly — edit `../chrome`, then re-run `build.sh`
  and rebuild in Xcode (⌘R).
- After the first build, `./build.sh` re-syncs `./extension` and **skips** the
  converter when the Xcode project already exists, so your manual "Sign to Run
  Locally" settings are preserved. Modes:
  - `./build.sh` — sync, then convert only on the first run (else skip).
  - `./build.sh --sync-only` — sync only; never run the converter.
  - `./build.sh --reconvert` — regenerate the Xcode project (resets signing).
- Re-syncing updates the **contents** of files already in the project. A
  brand-new file (e.g. a new icon) must be added to the Xcode project once —
  drag it into the extension's group, or run `--reconvert`.
- **Reliable reload after a code change** (Safari caches extension code hard):
  1. `./build.sh` (or `--sync-only`) to re-sync `./extension`.
  2. Quit Safari (⌘Q), reopen, re-tick **Develop → Allow Unsigned Extensions**.
  3. In Xcode press **⌘R**, then click **"Quit and Open Safari Extensions
     Preferences…"** in the run dialog.
  The header build stamp (e.g. `v0.1.10`) confirms the new code is live; a stale
  number means Safari is still running the old bundle.

---

## Safari quirks this works around

Hard-won notes (Safari 26.5) so the bridge's shape makes sense:

- **`inspectedWindow.eval` crashes Web Inspector** — natively, even for `1 + 1`,
  with host access granted. The whole messaging bridge exists to avoid it.
- **`devtools.inspectedWindow.tabId` is `-1`** (unusable) — so `bridge-sw.js`
  finds the Swiflow page by probing each tab's content script rather than
  addressing the inspected tab directly.
- **`background.service_worker` won't run** — declared + bundled correctly, but
  Safari never starts it (no "Web Extension Background Content" entry). We use a
  classic background page (`background.scripts`), debuggable under **Develop →
  Web Extension Background Pages**.
- **Async replies need the promise model** — Safari ignores Chrome's
  `sendResponse()` + `return true`; the relays return a Promise from `onMessage`.
- **`panel.onShown` doesn't fire / the panel window isn't exposed** — so polling
  is driven by the panel's own `document.visibilitychange`, not `devtools.js`.
- **MAIN-world access** — content scripts can't see `window.__swiflow` (isolated
  world), so `bridge-content.js` injects `bridge-page.js` (a
  `web_accessible_resource`) into the page's MAIN world to read it.
- **`iconPath` must be a real bundled file** — `panels.create(…, null, …)`
  silently fails in Safari; we pass `panel-icon.svg`.
- **Allow Unsigned Extensions resets** on every Safari relaunch.

---

## Limitations

- Same MVP limitations as the Chrome panel (read-only, no `@State` editing,
  no DOM overlay) — see `../chrome/README.md`.
- **Unsigned**: for local development only. Distribution (Developer ID
  signing, notarization, App Store) is intentionally out of scope.
- **macOS only**: a DevTools panel only renders in macOS Web Inspector.
