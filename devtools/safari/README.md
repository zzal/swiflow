# Swiflow DevTools (Safari Web Inspector, MVP)

A Safari Web Inspector panel for inspecting a running Swiflow app's
component tree and `@State` live. It is the Chrome DevTools panel
(`../chrome/`) repackaged for Safari — the panel code is shared
verbatim; only the manifest differs (no `side_panel`, no permissions).

**Requires:** macOS, **Safari 16.4+** (for the `devtools_page` API), and
**full Xcode.app** (the converter ships only with Xcode, not the Command
Line Tools).

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
4. Click ↻ Refresh to load the component tree.

The panel auto-refreshes when the inspected page navigates. Everything the
panel shows (tree pane, `@State` pane, footer, live indicator) is
documented in `../chrome/README.md` — the behavior is identical.

---

## Keeping in sync with the Chrome extension

- `../chrome/` is the single source of truth for all panel code.
- `manifest.json` here is the only Safari-specific file. If you bump
  `name`/`version` in `../chrome/manifest.json`, bump them here too.
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

---

## Limitations

- Same MVP limitations as the Chrome panel (read-only, no `@State` editing,
  no DOM overlay) — see `../chrome/README.md`.
- **Unsigned**: for local development only. Distribution (Developer ID
  signing, notarization, App Store) is intentionally out of scope.
- **macOS only**: a DevTools panel only renders in macOS Web Inspector.
