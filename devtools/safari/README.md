# Swiflow DevTools (Safari Web Inspector panel)

A Safari port of the Chrome DevTools panel in [`../chrome/`](../chrome/README.md) for
inspecting a running Swiflow app's component tree and `@State` live. Same panel,
same features — wrapped in a macOS app as Safari requires.

> **Building this?** Start with [`SPEC.md`](SPEC.md). It has the architecture,
> prerequisites, and the exact convert → build → sign → notarize steps. This
> README is the end-user install/use guide.

---

## Requirements

- **macOS** with **Safari 16 or newer** (Web Inspector Extensions support).
- The signed app, *or* Xcode to build it yourself (see `SPEC.md`).

A DevTools panel only exists in macOS Safari's Web Inspector — there is no iOS
build.

---

## Install

### From a signed build (teammates)

1. Get the notarized **Swiflow DevTools.app** and launch it once.
2. Safari → Settings → **Extensions** → enable **Swiflow DevTools**.

No "Allow Unsigned Extensions" needed — the app is notarized.

### Building it yourself (developers)

See [`SPEC.md`](SPEC.md). In short:

```bash
cd devtools/safari
./sync.sh        # assemble ./extension from the shared sources in ../chrome
./convert.sh     # generate the Xcode project
open "SwiflowDevTools/Swiflow DevTools/Swiflow DevTools.xcodeproj"
```

Then build & run in Xcode. For an unsigned local run, enable Safari → Develop →
**Allow Unsigned Extensions** (resets when Safari restarts).

---

## Use

1. Run a Swiflow app in dev mode, e.g. `cd examples/MiniRouter && swiflow dev`.
2. Open it in Safari, then open **Web Inspector** (⌥⌘I).
3. Click the **Swiflow** tab in the inspector's tab bar.

The panel auto-loads and live-updates within ~250 ms of each render.

### What it shows

- **Tree pane (left):** every mounted component in document order, depth-indented.
  A `[body→]` suffix marks a component whose body is another component anchor.
- **State pane (right):** click a row to see its `@State` (JSON-friendly
  primitives only — Bool / String / Int / Double / null).
- **Footer:** `Selector | Renders | LastPatch | LastRenderMs` for the selected
  component's root. The live dot is **green** (polling), **grey** (panel hidden),
  or **red** (no Swiflow runtime / page navigated away).
- **Error region:** red banner if `window.__swiflow` is missing — i.e. a
  non-Swiflow page, or a release build with `SWIFLOW_DEV` unset. Run `swiflow dev`,
  not a static release build.

Multi-root apps render one collapsible section per mounted selector.

---

## Limitations (MVP — same as the Chrome panel)

- Read-only: no `@State` editing.
- No DOM overlay / component picker.
- No per-row highlight when a `@State` value changes between polls.
- Panel is Chrome-DevTools-styled, not Safari-inspector-styled (cosmetic).

---

## Troubleshooting

**"Swiflow" tab missing.** Close and reopen Web Inspector. Confirm the extension
is enabled in Safari → Settings → Extensions.

**"No Swiflow runtime detected" but the app is running.** It's likely a release
build. `window.__swiflow` is attached only in dev mode (gated on
`window.SWIFLOW_DEV`). Run `swiflow dev`.

**Extension won't enable / disappears on restart.** Unsigned local builds need
Safari → Develop → **Allow Unsigned Extensions** re-toggled each launch. Use a
notarized build (`SPEC.md`) to avoid this.
