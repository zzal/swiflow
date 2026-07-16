# Contributing to Swiflow

Thank you for considering a contribution.

## Prerequisites

- **Swift 6.3+** (CI pins 6.3.2). Tests use the Swift Testing framework
  (`import Testing`).
- **WebAssembly Swift SDK** matching your toolchain, plus **binaryen**
  (`wasm-opt`) for release builds.
- **Node 20+** if you touch the JS driver or the Playwright suites.

Run `swiflow doctor` to verify the toolchain pieces (`swift`, `wasm-sdk`,
the swift.org `mac-toolchain` on macOS, `wasm-opt`) — it prints an install
hint for anything missing.

## Development

```bash
swift build                            # build all targets (host)
swift test                             # run all Swift tests
swift run swiflow --help               # try the CLI

cd js-driver && npm ci && npm test     # JS driver unit tests (jsdom)
```

End-to-end Playwright suites live in `Tests/playwright`, one config per
example app (`npm run test:counter`, or `npx playwright test
--config=playwright.<demo>.config.ts`). Build the release CLI first
(`swift build -c release --product swiflow`) — the harness scaffolds demos
with it, and a stale binary scaffolds stale code.

## Generated code

Two files in `Sources/SwiflowCLI` are **generated** — never edit them by hand:

- `EmbeddedDriver.swift` — embeds `js-driver/swiflow-driver.js` (the single
  source of truth) and its runtime siblings.
- `EmbeddedTemplates.swift` — embeds the project templates from `examples/`.

After editing any `js-driver/*.js` runtime file **or** anything under
`examples/` that a template ships, regenerate everything:

```bash
swift run swiflow-codegen all
```

This rewrites both embedded files *and* refreshes the runtime-JS copies
tracked inside each example. If you forget, the `embed-freshness` CI job
(and the byte-pin `DriverEmbedderTests` / `TemplateEmbedderTests`) will fail
and tell you exactly this.

Note that CI does **not** compile most example apps. If your change touches
one, build it locally (`swift build --package-path examples/<Name>` for a
host type-check, or `swiflow build --path examples/<Name>` for the real
wasm build) before opening the PR.

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
- Open a pull request against `main`. CI (Linux) must pass: the Swift test
  suite, JS driver tests, the `embed-freshness` gate, and the bundle-size
  budget.
- The Playwright E2E jobs are opt-in (they burn CI minutes): a maintainer adds
  the `run-e2e` label when a PR touches the driver, the service worker, or an
  e2e-covered example. Run the relevant suite locally either way.
- User-facing changes get a bullet under `[Unreleased]` in `CHANGELOG.md`.

## Reporting issues

Before filing, **search existing issues** (including closed ones) — add a
comment or a 👍 to an existing report instead of duplicating it. Keep it to
**one problem per issue**.

### Bug reports must include

- **Versions** — the output of `swiflow --version` and `swift --version`, and
  the Swiflow version your project's `Package.swift` pins (they can differ —
  say both).
- **Environment** — OS and version; for anything rendering in a page, the
  browser and version; whether it happened under `swiflow dev` (HMR) or a
  `swiflow build` output (they take different code paths).
- **Minimal reproduction** — the smallest project and steps that show the
  problem. Starting from a scaffold is ideal: name the template
  (`swiflow init My --template <Name>`) and give the exact edits/steps from
  there. "It breaks in my app" without a repro usually means a round-trip of
  questions before anyone can start.
- **Expected vs. actual** — one line each. What did you expect to happen, and
  what happened instead?
- **Evidence** — the browser DevTools console output (copy the text rather
  than screenshotting it, and include the *first* error, not just the flood
  that follows) and any relevant terminal output from the CLI. Screenshots or
  a short recording help for visual/layout issues.
- **For regressions** — the last version where it worked, if you know it.

### Feature requests

Lead with the **problem or use case**, not the mechanism — what you're trying
to build and where Swiflow gets in the way. An API sketch of how you'd like to
call it is welcome; note any workaround you're using today. Swiflow is pre-1.0
and deliberately small, so requests that fit the existing design
(components + tokens, media-first theming, no per-component branching) have
the best odds.

### Security issues

Do **not** open a public issue for anything security-sensitive (XSS escapes,
sanitizer bypasses, …). Contact the maintainer privately instead — via
GitHub's private vulnerability reporting if the repository's "Security" tab
offers it, otherwise through the contact details on the maintainer's GitHub
profile.

## License

By contributing, you agree your contribution will be licensed under the
Apache License, Version 2.0 (see [LICENSE](LICENSE)).
