# Swiflow Playwright e2e

Browser-based happy-path test for the Counter demo. Verifies @State
mutations propagate through the Scheduler + RAFScheduler + diff +
patch + JS driver round-trip end-to-end.

## Running locally

    cd tests/playwright
    npm install
    npx playwright install --with-deps chromium
    npm test

The first run scaffolds a fresh demo project under your temp directory,
builds it with `swiflow dev`, and points Playwright at it. Subsequent
runs reuse Playwright's browser binary cache.

## What it tests

- Counter renders with "Hello, Swiflow!" + "Count: 0" + Increment button
- Click increments visibly (1 → 2)
- Rapid clicks all register (no rAF drops)

## What it does NOT test

- Hot reload (would need source-file mutation mid-test; deferred)
- Multiple browsers (Chromium only; Firefox + WebKit are Phase 5+)
- Production builds (no `--production` flag exists yet)
