# BridgeJS Seam — Toolchain Spike Design

**Status:** Design (brainstormed 2026-06-19)

**Goal:** Prove — with evidence, in a browser — whether JavaScriptKit's **BridgeJS**
build-tool plugin can produce a working Swift↔JS seam through Swiflow's *actual*
build pipeline (`swiflow build` → `swift package … js`, and `swiflow dev` →
`CompilerBypass`), under strict-concurrency v6. The deliverable is a **findings
doc**, not a migration. The branch is throwaway and is **not** merged.

This de-risks the *separate* real seam migration sketched for seams A (inbound
event dispatch), B (outbound `mount` / imports), and C (the `Patch` stream). The
current hand-rolled seam lives in `Sources/SwiflowDOM/DispatcherBridge.swift`,
`Sources/SwiflowDOM/JSAdapter.swift`, and `Sources/SwiflowDOM/Renderer.swift:170-191`.

**Non-goals (this spike):**
- **Not** the real migration. We do **not** replace `window.__swiflowDispatch` in
  `SwiflowDOM`, touch the embedded-driver sync chain (`SwiflowCLI/EmbeddedDriver.swift`
  → 6 mirrored examples), or migrate the `Patch` enum.
- **Not** a merge. No PR; the branch and probe package are discarded once findings
  are recorded.
- **No** throughput work. The `@JS enum`/struct field-stack marshalling cost is a
  question for the real migration, not this spike.

---

## The decisions (from brainstorming)

1. **Spike, not migration.** Output = knowledge. Success is a documented yes/no on
   pipeline fit, not shippable code. A clean *red* is as valuable as a green.
2. **Isolated probe, not SwiflowDOM.** The `@JS` surface lives in a throwaway
   package's own target, so we never force experimental `Extern` onto the core
   library or destabilize the live seam to answer a build question.
3. **Representative shape.** The probe mirrors the real Seam A — an exported
   function taking a struct shaped like `EventInfo`, plus one imported function so
   the import direction is exercised too — not a bare `ping`.
4. **Both build paths.** Built via `swiflow build` *and* `swiflow dev`, because the
   central unknown is whether `CompilerBypass` runs the build-tool plugin. The
   bypass deliberately skips the full plugin build for speed — the same reason it
   once served command-ABI wasm (`Sources/SwiflowCLI/DevServer/CompilerBypass.swift:258`
   hand-injects the reactor flags it would otherwise lose).
5. **Outside `examples/`.** The probe is a standalone SwiftPM package at
   `spike/bridgejs-probe/`, built via `swiflow build --path …` / `swiflow dev --path …`.
   This dodges the embed-template regen that adding a real `examples/` app would
   trigger, and keeps the throwaway fully self-contained.

---

## Verified mechanism

BridgeJS is a **SwiftPM build-tool plugin**, not a manual `generate`/`link` step.
A target opts in:

```swift
.executableTarget(
  name: "App",
  dependencies: ["JavaScriptKit"],
  swiftSettings: [.enableExperimentalFeature("Extern")],         // generated glue uses @_extern(wasm)
  plugins: [.plugin(name: "BridgeJS", package: "JavaScriptKit")]
)
```

- **Export** Swift→JS: annotate with `@JS public func …`.
- **Import** JS→Swift: declare the JS API in `Sources/App/bridge-js.d.ts`; the
  plugin generates the Swift binding.
- Supported param/return types include `@JS struct`, `@JS enum` (with associated
  values), `Optional<T>`, `Array<T>`. **Not** supported: function-typed params —
  irrelevant here, since handlers cross as `Int` IDs, not closures.

Source: JavaScriptKit docs — *Exporting-Swift-to-JavaScript*,
*Importing-TypeScript-into-Swift*, *Ahead-of-Time-Code-Generation*.

---

## The probe

A standalone throwaway package `spike/bridgejs-probe/` (depends on the local
`swiflow` + `JavaScriptKit` + the `BridgeJS` plugin): a counter with one button.
Its app target sets `.swiftLanguageMode(.v6)` to surface the strict-concurrency
question, and carries Swiflow's `@Component` macro plugin alongside `BridgeJS` to
test plugin coexistence.

**Export (Swift → JS), shaped like the real dispatch seam:**
```swift
@JS struct EventInfo {                  // the real seam's fields (DispatcherBridge.swift)
    var type: String
    var targetValue: String?
    var targetChecked: Bool?
    var isSelfTarget: Bool
    var key: String?
    var shiftKey: Bool; var ctrlKey: Bool; var altKey: Bool; var metaKey: Bool
    var detail: String?
}

@JS public func spikeDispatch(handlerId: Int, event: EventInfo) {
    // mutate a counter, then call the imported sink below — proves both directions
}
```

**Import (JS → Swift)** via `bridge-js.d.ts`:
```ts
// Sources/BridgeJSProbe/bridge-js.d.ts
export function spikeLog(message: string): void;
```

**The page** wires a button click to call the generated `spikeDispatch` export with
a hand-built `EventInfo` (mirroring `serializeEvent` at `js-driver/swiflow-driver.js:75`);
the Swift side calls `spikeLog` back. Green = the click round-trips and the struct
fields arrive intact.

---

## Build matrix & the questions each answers

| Path | Command | Question |
|---|---|---|
| Release | `swiflow build --path spike/bridgejs-probe` → `swift package … js` | Does the BridgeJS plugin run end-to-end and emit working glue? |
| Dev/HMR | `swiflow dev --path spike/bridgejs-probe` → `CompilerBypass` | Does the bypass run the build-tool plugin, or skip it (as it skipped reactor conversion)? |

**Open questions the spike must answer with evidence:**

1. Does JSKit **0.53.0** (the current `Package.swift` pin) expose the `BridgeJS`
   plugin product, or must we bump / track `branch: "main"`? (Docs use `main`.)
2. Build-tool plugin under `swift package js`? Under `CompilerBypass`? If the
   bypass skips it, what step re-injects it (parallel to the reactor-flag injection
   at `CompilerBypass.swift:258`)?
3. Does `.enableExperimentalFeature("Extern")` + `@JS` compile under strict
   concurrency v6, and coexist with the `@Component` macro plugin on one target?
4. How is the generated `bridge-js.js` loaded/bound relative to PackageToJS's
   `index.js` and the driver's `init({ module })` (`js-driver/swiflow-driver.js:714`)?
   Automatic, or manual wiring?
5. Any collision between BridgeJS's `@_extern`/exports and the
   `-mexec-model=reactor … --export-if-defined` linker flags?

---

## Pass / fail

- **Green:** clicking the button fires `spikeDispatch` in Swift with `EventInfo`
  fields intact, and `spikeLog` reaches JS — through at least the `swiflow build`
  path — with the `CompilerBypass` behavior documented (works / works-with-an-
  identified-step / blocked-with-reason).
- **Red:** a blocking toolchain incompatibility (e.g. plugin absent on 0.53 and
  `main` also fails to build under v6 + the wasm SDK), captured precisely enough to
  inform the real-migration go/no-go.

Either outcome is a successful spike — the point is the answer, recorded.

---

## Output

- **Findings doc:** `docs/superpowers/specs/2026-06-19-bridgejs-seam-spike-findings.md`,
  written at the end, answering the five questions with evidence (build logs,
  screenshots of the working/failing page).
- **Discarded:** the branch (`spike/bridgejs-seam`, cut from `origin/main`) and
  `spike/bridgejs-probe/` are thrown away after findings are recorded.
- Findings feed the go/no-go on the real A+B+C migration, which gets its own spec.
