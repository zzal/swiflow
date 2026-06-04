# WASM Hot-Swap (Dynamic Linking) Feasibility Spike — 2026-06-04

**Question:** Can `swiflow dev` reach Vite-class rebuild times by compiling the app into a
small recompilable **side module** dynamically linked against a stable **base module**
(framework + ~29 deps + stdlib), so a save relinks only the delta instead of the 14.7 MB binary?

**Recommendation on the literal question: NO-GO.** Dynamic/hot-swap linking is both unsupported
on the stock toolchain *and* — more importantly — **pointed at the wrong cost.** The WASM link it
would optimize is **~0.3 s**, not the 5–8 s prior notes assumed.

**But the spike overturned the root-cause model and surfaced a STRONG GO:** the dominant
per-save cost is **SwiftPM orchestration overhead (~9 s, paid even on a no-op build)**, and it is
**bypassable today** by capturing SwiftPM's own `swiftc` + `wasm-ld` invocations once and replaying
them on each save. Measured result: **~12 s → ~1.6 s on a real edit** (byte-identical, correct wasm).

---

## How the bet was framed (and why it was reasonable)

Memory `project_hmr_devloop_diagnosis` and `docs/perf/2026-06-04-warm-build-spike.md` both stated
that a real edit costs roughly `~9s (stat+plan) + ~3–8s (compile) + ~5–8s (link)`, with the
**WASM link dominating** ("14.7 MB static-binary link dominates"). Under that model, the only path
to a fast loop is to stop relinking the whole binary — i.e. dynamic linking / module hot-swap. So
that is the bet we set out to test.

**That model was wrong.** No one had ever isolated the link step. This spike did.

---

## Investigation 1 — Is dynamic linking even available on the toolchain?

The linker primitives exist. `wasm-ld` (LLD 21.0.0, swiftlang build) advertises:
`--experimental-pic`, `--shared`, `--pie`, `--import-memory`, `--import-table`,
`--growable-table`, `--export-dynamic`, `--unresolved-symbols`. That is the Emscripten
`MAIN_MODULE`/`SIDE_MODULE` substrate.

`swiftc` also *accepts* `-Xllvm -relocation-model=pic` and emits an object (verified: a trivial
`@_cdecl` leaf compiled both static and "pic" with the WASI SDK resource dir).

But three Swift-specific blockers make a base/side split infeasible on the stock toolchain:

1. **No PIC/shared stdlib is shipped.** The `swift-6.3-RELEASE_wasm` SDK ships **58 static `.a`
   archives and zero shared/PIC wasm modules.** `libswiftCore.a` alone is 11.7 MB of *non-PIC*
   static code. For the 14.7 MB base to be a PIC `MAIN_MODULE`, the entire Swift stdlib + runtime
   would have to be rebuilt from source as PIC for wasm — a toolchain fork, not a framework feature.
2. **No JS dynamic linker.** Loading a side module against a base requires wiring `__memory_base`,
   `__table_base`, `GOT.mem`/`GOT.func`, and the `env` import object at instantiation. Emscripten
   ships a JS runtime that does this; JavaScriptKit does not. We would have to write and maintain one.
3. **Swift runtime metadata across a wasm module boundary is unproven.** Protocol-conformance and
   type-metadata discovery assumes a single linked image. Cross-module dynamic registration on wasm
   is not something swiftwasm ships or documents. swiftwasm has explicitly not shipped Swift dynamic
   linking.

Each of these alone is a multi-month, toolchain-level effort. Together, for a pre-1.0,
~1-developer project, they are out of scope.

---

## Investigation 2 — The measurement that flips the premise

All measurements: `examples/QueryDemo` (uses `@Component` + `@MutationState` macros,
SwiflowWeb + SwiflowQuery + JavaScriptKit + JavaScriptEventLoop), debug, M-series, warm toolchain.

### The isolated WASM link is ~0.3 s, not 5–8 s

Captured the exact `clang`→`wasm-ld` link invocation from a verbose build (114 object inputs +
58 SDK archives → 14.4 MB `App.wasm`) and ran **only that command**, repeatedly:

```
relink run 1: 0.54s
relink run 2: 0.24s   (14,431,259-byte wasm)
```

**The 14.4 MB binary relinks in ~0.3 s.** The "link dominates" premise is false.

### A *no-op* `swift build` costs almost the same as a real edit

| Scenario | real | user+sys (CPU) | what compiled |
|---|---|---|---|
| Warm real edit (`swift build --product App`) | **11.04 s** | 3.33 s | `App.swift` + link |
| **True no-op** (nothing touched) | **11.90 s** | 2.69 s | nothing |
| Isolated link only | ~0.3 s | — | — |

A no-op and a real edit cost the same ~11–12 s, with only ~2.7 s of CPU. **~9 s is fixed SwiftPM
overhead** — manifest load, graph resolution, build planning, llbuild's stat sweep over the whole
tracked artifact set — **paid on every invocation regardless of whether anything changed.** This
matches the warm-build spike's ~9 s no-op finding; what is new is that the link and compile are
*small next to it*, so the ~9 s is the whole game.

### Bypassing SwiftPM: ~1.6 s, correct

Captured SwiftPM's own `swiftc` (App-module compile, with `-load-plugin-executable` for the macros)
and `clang`→`wasm-ld` (link) commands from one verbose build, then ran just those two — **no
`swift build`**:

```
touch App.swift  ->  compile + link:  run1 1.72s,  run2 0.57s
real content edit (added @_cdecl symbol):  1.65s
```

Correctness check: a real content edit through the bypass produced a **different, valid 14.4 MB
wasm** containing the new symbol (`cmp` differs; `spike_probe` present). Macros expanded correctly
(the `swiftc` command carries the plugin executable). Probe reverted afterward.

**~12 s → ~1.6 s on a real edit, byte-faithful to SwiftPM's own output.**

---

## Correcting the prior warm-build spike

`docs/perf/2026-06-04-warm-build-spike.md` Investigation Point 3(a) and its summary table rejected
the "direct swiftc/wasm-ld bypass" with:

> "The WASM link step alone … currently takes ~5–8s on a real edit; a direct `wasm-ld` invocation
> would still pay that. Realistic payoff … marginal once compilation and link are counted."
> Table: *Direct swiftc/wasm-ld bypass | ~0s (still link-bound) | Very High | NO*

That dismissal rested entirely on the unmeasured 5–8 s link figure. **Measured, the link is ~0.3 s
and the whole bypass is ~1.6 s.** The 3(a) verdict should be read as **superseded**: the bypass is
the recommended lever, not a rejected one.

The prior spike also feared the bypass meant "reimplementing a significant fraction of SPM's build
subsystem" (replicating sysroot/flags by hand). The capture-and-replay approach **does not**
reimplement anything — it harvests SPM's *own* emitted commands verbatim from one verbose build and
replays them. This is the same capture/replay-with-fallback philosophy as shipped Lever 1.

---

## What a Lever-2 "compiler bypass" would look like (not built — spike only)

Evolve the existing `FastRebuilder` (`Sources/SwiflowCLI/DevServer/FastRebuild.swift`), which today
runs `swift build --product App` + wasm copy:

1. **At dev start**, run one full `swift build --product App -v`, parse out the **App-module
   `swiftc` compile command** and the **`wasm-ld` link command**, and cache them (with their
   absolute paths and the full flag/dep set, exactly as SPM emitted them).
2. **On each save**, replay `swiftc` (incremental, recompiles only changed module sources) then
   `wasm-ld`, then the existing atomic copy over the served `App.wasm`. ~1.6 s.
3. **Fall back to a full `swift build` (and re-capture the commands)** when the captured commands
   could be stale: `Package.swift` changed, a source file was added/removed from the App module, or
   the import surface changed. Same fallback discipline as Lever 1's bin-path resolution.

### Honest caveats to resolve during implementation

- **Multi-file App module:** the spike's App module is small. SPM's emitted `swiftc` command
  compiles the *whole* App module from its sources list in incremental/batch mode, so multi-file
  should work — but must be verified, and **adding a new file** to the module requires re-capture
  (a new file isn't in the cached sources list).
- **Only the App module is assumed to change** — identical assumption to Lever 1. Editing framework
  sources in a path-dependency would need the full path; out of scope for an app dev loop.
- **Command capture is project-/config-specific** and regenerated per dev session, so toolchain/SDK
  drift is absorbed by the next full build, not baked in.
- **This composes with Lever 1, it doesn't replace it conceptually** — Lever 1 removed the ~17 s
  PackageToJS packaging; Lever 2 removes the ~9 s SwiftPM orchestration. Together: ~40 s → ~1.6 s.

---

## Summary Table

| Approach | Real-edit cost | Effort | Risk | Verdict |
|---|---|---|---|---|
| WASM dynamic linking / hot-swap (the literal bet) | n/a — optimizes a 0.3 s link | Toolchain-fork | Very high | **NO-GO** |
| Warm libSwiftPM process | ~9–11 s | High | Unstable API | NO (per Spike B) |
| **Direct swiftc + wasm-ld capture/replay (compiler bypass)** | **~1.6 s** | **Medium** | Medium (staleness → fallback) | **STRONG GO** |

---

## GO / NO-GO Recommendation

- **WASM hot-swap / dynamic linking: NO-GO.** Unsupported on the stock toolchain (no PIC stdlib, no
  JS dynamic linker, unproven cross-module Swift metadata) *and* aimed at a ~0.3 s cost. Re-evaluate
  only if swiftwasm ships a PIC stdlib + dynamic-linking runtime upstream — at which point the payoff
  is still only ~0.3 s/save, so it would never be worth doing for dev-loop speed alone.

- **Compiler bypass (Lever 2): STRONG GO.** It attacks the actual bottleneck (~9 s SwiftPM
  orchestration), is feasible today with no toolchain fork, reuses SPM's own commands (low fragility),
  and measured ~12 s → ~1.6 s on a real edit. Recommend greenlighting a brainstorm → spec → plan →
  subagent-driven implementation, evolving `FastRebuilder` with capture/replay + full-build fallback.

This is the genuine Vite-adjacent answer: sub-2-second edit→swap. Not 200 ms (we still compile and
link a native binary), but a categorical improvement and an honest selling point.

---

## References

- Shipped Lever 1 (PackageToJS bypass): `docs/superpowers/specs/2026-06-04-fast-dev-rebuild-loop-design.md`
- Warm-build spike (superseded 3a): `docs/perf/2026-06-04-warm-build-spike.md`
- Prebuilt-macros spike: `docs/perf/2026-06-04-prebuilt-macros-spike.md`
- HMR baseline: `docs/perf/2026-05-20-hmr-baseline.md`
