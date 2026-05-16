# Swiflow

A Vite-inspired developer ecosystem for Swift on the web.

Swiflow batches all DOM mutations from a Swift-WASM render cycle into a single
patch list and ships them across the JS bridge in one leap — making
Swift-on-the-web fast and frictionless.

**Status:** Phase 1 (the VDOM "Brain") is complete. The `Swiflow` Swift
package compiles and tests on macOS and Linux with no WASM toolchain required.
Phase 2 (the `swiflow` CLI, dev server, and JS driver) is in progress.

## What's in Phase 1?

- `VNode` — a tagged-enum virtual DOM with element / text / rawHTML cases.
- `Patch` — 16 mutation opcodes the (future) JS driver will execute.
- A hybrid diff engine — index-pair for unkeyed children, two-pointer + Map +
  LIS for keyed children (minimal-move output).
- A `@resultBuilder`-based DSL with lowercase free-function elements:
  ```swift
  let view = div(.class("container")) {
      h1("Hello, Swiflow!")
      ul {
          for item in items {
              li(.key(item.id)) { p(item.text) }
          }
      }
  }
  ```
- An XSS-safe `rawHTML(_:)` escape hatch (search `rg "rawHTML\("` to audit
  every use).

## Quick start

```bash
swift test
```

All Phase 1 functionality is exercised by the `SwiflowTests` target — 103
tests across 20 suites.

## Architecture

See [docs/brainstorm/](docs/brainstorm/) for the original design exploration
and [docs/superpowers/plans/](docs/superpowers/plans/) for the Phase 1
implementation plan that produced this code.

## License

Apache 2.0. See [LICENSE](LICENSE).
