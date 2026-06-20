# BridgeJS Seam Toolchain Spike — Findings

**Status:** Complete (spike run 2026-06-19). Throwaway branch `spike/bridgejs-seam`,
probe at `spike/bridgejs-probe/`. Design: `2026-06-19-bridgejs-seam-spike-design.md`.

## TL;DR — feasible, but deferred (not now)

**Decision (2026-06-19): defer — do not migrate yet.** BridgeJS is officially
experimental ("API may change frequently — use at your own risk") and the current
hand-rolled `JSObject`/`JSClosure` seam works, so there is no forcing function — the
working incumbent wins. Adopting wouldn't be reckless (small, contained seam; JSKit
pinned `upToNextMinor`), just unjustified for a non-urgent improvement. **Revisit
when** BridgeJS drops "experimental" (or lands in a stable JSKit line), a real seam
pain appears (patch-stream perf wall, a marshalling bug, an untyped-boundary break),
or something needs the typed boundary (e.g. a third party calling into the wasm).
The "GO" findings below are the *feasibility* verdict — what the spike proved — not
a recommendation to adopt now.

BridgeJS works through Swiflow's *real* pipeline today: the plugin ships in the
pinned **JSKit 0.53.0**, codegen runs under `swift package js`, the export
round-trip (JS→wasm→JS, struct fields intact) was **browser-verified**, and it
compiles under **strict-concurrency v6** alongside the `@Component` macro. Two real
gaps to close in the migration: (1) the **dev/HMR fast path breaks on `@JS`-surface
edits** (stale generated glue → a failed rebuild, not just stale output), and (2)
the **import direction needs the `typescript` npm package**. Neither is a blocker.

## Verdicts

**Q1 — JSKit 0.53.0 exposes the BridgeJS plugin? → YES.**
`.plugin(name: "BridgeJS", package: "JavaScriptKit")` resolved on the existing
`0.53.0` pin; the build compiled `BridgeJSTool` + `BridgeJSMacros-tool` and ran
"Generate BridgeJS code". **No `branch: "main"` bump needed.**

**Q2-release — codegen runs under `swift package js`? → YES.**
The build-tool plugin generated `BridgeJS.swift` (compiled into `App.wasm`), and
PackageToJS emitted the JS glue (`bridge-js.js` + `bridge-js.d.ts`) alongside
`index.js`/`instantiate.js`. `instantiate.js` imports `createInstantiator` from
`bridge-js.js` and auto-wires the `bjs` imports + typed exports — **no manual
`link` step**.

**Q2-dev — `CompilerBypass` runs codegen on HMR? → NO after the first rebuild (the main gap — worse than first measured).**
`swiflow dev` does a full initial build (codegen runs). The *first* edit triggers
`capturing compile commands (one-time)` and succeeds: adding `@JS public func
spikePing()` regenerated `BridgeJS.swift` (mtime 16:50:14) + relinked `App.wasm`
(16:50:16) — but already left the served `bridge-js.js` stale (16:49:19).
**Subsequent** fast rebuilds replay those cached commands, which **do NOT re-run
BridgeJS generate** — so the generated `BridgeJS.swift` *also* goes stale. The next
`@JS`-surface edit (reverting `spikePing`) **failed the rebuild outright**:

```
BridgeJS.swift:89:15: error: cannot find 'spikePing' in scope
    let ret = spikePing()
swiflow: rebuild failed — swift build failed with exit code 1.
```

The stale generated wrapper `_bjs_spikePing()` still called the function the edit removed.
- **Consequence:** body-only edits hot-reload fine, but **any `@JS`-surface change
  needs a full rebuild** — the bypass serves stale *generated* glue (`BridgeJS.swift`
  *and* `bridge-js.js`), and a removal/rename breaks compilation. Same family as the
  reactor-flag bypass gap (`Sources/SwiflowCLI/DevServer/CompilerBypass.swift:258`),
  but now hitting generated sources, not just linker flags.
- **Fix:** detect `@JS`-surface changes (or just the presence of `@JS` / `bridge-js.*`)
  and fall back to a full `swift package js` rebuild (re-run BridgeJS generate +
  link); only body-only edits take the fast path.

**Q3 — `@JS` + `Extern` compile under v6 + the `@Component` macro? → YES.**
The probe target carries `.swiftLanguageMode(.v6)`,
`.enableExperimentalFeature("Extern")`, the `BridgeJS` plugin, AND Swiflow's
`@Component` macro on one target — all compiled and linked, no concurrency or
`@_extern` diagnostics.

**Q4 — how is `bridge-js.js` bound vs the driver's `init()`? → AUTO-WIRED; one driver gap.**
`instantiate.js` calls `createInstantiator(...).addImports()` (satisfies the wasm
`bjs` imports) and `.createExports(instance)` (typed `spikeDispatch(handlerId,
event)`), returned as `result.exports` from `init()`. The wasm instantiates and the
export works with **zero** hand-wiring. **Only gap:** the Swiflow driver discards
`init()`'s return (`js-driver/swiflow-driver.js:714`), so the bridge exports aren't
surfaced to page code. The migration needs the driver to capture `result.exports`
(and, for the real seam, call the *exported* dispatch instead of
`window.__swiflowDispatch`).

**Q5 — collision with `-mexec-model=reactor`? → NO.**
The release `App.wasm` carries both the reactor entry points (`_initialize`,
`__main_argc_argv`, via `crt1-reactor.o --entry _initialize
--export-if-defined=__main_argc_argv`) AND BridgeJS's `@_expose(wasm)`
`bjs_spikeDispatch` plus `@_extern(wasm, module: "bjs")` imports
(`swift_js_struct_lower/lift_EventInfo`, the push/pop stack). Link succeeded; the
browser ran it. They coexist cleanly.

## Browser proof (release path)

Served the release build (`python3 -m http.server`), loaded in Chrome: the Swiflow
`Probe` rendered into `#app`, `init()` returned `exports: spikeDispatch`, and
clicking the button produced:

```
swift got handlerId=7 type=click self=true
```

JS called `exports.spikeDispatch(7, {type:"click", isSelfTarget:true, …})` →
BridgeJS lowered the `EventInfo` struct across → Swift received every field intact →
Swift called back to JS. Full JS→wasm→JS round-trip, alongside a live Swiflow render.

## Setup requirements discovered

1. **`tsconfig.json` at the package root** is required whenever a `bridge-js.d.ts`
   exists (the build plugin passes it as `--project`). Missing → build fails
   ("missing inputs: tsconfig.json"). Source: `BridgeJSBuildPlugin.swift`.
2. **The import direction (`ts2swift`) needs the `typescript` npm package** available
   to the plugin's bundled `cli.js` — the resolved checkout doesn't vendor it
   (`ERR_MODULE_NOT_FOUND: typescript`). The **export** direction needs neither node
   nor typescript. *This spike proved the export direction end-to-end and DEFERRED
   the full import round-trip; the requirement is recorded, not yet exercised.*
3. **`@JS public struct` used as an exported-func parameter needs an explicit
   `public init`** — the generated `@_transparent` glue can't reference the
   synthesized internal memberwise init.
4. **Struct marshalling is field-by-field** (`bridgeJSStackPush/Pop` + a JS-side
   `lower`/`lift` per field). Confirms the throughput caveat: expressible and
   type-safe, but per-field boundary cost — measure before routing the high-volume
   patch stream (Seam C) through it.

## Recommendation — incremental migration, in safety order

1. **Seam B (outbound `mount`) + Seam A (inbound dispatch export)** — both proven
   here. Wire the driver to capture `result.exports` and call the exported dispatch.
   Add the package-root `tsconfig.json` and the `public init` pattern.
2. **Close the dev gap** — `@JS`-surface edits must trigger a full rebuild (the
   bypass leaves *both* `BridgeJS.swift` and `bridge-js.js` stale and can fail the
   rebuild) — before relying on BridgeJS under `swiflow dev`.
3. **Vendor `typescript`** (or document `npm install`) before using typed imports
   (`bridge-js.d.ts`) — or keep using classic JSKit dynamic calls for the JS→Swift
   sink, as this probe did.
4. **Seam C (Patch enum)** — defer until the field-by-field marshalling cost is
   measured against the current JSObject path.

## Teardown

`spike/bridgejs-seam` and `spike/bridgejs-probe/` are throwaway — **do not merge the
probe.** Salvage only these two docs (`…-spike-design.md`, `…-spike-findings.md`)
onto a docs branch + `--admin --rebase` PR, then `git branch -D spike/bridgejs-seam`.
