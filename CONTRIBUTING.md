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

## Workflow

- Fork; create a topic branch.
- Keep commits small and focused; conventional commit prefixes are appreciated
  (`feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`).
- Open a pull request against `main`. CI must pass on macOS and Linux.

## License

By contributing, you agree your contribution will be licensed under the
Apache License, Version 2.0 (see [LICENSE](LICENSE)).
