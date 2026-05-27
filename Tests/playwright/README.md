# Swiflow Playwright e2e

Browser-based happy-path tests covering the parts of Swiflow that can
only be verified end-to-end: `@State` round-trip through the
Scheduler + RAFScheduler + diff + patch + JS driver, router navigation
in a real browser, the WASM-fetch progress overlay, and the service
worker's cache.

## First-time setup

```bash
cd Tests/playwright
npm install
npx playwright install --with-deps chromium
```

## Running each suite

The default `npm test` runs everything — three webServers come up
(Counter on :3000, RouterDemo on :3001, SW release demo served by
python3 on :3002) and all four specs execute. Cold runs take ~20 min
because the SW release build is expensive (`swiflow build` ships a
full WASM release).

When iterating locally, prefer the per-suite scripts. Each loads a
purpose-built config that spins up only the server its spec needs:

| Command | Spec | Server | Mode | Wall-clock (cold) |
|---|---|---|---|---|
| `npm run test:counter` | `counter.spec.ts` | `swiflow dev` on :3000 (scaffolded Counter demo) | dev | ~1 min |
| `npm run test:router` | `router.spec.ts` | `swiflow dev --port 3001` against `examples/RouterDemo/` | dev | ~1 min |
| `npm run test:sw` | `sw-cache.spec.ts` + `progress.spec.ts` | `python3 -m http.server 3002` against a scaffolded release build | release | ~5 min (release WASM build) |
| `npm test` | all four specs | all three of the above | mixed | ~20 min |

Warm runs of each are much faster: dev-server-backed specs (`test:counter`,
`test:router`) skip rebuilding because SwiftPM caches per-target;
`test:sw` re-runs `swiflow build` on every invocation (it scaffolds a
fresh temp project each session) so it remains expensive.

## Direct invocation

Each script just calls `playwright test --config=<file>`. Useful when
filtering further:

```bash
# A single test inside a suite
npx playwright test --config=playwright.router.config.ts -g "Back button"

# Open Playwright's debug UI on a single suite
npx playwright test --config=playwright.counter.config.ts --ui
```

## What each spec covers

- **`counter.spec.ts`** — `@State` mutation round-trip via the
  Increment button. Rapid clicks all register (no rAF drops).
  Asserts zero `console.error` on load and during interaction.
- **`router.spec.ts`** — Hash-mode `SwiflowRouter`: initial render,
  in-app `Link` click navigation, `Back` button via `router.back()`
  + browser history. Exercises nested-component `onAppear` (Link's
  click handler) and the diff's DOM sync on component-type swap.
- **`progress.spec.ts`** — Driver pre-fetches App.wasm via
  `fetchWithProgress` and writes the percent to
  `documentElement.dataset.swiflowProgress`. Asserts the attribute
  appears and reaches `"100"`.
- **`sw-cache.spec.ts`** — Service worker registers on release
  builds, caches WASM + JS by content hash, and serves visit #2+
  from local cache.

## What it does NOT test

- Hot reload (would need source-file mutation mid-test; deferred).
- Multiple browsers (Chromium only; Firefox + WebKit are Phase 5+).
- HMR `@State`-preserving swaps (covered by the Phase 8 baseline
  document, not Playwright).

## CI

`.github/workflows/ci.yml` runs the default `npm test` on every PR
(see the `playwright-e2e` job). The full suite is the source of
truth for shipping; the per-spec scripts are a local-iteration
convenience.

> **Caveat:** the project's normal workflow pushes directly to `main`,
> which does not run Playwright. So per-spec smoke runs locally are
> the real gate for any framework change that could affect runtime
> behavior (lifecycle hooks, diff, scheduler, router internals, DOM
> patches). Run the relevant suite manually before pushing.
