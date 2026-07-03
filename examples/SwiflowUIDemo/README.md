# SwiflowUIDemo

Browser proof-of-concept for the SwiflowUI v0 layout primitives.

## What it shows

- `VStack` / `HStack` with token-var spacing (`.md`, `.lg`, `.xl`)
- `.padding(_:)` postfix modifier that maps to `--sw-space-*` CSS custom properties
- Token-based reskin: overriding `--sw-space-md` in one `:root` rule changes every gap at once

## Run

```bash
swiflow dev --port 3003
```

Open <http://localhost:3003> in a browser.

## Reskin experiment

Open `index.html` and uncomment the `:root` override inside `<style>`:

```css
/* :root { --sw-space-md: 2.5rem } */
```

Reload — every `HStack(spacing: .md)` gap widens instantly, with no Swift recompile needed.
