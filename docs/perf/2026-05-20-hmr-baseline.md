# HMR Baseline — Phase 8

> **Status:** Measurement protocol documented; specific numbers
> recorded when Alain runs the dev server against the Counter
> template on M1 Max with Swift 6.3 / WASM SDK 6.3. Times below
> are populated as runs complete.

## Measurement protocol

1. **Setup:** `cd examples/HelloWorld` and `swift build -c release --product swiflow` from repo root.
2. **Cold build:** From `examples/HelloWorld`, run `swift package clean` then `../../.build/release/swiflow dev`. Time from the initial-build banner to the first paint in the browser (visible Counter at 0).
3. **Hot rebuild + HMR swap:** With the dev server warm and the Counter clicked to a non-zero count (say 7):
   - Open Chrome DevTools' Console.
   - Touch `examples/HelloWorld/Sources/App/App.swift` (no semantic change — e.g. add a trailing newline or edit a string literal).
   - Read the `[swiflow] hmr-swap took Xms` line in the console.
   - Verify the counter still reads 7 in the DOM (state preserved).
4. **State-survival visual:** Type "hello" into the greeting input. Save a trivial edit. Verify "hello" survives. Toggle the celebrate checkbox. Save. Verify the toggle state survives.

## Results

| Scenario | Time | Notes |
| --- | --- | --- |
| Cold build (Counter, after `swift package clean`) | _measured-on-first-run_ | dominated by Swift→WASM compile + linker |
| Hot rebuild + HMR swap (Counter) | _measured-on-first-run_ | save → pixels, `@State` preserved |
| Full-reload (pre-Phase-8 baseline) | _measured-on-first-run_ | reference: pre-Phase-8 behavior, kept for the contrast it provides |

## What changed

- **Pre-Phase 8:** every save → full page reload → `@State` lost,
  scroll position lost, focus lost. The 8s rebuild was the
  smaller half of the DX cost; losing context was the bigger
  half.
- **Post-Phase 8:** every save → WASM hot swap →
  `@State` survives. Scroll position and focus still reset
  (deferred to Phase 9+).

The motto target — *save → pixels feels instant* — is met when
the user's mental model of "I'm typing into this field, this
counter is at 7, I'm trying a render tweak" survives the save.
That's the bar the perceptual measurement reflects.

The instrumentation: the JS driver brackets the HMR pipeline
(snapshot extract → maps clear → mount-target clear → dynamic
`import()` → first patches applied) with `performance.now()`
and logs `[swiflow] hmr-swap took Xms` on success. This excludes
the file-watcher + Swift rebuild time (which is reported by the
CLI as it happens), so the in-browser number reflects the work
that begins when the new WASM lands.

## Reproduction

The repo state at the time of Phase 8's commit on origin/main is
the canonical reference; the perf doc's measurement protocol
above produces numbers comparable across runs.

## Dev rebuild loop — bypass PackageToJS (2026-06-04)

`swiflow dev` no longer re-runs `swift package js` on every save. The initial
build still runs the full plugin (generating the JS glue + first wasm); each
subsequent save runs a plain `swift build --product App` and copies the fresh
wasm over `.build/plugins/PackageToJS/outputs/Package/App.wasm`, reusing the
glue. This removes the ~17s PackageToJS packaging that reran every save.

**Why glue reuse is safe:** Swiflow apps have an empty wasm-imports set
(`wasm-imports.json` is `[]`) — JavaScriptKit's Swift↔JS bridge is a fixed
runtime ABI, so app-source edits don't change the wasm's imports, and the
generated `index.js`/`instantiate.js`/`runtime.js` glue is invariant across
edits.

**Limitation:** if a project ever changes the low-level JS *import* surface
(not reachable through normal `@Component`/JavaScriptKit usage), the served
glue could go stale. Fix: restart `swiflow dev` (re-runs the full initial
`swift package js`). If resolving the raw wasm bin path fails at startup, the
loop automatically falls back to the full packaging path per save.

**Still in the loop (not addressed here):** ~5–8s compile + WASM relink, ~1s
SwiftPM, and ~9s macro/swift-syntax build-graph stat overhead (Lever 2 spike;
see the design doc).
