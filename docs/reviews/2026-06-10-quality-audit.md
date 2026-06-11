# Quality Audit — 2026-06-10

> **Status: COMPLETE — 11 of 11 units.** Audit of all 9 `Sources/` modules (each in silo),
> the JS driver, and one cross-module architecture pass. Built-by-AI-agents codebase;
> the audit hunts "AI slop": task-focused changes that ignored the architectural picture.
> Every Critical/High finding is re-verified at source by the orchestrating reviewer
> before landing here. Severity: Critical = user-facing correctness/architecture flaw;
> High = significant design problem or latent bug; Medium = real but contained; Low = nit.
>
> Excluded from style critique: generated files (`Sources/SwiflowCLI/EmbeddedDriver.swift`,
> `EmbeddedTemplates.swift`). Out of scope: fixes, spec-drift vs docs/superpowers, Tests/ quality.

## Running tally

| Unit | Status | Critical | High | Medium | Low |
|---|---|---|---|---|---|
| Swiflow (core) | ✅ audited | 0 | 0 | 4 | 5 |
| Cross-module architecture | ✅ audited | 0 | 0 | 2 | 5 |
| SwiflowCLI | ✅ audited | 0 | 0 | 4 | 4 |
| SwiflowDOM | ✅ audited | 0 | 0 | 5 | 3 |
| SwiflowFetcher | ✅ audited | 0 | 0 | 3 | 4 |
| SwiflowMacrosPlugin | ✅ audited | 0 | 0 | 5 | 4 |
| SwiflowQuery | ✅ audited | 0 | 0 | 4 | 5 |
| SwiflowRouter | ✅ audited | 0 | 0 | 3 | 5 |
| SwiflowTesting | ✅ audited | 0 | 0 | 3 | 2 |
| SwiflowUI | ✅ audited | 0 | 0 | 2 | 1 |
| js-driver | ✅ audited | 0 | 0 | 2 | 4 |
| **Total** | | **0** | **0** | **37** | **42** |

**Verdict in one paragraph:** Module internals are far better than typical AI-built
code — disciplined access control, real invariant comments, correct subtle algorithms,
clean layering, zero rename residue. The slop is not in any file; it is *between* the
silos: the test harness systematically under-simulates the browser (lifecycle, event
payloads, re-render scope) while claiming fidelity; dev-time machinery (HMR, DevAPI,
service worker) was bolted on phase-by-phase without an ownership story for
update/teardown/multi-root; and several modules carry the scar tissue of completed
phases (dead dual-modes, dead facades, "later tasks" comments describing the past).
Exactly the failure mode this audit was commissioned to find — task-complete,
big-picture-incomplete.

---

## Unit 1 — Sources/Swiflow (core)

**Health verdict:** Genuinely well-architected — disciplined `package`-scoped access
control around the patch pipeline, correct LIS-based keyed diff, invariant-dense
docs — but carries one security-invariant hole and a cluster of stale phase-narrative
comments concentrated in the riskiest file.

### HIGH — URLSanitizer bypass via postfix modifiers *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-invariant-holes.md]**
`Sources/Swiflow/DSL/VNodeModifiers.swift:32-34`
```swift
func attr(_ name: String, _ value: String) -> VNode {
    mergeAttribute(self) { $0.attributes[name] = value }
}
```
The prefix path sanitizes URL attributes (`DSL/Modifiers.swift:126-139` routes
`href/src/action/formaction` through `URLSanitizer.sanitize`), but postfix
`VNode.attr`/`.data` write directly into `attributes` with no check — contradicting
the documented invariant at `URLSanitizer.swift:14-17` ("every URL-bearing attribute…
passes through sanitize; rawHTML is the only documented bypass"). Latent today (no
caller uses postfix `.attr("href", …)`), but it is a public door around the XSS allowlist.

### MEDIUM — Duplicated HMR restore loop; older half production-dead
`Reactivity/Component.swift:188-200` vs `Reactivity/HMR.swift:222-232` contain the
identical restore loop. `wireStateAndRestore` was written to replace the old pair
(Component.swift:163-165), yet `HMRWalker.applyRestore` survives — called only from
`Tests/SwiflowTests/HMR/*` (5 files); production flows through `HMRRestoreInstall.stateFor`
→ `wireStateAndRestore`. A fix applied to one copy silently misses the tested copy.

### MEDIUM — Triplicated removal/animateExit block in the child diffs
`Diff/IndexedChildrenDiff.swift:83-98`, `Diff/KeyedChildrenDiff.swift:173-191`,
`Diff/KeyedChildrenDiff.swift:276-293` — three near-identical ~15-line
exit-animation/remove blocks; the cross-kind replacement splice appears 4 times.
Any detach-ordering fix must land in 3-4 places.

### MEDIUM — Stale comments inside KeyedChildrenDiff (the riskiest code)
- `KeyedChildrenDiff.swift:12-14`: header describes `"__index_<i>"` key scheme the
  code never uses (actual: `__noKey_<handle>` / `__noKey_unkeyed` / `__noKey_structural#<offset>`).
- `KeyedChildrenDiff.swift:447-455`: "FIX THEN" note describes a fix that
  `bucketKey(_:offset:)` (lines 415-420) already implements; its premise about
  `ChildrenBuilder` flattening is also stale (now emits `.fragment`, ResultBuilder.swift:35-56).
- `KeyedChildrenDiff.swift:201-203`: points at "lines ~176-186"; the check is at 32-50.

### MEDIUM — Field init mutates @State during body evaluation
`Forms/Field.swift:13-22` — first construction snapshots into FormController via
`ctrl.set(updated)` inside `body`, violating the body-purity rule documented at
`Reactivity/Component.swift:20`. Converges (guarded by `== nil`) but institutionalizes
a forbidden pattern and costs an admitted extra render.

### LOW
- **Unused public styling API:** `Attribute.transition/.animation/.cssVar`
  (`DSL/Modifiers.swift:86-96`) + postfix twins (`DSL/VNodeModifiers.swift:58-68`) —
  six public symbols, zero callers repo-wide, no tests.
- **False "set exactly once" comments on MountNode:** `MountTree.swift:29-31,45-47` —
  `update()` mutates `componentBody` every component re-render (`Diff/Diff.swift:466`).
- **Phase/task narration residue:** 35 "Phase N / Task N" comments in shipped code
  (e.g. `Diff/Diff.swift:378` "Children diff lands in Tasks 16-17" — it landed, two
  lines below); redundant double-comment + no-op assignment at `KeyedChildrenDiff.swift:244-252`.
- **Stale header count:** `DSL/Elements.swift:3` says "20 lowercase factories"; file has ~31.
- **Diagnostic message/behavior mismatch:** `DSL/TaskModifier.swift:31`,
  `DSL/VNodeModifiers.swift:4-5,11` say "silently ignored", but `swiflowDiagnostic` is a
  `preconditionFailure` in DEBUG (`Reactivity/Diagnostics.swift:34`).

### Strengths
- Patch pipeline (`Patch`, `PatchPayload`, `PatchSerializer`, `MountNode`,
  `HandlerRegistry`, `HandleAllocator`) fully `package`-scoped (~114 declarations) —
  wire format kept out of user API.
- Fragment-aware DOM placement centralized in `Diff/DOMAnchors.swift` (three small
  total functions), honored by both child-diff strategies.
- `Event.domName` (`DSL/Event.swift:28-36`) encodes the release reflection-metadata
  post-mortem as an invariant comment — institutional memory done right.
- Handler lifecycle (stable `ScopeID`, `withScope` pinning, eager `remove(id:)`) is
  coherent and heavily tested.

**Clean:** 0 stale SwiflowWeb/SwiflowHTTP references. 48/48 files read.

---

## Unit 2 — Cross-module architecture

**Architecture verdict:** Layering fundamentally sound — dependency graph matches the
declaration exactly (every `import` verified), runtime and CLI never touch each other,
the Swift↔JS patch contract is field-for-field identical across all 19 opcodes, and the
Foundation-free runtime genuinely holds across all six WASM-bound modules. Erosion
concentrates at the renderer/testing boundary: the handler registry was never lifted
into a core ambient seam the way `RenderObserverBox`/`TaskScope` were, and the two High
findings cascade from that.

### HIGH — Public event-modifier API implemented twice with divergent semantics *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-handler-seam-harness-fidelity.md]**
`Sources/SwiflowDOM/AttributeModifiers.swift:31-59,67-82` vs
`Sources/SwiflowTesting/TestingModifiers.swift:8-58`. Same public signatures
(`VNode.on`, `Attribute.on`) defined in two modules against two different private
ambients. DOM: `preconditionFailure` when used outside a render cycle; Testing:
`guard let registry = _testAmbientHandlers else { return .skip }` — silent no-op.
Testing mirrors only `.on`; none of `.value/.checked/.selection/.ref`
(AttributeModifiers.swift:93-160,186-265) exist headlessly, so two-way-binding
components are untestable via SwiflowTesting. Root cause: the handler-registry ambient
lives in SwiflowDOM instead of core — which already solved this exact problem three
times (`RenderObserverBox`, `SwiflowTaskRuntime.currentScope`, `AmbientEnvironment`).
A core ambient box would delete TestingModifiers entirely.

### HIGH — TestRenderer skips production lifecycle *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-handler-seam-harness-fidelity.md]**
`Sources/SwiflowDOM/Renderer.swift:251` calls `firePostRenderLifecycle`; `:261` calls
`destroy`. `Sources/SwiflowTesting/TestRenderer.swift` contains zero calls to either
(grep confirmed), and `RenderObserverBox.current?.componentDidUnmount` (Diff.swift:656)
is unreachable under test. `onAppear/onChange/onDisappear` never fire in SwiflowTesting.
Concretely: `RouterRoot.onAppear()` (RouterRoot.swift:61-70) and `Link.onAppear()`
(Link.swift:56-66) install listeners there — the router's browser behavior is
structurally invisible to its own test target.

### MEDIUM — TestRenderer discards the patch stream
`TestRenderer.swift:67,92,110` read only `result.newMountTree`; `DiffResult.patches`
is dropped. Both ends are unit-tested (PatchSerializerTests; js-driver/test/opcodes.test.js)
but no host-side test exercises diff-emitted patch *sequences* against apply semantics —
ordering contracts like Patch.swift:86-89 ("createElement patches MUST precede…")
are enforced only by comment.

### MEDIUM — Foundation-free CI guard covers 3 of 6 WASM-bound modules
`.github/workflows/ci.yml:125-128` greps only `Swiflow SwiflowRouter SwiflowDOM`;
SwiflowQuery, SwiflowFetcher, SwiflowUI also ship in the WASM binary and are unguarded.
All currently clean, but the guard's own "update this list when adding a new runtime
module" comment was already not honored for three modules. **[FIXED — see docs/superpowers/plans/2026-06-10-invariant-holes.md]**

### MEDIUM — Incoherent @_exported / umbrella strategy
`SwiflowDOM/SwiflowDOM.swift:12` and `SwiflowDOM/AttributeModifiers.swift:3` both
`@_exported import Swiflow` (second is redundant); SwiflowDOM does not re-export
SwiflowQuery despite depending on it; Router/Query/UI/Fetcher re-export nothing.
Visible in the repo's own examples: TodoCRUD imports `SwiflowDOM, SwiflowQuery,
SwiflowFetcher` (relying on the re-export), MiniRouter imports `Swiflow` *and*
`SwiflowDOM` (redundant). No consistent answer to "what do I import."

### LOW
- **Link bypasses the framework's own event seam:** `SwiflowRouter/Web/Link.swift:59-65`
  uses raw `JSClosure` + `addEventListener` via `Ref` instead of `.on(.click)` →
  HandlerRegistry → patch → driver. Invisible to TestRenderer's `click()`; listener
  never removed. A casualty of the missing core handler seam (`.on` lives in SwiflowDOM,
  which Router doesn't depend on).
- **Module-name shadowing:** `SwiflowDOM/SwiflowDOM.swift:16` `public enum Swiflow {}` —
  wherever SwiflowDOM is imported, qualified `Swiflow.VNode` resolves to the enum and fails.
- **JSClosure-retention pattern hand-copied six times** across SwiflowDOM/SwiflowRouter
  (RAFScheduler, TimerHandle, BackgroundRevalidation, DispatcherBridge, DevAPI,
  RouterRoot+Link — one comment literally says "Matches the `rafClosure` pattern");
  each copy independently risks the nil-after-removeEventListener ordering bug
  BackgroundRevalidation.swift:68-69 documents.
- **SwiflowQuery (and its test target) is the only target missing `.swiftLanguageMode(.v6)`**
  in Package.swift — compiles under different concurrency rules than the rest.
- **`animateExit` is the only opcode with no JS apply-side test** (driver arm
  swiflow-driver.js:129-143 owns removal timing via setTimeout).

### Patch contract: verified clean
All 19 opcodes enumerated on both sides (PatchSerializer.swift vs swiflow-driver.js
`applyOne` :87-281): no emitted-but-unhandled, no handled-but-never-emitted, no payload
shape mismatches. Driver has defense-in-depth (innerHTML refusal at :173, self-correcting
addHandler, default-arm logging for unknown ops).

### Checked, no finding
URL/query-string logic (RoutePattern vs HTTPClient — different jobs); Clock vs Timing vs
RAFScheduler (distinct concerns); JS-value marshalling (three small shape-distinct
converters); rename residue (zero SwiflowWeb/SwiflowHTTP hits in Sources/, js-driver/,
examples/); `@testable` leaks (none); CLI↔runtime contamination (none).

### Seam assessment
- **RenderObserverBox** — minimal, used exactly as designed; the best seam in the codebase.
- **RenderObserver** — clean 3-method protocol, genuinely query-agnostic; lightly frayed
  at the testing edge (TestRenderer re-implements willEvaluate/didEvaluate manually,
  never triggers unmount).
- **_ComponentRuntime** — tight; macro-emitted only, guarded downcasts in core only. Healthy.
- **AnyComponent** — no tendrils; `package` reads confined to SwiflowTesting identity
  checks and SwiflowDOM's `typeID`. Note: the overall `package` surface is large
  (~120 declarations) but consumed as intended by the two renderer backends; a few
  markers are overshoot (`HMRBridge`, `Renderer.teardown` used only within SwiflowDOM).

### Strengths
- Wire-contract discipline: 19 opcodes documented identically on both sides, with
  deliberate audit affordances and defense-in-depth.
- Layering hygiene rare for 25 days of phased agent work: zero graph deviations,
  zero CLI↔runtime contamination, zero rename residue.
- Core seams are real abstractions, not tunnels; they degrade gracefully and document why.
- Foundation-free runtime holds across all six WASM-bound modules, not just the
  three CI-guarded ones.

---

## Unit 3 — Sources/SwiflowCLI

**Health verdict:** Genuinely good shape — small single-responsibility files, deliberate
testability seams, unusually substantive comments — but the HMR evolution left a real
user-facing bug (HTML edits never reach the browser), `doctor` drifted out of sync with
what `build`/`dev` actually require, and a systematic `ValidationError` misuse degrades
error UX across all commands.

### HIGH — HTML/JS edits trigger a rebuild but never update the page *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-devloop-delivery-correctness.md]**
`Commands/DevCommand.swift:151-183` — the watcher tracks `extensions: ["swift", "html",
"js"]`, but the loop body unconditionally calls `await server.hub.broadcastHMRSwap(...)`.
The driver's `hmr-swap` handler (js-driver/swiflow-driver.js:493-560) only re-imports
`index.js` + wasm; it calls `location.reload()` only on swap *failure*. Saving
`index.html` runs a full Swift rebuild and swaps the unchanged wasm — the edited HTML is
never refetched. `broadcastReload()` exists for exactly this (`WebSocketHub.swift:42`)
but has **zero production callers** (grep: only tests + two stale comments). Classic
bolt-on: HMR replaced reload wholesale instead of dispatching per file type.

### HIGH — `swiflow doctor` doesn't check what `build`/`dev` actually require *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-devloop-delivery-correctness.md]**
`Commands/DoctorCommand.swift:60-75` — the report covers only `swift` and `wasm-sdk`.
`Toolchain/MacToolchainProbe.swift:3-6` documents that on macOS the build fails without
a swift.org toolchain, and doctor never probes it (nor binaryen/wasm-opt — grep: zero
references in DoctorCommand). Doctor prints "All checks passed." on a machine where
`swiflow build` immediately fails. (Independently corroborated on this machine during
toolchain setup.)

### MEDIUM — `ValidationError` misused for runtime failures (12 sites)
`Commands/BuildCommand.swift:245-249`:
```
} catch let error as BuildCommandError {
    throw ValidationError(String(describing: error))
}
```
ArgumentParser treats `ValidationError` as a usage error: full usage block + exit 64
(EX_USAGE). A failed compile followed by a usage dump is misleading, and
`String(describing:)` defeats the typed-error taxonomy. Same pattern at
DevCommand.swift:44,56,61,74,80,103 and InitCommand.swift:117,134.

### MEDIUM — DoctorCommand reimplements spawning + SDK detection with different semantics
`Commands/DoctorCommand.swift:88-103` rolls its own raw `Process`+`Pipe` helper instead
of `ProcessRunner`; `probeWasmSDK` (:81) matches `$0.contains("wasm")` while
`Toolchain/WasmSDKProbe.swift:59` uses `hasSuffix("_wasm")` — doctor can say "found"
for an SDK listing build's probe rejects. The duplicated spawn helper also lacks the
concurrent-drain protection ProcessRunner.swift:97-120 was built for.

### MEDIUM — ~55 lines of copy-pasted preflight between Build and Dev
`BuildCommand.swift:188-234` vs `DevCommand.swift:40-88`: identical path validation,
locator, SDK resolution (same `catch let WasmSDKProbeError` translation), TOOLCHAINS
probe — already drifting in idiom (if/else vs ternary). A shared
`resolveBuildEnvironment()` would collapse both.

### MEDIUM — No coalescing of saves during a rebuild
`DevCommand.swift:171` — `for await changed in watcher.changes()` with multi-second
rebuilds inline over an unbounded `AsyncStream` (FileWatcher.swift:42). Three saves
during a long rebuild queue three more sequential rebuilds; only the last is useful.
Dev-only latency; the loop is correctly serial.

### LOW
- **Dead/test-only members + stale comments:** `WasmSDKProbe.pickDefault` (:65, callers
  only in tests); `DevServer.swift:6` + `WebSocketHub.swift:4` still say DevCommand
  "calls broadcastReload()" (stale since the HMR switch); `WebSocketHub.clientCount`
  (:87) documented "Test-only" but lives on the production actor.
- **Unnecessary `public`/`package` on an executable target:** `Swiflow.swift:17-26`,
  `BuildCommand.swift:283` — all tests use `@testable import`.
- **No-op JSON `\/` stripping with a wrong justification:** `WebSocketHub.swift:73-76`
  — the driver `JSON.parse`s the payload, for which `\/` is already valid.
- **Talking-to-reviewer comments:** `BuildCommand.swift:210-214` (justifies a catch
  idiom, cites a line number that no longer matches); `DriverEmbedder.swift:17-19`
  (advice to future reviewers, not behavior); `DoctorCommand.swift:36` hint points
  binary-only users at "README.md → Prerequisites".

### Strengths
- Consistent, deliberate testability seams: `ProcessRunner` protocol + stub, pure
  `BuildInvocation.composeArguments()`, free-function `HTTPRouter.build`, pure
  `DevModeInjection`/`Templates.render`.
- `ProcessRunner`'s concurrent pipe-drain (documented deadlock mode under pool
  saturation) and `WebSocketHub`'s drop-on-write-failure semantics show real systems care.
- Comments overwhelmingly explain *why* with verifiable specifics (reactor vs command
  ABI in CompilerBypass, raw-string newline round-trip rules in both embedders).
- Thoughtful error taxonomy (`BuildCommandError`, `WasmSDKProbeError`) — only its
  delivery via `ValidationError` is wrong.

**Stats:** 23/23 non-generated files read; ArgumentParser exit-64 behavior asserted
from library knowledge, not executed; HTML-staleness bug verified by reading the
driver source, not by running `swiflow dev`.

---

## Unit 4 — Sources/SwiflowDOM

**Health verdict:** A competently structured thin bridge with good JSClosure-lifetime
discipline, but its multi-root story is half-true (HMR plumbing is hard-wired
single-root), HMR serves stale CSS by design, a dead "Phase 2a" dual-mode threads
optionality through the whole Renderer, and all dev/HMR surfaces ship in the
size-sensitive release wasm behind runtime-only gates. Zero direct tests.

### HIGH — Multi-root HMR loses state: snapshot exporter is last-writer-wins *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-swiflowdom-final-highs.md]**
`SwiflowDOM.swift:83-85`:
```swift
HMRBridge.installSnapshotExporter { [weak renderer] in
    renderer?.mountTree
}
```
Each `render(into:)` overwrites the global exporter with a closure over only the newest
root, while the same file (:40) promises "Multiple roots can be mounted at different
selectors." Two roots → HMR snapshots only the last-mounted one; unmounting it makes
the exporter return empty for survivors (weak ref dies). Compounding:
`takePendingSnapshot()` (`HMRBridge.swift:77`) clears the pending snapshot on first
read, so after a swap the first root consumes the whole index and the second restores
nothing. The JS driver corroborates the single-root assumption (one `let mountSelector`,
swiflow-driver.js:31, overwritten per mount). Multi-root renders/dispatches fine but
silently corrupts on HMR.

### HIGH — HMR serves stale CSS; the skip is documented as a feature *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-devloop-delivery-correctness.md]**
`CSS/CSSInjector.swift:39-51` skips injection when `<style id="swiflow-*">` already
exists ("e.g. an HMR swap re-running setup"), but the driver's `hmrSwap`
(swiflow-driver.js:511-530) clears nodes/listeners/mount target and never removes
injected styles. Editing a component's `scopedStyles` and saving shows stale styles
until a manual full reload — in the exact workflow (dev HMR) this code serves.

### HIGH — Dead "Phase 2a" dual-mode permeates Renderer *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-swiflowdom-final-highs.md]**
`Renderer.swift:30,95-103,149-151,167-173` — `init(viewProducer:)` has zero callers
anywhere (grep: Sources/, Tests/, examples/). The dead mode forces
`rootComponent`/`scheduler` to be Optionals, adds a `preconditionFailure` arm in
`renderOnce()`, and props up the public `Swiflow.rerender()` API whose only repo
references are a README mention and a CLI test asserting templates do NOT use it.

### HIGH — Dev/HMR machinery ships active in release wasm *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-swiflowdom-final-highs.md]**
`DevAPI.swift:27` gates on runtime `SWIFLOW_DEV` only; `DevAPI.installAll()` is called
unconditionally from render/unmount, and `HMRBridge.installSnapshotExporter` has no
gate at all — production apps expose a working `window.__swiflow.hmrSnapshot`
(state-exfiltration surface + dead weight). `BuildCommand.swift:116-118` release flags
include no `-D` define (verified), so DevAPI/DevAPIFormatter/HMR walkers cannot be
dead-stripped. Contradicts the project's heavily-invested bundle-size goal.

### MEDIUM
- **Stale, contradictory multi-root docs:** `Renderer.swift:10-12` ("Multiple roots are
  out of scope for Phase 2a / Phase 3 v1", wrong signature cited) vs
  `SwiflowDOM.swift:40` (multi-root supported) vs DevAPI (multi-root by design); same
  staleness at `RAFScheduler.swift:23-26`.
- **DevAPI duplicates HMRBridge's state encoder and admits it:** `DevAPI.swift:102-123`
  vs `HMRBridge.swift:122-150` — two hand-copied Any→JSValue type ladders ("Phase 15:
  same shape as HMRBridge.encodeStateMap").
- **DevAPI re-install is a self-contradicted no-op:** `DevAPI.swift:19-21` — all four
  closures read the global `renderers` dict at call time, so re-installing changes
  nothing; the stated rationale is false and drives an unnecessary call in `unmount`.
- **RAFScheduler dirty set is write-only; fresh JSClosure per frame:**
  `RAFScheduler.swift:31,61-63,73,86-91` — identities collected, only emptiness checked
  (flush full-tree re-renders; a Bool would do); `scheduleRAFIfNeeded()` allocates a new
  JSClosure every animation frame in the hot path.
- **Three wrong access levels in one small module:** fully-`public` RAFScheduler with
  zero external users; `package` HMRBridge used only inside SwiflowDOM; `package func
  teardown()` on an internal class.

### LOW
- **Foundation cargo-cult comment, duplicated:** `HMRBridge.swift:134-135` +
  `DevAPI.swift:108-109` — "Swift bridges Bool to NSNumber" is false on WASM (no ObjC
  bridging); harmless ordering, wrong justification, copy-pasted twice.
- **Non-reentrant ambient with nil-reset instead of save/restore:**
  `Renderer.swift:138-145` — lifecycle hooks fire while `_currentRenderingRenderer` is
  set; a synchronous nested render would nil the outer ambient. No breakage today;
  fragile next to `firePostRenderLifecycle`.
  **[RESOLVED AS SIDE EFFECT — `_currentRenderingRenderer` was deleted by the
  handler-seam move; see docs/superpowers/plans/2026-06-10-handler-seam-harness-fidelity.md]**
- **DevAPI `state(path)` multi-root semantics differ from siblings:** `DevAPI.swift:51-59`
  — tree()/handlers()/perf() are per-selector; `state` is first-match-wins over
  unordered dict iteration (nondeterministic with same path in two roots).

### Riskiest untested code (zero direct tests)
1. `renderOnce()`'s replaceMount splice + pre-diff ID snapshot lifecycle partition
   (`Renderer.swift:185-251`) — most intricate, ordering-sensitive logic in the module.
2. HMR encode/decode/Int-coercion ladder (`HMRBridge.swift:152-203`) — existing
   "round-trip" tests re-implement expected behavior rather than calling HMRBridge.
3. `teardown()` ordering and BackgroundRevalidation listener add/remove symmetry.

### Strengths
- JSClosure retention/release handled carefully and consistently documented across
  DispatcherBridge, Timing, BackgroundRevalidation, RAFScheduler.
- `RAFScheduler.rafFired()` clears scheduling state before `flush()` — the
  markDirty-during-render reentrancy case is correctly handled and explained.
- Global handle allocator + globally unique handler IDs make the driver's maps
  collision-free across roots — the render/event path genuinely supports multi-root.
- `#if canImport(JavaScriptKit)` empty-stub strategy keeps the host package buildable
  on macOS without contorting code.

**Clean:** zero stale SwiflowWeb references (rename done properly). 11/11 files read.
Unverifiable: whether `-Osize` strips any DevAPIFormatter code in practice.

---

## Unit 5 — Sources/SwiflowFetcher

**Health verdict:** One of the healthier modules — small, coherent, genuinely Sendable,
with a correct JSValue-never-escapes containment design — but the `HTTP` static facade
is dead weight and the "RFC 8259" serializer has a non-finite-double hole.

### MEDIUM
- **`HTTP` facade has zero callers repo-wide:** `HTTP.swift:18-46` — five static verbs,
  each a one-line wrapper over `HTTPClient()`. Grep: only its own doc comment matches;
  TodoCRUD and the embedded template use `HTTPClient(baseURL:)` directly. Five
  duplicated generic signatures that must track `HTTPClient` in lockstep — speculative
  surface.
- **Non-finite doubles produce invalid JSON:** `JSONValue.swift:68` —
  `case .double(let d): return String(d)` → `.infinity` serializes as `"inf"`, `.nan`
  as `"nan"`, despite the file advertising RFC 8259. A computed NaN in a request body
  becomes a server-side parse error with no client-side diagnostic. Untested (tests
  cover only `2.5`).
- **Non-2xx errors discard the response body:** `HTTPClient.swift:115-117` —
  `throw HTTPError.status(Int(response.status.number ?? 0))` loses the error payload
  (`{"error": …}`) and statusText; the `?? 0` fallback can surface as meaningless
  "HTTP 0".

### LOW
- **JSON `Content-Type` silently clobbers caller-supplied headers:**
  `HTTPClient.swift:101-103` runs after the header merge, contradicting the documented
  "per-call header overrides" rule (:37).
- **`patch` has zero callers repo-wide** — defensible verb-set completeness, but
  untested public API.
- **Standalone module documented against Swiflow internals:** `HTTPClient.swift:27-29`
  says "Swiflow.render(...) installs the JS event-loop executor, so no setup is
  required" — the installer lives in SwiflowDOM; a truly standalone consumer gets
  hanging `JSPromise` awaits with no hint that `installGlobalExecutor()` is their job.
- **Defensive duplicate-key literal semantics, celebrated by a test:**
  `JSONValue.swift:50-54` — "last value wins (rather than trapping) — defensive"
  silently diverges from Swift's own Dictionary literal (which traps), for a case the
  comment itself says shouldn't happen.

### Riskiest untested behavior
`resolve()` URL joining, header merge precedence, and the error mapping are all behind
`#if canImport(JavaScriptKit)` and `private` — the single host test file structurally
cannot reach them. `resolve` is pure string logic that could be extracted and tested.

### Strengths
- Disciplined three-case error taxonomy (transport/status/decoding), Equatable, no
  stringly-typed throws.
- JSValue containment is correct and explicitly reasoned; the module degrades to
  `JSONValue`+`HTTPError` off-WASM, which is what makes host testing possible.
- The pure-Swift string escaper is correct where tested (short escapes, `\u00XX`
  control chars, non-ASCII passthrough) with good edge coverage.

**Clean:** zero stale SwiflowHTTP references; Sendable annotations genuine, no
`@unchecked`. 4/4 source files + tests read.

---

## Unit 6 — Sources/SwiflowMacrosPlugin

**Health verdict:** Small and mostly disciplined with good happy-path tests, but the
@Component state-cell scanner has drifted from @State's validation rules, optionality
detection is string-fragile, and there are clear migration-residue / task-narration
artifacts.

### HIGH — Optionality detected by string suffix; `Optional<T>` spelling produces wrong code *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-invariant-holes.md]**
`ComponentMacro.swift:98`:
```swift
let isOptional = valueType.hasSuffix("?")
```
`@State var x: Optional<Int>` (legal spelling) is classified non-optional: its snapshot
closure skips `HMRNilSentinel` normalization and gets `restoreNil: { _ in false }` —
silently reintroducing exactly the type-erased-nil bug the comment at :100-102 says
this code exists to prevent. Wrong code, no diagnostic.

### MEDIUM
- **Scanner doesn't re-check what StateMacro rejects:** `ComponentMacro.swift:91-95` —
  `@State let x` / computed `@State var` still get a `StateCell` emitted, producing
  cascade errors inside generated code on top of the real diagnostic. The two macros
  should share one "valid state cell" predicate.
- **Dead `MacroState` branch + phase narration:** `ComponentMacro.swift:76-79,88` —
  `attrName == "MacroState" || attrName == "State"`, but no `macro MacroState` is
  declared anywhere in the repo (grep: only a docs/superpowers plan mentions it).
  Migration residue from "Phase 15 Task 4/6", per its own comment.
- **Module-qualified attribute spellings silently skipped:** name-text-only matching on
  `IdentifierTypeSyntax` (`ComponentMacro.swift:83-88,173-175`) misses `@Swiflow.State`
  / `@SwiflowQuery.MutationState` (which the compiler expands) — for the latter, `bind`
  never wires the mutation handle: dead at runtime, no diagnostic.
- **No emitted name is fully qualified:** e.g. `StateMacro.swift:101`
  `Binding<\(raw: valueType)>`, `ComponentMacro.swift:130` `StateCell<\(className)>` —
  a user type named `Binding`/`StateCell`/`Component` shadows the framework's and
  breaks expansion confusingly. `runtimeOwner`/`runtimeScheduler` member names are also
  unprefixed (collision-prone).
- **No `static`/`lazy` rejection; first-binding-only:** `@State static var` / `lazy`
  pass all guards and fail with downstream compile errors instead of a diagnostic;
  `@MutationState var a, b: CreateTodo` (peer macro — compiler doesn't block
  multi-binding) silently processes only `bindings.first` (MutationStateMacro.swift:17).

### LOW
- `MutationStateMacro.swift:15-25` lumps let/computed/missing-type into one generic
  message where StateMacro has three precise diagnostics; punctuation style differs
  across the three macros.
- `ComponentMacro.swift:71-74` — `.open` arm is unreachable (`open final` is illegal;
  non-final rejected earlier). Dead guard for an impossible shape.
- Repo-internal citations baked into source: "Per Phase 15 Task 1 finding:",
  "(spec §8, B1)" (`ComponentMacro.swift:100,169`; `MutationMacro.swift:6`).
- `Sources/Swiflow/Macros.swift:27` — `@attached(peer, names: arbitrary)` where
  StateMacro only emits `$name`; should be `prefixed($)` so the compiler can scope
  name lookup.

### Strengths
- Existing diagnostics are precise and correctly anchored (points at the
  `struct`/`enum`/`actor` keyword, not the whole decl); dual
  ExtensionMacro/MemberMacro paths diagnose once and bail quietly on the other.
- Real subtlety handled correctly with dedicated tests: the `didSet` write-drop via
  `shouldDropWrite()` and the optional/HMRNilSentinel snapshot split.
- Emission matches the `_ComponentRuntime` contract in core exactly (member names,
  `@MainActor static let stateCells`, `bind` signature, public-witness handling).

**Stats:** 4/4 plugin files read + Macros.swift + MutationMacro.swift (which actually
declares @MutationState, in SwiflowQuery). Tests: 15 cases, happy paths + key
diagnostics; not covered: actor/enum, static/lazy, multi-binding, `Optional<T>`
spelling, any MutationState misuse.

---

## Unit 7 — Sources/SwiflowQuery

**Health verdict:** One of the healthiest modules — a genuinely coherent
generation-guarded state machine with strong invariant comments and real test
coverage — but with a classic task-focused blind spot (no cache eviction story at
all), one latent concurrency hazard in mutation rollback, and dead speculative
plumbing shipped as load-bearing API.

### HIGH — No cache eviction / GC: entries live forever *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-invariant-holes.md]**
`QueryClient.swift:10` — `var entries: [QueryKey: QueryEntry] = [:]`. Verified: the
only `removeAll` in the module is on subscriptions; no `removeValue`/clear API exists
for `entries`. `reconcile` (:236) only inserts; `dropComponent` removes subscriptions
but never the entry. Every entry permanently retains its `value: Any?` payload AND its
`boxedFetch` closure (capturing the query's dependencies, QueryEntry.swift:34). For
parameterized keys (`["users", id]`, `["todos", page]`) the cache grows unboundedly
over an SPA session — React Query's `gcTime`/zero-observer collection concept is simply
absent. Each phase (queries → mutations → optimistic → background) extended entry
lifetime; no phase asked "when does an entry die?"

### MEDIUM
- **Concurrent-mutation rollback can clobber newer state and cancel its repair fetch:**
  `MutationState.swift:115` — rollback writes back the pre-A snapshot after mutation B
  has touched the same key, and `setQueryData` (QueryClient+Cache.swift:25-28) bumps the
  generation and cancels B's in-flight refetch, so the wrong value persists until the
  next trigger. The comment ("concurrent mutations never share rollback state", :57)
  answers the wrong question — the hazard is interleaved cache state, not shared stacks.
- **Dead speculative plumbing:** `QueryEntry.swift:36-41` — `valuesEqual` is a required
  init parameter, synthesized per observation (QueryClient.swift:286), supplied at 18
  test call sites, read nowhere in production (admitted at QueryClient.swift:128:
  "reserved for markDirty-gating once select change-detection lands (deferred)"). Also
  drags `Equatable` onto `Query.Value` solely for this unused witness.
- **`subscribe` never refreshes a subscriber's scheduler:** `QueryClient.swift:36-41` —
  re-subscribing discards the new `(owner, scheduler)` pair; `scheduler` is weak, and
  notify keeps schedulerless subscribers alive — if a root's scheduler were ever
  replaced, that component's `markDirty` is silently skipped forever. The invariant
  ("one scheduler for app lifetime") is unstated and unenforced.
- **Supersede ritual duplicated, drift visible:** `QueryClient.swift:196-201` vs
  `QueryClient+Cache.swift:25-32` — six lines of entry-invariant surgery in two places,
  the second admitting the copy ("mirrors forceStaleAndRefetch"); the retry phase
  already had to remember both sites when it added `nextRetryDue`/`failureCount`.

### LOW
- **Stale task-board narration:** `QueryClient.swift:6` "(later tasks)"; :151 "Filled
  in by later tasks." on a `tick` that is fully implemented and production-wired; :158
  "(scheduled by Task 7)"; spec cross-refs `(§11, B3)`, `(spec §8)`, "B1 guarantees…"
  referencing a planning doc not in the repo.
- **Ambient-seam access duplicated:** `Query+Component.swift:10` re-implements
  `RenderObserverBox.current as? QueryClient` instead of calling the dedicated
  `_currentRenderQueryClient()` (MutationState.swift:11-13) — query path and mutation
  path each grew their own seam in their own phase.
- **`ManualClock` thread-safety promise is comment-only:** `Clock.swift:36-42` —
  "@MainActor use only" but unannotated and not Sendable; nothing enforces it (the
  missing `.v6` language mode, filed under cross-module, is what lets this slide).
- **`QueryState.isSuccess` lies under SWR-with-error:** `QueryState.swift:17` —
  after a failed background refetch, `error != nil` and `isSuccess == true` hold
  simultaneously.
- **Minor cohesion misplacements:** `makeSnapshot` (a QueryState factory) lives in
  QueryEntry.swift; MutationState.swift hosts four unrelated tiers at 172 lines while
  Invalidation.swift/MutationMacro.swift are 8-9 lines; `MutationHandle.isIdle` has
  zero users anywhere including tests.

### Verified non-findings
`tick`/`focusChanged` are production-wired with proper Clock injection (no raw timers);
`ManualClock`'s `public` is justified (used by SwiflowTesting); all other public
symbols have external users in examples; query-vs-mutation retry asymmetry is by
design; the generation-guard ordering in `commitFetch` is correct and unusually
well-reasoned.

### Strengths
- The generation/supersede mechanism is correct, and its trickiest ordering hazard
  (guard before nil-ing `inFlight` in `commitFetch`, QueryClient.swift:99-105) is
  documented with the exact failure mode it prevents.
- Invariants are mostly *stated* and match the code (subscriber liveness, retry counter
  ownership, focus-double-fire dedup).
- Disciplined API tiering: `package` for test hooks, `public` only for user surface,
  rationale at each boundary.
- `RetryPolicy.delay` overflow handling (cap-check before doubling) is defensive
  arithmetic done right.

**Stats:** 15/15 files read + BackgroundRevalidation/AsyncTestHarness/examples for
usage verification. Unverifiable: whether a root's Scheduler can be replaced in
practice (trigger condition for the subscribe finding).

---

## Unit 8 — Sources/SwiflowRouter

**Health verdict:** Structurally one of the cleaner modules — the Core/Web split is
genuinely principled (zero JS in Core/, pure well-tested matching) — but history mode
is half-implemented (query strings silently lost on load/back), and Link is
mode-unaware, so the default hash mode renders broken hrefs.

### HIGH — History mode drops query strings on initial load and popstate *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-invariant-holes.md]**
`Web/RouterRoot.swift:90-92`:
```
case .history:
    return loc["pathname"].string ?? "/"
```
`readPath` never reads `location.search`. `navigate("/search?q=x")` works (push sets
`currentPath` directly), but Back (popstate → sync → readPath) or a fresh page load
yields `/search` with empty `RouterContext.query`. Hash mode is unaffected (query rides
inside the hash). Asymmetric, state-dependent data loss — and no example or test
exercises `.history` at all.

### HIGH — Link is mode-unaware; hrefs are wrong under the default hash mode *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-invariant-holes.md]**
`Web/Link.swift:51,55` — always emits `.attr("href", path)`. RouterRoot defaults to
`.hash`, where the canonical URL is `#/about`, but Link writes `href="/about"`. The
unconditional `preventDefault` papers over it for plain left-clicks; cmd/middle-click,
"copy link address," and no-JS fallback all navigate to a real server path instead of
the hash route. `Router` carries `path` but no `mode` (verified by grep) — Link
couldn't adapt even if it tried.

### MEDIUM
- **Path params never percent-decoded while query params are:** `RoutePattern.swift:90`
  stores raw segments; `splitQuery` runs a hand-rolled RFC 3986 decoder on query
  pairs. `/users/john%20doe` → `params["id"] == "john%20doe"`, but
  `?name=john%20doe` → `"john doe"`. Zero tests cover encoded path segments.
- **`matchFull`/`matchPrefix` are copy-paste twins:** `RoutePattern.swift:78-110` —
  literal/param arms character-identical; divergence already visible in mid-pattern
  wildcard behavior, and both silently make any segment after `*` unmatchable
  (`/a/*/b` can never match, no diagnostic).
- **Query parsing drops valueless keys, last-wins duplicates:**
  `RouteMatching.swift:50-58` — `?debug` vanishes; `?tag=a&tag=b` keeps `b`. Neither
  behavior documented; `[String: String]` forecloses duplicates by type.

### LOW
- **Inconsistent trailing-slash normalization:** pattern init drops one trailing slash;
  path normalize loops — `Route("/users//")` produces segments that can never match.
- **Triple-redundant query stripping:** `matchRoutes`, `RoutePattern.match`→`normalize`,
  and pattern `init` each strip queries because each function distrusts its caller.
- **Phase-narration in committed code:** RouteMatchingTests.swift:108,118-119 ("the
  Task 2 stdlib decoder must…"); `RouteMatching.swift:108` comment defending `&+`
  while the adjacent expression uses plain `-`.
- **Side-effectful `body` in Link:** `Link.swift:43` mutates `capturedNavigate` during
  render to smuggle the environment value into `onAppear` — a workaround for the
  lifecycle gap filed under cross-module.
- **Hardcoded English 404 fallback, undocumented catch-all:** `RouterRoot.swift:55`;
  `Route("*")` works but `params["*"]` appears in no doc comment.

### Strengths
- The Core/Web split is real: `Core/` has zero JavaScriptKit imports; the pure matcher
  is directly unit-testable and tested (6 files).
- The hand-rolled `percentDecode` is genuinely good wasm-target engineering: strict
  UTF-8 validation via `Unicode.UTF8.ForwardParser`, nil-on-malformed, regression
  tests for lowercase hex, multi-byte UTF-8, lone `%`, bad hex.
- Disciplined access control: `RoutePattern`/`RouteDefinition`/`matchRoutes` are
  `package`; every public symbol has external users — no dead public API.

**Stats:** 9/9 files read + tests + MiniRouter example. Unverifiable: runtime `.history`
behavior (no example, no test, untestable off-wasm given the harness lifecycle gap).

---

## Unit 9 — Sources/SwiflowTesting

**Health verdict:** Structurally one of the healthier modules — the async harness
properly composes the sync one and the query wiring mirrors production — but the
event-simulation layer is low-fidelity: it hand-builds `EventInfo` with fewer fields
than the JS driver ever sends, leaving checkbox/radio components untestable and
blur-validation paths returning nil where the browser returns a value.

### HIGH — Event payloads omit `targetChecked`; checkboxes/radios untestable *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-handler-seam-harness-fidelity.md]**
`TestRenderer.swift:187,196,205,214` — all four dispatches build `EventInfo` without
`targetChecked`; no `check()`/toggle API exists. The driver
(js-driver/swiflow-driver.js:70-80) sends `targetChecked` on every event with a
checkable target, and `.checked(_:)`'s handler reads exactly that field — so
simulating a checkbox through the harness is a guaranteed silent no-op. Test authors
already route around it: `CheckedSelectionBindingTests.swift` hand-builds synthetic
`EventInfo(type: "change", targetChecked: true)` instead of using the harness.

### HIGH — `blur()` drops the target value the browser always sends *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-handler-seam-harness-fidelity.md]**
`TestRenderer.swift:205` — `EventInfo(type: "blur")`. The driver's `serializeEvent`
snapshots `target.value` for any value-bearing target, so a validate-on-blur handler
reading `info.targetValue` works in production but receives nil under test. (Click on
buttons/inputs similarly gets `targetValue: ""` from the driver, nil here.)

### HIGH — Nested re-render diverges from production while claiming faithfulness *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-handler-seam-harness-fidelity.md]**
`TestRenderer.swift:93-111` — a nested component's `@State` change diffs only
`node.componentBody`; production always re-renders from root
(SwiflowDOM/Renderer.swift:120-124). A parent whose body reads shared mutable state
refreshes in the browser but not in the harness. The adjacent comment cites the
production behavior and asserts "this keeps the TestRenderer faithful to it" —
a confident faithfulness claim attached to a divergence.

### MEDIUM
- **Split selector models in one API:** `TestHarness.swift:76-102` — `click` addresses
  by `(tag, text)`; `input`/`blur`/`change` by `(tag, index)` with `text: nil`
  hard-coded. You can click "Save" by label but must count inputs by position.
- **All interactions fail by silent no-op with three indistinguishable causes:**
  `TestRenderer.swift:184-188` — wrong tag, no text match, or handler-less element all
  degrade to nothing; no throwing variant, no `Issue.record`; first-match-no-handler
  no-ops even if a later match has one; no bubbling, unlike the browser.
- **TestNode omits `style`; rawHTML invisible to all queries:** `TestHarness.swift:5-14`
  exposes tag/text/attributes/properties only (`.style(...)` output unassertable);
  `.rawHTML` falls into `default:` in both `textContent` and `findElements` — silent
  blind spot, zero rawHTML coverage in the module's own tests.

### LOW
- **Placeholder-clock design:** `AsyncTestHarness.swift:30-36` — shared-client init
  stores a dead `ManualClock()` + `ownsClock` flag + three comment blocks explaining
  the dead object, instead of an optional; `advance(by:)`'s precondition papers over
  it at runtime.
- **`change()` has one user repo-wide; phase narration:** "Phase 20" / "Phase 13c" /
  "(spec §8.2, B1)" comments citing the agents' planning docs; `RerenderRelay:
  @unchecked Sendable` smuggling a weak ref, immediately re-anchored with
  `MainActor.assumeIsolated`.

### Strengths
- No sync/async copy-paste: `AsyncTestHarness` composes `TestHarness` and forwards
  8 one-liners.
- Query wiring coherent with production, not a parallel invention: `advance()`/`focus()`
  call exactly the two entry points production's BackgroundRevalidation drives;
  `settle()`'s fixed-point loop with `maxRounds` is genuinely well-reasoned.
- API is used, not speculative: find/findAll/click/input/exists/blur/settle/advance/
  focus all have 10-20 real consumers across Tests/.

**Stats:** 4/4 files read + VNode/DispatcherBridge/Renderer/driver cross-reads.
Unverifiable: nested-re-render divergence established by reading both renderers, not
a runtime repro.

---

## Unit 10 — Sources/SwiflowUI

**Health verdict:** Small, well-tested, idiomatically consistent foundation — the real
problems are an install-ordering footgun its own doc comment encourages, and modifiers
that emit token vars without guaranteeing the tokens exist.

### HIGH — `installBaseStyles()` "up front" advice silently breaks injection *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-invariant-holes.md]**
`Theme.swift:27-29` advertises: "also public so apps/tests can install deterministically
up front." But the emit sink is wired only inside `Swiflow.render`
(`SwiflowDOM.swift:72` → `CSSInjector.setup()`), and `StyleInjectionRegistry.swift:20-21`
warns: "ids recorded before the sink is set are not re-emitted retroactively." An app
following Theme.swift's advice records `swiflow-ui-base` against a nil sink — the base
sheet is never injected, every `var(--sw-space-*)` resolves to nothing, no diagnostic.
The hazard extends to init-time construction: `let root = factory()` (SwiflowDOM.swift:71)
runs one line before `CSSInjector.setup()` (:72). A siloed-task miss: the module's doc
comment contradicts the registry's documented constraint one dependency down.

### MEDIUM
- **`.padding`/`.gap` modifiers don't trigger base-style installation:**
  `Modifiers.swift:8` — no `ensureBaseStyles()` call (and can't have one: the extension
  isn't `@MainActor`). Theme.swift:38 claims the trigger is "called by every primitive
  constructor" — `div(...).padding(.md)` on a stack-free page emits
  `padding: var(--sw-space-md)` against a `:root` never installed. The injection
  contract covers half the public surface.
- **4 of 9 tokens are speculative — defined but unreachable from the Swift API:**
  `Theme.swift:19-22` defines `--sw-radius/--sw-accent/--sw-surface/--sw-text`;
  Tokens.swift exposes accessors only for the 5 spacing vars. `--sw-text` appears in
  exactly one file repo-wide; the comment "the rest is the forward contract that
  skinned components will read" is self-aware speculative scaffolding.

### LOW
- **Usage is demo-only:** the only consumers of VStack/HStack/padding are
  examples/SwiflowUIDemo and its byte-identical embedded template; none of the other
  6 examples use the module. Acceptable for the newest module, but currently the demo
  exists to justify the module rather than vice versa.

### Note (twist on the filed CSSInjector HMR issue)
Token-value edits in Theme.swift won't show on HMR swap (same id-based skip;
`CSSInjector.reset()` has zero callers outside tests) — strictly a sub-case of the
filed SwiflowDOM finding; SwiflowUI adds no new mechanism.

### Strengths
- Faithful to the core DSL idiom: variadic `Attribute...` + `@ChildrenBuilder`,
  lowering through `element()`/`applyAttributes`; last-write-wins verified by test;
  the Capitalized-vs-lowercase naming split is deliberate and documented.
- Test quality genuinely good for 157 lines: idempotency via the swappable emit sink,
  defaults, gap-omission, children preservation, attribute-override semantics;
  `@Suite(.serialized)` where global state is touched.
- No comment slop in-module: doc comments explain lowering decisions, not tasks.

**Stats:** 4/4 sources + 4/4 tests read, plus registry/injector/render-ordering and DSL
comparison reads. Tokens: 9 defined / 5 accessor-backed / 1 fully unused. Unverifiable:
finding 1 derived from code ordering + the registry's own doc, not a WASM run.

---

## Unit 11 — js-driver (swiflow-driver.js + swiflow-sw.js)

**Health verdict:** Unusually disciplined for AI-built code — coherent sections, a
defensible XSS story, real reconnect/backoff — but it ships one production-critical
service-worker design flaw (no update path → permanently stale deploys) and a
patch-application layer with inconsistent missing-node handling that can leave the
page half-patched with no signal outside dev mode.

### CRITICAL — Service worker has no update trigger; production users pinned to the first deploy forever *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-devloop-delivery-correctness.md]**
`swiflow-sw.js:71-92` + `swiflow-driver.js:40`. The manifest is read only in
`install`/`activate`; the fetch handler is caches-first
(`caches.match(event.request) ?? fetch(...)`). Asset URLs are unversioned and
identical across builds (`BuildCommand.writeManifest` emits `outputPrefix + "App.wasm"`
every build; only the sha256 changes). Since `swiflow-sw.js` itself is byte-identical
across app builds, the browser's SW update check never finds a new worker, `install`
never re-fires, the new manifest is never fetched, and `caches.match` serves the
first-ever-cached App.wasm/index.js on the unchanged URL — indefinitely. The
hash-versioned cache names and `cleanupStale` create the *appearance* of an
invalidation strategy that never executes after the first install. The empty
`message` handler ("Reserved for Track 3") means the page can't poke the SW to
re-check either.

### HIGH — Missing-node handling is mixed crash/silent; no per-patch isolation *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-devloop-delivery-correctness.md]**
`swiflow-driver.js:146-156` — structural ops dereference unconditionally
(`nodes.get(p.parent).appendChild(nodes.get(p.child))` → TypeError on a stale handle)
while `animateExit`/`destroyNode`/`removeHandler`/`setRawHTML` silently no-op.
`applyPatches` (:339-343) has no per-patch try/catch, so one bad handle aborts the
rest of the batch mid-frame — half-patched DOM. Dev mode catches it via the RAF shim
and shows the overlay; production does not (next finding): the same differ bug crashes
visibly in dev and corrupts silently in prod.

### HIGH — Error overlay + RAF try/catch exist only behind `SWIFLOW_DEV` *(verified)* **[FIXED — see docs/superpowers/plans/2026-06-10-devloop-delivery-correctness.md]**
`swiflow-driver.js:386-470` are dev-gated; the production boot path's only failure
signal is `console.warn("swiflow: WASM init failed", e)` (:642) — a warn, not error.
A production render exception or init failure leaves a frozen/blank page with zero
user-visible signal and the progress attribute stuck mid-value.

### MEDIUM
- **`hmrSwap` has no reentrancy guard:** :511-562 — fired from `ws.onmessage` without
  awaiting; a second swap mid-swap (easy given the dev server's unconditional
  broadcasts, filed under SwiflowCLI) runs concurrent snapshot/clear/import — both
  modules can mount and dispatch interleaved. **[FIXED — see docs/superpowers/plans/2026-06-10-devloop-delivery-correctness.md]**
- **`animateExit`'s deferred `nodes.delete` races handle reuse:** :129-142 — the
  setTimeout deletes by handle up to durationMs later; if Swift reissues that handle
  first, the timer evicts the new node (then structural ops hit the crash path).
  Handle-reuse behavior is unverifiable from the JS silo; the assumption is unstated.
- **Dead catch around `fetchWithProgress`:** :629-634 — the function is async, so the
  `catch` (and its advertised "falling back to default init") is unreachable; a
  never-re-checked guard. **[FIXED — see docs/superpowers/plans/2026-06-10-devloop-delivery-correctness.md]**
- **Riskiest rewritten logic untested:** `destroyNode`'s numeric-prefix
  listener-cleanup loop (:114-125, rewritten per its own comment to fix a
  `startsWith` bug) has zero coverage; also untested: HMR map-clearing, reload
  fallback, double-swap.

### LOW
- Changelog narration in comments (:105-113 "Previously this case only deleted… and
  falsified the comment that claimed…"); vestigial no-op `registerDispatcher`
  citing "Task 6"; sw.js citing "Track 3".
- `hmrSwap` clears `nodes` and `listeners` but not `mountedRoots` — one of three
  module-level maps exempt from the reset (functionally harmless today).
- `__bootForTest` is a pure alias of `__boot` — redundant test seam.
- WASM path is a named constant; the sibling index.js path is an inline literal.

### Strengths
- Deliberate XSS containment: all unescaped-HTML writes funnel through one
  `parseRawHTML` helper; `setProperty` actively throws on `innerHTML`; the
  grep-auditability claims in comments are true.
- WebSocket reconnect done right: exponential backoff 250ms→5s cap, reset on open —
  the page reattaches after a dev-server restart.
- Genuinely sharp edge-case handling: numeric-prefix handle parsing, `removeProperty`
  for CSS custom properties, self-correcting duplicate handler detach,
  reader-cancel-on-error in fetchWithProgress.

**Stats:** 1,671 lines read (driver 645, sw 108, 8 test files 918) + the CLI
manifest-writer. All 33 jsdom tests pass (required `npm install`; node_modules was
absent). Coverage: 15 of 19 opcodes tested; gaps concentrate exactly on the risky
paths (destroyNode cleanup, HMR failure/reentrancy, mid-batch failure, prod boot).

---

# Synthesis

## The five systemic themes

1. **The harness lies (test-vs-production fidelity).** TestRenderer skips lifecycle
   (`onAppear` never fires), omits event fields the driver always sends
   (`targetChecked`, blur's `targetValue`), re-renders narrower than production, and
   silently no-ops on selector misses — while TestingModifiers duplicates the public
   event API against a different ambient with opposite failure semantics. Components
   can pass their tests and fail in the browser, which is the worst property a
   framework's own harness can have. Root cause is architectural and fixable in one
   move: lift the handler-registry ambient into core (the pattern already exists three
   times: `RenderObserverBox`, `SwiflowTaskRuntime.currentScope`, `AmbientEnvironment`).

2. **Dev-time machinery without an ownership story.** HMR loses multi-root state,
   serves stale CSS, has no reentrancy guard; the dev server can't trigger a plain
   reload; the service worker can never update a production deploy; dev surfaces ship
   ungated in the size-optimized release wasm. Each phase added a capability; no phase
   owned update/teardown/concurrency.

3. **Completed-phase scar tissue.** Dead dual-mode (`viewProducer`/`rerender`), dead
   facade (`HTTP`), dead branch (`MacroState`), production-dead duplicate
   (`applyRestore`), write-only plumbing (`valuesEqual`), and ~50 phase/task-narration
   comments — several actively false ("Filled in by later tasks." above implemented
   code; "set exactly once" on per-render mutations; a faithfulness claim on a
   divergence).

4. **Documented invariants without enforcement.** The URLSanitizer "every URL passes
   through sanitize" invariant has a public bypass; body-purity is violated by core's
   own `Field`; the CI Foundation-guard covers 3 of 6 WASM modules; patch-ordering
   contracts live only in comments (TestRenderer discards the patch stream that could
   verify them).

5. **Boundary asymmetries.** Path params undecoded while query params get a deluxe
   decoder; history mode loses queries where hash mode doesn't; Link hrefs ignore the
   routing mode; `installBaseStyles()`'s advice contradicts the registry's documented
   sink-ordering constraint one dependency down.

## Prioritized recommendations

1. **Fix the service-worker update path (the one Critical).** Version the SW file per
   build (embed the manifest hash into swiflow-sw.js at build time) or fetch the
   manifest network-first in the fetch handler. Until then, every production deploy
   behind the SW is permanently stale for returning visitors.
2. **Lift the handler registry into a core ambient seam.** Deletes TestingModifiers,
   unifies `.on`, lets Link use the framework's own event system, and makes
   `.value/.checked/.selection/.ref` testable — one fix, four filed findings.
3. **Make the harness honest:** fire lifecycle hooks, send driver-shaped event
   payloads (targetChecked, blur/click targetValue), re-render from root, and make
   interaction misses loud (throw or `Issue.record`).
4. **Gate dev surfaces behind a compile-time flag** (`-D SWIFLOW_DEV` in dev builds;
   release gets dead-stripped DevAPI/HMR) — bundle size and the snapshot-exfiltration
   surface in one move.
5. **Dev-loop correctness batch:** dispatch reload-vs-hmr-swap per file type; remove
   stale `<style id="swiflow-*">` on swap; add an hmrSwap in-flight guard; per-patch
   try/catch in applyPatches with a prod-visible error signal; make `doctor` probe
   what `build` requires.
6. **Close the invariant holes:** route postfix `.attr`/`.data` through URLSanitizer;
   extend the CI Foundation grep to all six WASM modules; add query-cache eviction
   (zero-observer GC with a gcTime); decide history-mode's query story and Link's
   mode-aware hrefs.
7. **Slop sweep (mechanical, low-risk):** delete the dead code (viewProducer mode +
   rerender, HTTP facade, MacroState branch, applyRestore, valuesEqual, pickDefault,
   transition/animation/cssVar modifiers), fix the ~10 actively-false comments, strip
   phase/task citations, collapse the Build/Dev preflight and the supersede ritual.

## What's genuinely healthy (keep doing this)

- The 19-opcode patch contract: documented identically on both sides, field-for-field
  exact, with defense-in-depth (innerHTML refusal, self-correcting addHandler) and
  true grep-auditability claims.
- Layering: zero dependency-graph deviations, zero CLI↔runtime contamination, zero
  `@testable` leaks, genuinely Foundation-free WASM runtime, zero rename residue from
  SwiflowWeb→SwiflowDOM / SwiflowHTTP→SwiflowFetcher in code.
- Access-control discipline: ~114 `package` declarations in core keep the wire format
  out of user API; SwiflowRouter and SwiflowQuery tier their surfaces deliberately.
- Pockets of excellent engineering: the LIS keyed diff, the generation-guarded query
  supersede mechanism, the hand-rolled percent-decoder and RFC 8259 escaper, the
  ProcessRunner pipe-drain, WebSocket reconnect backoff, and post-mortems encoded as
  invariant comments (`Event.domName`).
- Testability seams built on purpose: ProcessRunner protocol + pure argument
  composers, the swappable style-injection sink, ManualClock, `settle()`'s fixed-point
  loop.

## Methodology

11 read-only audit agents (9 module silos + js-driver + one cross-module architect),
dispatched sequentially, each briefed with the dependency map, generated-file
exclusions, and a quoted-evidence requirement. Every Critical/High finding (20) was
re-verified at source by the orchestrating reviewer before inclusion; one agent ran
the jsdom suite (33/33 passing). Severity counts: 1 Critical, 19 High, 40 Medium,
42 Low across ~16.7k lines of Swift/JS. Out of scope: fixes, spec-drift vs
docs/superpowers, Tests/ quality (noted only where coverage gaps bear on findings).
