# RouterDemo

A Swiflow project demonstrating client-side routing with `SwiflowRouter`.

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

- The router renders the `/` route from `Sources/App/App.swift`.
- Navigating to `/about` or `/users/:id` swaps the page content via
  the `Route` declarations.
