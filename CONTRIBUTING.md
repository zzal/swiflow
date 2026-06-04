# Contributing to Swiflow

Thank you for considering a contribution.

## Development

```bash
swift build                            # build all targets
swift test                             # run all tests
swift run swiflow --help               # try the CLI
```

Tests use the Swift Testing framework (`import Testing`), available in Swift
6.0 and later.

## When you change the JS driver

`js-driver/swiflow-driver.js` is the single source of truth. The CLI embeds
its contents via codegen. After editing the driver, regenerate the embedded
copy:

```bash
swift scripts/embed-driver.swift
```

(If you forget, the `DriverEmbedderTests` freshness check will fail in CI
and tell you exactly this command to run.)

## Troubleshooting

**`Internal Error: DecodingError.dataCorrupted: ... Corrupted JSON. Underlying
error: unexpected end of file`** printed several times during `swift build`
(or `swiflow build` / the initial `swiflow dev` build) is **benign Swift 6.3
toolchain noise, not an error in your build.** As long as the build ends with
`Build complete!`, the output is correct.

It comes from macro expansion: each module that expands a macro (`@Component`,
`@MutationState`, …) talks to `swift-plugin-server` over a pipe, and when that
connection closes the compiler does one last JSON read, hits EOF, and logs
this non-fatal line. You'll see roughly one per macro-using module, and none on
a true no-op build. It is not cache corruption — `swift package clean` won't
change it — and there's nothing to fix in Swiflow (macros are core to the
framework). It will most likely disappear on a future toolchain. Don't filter
it out of build logs wholesale, or you'll also hide a genuine internal error if
one ever occurs.

## Workflow

- Fork; create a topic branch.
- Keep commits small and focused; conventional commit prefixes are appreciated
  (`feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`).
- Open a pull request against `main`. CI must pass on macOS and Linux.

## License

By contributing, you agree your contribution will be licensed under the
Apache License, Version 2.0 (see [LICENSE](LICENSE)).
