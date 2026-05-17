# Swiflow

A Vite-inspired developer ecosystem for Swift on the web.

Swiflow batches all DOM mutations from a Swift-WASM render cycle into a single
patch list and ships them across the JS bridge in one leap — making
Swift-on-the-web fast and frictionless.

**Status:** Phase 2b complete. The `swiflow` CLI now scaffolds (`init`) and
builds (`build`) projects end-to-end. The dev server (`swiflow dev`) lands
in Phase 2c.

## Quick start

```bash
# 1. Build the CLI.
swift build -c release --product swiflow

# 2. Scaffold a project.
./.build/release/swiflow init my-app --swiflow-source $(pwd)
cd my-app

# 3. Build the WASM bundle.
../.build/release/swiflow build

# 4. Serve.
python3 -m http.server 3000
# Open http://localhost:3000
```

Prerequisites: Swift 6.0+ and a WebAssembly Swift SDK installed via
`swift sdk install`. See <https://swift.org/install> for SDK URLs.

## What's in the box

- **`Swiflow`** — pure-Swift VDOM core: tagged-enum `VNode`, 16-opcode `Patch`,
  hybrid keyed (LIS-based) + indexed children diff, `@resultBuilder` DSL.
- **`SwiflowWeb`** — WASM-only renderer + JavaScriptKit bridge.
- **`swiflow`** — the CLI: `init` scaffolds, `build` wraps `swift package js`
  with the right SDK + toolchain auto-detection.
- **JS driver** — vanilla JS, ~200 lines, embedded into the CLI binary as
  generated Swift code (single source of truth: `js-driver/swiflow-driver.js`).

## Architecture

See [docs/brainstorm/](docs/brainstorm/) for the original design exploration
and [docs/superpowers/plans/](docs/superpowers/plans/) for the per-phase
implementation plans.

## Testing

```bash
swift test
```

Phase 1+2a+2b ships 163 tests across 33 suites (run `swift test`
yourself to confirm). Tests that require the WASM SDK end-to-end are gated
and skip cleanly when it's absent.

## License

Apache 2.0. See [LICENSE](LICENSE).
