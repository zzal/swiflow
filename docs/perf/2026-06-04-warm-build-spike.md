# Warm/Persistent Build Feasibility Spike — 2026-06-04

**Question:** Can the ~9s per-invocation `swift build` no-op overhead be structurally reduced
by holding the build system warm across dev-loop rebuilds — and if so, at what effort/risk?

**Recommendation: GO-LATER (defer; payoff off a real edit is ~2–3s, effort is high, API is
unstable, and the WASM cross-compile path has additional blockers).**

---

## Background and Context

Spike A (see `docs/perf/2026-06-04-prebuilt-macros-spike.md`) established:

- Swiflow dev-loop no-op `swift build` wall time: **~9s** (9.06s measured), ~1.2s CPU — I/O-bound.
- Root cause: llbuild's per-invocation stat pass over **576 tracked artifact files** (353 host/tool
  objects, 117 WASM-side, plus `.swiftmodule`, `.d`, `.swiftsourceinfo`, etc.).
- A minimal JS-only package no-op-builds in ~1s, establishing the theoretical floor.
- Prebuilt-macros lever is already engaged and contributed only ~0.5s of the savings.
- Spike B question: can keeping a warm/persistent process avoid paying that stat sweep?

---

## Investigation Point 1 — libSwiftPM as a Library Dependency

### What is exposed

SwiftPM exposes two library products via the `swiftlang/swift-package-manager` repo:

- **`SwiftPM` / `SwiftPM-auto`**: Full build stack. Includes targets `Build`, `LLBuildManifest`,
  `SPMLLBuild`, `SourceKitLSPAPI`, plus all data-model targets.
- **`SwiftPMDataModel` / `SwiftPMDataModel-auto`**: Data model only (package graph, loading,
  resolution), no build execution. Includes `Workspace` but not `Build`.

The `Workspace` module (in both products) does contain a long-lived process comment in its source:
the code notes that "long-running host processes (like IDEs) need special handling in case other
SwiftPM processes (like CLI) made changes." This suggests the API was designed with Xcode/SourceKit
in mind, not a custom build runner.

### API stability

The `Documentation/libSwiftPM.md` in the repo states explicitly:

> "The libSwiftPM API is currently _unstable_ and may change at any time."

This has been the documented status for years with no announced stabilization date.

### Practical use from Swiflow

Swiflow is itself a SwiftPM package. Using libSwiftPM as a dependency would mean Swiflow pulls in
the entire swift-package-manager package (itself a large SPM package with ~40+ targets) as a
declared dependency. The version of libSwiftPM must match the exact Swift toolchain version in use
at runtime — so a binary distributed to a user running Swift 6.3 must be built against the Swift
6.3 version of libSwiftPM, and will break on Swift 6.4, etc. This is the standard caveat for all
libSwiftPM consumers (Xcode is Apple's own; SourceKit-LSP tracks the toolchain).

### What the Build module would give you

The `Build` module inside libSwiftPM contains `BuildOperation`, which is how the `swift build`
CLI drives llbuild internally. In principle a long-lived process could:
1. Load the package graph once (via `Workspace`).
2. Create a `BuildOperation` and call it repeatedly.

However, this brings us directly to Point 2: whether doing so actually avoids the stat pass.

**Finding:** libSwiftPM is real, usable, and exposes the right entry points — but it is explicitly
unstable, version-locked to the toolchain, and adds the entire SPM codebase as a dependency.

---

## Investigation Point 2 — Does a "Warm Process" Actually Avoid the ~9s?

This is the critical nuance. The investigation found that **simply keeping a process alive does NOT
skip the stat pass** in llbuild. Here is why:

### How llbuild detects changes

llbuild stores, in `build.db` (a SQLite database), the `stat()` result for every tracked input and
output: `st_dev`, `st_ino`, `st_mode`, `st_size`, `st_mtime`. On every invocation — even within a
single long-lived process — llbuild must re-stat each tracked node to compute its current
"signature" and compare it against the cached signature. This is by design: without re-stat'ing
you cannot know whether a source file has changed since the last build.

Evidence from the llbuild `BuildSystemFrontend.cpp` source (investigated directly):
- The `resetAfterBuild()` method suggests the system can be reused for multiple builds.
- However, `initialize()` re-creates the `BuildSystem` and re-loads the build description each
  time. There is no in-process caching of node signatures between build invocations.
- No FSEvents, kqueue, or inotify integration appears anywhere in `BuildSystemFrontend.cpp` or
  `BuildSystemBindings.swift`.

The `BuildSystemFrontend` is designed as a discrete build-per-call tool, not a watch server.

### What a warm process would actually save

The ~9s no-op cost breaks down roughly as:
- SPM process startup + manifest evaluation: ~1–1.5s (this IS avoidable by keeping a process warm)
- Package graph resolution check: ~0.5s (avoidable in-process if the graph is cached)
- Build description construction + LLBuild manifest write: ~1–2s (partially avoidable)
- **llbuild stat pass over ~576 files**: This dominates the remaining budget. Each `stat()` call
  is cheap (~1–10µs), but 576 files × multiple stat rounds (inputs + outputs) + SQLite writes
  adds up. This is NOT avoidable without FSEvents-driven invalidation.
- SQLite read/write round-trips for build.db: partially avoidable with a warm DB connection.

Rough estimate of warm-process savings without FSEvents: **~2–3s** (saving the SPM startup,
manifest parse, and graph resolution phases). The llbuild stat sweep itself — likely ~5–6s of
the 9s — would still run on every build invocation even in a warm process.

### What would actually get to ~1s: FSEvents-driven invalidation

To approach the ~1s floor, the system would need:
1. A persistent FSEvents (or kqueue) watcher that tells llbuild "only these N files changed."
2. llbuild only re-stat'ing and re-evaluating nodes in the changed subgraph.
3. For a no-op (no files actually changed), llbuild could skip the stat pass entirely.

llbuild's design does not expose this. Its `BuildSystem` API has no "here are the changed nodes,
skip the rest" entry point. Xcode uses FSEvents + its own build graph manager (now via the
`swiftlang/swift-build` project) to achieve fast no-op builds — but that infrastructure is not
part of llbuild's public API surface.

**Finding:** A warm process would save ~2–3s (SPM startup + manifest phases) but would NOT avoid
the llbuild stat pass. Reaching the ~1s floor requires FSEvents integration with llbuild internals,
which has no public API.

---

## Investigation Point 3 — Alternative Levers

### (a) Driving `swiftc` + `wasm-ld` directly (bypassing SPM/llbuild for the hot loop)

**Concept:** For the dev loop, maintain a custom minimal build graph: parse `.d` files left by
`swiftc`, use FSEvents to know which source files changed, invoke `swiftc` only on changed modules,
then link. Skip SPM and llbuild entirely.

**Effort:** Very high. Requires:
- A correct Swift module dependency graph builder (`.swiftmodule`, `.swiftinterface` semantics).
- A working `swiftc` invocation for WASM cross-compilation (the `-sdk` / `--swift-sdk` flags
  that SPM synthesizes must be replicated manually, including the WASM sysroot).
- A `wasm-ld` link step with the right flags (WASM-specific link flags, runtime library paths,
  etc. that SPM/llbuild constructs).
- Correctness: must handle macro plugin host builds separately (macros run on the host triple,
  not the WASM triple).

This is essentially reimplementing a significant fraction of SPM's build subsystem for the WASM
cross-compile case. The WASM link step alone (linking all stdlib + runtime objects) currently
takes **~5–8s** on a real edit; a direct `wasm-ld` invocation would still pay that. Realistic
payoff for typical source edits: marginal once compilation and link are counted.

**Risk:** High. Any SPM SDK or toolchain update may change the invocation shape (flags, sysroot
paths, runtime library locations). Maintenance burden would be ongoing.

**Verdict:** Not recommended at Swiflow's current maturity (pre-1.0, ~1 developer).

### (b) Reducing the tracked artifact set

The current 576-object count is driven by:
- 117 swift-syntax host objects (already partially reduced by prebuilts — Spike A).
- ~236 other host/tool objects (JavaScriptKit macros, BridgeJSMacros, SwiflowMacrosPlugin,
  ArgumentParser, etc.).
- ~117 WASM-side Swiflow framework objects.
- ~106 WASM-side app + dependency objects.

Reducing host-side objects further (e.g. binary distributing BridgeJSMacros, JavaScriptKit macro
plugin) would reduce the stat budget slightly. However, each binary artifact substitution requires
either upstream adoption or a custom prebuild pipeline, and the payoff per artifact is small
(each saved object is ~1–10µs of stat cost).

The largest reducible chunk would be if swift-syntax prebuilts reached full coverage (0 swift-syntax
`.o` files) — but Spike A shows that is blocked by the 6.0.3 vintage prebuilt mismatch, not
something Swiflow can fix unilaterally.

**Verdict:** Minor incremental improvements possible but cannot reach the ~1s floor.

### (c) Swift Build (swiftlang/swift-build) — upstream improvement signal

Apple open-sourced `swiftlang/swift-build` in February 2025 as the high-level build engine
(currently used by Xcode) that sits on top of llbuild. The migration plan (forums thread
"Evolving SwiftPM Builds with Swift Build"):

- 2026 H1: Feature/platform parity, recommend to all users.
- Mid-2026: `--build-system swiftbuild` becomes the default; existing engine deprecated.
- 2026 H2: Existing engine removed.

However:
1. As of the October 2025 update, swift-build supports ~92% of Linux packages and ~71% of Windows
   packages but **WASM cross-compilation support is not mentioned** in any forum thread or
   announcement.
2. swift-build's faster build planning (the `TargetBuildGraph` caching fix tracked in
   `swiftlang/swift-build#1111`) targets large Xcode monorepos (2,100+ targets, 60s overheads),
   not the small WASM cross-compile case Swiflow faces.
3. No watch mode, daemon mode, or persistent process is mentioned anywhere in the swift-build
   announcements.

swift-llbuild2 (a "fresh take, fully async, NIO-based" experiment at `apple/swift-llbuild2`) was
also investigated. It is experimental, has 306 stars, version 1.0.2 released May 2026, but has no
documentation of watch mode, persistent warm processes, or WASM support.

**Verdict:** Swift Build migration may improve no-op performance for large projects but is not
targeted at the Swiflow WASM use case, WASM SDK compatibility is uncertain, and the timeline
(mid-2026 for default, late 2026 for removal of old engine) means benefit is 6–18 months out.
Worth monitoring passively; not actionable now.

---

## Investigation Point 4 — Honest Payoff Analysis Off a Real Edit

This is the most important framing question.

### What the ~9s no-op covers vs. what a real edit costs

The ~9s no-op overhead is the **lower bound** of any `swift build` invocation — it is the cost
of llbuild deciding "nothing to do." When a real source file changes:

- The stat pass still runs (same cost as no-op: it must stat everything to find what changed).
- Then: incremental Swift compilation of the changed module(s): **~3–8s** depending on module
  size and change scope.
- Then: WASM link step (because any `.o` change triggers relink of the final `.wasm`): **~5–8s**
  (dominated by linking the entire Swift stdlib and runtime into the wasm binary).

So a real single-file edit currently costs approximately:
```
~9s (stat+plan) + ~3–8s (compile) + ~5–8s (link) = ~17–25s total
```
(The compile + link overlap partially with the plan step in parallel pipelines, but SPM's WASM
single-product build is mostly sequential.)

### What a warm build would save off a real edit

A warm process that saves ~2–3s of SPM startup/manifest phases would reduce:
```
Real edit: 17–25s → 14–22s (saving ~2–3s)
```
**That is a ~10–15% improvement on a real edit.** The link step alone (~5–8s) is unchanged.
The compile step is unchanged. The stat pass is largely unchanged.

Compare this to: a developer saves a Swift file and waits 17–25s for the browser to reload.
Shaving 2–3s off that is psychologically marginal — the edit→see loop is still slow enough
to break flow.

### What would actually be noticeable

A genuinely noticeable improvement would require eliminating the link step (e.g. WASM hot-patch
/ module-level dynamic loading — a deep prerequisite not available in the WASM runtime today)
or the compile step (incremental compilation at sub-module granularity, which Swift already does
but still costs several seconds for even a trivial change in a large module).

The warm-build approach only attacks the SPM-overhead component, which is the smallest slice
of a real edit's cost once link+compile are included.

---

## Summary Table

| Approach | Est. Savings (no-op) | Est. Savings (real edit) | Effort | API Stability | Verdict |
|---|---|---|---|---|---|
| Warm libSwiftPM process (no FSEvents) | ~2–3s | ~2–3s | High | Unstable, version-locked | NO |
| Warm libSwiftPM + FSEvents invalidation | ~7–8s | ~2–3s | Very High | Unstable + custom FS infra | NO |
| Direct swiftc/wasm-ld bypass | Potentially ~7–8s | ~0s (still link-bound) | Very High | Fragile, toolchain-coupled | NO |
| Reduce artifact count (binary prebuilts) | ~0.5–1s incremental | ~0.5–1s | Medium | Fine | Maybe (marginal) |
| Wait for Swift Build migration + WASM support | Unknown | Unknown | 0 (upstream) | Good (official) | LATER |

---

## GO / NO-GO / GO-LATER Recommendation

**GO-LATER — with a clear re-evaluation trigger.**

**Reasoning:**

1. **Honest payoff ceiling is low.** The warm-build approach can save ~2–3s off a real edit
   (by eliminating SPM process startup + manifest phases). The WASM link step (~5–8s) and
   incremental compile (~3–8s) are untouched. A real edit currently costs ~17–25s end-to-end;
   a warm build would make it ~14–22s. This is not the 2–3× improvement that would change
   the developer experience.

2. **No-op savings are irrelevant to developer experience.** The 9s no-op time is paid when
   nothing changed — a meaningless case in practice (who saves without changing anything?).
   The no-op benchmark motivated the investigation but does not represent real workflow cost.

3. **The most impactful lever is the WASM link step**, not SPM overhead. The ~5–8s link step
   is paid on every successful real edit and is the dominant cost. Attacking it would require
   either WASM dynamic linking / module hot-swap (a deep platform capability gap today) or
   eliminating the link step via an alternative runtime strategy.

4. **libSwiftPM API instability is a genuine long-term cost.** Any code written against
   libSwiftPM must be retested and potentially rewritten on every Swift toolchain update.
   For a pre-1.0 project maintained by one developer, this is a significant ongoing tax.

5. **FSEvents-driven invalidation has no public API hook in llbuild.** The only way to
   approach the ~1s no-op floor is with FSEvents integration at the llbuild level, which
   Xcode does internally. This is not a documented, stable, or accessible API path.

6. **Re-evaluate when:** (a) Swift Build gains WASM cross-compile support and becomes the
   default engine (mid-2026 per current plan) — it may bring faster build planning as a
   side effect; (b) WASM dynamic linking / hot-patching becomes viable in the SwiftWasm
   stack (this would attack the link-step bottleneck, the real win); (c) Swiflow reaches
   a scale (many modules, many developers) where even marginal per-save improvements justify
   a high-effort, high-maintenance solution.

**The better short-term direction:** invest in perceptual latency (show a "building..." spinner
immediately on save, so the user isn't staring at silence for 10s) rather than structural latency
(the actual rebuild time). The two are independent. A 10-15s build with instant feedback feels
much faster than a 9s build with delayed feedback.

---

## References

- libSwiftPM documentation: https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/libSwiftPM.md
- llbuild BuildSystem documentation: https://github.com/swiftlang/swift-llbuild/blob/main/docs/buildsystem.rst
- llbuild BuildSystemFrontend source: https://github.com/apple/swift-llbuild/blob/master/lib/BuildSystem/BuildSystemFrontend.cpp
- llbuild Swift bindings: https://github.com/swiftlang/swift-llbuild/blob/main/products/llbuildSwift/BuildSystemBindings.swift
- How Xcode builds (llbuild internals): https://gist.github.com/lalunamel/716de8bb16cbf1d942324fc2120931ee
- Swift Build open-source announcement (Feb 2025): https://www.swift.org/blog/the-next-chapter-in-swift-build-technologies/
- Evolving SwiftPM Builds with Swift Build (forum): https://forums.swift.org/t/evolving-swiftpm-builds-with-swift-build/77596
- SwiftPM on Swift Build October 2025 Update: https://forums.swift.org/t/swiftpm-on-swift-build-october-update/82889
- Swift Build issue #1111 (build planning overhead): https://github.com/swiftlang/swift-build/issues/1111
- swift-llbuild2 (experimental): https://github.com/apple/swift-llbuild2
- Spike A (prebuilt macros): docs/perf/2026-06-04-prebuilt-macros-spike.md
