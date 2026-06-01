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
- A paragraph: **Status: idle** on first load, then immediately **Status: loading…**
  as the `.task` fires for `userID = 1`, then after ~400 ms: **Status: loaded user #1**.
- A button: **Load user 1** (then 2, 3, …) — each click increments `userID`,
  cancels the previous task, and re-runs the effect: status goes `loading…` then
  `loaded user #N`.
