# Debugging Swiflow apps in the browser

Swiflow's dev builds embed DWARF debug symbols inside the produced `.wasm`
binary via PackageToJS's `--debug-info-format dwarf` flag (set automatically
by `swiflow dev` — see [BuildCommand.swift:105](../Sources/SwiflowCLI/Commands/BuildCommand.swift#L105)).
Chrome's C/C++ DevTools extension reads those symbols directly and maps WASM
traps back to Swift source lines.

This avoids the need for separate `.wasm.map` source-map files — the Swift
WASM toolchain doesn't emit them at all. The PackageToJS plugin's only
debug-info control surface is `--debug-info-format {none | dwarf | name}`,
and DWARF embedded in the `.wasm` is the canonical path.

## One-time setup

1. Install the **C/C++ DevTools Support (DWARF)** extension for Chrome:
   <https://chromewebstore.google.com/detail/cc++-devtools-support-dwa/pdcpmagijalfljmkmjngeonclgbbannb>
2. In Chrome, open DevTools → ⚙ Settings → Experiments → enable
   **"WebAssembly Debugging: Enable DWARF support"**.
3. Close and reopen DevTools so the change takes effect.

## Per-app workflow

```bash
swiflow dev   # builds with --debug-info-format dwarf, serves on :3000
```

1. Open the app at <http://localhost:3000> in Chrome.
2. Open DevTools → **Sources** panel.
3. Trigger a trap (e.g. add `fatalError("test trap")` inside your Component's
   `body`) or set a breakpoint inside a Swift source file in the Sources
   panel tree.
4. The stack trace and source view should resolve to Swift filenames and
   line numbers (e.g. `App.swift:42`) rather than raw hex offsets like
   `wasm-function[42]:0x1f3a`.

## Verifying DWARF is embedded

If the stack frames are still showing hex offsets, first confirm the
`.wasm` actually contains DWARF (it should, in dev mode):

```bash
strings .build/plugins/PackageToJS/outputs/Package/App.wasm \
  | grep -E "^\.debug_" | sort -u
```

You should see six custom section names:

```
.debug_abbrev
.debug_info
.debug_line
.debug_loc
.debug_ranges
.debug_str
```

If those are missing, the WASM was built without DWARF — either you ran
`swiflow build` (release mode strips debug info) instead of `swiflow dev`,
or the build cache served a stale stripped binary. Re-run `swiflow dev` to
trigger a fresh debug-mode build.

If the DWARF sections are present but Chrome still shows hex, the extension
is most likely not loaded — check `chrome://extensions` and confirm
"C/C++ DevTools Support (DWARF)" is enabled.

## Limitations

- **Release builds strip DWARF.** When `swiflow build --production` lands
  (deferred to a future phase), it will run `wasm-opt -Os` and strip debug
  info for size. Stack frames in production-mode builds fall back to hex
  offsets — keep DWARF flows for dev only.
- **Closure stepping is limited.** Chrome's C/C++ extension is built for
  C/C++ debug semantics; it doesn't step through Swift's escaping-closure
  control flow as cleanly as native Swift debugging on macOS/Linux. Trap
  resolution and breakpoint placement work well; "step into a `.on("click",
  …)` closure" can land in unexpected frames. File issues against
  Chromium's WebAssembly debugging stack for missing features.
- **No source-maps fallback.** Browsers without the C/C++ extension
  installed cannot read DWARF. Source-map files (`.wasm.map`) would be the
  cross-browser fallback, but the Swift WASM toolchain doesn't emit them —
  installing the Chrome extension is the only path today.

## Background

The DWARF-only debug story was confirmed by a Phase 4 spike on 2026-05-19.
PackageToJS's CLI surface (`swift package js --help`) lists no source-map
output flag, fresh dev-mode builds verifiably contain the six standard
DWARF custom sections, and the official Chrome extension reads them
directly. Adding a `swiflow build --emit-source-maps` CLI flag was
considered and rejected — it would have had nothing in the toolchain to
wire to.
