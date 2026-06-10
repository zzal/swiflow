# Quality Audit — 2026-06-10 (IN PROGRESS)

> **Status: 2 of 11 units complete.** Audit of all 9 `Sources/` modules (each in silo),
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
| Swiflow (core) | ✅ audited | 0 | 1 | 4 | 5 |
| Cross-module architecture | ✅ audited | 0 | 2 | 3 | 5 |
| SwiflowCLI | pending | | | | |
| SwiflowDOM | pending | | | | |
| SwiflowFetcher | pending | | | | |
| SwiflowMacrosPlugin | pending | | | | |
| SwiflowQuery | pending | | | | |
| SwiflowRouter | pending | | | | |
| SwiflowTesting | pending | | | | |
| SwiflowUI | pending | | | | |
| js-driver | pending | | | | |

**Emerging theme:** modules are strong in silo; the slop concentrates at the
renderer/testing boundary — specifically the absence of a core ambient seam for the
handler registry, from which several findings cascade.

---

## Unit 1 — Sources/Swiflow (core)

**Health verdict:** Genuinely well-architected — disciplined `package`-scoped access
control around the patch pipeline, correct LIS-based keyed diff, invariant-dense
docs — but carries one security-invariant hole and a cluster of stale phase-narrative
comments concentrated in the riskiest file.

### HIGH — URLSanitizer bypass via postfix modifiers *(verified)*
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

### HIGH — Public event-modifier API implemented twice with divergent semantics *(verified)*
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

### HIGH — TestRenderer skips production lifecycle *(verified)*
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
module" comment was already not honored for three modules.

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
