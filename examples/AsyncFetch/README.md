# AsyncFetch

A Swiflow example demonstrating `.task(rerunOn:)` — Phase 20 async task effects.

## Build

```bash
swiflow build
```

This wraps `swift package js --use-cdn --product App -c release` after
probing for an installed WASM SDK. The output lands at
`.build/plugins/PackageToJS/outputs/Package/`.

## Serve

Any static HTTP server works:

```bash
python3 -m http.server 3000
```

Then open <http://localhost:3000>.

## What you should see

- A heading: **Async fetch demo**
- A paragraph that starts at **Status: idle** for one frame, flips to
  **Status: loading…** as the `.task` fires for `userID = 1`, then after ~400 ms
  shows **Status: loaded user #1**.
- A button: **Load next user** — each click increments `userID` (the `.task`'s
  `rerunOn:` dependency), which cancels the in-flight task and re-runs the effect:
  status goes `loading…` then `loaded user #N`.
