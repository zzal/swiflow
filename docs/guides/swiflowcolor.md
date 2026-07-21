# SwiflowColor — programmatic theme generation

`SwiflowColor` is the contrast-validated color library behind `swiflow theme`. It is a
**native-only** Swift library (macOS/Linux host tooling, build plugins, design scripts) — it is
NOT for the browser and is never a dependency of the wasm `SwiflowUI` module.

The flip side of that boundary: **no runtime contrast checking exists**.
Validation happens at *generation* time (`swiflow theme`, the shipped-sheet
tests) — a token you re-point at runtime (`Theme { }`, user CSS overrides)
is trusted as-is. If your app themes dynamically, run the generator or its
validators over every palette you ship rather than expecting the browser
bundle to catch a low-contrast override.

Add it to a host tool/target:

```swift
.product(name: "SwiflowColor", package: "Swiflow")
```

## Generating a theme

```swift
import SwiflowColor

let result = try ThemeGenerator.generate(
    .init(primary: "oklch(0.55 0.22 264)", danger: "#e11d48", includeNeutrals: true)
)

if result.isValid {
    try result.css.write(toFile: "theme.css", atomically: true, encoding: .utf8)
} else {
    for failure in result.failures { print(failure) }   // WCAG + advisory APCA per token
}
```

Colors are **OKLCH-primary**: each seed is an `oklch(L C H)` string *or* hex (`#rgb`/`#rrggbb`) —
OKLCH is the engine's native space, so an `oklch()` seed skips the hex round-trip. `generate(_:)`
throws `ThemeError.invalidColor` / `.invalidHex` only for malformed input; contrast shortfalls are
**returned** in `result.failures` (each carries the WCAG ratio + an advisory APCA Lc), never thrown
— the caller decides whether to treat them as fatal (the `swiflow theme` CLI does).

`ThemeOptions` mirrors the CLI flags: `primary` (required), optional `danger`/`success`/
`warning`/`info` status seeds, and `includeNeutrals`.

## Contrast metrics

```swift
let ratio = try Contrast.wcag("oklch(0.45 0.2 264)", "#ffffff")  // WCAG 2.x ratio (1…21)
let lc = try Contrast.apca(text: "#1d4ed8", bg: "#ffffff")       // APCA Lc (advisory)
```

Both accept `oklch()` or hex (an oklch seed is gamut-clamped to sRGB for the metric) and throw
`ThemeError.invalidColor` / `.invalidHex` on malformed input.
