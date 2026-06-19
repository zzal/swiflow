# BridgeJS Seam Toolchain Spike — Findings

**Status:** Complete (spike run 2026-06-19). Throwaway branch `spike/bridgejs-seam`,
probe at `spike/bridgejs-probe/`. Design: `2026-06-19-bridgejs-seam-spike-design.md`.

## TL;DR — GO (with two tractable gaps)

BridgeJS works through Swiflow's *real* pipeline today: the plugin ships in the
pinned **JSKit 0.53.0**, codegen runs under `swift package js`, the export
round-trip (JS→wasm→JS, struct fields intact) was **browser-verified**, and it
compiles under **strict-concurrency v6** alongside the `@Component` macro. Two real
gaps to close in the migration: (1) the **dev/HMR path leaves the JS glue stale**
on `@JS` changes, and (2) the **import direction needs the `typescript` npm
package**. Neither is a blocker.

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

**Q2-dev — `CompilerBypass` runs codegen on HMR? → PARTIALLY (the main gap).**
Added a `@JS public func spikePing()` live and saved. The bypass re-ran the
build-tool plugin (regenerated `BridgeJS.swift` *with* `spikePing`, mtime 16:50:14)
and relinked a fresh `App.wasm` (16:50:16) — but **did NOT re-run PackageToJS
packaging**, so the served `bridge-js.js` stayed stale (16:49:19, no `spikePing`).
- **Consequence:** changing the `@JS` surface in dev yields a **wasm/JS-glue
  mismatch** — new exports aren't callable, and a changed `bjs` import surface
  could fail instantiation. Same shape as the historical reactor-flag bypass gap
  (`Sources/SwiflowCLI/DevServer/CompilerBypass.swift:258`).
- **Fix:** on a `@JS`-surface change, re-run the BridgeJS link / PackageToJS
  packaging for `bridge-js.js`, or detect such changes and fall back to a full
  rebuild. Body-only edits (not touching the `@JS` signature) are unaffected.

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
2. **Close the dev gap** (regenerate `bridge-js.js` on `@JS` changes, or full-rebuild
   fallback) before relying on BridgeJS under `swiflow dev`.
3. **Vendor `typescript`** (or document `npm install`) before using typed imports
   (`bridge-js.d.ts`) — or keep using classic JSKit dynamic calls for the JS→Swift
   sink, as this probe did.
4. **Seam C (Patch enum)** — defer until the field-by-field marshalling cost is
   measured against the current JSObject path.

## Teardown

`spike/bridgejs-seam` and `spike/bridgejs-probe/` are throwaway — **do not merge the
probe.** Salvage only these two docs (`…-spike-design.md`, `…-spike-findings.md`)
onto a docs branch + `--admin --rebase` PR, then `git branch -D spike/bridgejs-seam`.
