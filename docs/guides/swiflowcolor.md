# SwiflowColor — programmatic theme generation

`SwiflowColor` is the contrast-validated color library behind `swiflow theme`. It is a
**native-only** Swift library (macOS/Linux host tooling, build plugins, design scripts) — it is
NOT for the browser and is never a dependency of the wasm `SwiflowUI` module.

Add it to a host tool/target:

```swift
.product(name: "SwiflowColor", package: "Swiflow")
```

## Generating a theme

```swift
import SwiflowColor

let result = try ThemeGenerator.generate(
    .init(primary: "#7c3aed", danger: "#e11d48", includeNeutrals: true)
)

if result.isValid {
    try result.css.write(toFile: "theme.css", atomically: true, encoding: .utf8)
} else {
    for failure in result.failures { print(failure) }   // WCAG + advisory APCA per token
}
```

`generate(_:)` throws `ThemeError.invalidHex` only for malformed hex. Contrast shortfalls are
**returned** in `result.failures` (each carries the WCAG ratio + an advisory APCA Lc), never
thrown — the caller decides whether to treat them as fatal (the `swiflow theme` CLI does).

`ThemeOptions` mirrors the CLI flags: `primary` (required), optional `danger`/`success`/
`warning`/`info` status seeds, and `includeNeutrals`.

## Contrast metrics

```swift
let ratio = try Contrast.wcag("#1d4ed8", "#ffffff")              // WCAG 2.x ratio (1…21)
let lc = try Contrast.apca(textHex: "#1d4ed8", bgHex: "#ffffff") // APCA Lc (advisory)
```

Both validate hex and throw `ThemeError.invalidHex` on malformed input.
