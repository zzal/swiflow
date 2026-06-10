# SwiflowDOM Final Highs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clear the 3 remaining audit HIGHs (all in SwiflowDOM) from `docs/reviews/2026-06-10-quality-audit.md` — multi-root HMR state loss, the dead Phase-2a dual-mode, and dev/HMR machinery shipping in release wasm.

**Architecture:** Three independent fixes. (1) Delete the never-called `viewProducer` Renderer mode, collapsing the dual-init to the single Component-root path. (2) Make HMR multi-root-correct: a host-tested core aggregation helper snapshots all roots' trees, and the pending-restore index is cached (not consumed-once) so every root's first render reads it. (3) Add a compile-time `SWIFLOW_RELEASE` define on the `swiflow build` release path and `#if !SWIFLOW_RELEASE`-gate the DevAPI + HMR machinery so the linker dead-strips it from production wasm.

**Tech Stack:** Swift 6 / SwiftPM. Most of SwiflowDOM is `#if canImport(JavaScriptKit)`-gated → NOT compiled on host; those edits are verified by host `swift build` (compiles the empty stub), the host suite staying green (shared core), and the wasm build. The two genuinely host-testable seams — `HMRWalker.snapshot(fromRoots:)` in core and `BuildInvocation.composeArguments()` in the CLI — get real TDD tests.

**Audit findings cleared:** Unit 4 HIGH (multi-root HMR last-writer-wins), Unit 4 HIGH (dead Phase-2a dual-mode), Unit 4 HIGH (dev/HMR in release wasm). Also Unit 4 MEDIUM "stale, contradictory multi-root docs" and "DevAPI re-install no-op" partially, and the Unit 1/core LOW stale "Phase 2a" comments — incidental.

---

## Environment notes (read first)

- Swift tests: ALWAYS `env -u SWIFLOW_SOURCE swift test`. Suite is **796 tests / 181 suites green** on `main` @ `38b4968`.
- Branch: `git checkout -b feat/swiflowdom-final-highs` from `main`.
- **No js-driver edits** in this plan → no embed/codegen steps.
- **JSKit-gating reality:** `Sources/SwiflowDOM/*` compiles to an empty module on host (macOS/Linux dev machines) because of `#if canImport(JavaScriptKit)`. So edits there cannot break host tests and cannot be host-unit-tested. After any SwiflowDOM edit, the verification is: (a) `env -u SWIFLOW_SOURCE swift build` succeeds (host stub still compiles); (b) `env -u SWIFLOW_SOURCE swift test` stays green (proves shared core untouched); (c) the manual wasm build in the end-to-end section. Do NOT fabricate host tests for JSKit-gated code.
- Tasks are independent in effect but ORDER MATTERS for clean diffs: Task 1 simplifies Renderer; Task 2 finalizes the HMR logic in SwiflowDOM.swift/HMRBridge; Task 3 wraps the now-final DevAPI + HMR in `#if` gates. Execute 1 → 2 → 3 → 4.

## File structure

| File | Action | Responsibility |
|---|---|---|
| `Sources/SwiflowDOM/Renderer.swift` | modify | drop the `viewProducer` mode; `rootComponent` non-optional; delete the precondition arm + stale Phase-2a docs |
| `Sources/Swiflow/Reactivity/HMR.swift` | modify | add host-tested `HMRWalker.snapshot(fromRoots:)` aggregation helper |
| `Sources/SwiflowDOM/HMR/HMRBridge.swift` | modify | exporter aggregates all roots; pending index cached-not-consumed (`pendingRestoreIndex()`) |
| `Sources/SwiflowDOM/SwiflowDOM.swift` | modify | install one aggregating exporter; consult cached restore index per root; gate HMR+DevAPI in release |
| `Sources/SwiflowDOM/DevAPI.swift` | modify | `#if !SWIFLOW_RELEASE` gate with an empty `installAll()` stub in release |
| `Sources/SwiflowCLI/Commands/BuildCommand.swift` | modify | release `composeArguments()` adds `-Xswiftc -DSWIFLOW_RELEASE` |
| Tests (core HMR aggregation, build args) | create/modify | the two host-testable seams |
| `CHANGELOG.md`, `docs/reviews/2026-06-10-quality-audit.md` | modify | bookkeeping |

---

### Task 1: Delete the dead Phase-2a `viewProducer` Renderer mode

`Renderer` has two inits: `init(viewProducer:selector:)` (Phase 2a) and `init(rootComponent:selector:)` (Phase 3). The `viewProducer` init has **zero callers** anywhere (grep `viewProducer` across Sources/Tests/examples → only Renderer.swift's own definition). It forces `rootComponent` to be Optional, props up a `preconditionFailure` else-arm in `renderOnce()`, and litters the file with two-mode narration and a stale "Multiple roots out of scope for Phase 2a / Phase 3 v1" comment. Removing it is pure dead-code deletion. (`Swiflow.rerender()` STAYS — it iterates `renderers` calling `renderOnce()`, works fine for component roots, and is independent of `viewProducer`.)

**Files:**
- Modify: `Sources/SwiflowDOM/Renderer.swift`

**Verification note:** `Renderer` is JSKit-gated (no host tests, not host-compiled). This task is verified by grep + host build + suite-green + the wasm build. No unit test to write — do not fabricate one.

- [ ] **Step 1: Confirm zero callers**

Run:
```bash
grep -rn "viewProducer" Sources/ Tests/ examples/
```
Expected: matches ONLY inside `Sources/SwiflowDOM/Renderer.swift` (the definition + its own doc/comments). If any OTHER file references `viewProducer`, STOP and report — the mode is not actually dead.

- [ ] **Step 2: Remove the stored property and its init**

In `Sources/SwiflowDOM/Renderer.swift`:

Delete the property (currently lines ~27-30):
```swift
    /// Non-nil only for the Phase 2a (viewProducer) init. Exactly one of
    /// `viewProducer` and `rootComponent` is non-nil at any given time.
    let viewProducer: (() -> VNode)?
```

Change `rootComponent` from optional to non-optional:
```swift
    /// The live Component instance this renderer renders.
    let rootComponent: AnyComponent
```

Delete the entire Phase-2a init (currently lines ~92-101):
```swift
    /// Phase 2a init: ...
    init(viewProducer: @escaping () -> VNode, selector: String, handles: HandleAllocator = sharedHandleAllocator) {
        self.viewProducer = viewProducer
        self.rootComponent = nil
        ...
    }
```

In the surviving `init(rootComponent:selector:handles:)`, delete the now-invalid `self.viewProducer = nil` line.

- [ ] **Step 3: Collapse the render branch**

In `renderOnce()`, replace the whole `nextVNode` production block — currently:
```swift
        let nextVNode: VNode

        if let producer = viewProducer {
            // Phase 2a: evaluate the producer closure.
            nextVNode = producer()
        } else if let root = rootComponent {
            // Phase 3: wrap the existing component instance ...
            let desc = ComponentDescription(
                typeID: root.typeID,
                key: nil,
                factory: { root }
            )
            nextVNode = .component(desc)
        } else {
            preconditionFailure(
                "Renderer has neither a viewProducer nor a rootComponent. ..."
            )
        }
```
with:
```swift
        // Wrap the live component instance in a VNode.component description
        // whose factory returns THE SAME instance rather than constructing a
        // fresh one. Critical for the diff's reuse arm: on first render
        // `desc.instantiate()` is called once in `mount()`, yielding the
        // already-live instance; on subsequent renders the same-typeID path
        // reuses the mount-tree node and calls `body` on the existing
        // instance — the factory is never called again.
        let root = rootComponent
        let nextVNode: VNode = .component(
            ComponentDescription(typeID: root.typeID, key: nil, factory: { root })
        )
```

- [ ] **Step 4: Fix the stale comments**

In the `mount` section, the comment "For a viewProducer tree, domHandle == handle (no anchor layer), so this is correct in both modes." (~line 236) — replace with: "The mount tree root is the component anchor whose `handle` is structural-only; `domHandle` is the body's real DOM handle, which is what the driver attaches at `selector`."

In the type's header doc (~lines 7-23), delete the "Two initialization modes" section and the Phase 2a bullet, and delete the stale sentence "Multiple roots are out of scope for Phase 2a / Phase 3 v1." Replace the header with a concise version:
```swift
/// Owns Swiflow's per-application render state in a WASM/browser environment.
///
/// One Renderer is created per mounted root by `Swiflow.render(into:_:)` and
/// stored in the module-global `renderers` dict keyed by selector. It wraps a
/// live Component instance and wires a `RAFScheduler` so `@State` mutations
/// schedule re-renders via `requestAnimationFrame` automatically.
```
Also fix the `_schedulerBox` doc that says "Phase 2a init leaves this at its default `nil`. Phase 3 init assigns..." — simplify to: "Assigned the `RAFScheduler` in `init` after `self` is fully initialised (the scheduler closure needs a weak `self`, which can only be formed once all stored properties are set)."

- [ ] **Step 5: Verify build + suite + grep**

Run:
```bash
env -u SWIFLOW_SOURCE swift build
grep -rn "viewProducer" Sources/ Tests/ examples/   # expect: zero matches
env -u SWIFLOW_SOURCE swift test 2>&1 | tail -2      # 796 green (shared core untouched)
```
Expected: build succeeds; zero `viewProducer` matches; suite green.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(dom): delete the dead Phase-2a viewProducer Renderer mode

Zero callers anywhere. Collapses the dual-init to the single
Component-root path: rootComponent is non-optional, the preconditionFailure
arm and two-mode narration are gone, and the stale 'multiple roots out of
scope' comment is removed. Clears audit HIGH: 'dead Phase-2a dual-mode
permeates Renderer'."
```

---

### Task 2: Multi-root-correct HMR

Two verified bugs (audit Unit 4 HIGH): (a) `SwiflowDOM.render(into:)` calls `HMRBridge.installSnapshotExporter { [weak renderer] in renderer?.mountTree }` on every render, so the single global `window.__swiflow.hmrSnapshot` closes over only the **newest** root — a two-root app snapshots only the last; (b) `HMRBridge.takePendingSnapshot()` reads `window.__swiflowPendingSnapshot` and nils it on **first** call, so the first root's `render(into:)` consumes the whole index and later roots restore nothing. Fix: aggregate the export across all roots (via a host-tested core helper), and cache the parsed pending index so every root's first render reads it.

**Scope note:** snapshot identity is `(path, typeName, key)` where `path` is relative to each root's own tree. Distinct component types per selector never collide. Mounting the **identical** component type with identical internal structure at two selectors and expecting HMR to keep them separate is a documented v1 limitation (out of scope) — note it in the code, don't solve it.

**Files:**
- Modify: `Sources/Swiflow/Reactivity/HMR.swift` (core helper — host-tested), `Sources/SwiflowDOM/HMR/HMRBridge.swift`, `Sources/SwiflowDOM/SwiflowDOM.swift`
- Test: `Tests/SwiflowTests/Reactivity/HMRMultiRootTests.swift` (create — core helper only)

- [ ] **Step 1: Write the failing core-helper test**

`HMRWalker` is in core (`Sources/Swiflow/Reactivity/HMR.swift`), host-testable. Read the existing HMR tests (`grep -rln "HMRWalker" Tests/`) to learn how the suite builds a `MountNode` tree with components carrying `@State` and calls `HMRWalker.snapshot(from:)`. Mirror those helpers.

```swift
// Tests/SwiflowTests/Reactivity/HMRMultiRootTests.swift
import Testing
@testable import Swiflow

@Suite
@MainActor
struct HMRMultiRootTests {

    /// The multi-root aggregator must equal the concatenation of each root's
    /// individual snapshot — no root is dropped (the audit's last-writer-wins
    /// export bug), order is root-by-root.
    @Test func snapshotFromRootsConcatenatesPerRootSnapshots() {
        // Build two independent mount trees, each with at least one @State
        // component, the way the existing HMRWalker tests do. Call them
        // treeA and treeB.
        // let treeA = ... ; let treeB = ...

        // let individual = HMRWalker.snapshot(from: treeA)
        //                 + HMRWalker.snapshot(from: treeB)
        // let aggregated = HMRWalker.snapshot(fromRoots: [treeA, treeB])

        // #expect(aggregated.count == individual.count)
        // #expect(aggregated.map(\.path) == individual.map(\.path))
        // #expect(!aggregated.isEmpty)   // both roots contributed
    }

    @Test func snapshotFromEmptyRootsIsEmpty() {
        #expect(HMRWalker.snapshot(fromRoots: []).isEmpty)
    }
}
```

Write the first test as REAL code using the suite's tree-building helpers (the commented lines are the contract). If building a `MountNode` with `@State` in a test is non-trivial, copy the exact setup from the existing `HMRWalker.snapshot(from:)` test and use TWO such trees.

- [ ] **Step 2: Run to verify failure**

Run: `env -u SWIFLOW_SOURCE swift test --filter HMRMultiRootTests`
Expected: compile failure — `HMRWalker.snapshot(fromRoots:)` doesn't exist.

- [ ] **Step 3: Add the core aggregation helper**

In `Sources/Swiflow/Reactivity/HMR.swift`, inside `package enum HMRWalker`, next to the existing `snapshot(from:)`:

```swift
    /// Aggregates snapshots across multiple render roots, in order. The HMR
    /// exporter walks every live root so a multi-root app preserves all roots'
    /// `@State` across a hot-swap (not just the last-mounted root).
    ///
    /// v1 limitation: snapshot identity is `(path, typeName, key)` relative to
    /// each root's own tree, so mounting the identical component type with
    /// identical structure at two selectors can collide. Distinct component
    /// types per selector — the normal case — never collide.
    package static func snapshot(fromRoots roots: [MountNode]) -> [ComponentSnapshot] {
        roots.flatMap { snapshot(from: $0) }
    }
```

- [ ] **Step 4: Run the core test**

Run: `env -u SWIFLOW_SOURCE swift test --filter HMRMultiRootTests` → both tests pass.

- [ ] **Step 5: Aggregate the exporter (JSKit-gated)**

In `Sources/SwiflowDOM/HMR/HMRBridge.swift`, change `installSnapshotExporter` to take a roots provider:

```swift
    /// Install `window.__swiflow.hmrSnapshot = () => [...]`. The exported
    /// function walks EVERY live root's mount tree at call time (via the
    /// provider), aggregates with `HMRWalker.snapshot(fromRoots:)`, and
    /// JS-encodes the result. Installing once over the global root set (rather
    /// than per-render over a single root) is what makes multi-root HMR keep
    /// every root's state instead of only the last-mounted one.
    @MainActor
    package static func installSnapshotExporter(rootsProvider: @escaping @MainActor () -> [MountNode]) {
        let snapshotFn = JSClosure { _ in
            let snaps = HMRWalker.snapshot(fromRoots: rootsProvider())
            return encodeToJS(snaps)
        }
        // … keep the existing window.__swiflow namespace-create + ns.hmrSnapshot
        //   assignment + snapshotClosure retention block byte-identical …
    }
```
(Only the signature + the first three lines of the body change — the namespace plumbing and `snapshotClosure = snapshotFn` retention stay exactly as they are. The old `treeProvider` returned `MountNode?`; the new `rootsProvider` returns `[MountNode]`.)

- [ ] **Step 6: Cache the pending restore index (JSKit-gated)**

In `Sources/SwiflowDOM/HMR/HMRBridge.swift`, add module statics and a cached accessor; rename the parse to private. Replace the `takePendingSnapshot()` public surface with:

```swift
    // MARK: - Pending snapshot consumer (JS → Swift), cached across roots

    /// Parsed pending-restore index for THIS module instance. A fresh module
    /// after a hot-swap starts with `pendingRead == false`, so the first
    /// `pendingRestoreIndex()` re-parses `window.__swiflowPendingSnapshot`.
    nonisolated(unsafe) private static var pendingIndex: [SnapshotKey: [String: Any]]?
    nonisolated(unsafe) private static var pendingRead = false

    /// The restore index every root's first render consults. Parsed exactly
    /// once per module instance (reading + nil-ing the JS global on the first
    /// call), then CACHED — so a second/third root's `render(into:)` still sees
    /// the index instead of nil. Returns nil when no swap is pending.
    @MainActor
    package static func pendingRestoreIndex() -> [SnapshotKey: [String: Any]]? {
        if !pendingRead {
            pendingRead = true
            pendingIndex = parsePendingSnapshot()
        }
        return pendingIndex
    }
```

Rename the EXISTING `takePendingSnapshot()` method to `private static func parsePendingSnapshot()` — its body (read JS global, nil it, decode into the index) stays byte-identical; only the name + access level change. (Grep `takePendingSnapshot` across Sources/ to confirm the only caller is `SwiflowDOM.swift`, updated next.)

- [ ] **Step 7: Update render(into:) to install-once + cache-consult (JSKit-gated)**

In `Sources/SwiflowDOM/SwiflowDOM.swift` `render(into:)`, replace the pending-snapshot block — currently:
```swift
        let pendingIndex = HMRBridge.takePendingSnapshot()
        if let index = pendingIndex {
            HMRRestoreInstall.stateFor = { path, typeName, key in
                let lookupKey = SnapshotKey(path: path, typeName: typeName, key: key)
                return index[lookupKey]
            }
        }

        let root = factory()
        CSSInjector.setup()
        let renderer = Renderer(rootComponent: AnyComponent(root), selector: selector)
        DispatcherBridge.install()
        RefResolverInstall.resolver = { handle in … }

        HMRBridge.installSnapshotExporter { [weak renderer] in
            renderer?.mountTree
        }

        renderer.renderOnce()

        if pendingIndex != nil {
            HMRRestoreInstall.stateFor = nil
        }

        renderers[selector] = renderer
        DevAPI.installAll()
```
with:
```swift
        // Pending-restore index is cached in HMRBridge so EVERY root's first
        // render reads it (not just the first-mounted root). Install the
        // restore hook for the duration of this root's first render only.
        let pendingIndex = HMRBridge.pendingRestoreIndex()
        if let index = pendingIndex {
            HMRRestoreInstall.stateFor = { path, typeName, key in
                index[SnapshotKey(path: path, typeName: typeName, key: key)]
            }
        }

        let root = factory()
        CSSInjector.setup()
        let renderer = Renderer(rootComponent: AnyComponent(root), selector: selector)
        DispatcherBridge.install()
        RefResolverInstall.resolver = { handle in
            guard let swiflowGlobal = JSObject.global.swiflow.object else { return nil }
            let result = swiflowGlobal.nodeForHandle!(JSValue.number(Double(handle)))
            return result.object
        }

        renderers[selector] = renderer

        // One aggregating exporter over the global root set — re-installed each
        // render (idempotent; it closes over `renderers`, not a single root) so
        // every live root contributes to a hot-swap snapshot.
        HMRBridge.installSnapshotExporter { renderers.values.compactMap(\.mountTree) }

        renderer.renderOnce()

        if pendingIndex != nil {
            HMRRestoreInstall.stateFor = nil
        }

        DevAPI.installAll()
```
(Note: `renderers[selector] = renderer` MOVED above the exporter install so the just-mounted root is included in the `renderers` the exporter closes over. The `RefResolverInstall.resolver` block is unchanged — shown in full only so you place the moved lines correctly.)

- [ ] **Step 8: Verify build + suite**

Run:
```bash
env -u SWIFLOW_SOURCE swift build
grep -rn "takePendingSnapshot" Sources/   # expect: zero (renamed to parsePendingSnapshot, private)
env -u SWIFLOW_SOURCE swift test 2>&1 | tail -2   # 798 green
```
Expected: build succeeds; no stray `takePendingSnapshot`; suite green (the 2 new core tests included).

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "fix(dom): multi-root-correct HMR snapshot export + restore

The exporter now aggregates every live root's tree (core helper
HMRWalker.snapshot(fromRoots:)) instead of closing over the last-mounted
root, and the pending-restore index is cached per module instance so each
root's first render reads it instead of the first root consuming it.
Clears audit HIGH: 'multi-root HMR loses state: snapshot exporter is
last-writer-wins'."
```

---

### Task 3: Gate dev/HMR machinery out of release wasm

`DevAPI.installAll()` is called unconditionally from render/unmount and gated only at runtime (`SWIFLOW_DEV`); the HMR snapshot/restore has no compile gate. Release builds pass no `-D` define, so none of it dead-strips — production wasm ships a working `window.__swiflow.hmrSnapshot` (state-exfiltration surface) and the DevAPI/DevAPIFormatter/HMR-walker weight. Fix: `swiflow build`'s release path defines `SWIFLOW_RELEASE`, and the dev/HMR machinery is wrapped in `#if !SWIFLOW_RELEASE` so the linker strips it. The runtime `SWIFLOW_DEV` check stays as the second layer for non-release (plain `swift build` debug) builds.

**Files:**
- Modify: `Sources/SwiflowCLI/Commands/BuildCommand.swift` (release args — host-tested), `Sources/SwiflowDOM/DevAPI.swift`, `Sources/SwiflowDOM/SwiflowDOM.swift`
- Test: `Tests/SwiflowCLITests/BuildInvocationTests.swift` (extend; find the existing file that tests `composeArguments()` — `grep -rln "composeArguments\|BuildInvocation" Tests/`)

- [ ] **Step 1: Write the failing build-args test**

Find the existing `composeArguments()` test file and ADD (matching its setup for constructing a `BuildInvocation` in `.release` vs `.dev`):

```swift
    @Test func releaseBuildDefinesSwiflowRelease() {
        let args = <BuildInvocation in .release>.composeArguments()
        // The define must be present as an -Xswiftc pair so it reaches every
        // target's swiftc (including SwiflowDOM), enabling #if !SWIFLOW_RELEASE
        // dead-stripping of the dev/HMR machinery.
        #expect(adjacentPair(args, "-Xswiftc", "-DSWIFLOW_RELEASE"))
    }

    @Test func devBuildDoesNotDefineSwiflowRelease() {
        let args = <BuildInvocation in .dev>.composeArguments()
        #expect(!args.contains("-DSWIFLOW_RELEASE"))
    }
```

where `adjacentPair(_:_:_:)` is a helper checking the two strings appear consecutively (write it inline, or assert `args.contains("-DSWIFLOW_RELEASE")` plus that the element before it is `-Xswiftc` by index). Match how the existing tests construct `.release`/`.dev` invocations (read them first — there is already a release-flag test for `-Osize`).

- [ ] **Step 2: Run to verify failure**

Run: `env -u SWIFLOW_SOURCE swift test --filter BuildInvocation`
Expected: `releaseBuildDefinesSwiflowRelease` FAILS (no `-DSWIFLOW_RELEASE` yet).

- [ ] **Step 3: Add the release define**

In `Sources/SwiflowCLI/Commands/BuildCommand.swift`, in `composeArguments()`'s `.release` branch, append the define to `prePluginArgs` alongside the existing `-Osize`/`-gnone`/`-disable-reflection-metadata`:

```swift
            prePluginArgs.append(contentsOf: [
                "-Xswiftc", "-Osize",
                "-Xswiftc", "-gnone",
                "-Xswiftc", "-disable-reflection-metadata",
                // Compile-time strip dev/HMR machinery: SwiflowDOM gates DevAPI
                // and the HMR snapshot/restore behind `#if !SWIFLOW_RELEASE`,
                // so this define lets the linker dead-strip them (and the
                // core DevAPIFormatter they reference) from the release wasm.
                "-Xswiftc", "-DSWIFLOW_RELEASE",
            ])
```

- [ ] **Step 4: Run the build-args test**

Run: `env -u SWIFLOW_SOURCE swift test --filter BuildInvocation` → both new tests pass.

- [ ] **Step 5: Gate DevAPI (JSKit-gated)**

In `Sources/SwiflowDOM/DevAPI.swift`, wrap so `installAll()` becomes a no-op in release while call sites stay clean. Change the structure to:

```swift
#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

enum DevAPI {
#if !SWIFLOW_RELEASE
    // … ALL the existing closure-retention statics + the full installAll()
    //   body byte-identical …
#else
    /// Release builds strip the dev inspection API entirely; this stub keeps
    /// the `DevAPI.installAll()` call sites compiling. The linker dead-strips
    /// the call and the (now-unreferenced) core DevAPIFormatter.
    @MainActor static func installAll() {}
#endif
}

#endif
```
(Move the existing `treeClosure`/`stateClosure`/`handlersClosure`/`perfClosure` statics and the whole `installAll()` + `encodeStateForDisplay` into the `#if !SWIFLOW_RELEASE` arm; the `#else` arm has only the empty `installAll()`.)

- [ ] **Step 6: Gate the HMR machinery in render(into:) (JSKit-gated)**

In `Sources/SwiflowDOM/SwiflowDOM.swift` `render(into:)`, wrap the pending-restore consult and the exporter install (the Task-2 final shape) in `#if !SWIFLOW_RELEASE`. The structure becomes:

```swift
        let root = factory()
        CSSInjector.setup()
        let renderer = Renderer(rootComponent: AnyComponent(root), selector: selector)
        DispatcherBridge.install()
        RefResolverInstall.resolver = { handle in
            guard let swiflowGlobal = JSObject.global.swiflow.object else { return nil }
            let result = swiflowGlobal.nodeForHandle!(JSValue.number(Double(handle)))
            return result.object
        }
        renderers[selector] = renderer

#if !SWIFLOW_RELEASE
        // HMR (snapshot export + state restore) is a dev-only feature — there
        // is no hot-swap in a release build. Stripped at compile time.
        let pendingIndex = HMRBridge.pendingRestoreIndex()
        if let index = pendingIndex {
            HMRRestoreInstall.stateFor = { path, typeName, key in
                index[SnapshotKey(path: path, typeName: typeName, key: key)]
            }
        }
        HMRBridge.installSnapshotExporter { renderers.values.compactMap(\.mountTree) }
#endif

        renderer.renderOnce()

#if !SWIFLOW_RELEASE
        if pendingIndex != nil {
            HMRRestoreInstall.stateFor = nil
        }
#endif

        DevAPI.installAll()
```
(The executor-install guard, the `precondition` on duplicate selector, and `factory()` stay OUTSIDE the gate — those are not dev-only. `DevAPI.installAll()` stays unconditional; its release stub no-ops.)

- [ ] **Step 7: Verify host build (both configs compile) + suite**

The host build compiles WITHOUT `SWIFLOW_RELEASE` (so the `#if !SWIFLOW_RELEASE` arm is active) — confirms the dev path compiles. To also confirm the release arm compiles, do a one-off define-build:
```bash
env -u SWIFLOW_SOURCE swift build                                   # dev arm compiles
env -u SWIFLOW_SOURCE swift build -Xswiftc -DSWIFLOW_RELEASE        # release arm compiles (stubs active)
env -u SWIFLOW_SOURCE swift test 2>&1 | tail -2                     # 800 green
```
Expected: BOTH builds succeed (proves both `#if` arms are well-formed), suite green. (SwiflowDOM is JSKit-gated so the `#if !SWIFLOW_RELEASE` arms inside it aren't actually compiled on host — but `DevAPI`/`SwiflowDOM.swift` are still parsed enough that a malformed `#if` would error; the define-build is cheap insurance.)

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "fix(dom): compile-time gate dev/HMR machinery out of release wasm

swiflow build's release path now defines SWIFLOW_RELEASE; DevAPI and the
HMR snapshot/restore are wrapped in #if !SWIFLOW_RELEASE so the linker
dead-strips them (and the core DevAPIFormatter they reference) from the
production bundle. Runtime SWIFLOW_DEV stays as the second layer for
non-release debug builds. Clears audit HIGH: 'dev/HMR machinery ships
active in release wasm'."
```

---

### Task 4: CHANGELOG + audit bookkeeping

**Files:**
- Modify: `CHANGELOG.md`, `docs/reviews/2026-06-10-quality-audit.md`

- [ ] **Step 1: CHANGELOG**

Append to the existing `## [Unreleased]` → `### Fixed` list (match formatting):

```markdown
- **Multi-root HMR:** a hot-swap now preserves `@State` across all mounted
  roots, not just the last-mounted one.
- **Release bundle:** the dev inspection API (`window.__swiflow`) and HMR
  snapshot/restore machinery are compile-time stripped from `swiflow build`
  output — smaller wasm, and no dev-only state-export surface in production.
```

And to `### Changed` (or `### Removed` if the file has one — check; create `### Removed` per Keep-a-Changelog if neither fits):

```markdown
- Removed the internal Phase-2a `viewProducer` Renderer mode (never part of
  the public API; no behavior change for apps).
```

- [ ] **Step 2: Audit annotations**

Append ` **[FIXED — see docs/superpowers/plans/2026-06-10-swiflowdom-final-highs.md]**` to these three Unit 4 headings (search each; report any mismatch):
1. `### HIGH — Multi-root HMR loses state: snapshot exporter is last-writer-wins *(verified)*`
2. `### HIGH — Dead "Phase 2a" dual-mode permeates Renderer *(verified)*`
3. `### HIGH — Dev/HMR machinery ships active in release wasm *(verified)*`

- [ ] **Step 3: Update the Running tally**

Read the current table. Update: `SwiflowDOM` High 3 → 0; Total High 3 → 0. After this, the Total Critical/High columns are both **0** — note that in the table's verdict line or just leave the numbers. Report the before/after you actually found.

- [ ] **Step 4: Final verification + commit**

```bash
env -u SWIFLOW_SOURCE swift test 2>&1 | tail -2   # full suite green
git add CHANGELOG.md docs/reviews/2026-06-10-quality-audit.md
git commit -m "docs: changelog + audit bookkeeping for SwiflowDOM final highs"
```

---

## Verification (end-to-end)

1. `env -u SWIFLOW_SOURCE swift test` — full host suite green (≈800; exact per new tests).
2. `grep -rn "viewProducer\|takePendingSnapshot" Sources/` — zero matches (both removed/renamed).
3. Both `#if` arms compile: `env -u SWIFLOW_SOURCE swift build` AND `env -u SWIFLOW_SOURCE swift build -Xswiftc -DSWIFLOW_RELEASE` both succeed.
4. Manual (requires wasm toolchain) — the real proof for the JSKit-gated changes:
   - `cd examples/TodoCRUD && swiflow build` — compiles SwiflowDOM with `-DSWIFLOW_RELEASE`; the produced wasm should NOT expose `window.__swiflow` (load the built page, check `typeof window.__swiflow.hmrSnapshot === "undefined"`). Compare bundle size against a pre-change `swiflow build` — expect a reduction (DevAPI/DevAPIFormatter/HMR walker stripped).
   - `swiflow dev` on an example: HMR still works (the `#if !SWIFLOW_RELEASE` arm is active in dev), `window.__swiflow.tree()` still responds.
   - Multi-root HMR: a two-root example (or hand-mount two roots) — edit a `.swift` file, confirm BOTH roots keep their `@State` after the swap. (No two-root example exists today; this is inspection + the core aggregation test.)

## Out of scope (deliberately)

- Same-component-type-at-two-selectors HMR key namespacing (documented v1 limitation in the core helper).
- The remaining SwiflowDOM MEDIUMs (DevAPI duplicates HMRBridge's encoder; DevAPI re-install allocation; RAFScheduler dirty-set/per-frame JSClosure; access-level overshoot) and LOWs.
- Removing `Swiflow.rerender()` (kept — it's valid public API for component roots, independent of the deleted viewProducer mode).
