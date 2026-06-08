# Swiflow DevTools — Safari port: spec & Xcode handoff

**Goal:** ship the existing Chrome DevTools panel (`../chrome`) as a **Safari Web
Inspector Extension**, 1:1 in features, distributed as a **Developer-ID-signed,
notarized macOS app** so teammates can run it without "Allow Unsigned
Extensions."

**Status of this scaffold:** everything that does *not* require Xcode.app is
done (sources, manifest, scripts, docs). The Xcode-bound steps — convert,
build, create the Developer ID cert, archive, notarize — are scripted and
enumerated below for you to finish (e.g. via Claude Code inside Xcode).

---

## Why this is even possible

Safari **16+** supports *Web Inspector Extensions*, built with the same
JavaScript APIs as DevTools extensions in other browsers. Every API the panel
relies on is supported, so **the panel JS is unchanged across browsers**:

| API used by the panel | File | Safari 16+ |
|---|---|---|
| `devtools.panels.create` + `onShown`/`onHidden` | `devtools.js` | ✅ |
| `devtools.inspectedWindow.eval` | `panel.js` | ✅ |
| `devtools.network.onNavigated` | `panel.js` | ✅ |
| `chrome.*` namespace alias | both | ✅ (Safari also exposes `browser.*`) |

A DevTools panel only exists in **macOS** Safari's Web Inspector — iOS Safari
has no extension-panel surface — so the wrapper is **macOS-only**
(`--macos-only`).

---

## Architecture

Single source of truth; only the manifest diverges.

```
devtools/
├── chrome/                     ← Chrome extension (source of truth for panel logic)
│   ├── panel.js / panel.html      ─┐
│   ├── devtools.js / devtools.html │  shared verbatim, copied by sync.sh
│   ├── colors.css                  │
│   ├── design_system_tokens.css    │
│   └── application_tokens.css      ─┘
└── safari/                     ← THIS port
    ├── manifest.safari.json    ← the ONLY hand-maintained Safari source
    ├── sync.sh                 ← assembles ./extension from ../chrome + the manifest
    ├── convert.sh              ← safari-web-extension-converter → ./SwiflowDevTools (Xcode project)
    ├── notarize.sh             ← codesign + notarytool + staple (template)
    ├── extension/              ← (gitignored) staging dir the converter consumes
    └── SwiflowDevTools/        ← (gitignored) generated Xcode project
```

### Manifest delta (Chrome → Safari)

`manifest.safari.json` drops three Chrome-only things and keeps the rest:

| Removed | Why |
|---|---|
| `side_panel` + `"sidePanel"` permission | Chrome-only API; no Safari equivalent. The panel's primary surface is the DevTools tab anyway. |
| `"webNavigation"` permission | Unused — `devtools.network.onNavigated` needs no permission. Keeping it would trigger a needless Safari host-permission prompt. |
| `minimum_chrome_version` | Meaningless to Safari. |

Kept: `manifest_version: 3`, `name`, `version`, `description`, `devtools_page`.

### Theming note (non-blocking)

The panel imports Chromium's design-system token CSS (`design_system_tokens.css`
+ `colors.css`). These are **self-contained** (no `chrome://` refs), so they
render fine inside Safari's Web Inspector — the panel just looks
Chrome-DevTools-flavored rather than matching Safari's inspector chrome. Cosmetic
only; re-theme later if desired.

---

## Prerequisites (check before the signed path)

On this machine right now:

| Need | For | State | Action |
|---|---|---|---|
| Xcode.app (full) | converter + build/sign | ✅ Xcode 26.5 at `/Applications/Xcode.app` | — (scripts pin `DEVELOPER_DIR`; or `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`) |
| **Developer ID Application cert** | non-App-Store signing | ❌ `security find-identity -v -p codesigning` → 0 | **Create it:** Xcode → Settings → Accounts → (your team) → Manage Certificates → ＋ → *Developer ID Application* |
| notarytool credentials | notarization | ⚠️ binary present, no profile | `xcrun notarytool store-credentials swiflow-notary --apple-id … --team-id … --password <app-specific>` |

> Signing into Xcode with your Apple ID does **not** create a Developer ID cert
> automatically — that's the one explicit manual step left.

---

## Finish in Xcode

```bash
cd devtools/safari

# 1. Assemble the staging dir (already run once; re-run after editing ../chrome/panel.*)
./sync.sh

# 2. Generate the Xcode project (uses Xcode.app even if xcode-select points at CLT)
./convert.sh
#    → open "SwiflowDevTools/Swiflow DevTools/Swiflow DevTools.xcodeproj"
```

In Xcode:

3. The project has two targets: **`Swiflow DevTools`** (the macOS app) and
   **`Swiflow DevTools Extension`** (the appex). For **each**: Signing &
   Capabilities → set your **Team** → enable **Automatically manage signing**
   (gives you an *Apple Development* cert for local runs).
4. **Build & Run (⌘R)** once. The wrapper app launches; click its "Open Safari
   Settings" (or open Safari → Settings → Extensions) and **enable Swiflow
   DevTools**. For an unsigned local run you may need Safari → Develop →
   **Allow Unsigned Extensions** (resets each Safari restart).
5. Smoke-test (below).

For the **signed / notarized** deliverable:

6. Create the **Developer ID Application** cert (see Prerequisites).
7. Product → **Archive** → Distribute App → **Developer ID** → export the `.app`
   (or run `notarize.sh` against a Release build):
   ```bash
   APP_PATH="…/Swiflow DevTools.app" \
   SIGN_ID="Developer ID Application: <you> (TEAMID)" \
   NOTARY_PROFILE="swiflow-notary" \
   ./notarize.sh
   ```
8. Ship the stapled `.app`. Each teammate launches it once to register the
   extension, then enables it in Safari → Settings → Extensions — **no** unsigned
   toggle needed.

---

## Smoke-test checklist (mirror of the Chrome README)

1. [ ] App launches; "Swiflow DevTools" appears in Safari → Settings → Extensions, enabled.
2. [ ] `cd examples/MiniRouter && swiflow dev` (port 3001).
3. [ ] Open `http://127.0.0.1:3001` in Safari → open Web Inspector (⌥⌘I) → **Swiflow** tab.
4. [ ] The tree populates (auto-polls within ~250 ms); root component at top.
5. [ ] Click a component → its `@State` shows in the right pane.
6. [ ] Footer shows `Selector / Renders / LastPatch / LastRenderMs`; live dot is green.
7. [ ] Navigate to `about:blank` → red "No Swiflow runtime detected …"; navigate back → clears.

---

## Known differences / limitations vs. Chrome

- **No side panel** — DevTools-tab surface only (Safari has no `side_panel`).
- **Theming** — Chrome-DevTools-styled, not Safari-inspector-styled (cosmetic).
- **Distribution** — must ship a notarized `.app`; there is no "Load unpacked."
- Inherits all Chrome-MVP limits: read-only (no `@State` editing), no DOM
  overlay / component picker, no per-row change highlight.

## Open decisions for whoever finishes this

- **Bundle identifier:** scripts default to `com.swiflow.devtools`. Change via
  `BUNDLE_ID=… ./convert.sh` if you want it under your team's reverse-DNS.
- **Icons:** none yet (the Chrome MVP shipped none). The converter generates
  placeholders; add real app/extension icons before sharing widely.
- **Commit policy:** `extension/` and `SwiflowDevTools/` are gitignored as build
  artifacts. If you'd rather vendor the generated Xcode project, drop those lines
  from `.gitignore`.
