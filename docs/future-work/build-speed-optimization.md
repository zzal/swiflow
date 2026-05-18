# Build-Speed Optimization — Deferred Work

> **Status:** Punted from Phase 2c (see chat log 2026-05-18). Resume when initial-build friction starts blocking actual users, or when there's a natural pause between feature phases. Capture date: 2026-05-18.

## Why this exists

After Phase 2c landed, a smoke-test of `swiflow init demo && swiflow dev` exposed long initial build times (60–180 s on a developer laptop). The five levers below were identified as the realistic optimization moves; this doc preserves the analysis so we don't have to re-derive it later.

## What's slow on the cold path

For a fresh `swiflow init` → `swiflow dev`:

1. SwiftPM resolves Swiflow + JavaScriptKit + transitive deps (network roundtrips, git clones).
2. The whole graph compiles for `wasm32-unknown-wasi`. Swift's WASM compile path doesn't share intermediate artifacts with native compilation, so every module is fresh.
3. `--use-cdn` fetches JavaScriptKit's bundled JS runtime support from jsDelivr on every build.
4. The PackageToJS plugin runs the WASM↔JS bridge codegen.

Subsequent `swiflow dev` invocations on the same project drop to ~5–15 s thanks to SwiftPM's incremental cache. The pain is the *first* build.

## The five levers (ranked impact-per-effort)

### Lever 1 — Pre-warm the build cache during `swiflow init`
**Impact:** highest. **Effort:** lowest.

After scaffolding, `swiflow init` kicks off `swift package resolve` + a debug build in the background while the user reads the README. By the time they `cd` and run `swiflow dev`, the cache is already hot.

- ~40 LOC in `Sources/SwiflowCLI/Commands/InitCommand.swift` to spawn the background `Process` and print progress.
- The wall time doesn't go down — it moves into the window where users expect "setting up" to take a moment.
- **UX shape change:** `swiflow init` goes from ~1 s to ~30–60 s. Set expectations explicitly ("warming the build cache…").
- **Opt-out:** `--no-prebuild` flag for CI / power users.
- **Handling the race:** if the user runs `swiflow dev` before pre-warm finishes, just wait on the in-flight build (file-lock on `.build/` is the natural sync point).

### Lever 2 — Drop `--use-cdn`, vendor the JS runtime
**Impact:** medium. **Effort:** low.

`swiflow init` writes JavaScriptKit's runtime JS directly into the project (alongside `swiflow-driver.js`) and tells `swift package js` to skip the CDN fetch by pointing at the local copy.

- ~20 LOC. Add the runtime JS to the `Templates/` directory; pin to a specific JavaScriptKit runtime checksum so updates are intentional.
- Speed win: 1–5 s per build, more on slow networks. **Offline builds work** as a bonus.
- **Trade-off:** runtime.js pins to whatever version `swiflow init` shipped with. Updating Swiflow may require re-running init or building a `swiflow upgrade` command.
- **Touches:** `Sources/SwiflowCLI/Templates/Templates.swift`, `Sources/SwiflowCLI/Commands/BuildCommand.swift` (drop `--use-cdn` from the argv).

### Lever 3 — Stream a "Building…" page from `swiflow dev`
**Impact:** medium (perceived). **Effort:** medium.

Today `swiflow dev` blocks on the initial build, then starts the HTTP server. Instead: start the HTTP server immediately, serve a small "Building Swiflow app…" splash page with auto-reload, and swap to the real app once the build finishes (broadcast a `reload` over the existing WebSocket).

- ~80 LOC. A tiny templated splash HTML, a state machine in `DevServer` (`.building` / `.ready` / `.failed`), a build-failure-overlay variant for the `.failed` state.
- **Perceived speed:** dramatic. Users see *something* in <1 s instead of staring at a blank terminal.
- **Bonus:** the failure-overlay variant becomes the foundation for the Phase 4 "build failed" error UI that the original spec earmarked.
- **Touches:** `Sources/SwiflowCLI/Commands/DevCommand.swift` (sequencing), `Sources/SwiflowCLI/DevServer/DevServer.swift` (state), `Sources/SwiflowCLI/DevServer/HTTPRouter.swift` (splash route).

### Lever 4 — Ship pre-built binary artifacts
**Impact:** huge. **Effort:** huge (infrastructure).

`.binaryTarget(...)` lets us distribute precompiled `.xcframework`-equivalents for WASM. Build Swiflow + maybe JavaScriptKit per Swift+SDK combo, host on GitHub Releases, and `swiflow init` pulls the right blob. First build skips compilation entirely for everything below the user's `App.swift`.

- A release pipeline per Swift+SDK combination, host costs, version-skew handling, signing.
- Speed win: 60–120 s on cold builds. Game-changing.
- **Honest assessment:** six-month project, not a weekend project. Worth doing for Phase 4 when Swiflow has actual users to justify the maintenance.
- **Prerequisite:** Swift 6.x's `.binaryTarget` for WASM has gaps — verify support matrix before committing.

### Lever 5 — Phase-aware build progress output
**Impact:** low (real), medium (perceived). **Effort:** low.

Currently `swiflow build`/`dev` inherits `swift package js`'s output verbatim, which is noisy and doesn't communicate phase ("Resolving / Compiling Swiflow / Compiling App / Generating JS"). Replace with a phase-aware progress indicator.

- ~60 LOC. Parse swift's stdout, map to phase labels, print our own progress line.
- **Real speed win:** zero. Perceived speed: meaningful. 90 s with phase markers feels half as long as 90 s of `[42/978] Compiling Hummingbird MyFile.swift`.
- **Touches:** `Sources/SwiflowCLI/Commands/BuildCommand.swift` (the `Process` invocation; switch from `captureOutput: false` to a pipe + line-buffered parser).

## Recommended ordering when we resume

**Short phase (call it 2d) — quick wins:**
- Lever 2 (vendor runtime) — small, self-contained, no downside.
- Lever 5 (progress) — pairs naturally with #2 since you're already in the build-orchestration code.
- ~100 LOC, 1–2 commits, ~10 new tests.

**Focused phase (call it 2e) — perceived-speed UX:**
- Lever 3 (Building… splash) — biggest perceived-UX win for the dollar.
- Lever 1 (pre-warm during `init`) — same orchestration code, complements #3.
- ~150 LOC, 2–3 commits, ~15 new tests.

**Phase 4 (when there are users):**
- Lever 4 (binary artifacts) — only justifiable once the user base justifies the maintenance.

## Triggers to revisit

- A real user complains about slow initial builds.
- We add another big dep (a CSS-in-Swift system, a state-management library) that pushes cold builds past 5 minutes.
- We add CI for example projects and CI time becomes a bottleneck.
- Phase 4 starts and binary distribution becomes part of the release story.

## Out of scope here (related but separate)

- **`swiflow init` UX gap** (no `--path` flag, has to be run from the destination dir). Separate cosmetic fix, not a speed thing.
- **CI cache strategy** for the swiflow repo's own GHA workflow. The `swift sdk install` step takes ~30 s on cold runners; could be cached. Different problem, different cache.
- **Linker selection.** WASM SDK already uses wasm-ld; probably no room for improvement.
