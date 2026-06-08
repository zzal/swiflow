# Safari DevTools Web Extension — Design

**Date:** 2026-06-08
**Status:** Approved (design); implementation pending
**Author:** Swiflow team (with Claude)

## Summary

Port the existing Chrome DevTools panel (`devtools/chrome/`) to a **Safari
web extension** that can be loaded as a *temporary / unsigned* extension for
local development — the closest Safari equivalent to Chrome's "Load unpacked".
macOS-only. No notarization, no distribution, no App Store.

This replaces an earlier, heavier scaffold (commit `2e9b3d1`, reverted in
`e6523ed`) that bundled notarization, a `convert.sh`/`SPEC.md` distribution
handoff, and extra docs. We keep only the dev-loop pieces.

## Background & key facts

- **The panel uses standard WebExtension DevTools APIs**, not Safari's
  proprietary Web Inspector Extension API (WWDC22). Specifically it uses only:
  - `chrome.devtools.panels.create` (in `devtools.js`)
  - `chrome.devtools.inspectedWindow.eval` (in `panel.js`)
  - `chrome.devtools.network.onNavigated` (in `panel.js`)
- All three are supported in **Safari 16.4+** via the `devtools_page` manifest
  key. The dev machine runs macOS 26.5 / Safari 26.5, so support is present.
- Safari aliases the `chrome.*` namespace to `browser.*`, so the panel JS
  needs **zero changes**.
- The real JS uses **no** `webNavigation` and **no** `sidePanel`/`tabs` APIs
  (navigation refresh is `devtools.network.onNavigated`, which needs no
  permission). So the Safari manifest needs **zero permissions**.
- **Safari has no Chrome-style "Load unpacked".** Even a temporary/unsigned
  web extension must be wrapped in an Xcode app produced by
  `safari-web-extension-converter`, built, and run, with
  **Develop → Allow Unsigned Extensions** enabled. Notarization is required
  only for *distribution*, which is out of scope.
- **The converter ships only with full Xcode.app**, not the Command Line
  Tools. The dev machine currently has only Command Line Tools
  (`/Library/Developer/CommandLineTools`), so the convert+build step is
  deferred until Xcode is installed. Scaffolding itself needs no Xcode.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Platform | macOS only (`--macos-only`) | A DevTools panel only renders in macOS Web Inspector; iOS adds no value. |
| Workflow now | Scaffold now, defer Xcode | Manifest + build script + docs need no Xcode; convert+build is a documented manual step. |
| Source sharing | Single source of truth in `chrome/` | A build script assembles a staging dir from `../chrome`; Safari manifest is the only diverging file. Avoids drift. |
| Distribution | Out of scope | "Simpler path" — dev loop only. No notarization. |

## Directory layout — `devtools/safari/`

| File | Role | Tracked in git? |
|------|------|-----------------|
| `manifest.json` | Safari manifest, the only file that differs from Chrome. 5 keys only: `manifest_version: 3`, `name`, `version`, `description`, `devtools_page: "devtools.html"`. **No `permissions`.** | Yes — source of truth |
| `build.sh` | Assemble staging + (optionally) run the converter. See below. | Yes |
| `README.md` | End-user dev install/use workflow. | Yes |
| `.gitignore` | Ignore the `extension/` staging dir, the generated Xcode project, and `.DS_Store`. | Yes |

Also: **delete the stray `devtools/safari/.DS_Store`** currently present.

## `build.sh` behavior

1. **Assemble staging** into `devtools/safari/extension/` (gitignored):
   - Copy these 7 shared files **verbatim** from `../chrome`, erroring loudly
     if any is missing:
     `devtools.html`, `devtools.js`, `panel.html`, `panel.js`, `colors.css`,
     `design_system_tokens.css`, `application_tokens.css`.
   - Copy `devtools/safari/manifest.json` into `extension/manifest.json`.
2. **Convert (if Xcode available):** detect via
   `xcrun --find safari-web-extension-converter`.
   - If found, run:
     ```
     xcrun safari-web-extension-converter ./extension \
       --macos-only --app-name "Swiflow DevTools" \
       --bundle-identifier dev.swiflow.devtools --no-prompt --force
     ```
   - If not found, print the exact command above plus an Xcode-install hint
     (`install full Xcode.app, then sudo xcode-select -s /Applications/Xcode.app`)
     and exit 0 — the staging dir is still valid output.
3. `set -euo pipefail`; resolve paths relative to the script's own location so
   it works from any CWD.

## Dev workflow (documented in README.md)

1. Install full Xcode.app → `sudo xcode-select -s /Applications/Xcode.app`.
2. `cd devtools/safari && ./build.sh` → generates and opens the Xcode project.
3. In Xcode, for **both** the app and extension targets: Signing &
   Capabilities → **Sign to Run Locally** (Team: None).
4. Safari → **Develop → Allow Unsigned Extensions** (re-enable per Safari
   launch).
5. Build & Run the app in Xcode → enable **Swiflow DevTools** in Safari
   Settings → Extensions.
6. Open a Swiflow dev app (e.g. `cd examples/MiniRouter && swiflow dev`) →
   open Web Inspector (⌥⌘I) → click the **Swiflow** tab.

## Out of scope (YAGNI)

- Notarization / Developer ID signing / App Store distribution.
- iOS target.
- Separate `convert.sh` + `SPEC.md` distribution handoff (folded into
  `build.sh` + `README.md`).
- Signing automation beyond documenting "Sign to Run Locally".
- Auto-deriving `name`/`version`/`description` from the Chrome manifest — the
  Safari `manifest.json` mirrors them statically; README notes to bump
  together.

## Verification

Achievable now (no Xcode):
- `build.sh` assembles `extension/` with all 8 files.
- `extension/manifest.json` is valid JSON with the 5 expected keys and no
  `permissions`.
- The 7 synced files are **byte-identical** to their `chrome/` counterparts
  (e.g. `diff` / `cmp`).

Manual, deferred to the user after installing Xcode (documented, not executed
here):
- Converter generates a well-formed macOS project.
- Extension builds, loads in Safari, and the **Swiflow** Web Inspector tab
  shows the live component tree + `@State` against a running Swiflow dev app.
