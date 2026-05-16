# Swiflow

A Vite-inspired developer ecosystem for Swift on the web.

Swiflow batches all DOM mutations from a Swift-WASM render cycle into a single
patch list and ships them across the JS bridge in one leap — making
Swift-on-the-web fast and frictionless.

**Status:** Phase 1 (the VDOM "Brain") is in active development. Phase 2 (the
`swiflow` CLI and JS driver) follows. See [docs/brainstorm/](docs/brainstorm/)
for the original design exploration.

## Quick start (Phase 1 — library only)

```bash
swift test
```

The `Swiflow` Swift package builds and tests on macOS and Linux with no WASM
toolchain required.

## License

Apache 2.0. See [LICENSE](LICENSE).
