# Swiflow Hello World

A hand-crafted demo proving the Phase 2a renderer + JS driver round-trip
works in a real browser. **No CLI required** — Phase 2b's `swiflow init`
will automate this.

## Prerequisites

- Swift 6.0+ with the WebAssembly SDK installed. Pick the URL matching your
  Swift version from <https://swift.org/install>:
  ```bash
  swift sdk install <SDK URL for your Swift version>
  ```
- Any static HTTP server: `python3 -m http.server` is fine.

## Build

The build is driven by JavaScriptKit 0.53's PackageToJS plugin, which
compiles the WASM module **and** emits the JS bootstrap (WASI shim + Swift
runtime + import object wiring) in one step.

### macOS: pin the WASM-aware toolchain

The Xcode-default `swift` invokes the system clang, which has no WASM
backend and fails with `No available targets are compatible with triple
'wasm32-unknown-wasip1'`. Point at the Swift.org toolchain instead:

```bash
# Find the bundle identifier of your installed swift.org toolchain.
TOOLCHAIN_ID=$(plutil -extract CFBundleIdentifier raw \
  ~/Library/Developer/Toolchains/swift-latest.xctoolchain/Info.plist)
export TOOLCHAINS=$TOOLCHAIN_ID
```

Linux users skip this step — the distribution's `swift` already finds the
right clang.

### Build via PackageToJS

```bash
cd examples/HelloWorld

# Replace `swift-6.3-RELEASE_wasm` with whatever your `swift sdk list`
# reports for the installed WASM SDK.
swift package --swift-sdk swift-6.3-RELEASE_wasm js --product App -c release
```

Output lands at `.build/plugins/PackageToJS/outputs/Package/index.js` and
`.build/plugins/PackageToJS/outputs/Package/App.wasm`. `index.html`
imports the bootstrap from that relative path — do not move either file.

> **First build is slow** (~3–5 min). The transitive `swift-syntax`
> dependency JavaScriptKit pulls in for its macros has to compile from
> source. Incremental and debug builds (drop `-c release`) take seconds.

## Serve

Serve from the example root (so the relative `.build/...` path resolves):

```bash
python3 -m http.server 3000
```

## Verify

Open <http://localhost:3000> in a browser. You should see:

- A heading: **Hello, Swiflow!**
- A paragraph: **Count: 0**
- A button: **Increment**

Click the button. The count should increment with each click.

If it doesn't:

- Open DevTools console. Errors from `swiflow-driver: unknown opcode` mean
  a Swift-side `PatchSerializer.encode` mismatch with the driver's `switch`.
- Errors from `swiflow-driver: mount target '#app' not found` mean the
  driver script loaded BEFORE the `<div id="app">` exists; check the script
  ordering in `index.html`.
- Errors mentioning `__swiflowDispatch is not a function` mean the WASM
  module hasn't initialized yet (or threw during startup). Look further up
  the console for the actual exception.
- `Failed to fetch dynamically imported module: .../index.js` means the
  PackageToJS plugin hasn't been run yet (or you're serving from the
  wrong directory). Re-run the `swift package ... js` command above.

## What's next

Phase 2b will replace these manual steps with `swiflow init demo` +
`swiflow build`. Phase 2c will add `swiflow dev` with live reload.
