# Swiflow Hello World

A hand-crafted demo proving the Phase 2a renderer + JS driver round-trip
works in a real browser. **No CLI required** — Phase 2b's `swiflow init`
will automate this.

## Prerequisites

- Swift 6.0+ with the WebAssembly SDK installed:
  ```bash
  swift sdk install <swift.org WASM SDK URL for your Swift version>
  ```
  See <https://swift.org/install> for the current SDK URL.
- Any static HTTP server: Python's `python3 -m http.server` works.

## Build

```bash
cd examples/HelloWorld
swift build --swift-sdk wasm32-unknown-wasi -c release
cp .build/wasm32-unknown-wasi/release/App.wasm public/App.wasm
```

## Serve

```bash
cd public
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

## What's next

Phase 2b will replace these manual steps with `swiflow init demo` +
`swiflow build`. Phase 2c will add `swiflow dev` with live reload.
