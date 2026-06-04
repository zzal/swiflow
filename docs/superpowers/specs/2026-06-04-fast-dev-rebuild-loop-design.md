# Fast `swiflow dev` Rebuild Loop — Design

> **Status:** Approved design (2026-06-04). Next: implementation plan via
> `writing-plans`. Authored after a systematic-debugging + profiling pass;
> see memory `project_hmr_devloop_diagnosis`.

## Goal

Cut the `swiflow dev` save→swap latency from ~40s to near the WASM relink
floor (~6–9s) without changing the framework runtime, via two independent
levers. Lever 1 is certain; lever 2 is gated on a spike with a fallback.

## Background — measured diagnosis

All numbers from `/tmp/Smoke` (a HelloWorld-class app: `Swiflow` + `@Component`
+ `SwiflowWeb`), debug, warm, M-series. Each `swiflow dev` save runs
`swift package --swift-sdk <id> js --use-cdn --product App` (PackageToJS).

| Phase | Cost | Evidence |
| --- | --- | --- |
| SwiftPM floor (manifest+resolve+plan, no-op) | **~1s** | A minimal JavaScriptKit-only wasm package no-op builds in 0.8–1.4s (36 tracked artifacts). |
| Macro/swift-syntax build-graph stat overhead | **~9s** | Smoke no-op `swift build` is a stable ~9s (8.8–9.0s wall, **1.2s CPU**) — i.e. I/O-bound, not compute. Of 264 tracked build artifacts, **234 are swift-syntax** (the `@Component` macro's host dependency). |
| PackageToJS packaging | **~17s** | Reruns all 14 MiniMake tasks every save with zero incremental skip (all print `building` even on a no-op). |
| Compile + WASM relink (on a real edit) | **~5–8s** | `wasm-ld` statically links the full Swift runtime + deps into one ~14.7MB binary every time. |

Two facts that constrain the design:
- **The packaged `App.wasm` is a byte-identical copy of the raw build wasm in
  debug** (`cmp` exit 0; `shouldOptimize=false` → `syncFile`). `wasm-opt` and
  `--debug-info-format dwarf` are **no-ops in debug**.
- **The JS glue is invariant across edits.** `wasm-imports.json` is empty
  (`[]`) for Swiflow apps — JavaScriptKit's Swift↔JS bridge is a fixed runtime
  ABI, so app-source edits don't add wasm imports. `index.js`/`instantiate.js`/
  `runtime.js`/`platforms/*` therefore don't change between rebuilds.

Two facts that were **disproven** during profiling (do not pursue):
- **Dependency resolution is not the cost** — `swift package describe` (full
  manifest eval + resolution) is ~1.35s, and a no-op build with
  `--disable-automatic-resolution` is still ~9s.
- **The CLI/package split would not help** — hummingbird/nio/crypto aren't
  reachable from an example's App target, so they're never *built*; the ~9s is
  build-graph stat over the *reachable* graph (dominated by swift-syntax),
  which a split does not remove.

## Scope

**In:**
- Lever 1: bypass PackageToJS in the dev rebuild loop (`swift build` + wasm
  copy + glue reuse). Concrete, shippable on its own.
- Lever 2 (gated): a spike to make examples stop building/tracking
  swift-syntax via **prebuilt macros**; fold in if confirmed.
- Lever 2 fallback (gated): if prebuilt macros are infeasible, a **warm/
  persistent-build feasibility assessment** for the ~9s overhead.

**Out:**
- The ~5–8s compile+relink floor (would need WASM dynamic linking or a smaller
  dev binary — deferred).
- `swiflow build` (release) — keeps the full `swift package js` packaging; it
  needs `wasm-opt`, the manifest, and the full glue.
- The CLI/package split (disproven above).
- Any framework-runtime change.

## Lever 1 — bypass PackageToJS in the hot loop (certain)

### Behavior

`DevCommand.run()` today:
1. initial build: `BuildInvocation(.dev).run()` → `swift package js …`
2. watcher loop: on change → `BuildInvocation(.dev).run()` → broadcast.

New:
1. **Initial build unchanged** — `swift package js …` generates the JS glue +
   first wasm into `.build/plugins/PackageToJS/outputs/Package/`. This
   establishes the served bundle. (If the initial build fails, exit non-zero,
   as today.)
2. **Resolve the raw-wasm path once** after the initial build via
   `swift build --show-bin-path --swift-sdk <id> [toolchain env]` → that
   directory + `App.wasm` (e.g. `.build/wasm32-unknown-wasip1/debug/App.wasm`).
   Resolving rather than hardcoding the triple keeps it SDK-agnostic.
3. **Watcher loop: on change →**
   a. `swift build --swift-sdk <id> --product App` (debug; same toolchain env
      as the initial build). On failure: print the error, **do not broadcast**
      (unchanged contract).
   b. Copy the raw wasm → `.build/plugins/PackageToJS/outputs/Package/App.wasm`
      (atomic replace).
   c. Broadcast `hmr-swap` with the existing cache-buster URLs (unchanged
      `WebSocketHub.broadcastHMRSwap`).

The driver's `hmrSwap` (already fixed in commit `c79d3b1`) re-imports the glue
and calls `init({ module: fetchWithProgress(payload.wasmURL) })`, so the copied
wasm is what gets instantiated.

### Why no wasm-imports check is needed

Because Swiflow apps have an empty, stable import set (see Background), the
glue never needs regenerating between edits, so reusing it is safe. **Documented
limitation:** if a project ever changes the low-level JS *import* surface (rare;
not reachable through normal `@Component`/JavaScriptKit usage), the served glue
could go stale — the fix is to restart `swiflow dev`, which re-runs the full
initial `swift package js`. We deliberately do **not** port a wasm-import parser
into the CLI for v1 (YAGNI; keeps `SwiflowCLI` lean). If real usage ever shows
import drift, a cheap import-signature guard (re-run the full package step when
the new wasm's import section differs from the initial baseline) is the
documented hardening path.

### Components / files

- `Sources/SwiflowCLI/Commands/DevCommand.swift` — rewire the watcher loop to
  call the fast path; resolve + cache the raw-wasm bin path after initial build.
- New `Sources/SwiflowCLI/DevServer/FastRebuild.swift` (name TBD in plan) —
  a small unit owning: (a) compose the `swift build --product App` argv,
  (b) resolve the bin path via `--show-bin-path`, (c) copy the wasm into the
  PackageToJS output dir. Pure/argv-composing parts split from process I/O so
  they're unit-testable, mirroring `BuildInvocation`.
- `WebSocketHub`, `EmbeddedDriver`/`js-driver` — unchanged.

### Data flow

save → FileWatcher yields changed set → `swift build --product App` (raw wasm)
→ copy raw wasm → `outputs/Package/App.wasm` → `broadcastHMRSwap(wasmURL,
jsURL)` → driver re-imports glue + `init({module: fetch(wasmURL)})` → render.

### Error handling

- `swift build` non-zero → print stderr, skip broadcast, keep serving the last
  good bundle (unchanged "fix and save to retry" behavior).
- `--show-bin-path` failure → fall back to the full `swift package js` path for
  that rebuild (degrade to correct-but-slow rather than break).
- wasm copy failure → log and skip broadcast.

### Testing

- Unit: argv composition for `swift build --product App` (debug, SDK,
  toolchain env) — pure, like `BuildInvocationTests`.
- Unit: the wasm-copy step with a fixture file (source present/absent; atomic
  replace).
- Unit/integration: the loop chooses copy-not-repackage on a normal change and
  the full-package fallback when `--show-bin-path` fails.
- Manual/e2e: the existing in-browser check (save → non-blank swap + `@State`
  preserved), already validated for the driver fix.

## Lever 2 — kill the ~9s macro/swift-syntax overhead (spike-gated)

### Spike A — prebuilt macros

**Question:** can the `@Component` macro avoid building/tracking the 234
swift-syntax artifacts by using the Swift toolchain's prebuilt swift-syntax
(macro-prebuilts), so an example's no-op `swift build` drops from ~9s toward
the ~1s floor?

**Method:** investigate Swift 6.3 toolchain prebuilt-swift-syntax support and
how `SwiflowMacrosPlugin` consumes it; enable it for `/tmp/Smoke`; re-measure
the no-op build and the tracked-artifact count.

**Gate:**
- **Confirmed** (no-op drops materially, e.g. ≤ ~3s): fold prebuilt-macros
  enablement into the project/template so `swiflow dev` benefits; lands ~6–9s
  combined with lever 1. Document any toolchain-version requirement.
- **Not feasible:** proceed to Spike B.

### Spike B — warm/persistent build (fallback)

**Question:** can a long-lived dev build process hold llbuild's graph warm so
the 234-artifact stat is paid once (at `dev` start) rather than every save?

**Method:** assess `libSwiftPM` / a long-lived build orchestrator (SwiftPM has
no native daemon/watch). Prototype just enough to measure the second build's
no-op cost when the graph is held warm in-process.

**Gate:**
- **Viable:** pursue as its own plan (larger effort; bypass already shipped).
- **Not viable:** ship lever 1 only (~14–20s) and document the macro-graph
  overhead as a known, toolchain-bound limitation.

### Floor (acknowledged, out of scope)

Even with both levers, the ~5–8s compile + WASM relink and ~1s SwiftPM floor
remain. Attacking them (dynamic linking, a slimmer dev binary) is deferred.

## Risks / notes

- **Lever 1 is the value floor.** It's certain (~−17s), low-risk, and
  independently shippable; lever 2 is upside.
- **Spike outcomes are unknown by design** — the spec gates them so we never
  commit to a hard build (warm daemon) blind.
- **`swiflow build` must stay on the full path** — it needs `wasm-opt` and the
  generated glue; only `dev` bypasses.
- **Subagents touching git stay read-only** (shared worktree); SourceKit
  diagnostics are stale — trust `swift build`/`swift test`.
- **Any `examples/` change requires** `swift scripts/embed-templates.swift`
  regen or `TemplateEmbedderTests` fails (only relevant if the plan adds an
  example for testing).
