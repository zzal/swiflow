# HelloWorld

A Swiflow project — Swift-to-WebAssembly with a Vite-inspired dev loop.

## Build

```bash
swiflow build
```

This wraps `swift package js --use-cdn --product App -c release` after
probing for an installed WASM SDK. The output lands at
`.build/plugins/PackageToJS/outputs/Package/`.

## Serve

Phase 2b doesn't ship a dev server yet (Phase 2c will). Any static HTTP
server works:

```bash
python3 -m http.server 3000
```

Then open <http://localhost:3000>.

## What you should see

- A heading: **Hello, Swiflow!**
- A paragraph: **Count: 0**
- A button: **Increment** that increments the count on each click.
