# Scoped Re-render (Staged Fast-Path) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a single-component `@State` change re-render and diff only that component's subtree (not the whole tree from the root), cutting the virtualized-DataTable scroll latency from ~48ms toward ≤1 frame.

**Architecture:** A staged fast-path. All decision + execution logic lives in a new host-testable core file `Sources/Swiflow/Diff/ScopedRerender.swift`: a pure predicate `planRerender(root:dirtyIDs:)` returns `.scoped(anchor)` only for the safe single-dirty case and `.full` otherwise; `scopedRerender(anchor:…)` re-renders one subtree by reusing the existing `diff()` component-reuse arm rooted at the dirty anchor. The WASM-only `Renderer`/`RAFScheduler` get thin wiring that calls into that core. A complementary `DataTableBox.sortedIndices()` memo removes per-tick re-sorting in the surviving subtree.

**Tech Stack:** Swift 6.3, swift-testing (`import Testing`), SwiftPM. Core (`Swiflow`) and `SwiflowUI` compile + test on host (`swift test`). `SwiflowDOM` is WASM-only (`#if canImport(JavaScriptKit)`) and is verified by a wasm build of the demo + browser, not by `swift test`.

**Critical context for the implementer:**
- `diff(mounted:next:handles:handlers:scheduler:environment:) -> DiffResult` (`Sources/Swiflow/Diff/Diff.swift:30`) returns `.patches: [Patch]` and `.newMountTree: MountNode`. When `mounted` is non-nil and `next` is a `.component` with the **same** `typeID` + `key`, it fires the reuse arm: it re-evaluates `body` on the existing instance and reconciles the body subtree **in place**, returning the same `MountNode` object. That is exactly the subtree re-render we want — we just call it rooted at the dirty anchor instead of the root.
- `MountNode` (`Sources/Swiflow/MountTree.swift`): `component: AnyComponent?`, `componentBody: MountNode?`, `children: [MountNode]`, `parent: MountNode?` (weak), `vnode: VNode`, `scopeID: ScopeID?`. A component-anchor node has non-nil `component` + `componentBody`.
- `AnyComponent` (`Sources/Swiflow/Reactivity/Component.swift:77`): `.instance` (the `Component`), `.typeID: ObjectIdentifier` (`package`). `ComponentDescription(typeID:key:factory:)` is a `package init`.
- `firePostRenderLifecycle(_ node:preExistingIDs:)` (`Diff.swift:760`) walks a subtree firing `onChange()` for instances in `preExistingIDs`, `onAppear()` for the rest. `collectComponentIDs(_:)` (`Diff.swift:865`) returns all instance IDs in a subtree. Both `package`.
- `VNode` has a `.environmentOverride(overrides, child)` case and a `.component(ComponentDescription)` case.
- Test harness pattern (`Tests/SwiflowTests/Reactivity/ComponentUpdateTests.swift`): build `VNode.component(.init(Type.self) { Type() })`, call `diff(...)`, inspect `.newMountTree` / `.patches`. Plain `final class X: Component { var body: VNode { … } }` works as a test component and can override `onAppear()` / `onChange()`.

**Branch:** Work on `perf/scoped-rerender` (already created off `origin/main`; the spec lives there).

---

## Task 1: `findComponentAnchor` — locate a dirty anchor by identity

**Files:**
- Create: `Sources/Swiflow/Diff/ScopedRerender.swift`
- Test: `Tests/SwiflowTests/DiffTests/ScopedRerenderTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowTests/DiffTests/ScopedRerenderTests.swift`:

```swift
// Tests/SwiflowTests/DiffTests/ScopedRerenderTests.swift
import Testing
@testable import Swiflow

@Suite("Scoped re-render")
@MainActor
struct ScopedRerenderTests {

    // A child component nested inside a parent's body, so the mount tree has
    // a real anchor → body → anchor chain to walk.
    final class Child: Component {
        var label: String = "child"
        var body: VNode { p(label) }
    }
    final class Parent: Component {
        let child = Child()
        var body: VNode {
            div { VNode.component(.init(Child.self) { self.child }) }
        }
    }

    private func mountParent() -> (root: MountNode, parent: Parent, child: Child) {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let parent = Parent()
        let v = VNode.component(.init(Parent.self) { parent })
        let result = diff(mounted: nil, next: v, handles: handles, handlers: handlers)
        return (result.newMountTree, parent, parent.child)
    }

    @Test("finds the nested child anchor by instance identity")
    func findsNestedAnchor() {
        let (root, _, child) = mountParent()
        let anchor = findComponentAnchor(in: root, matching: ObjectIdentifier(child))
        #expect(anchor != nil)
        #expect(anchor?.component?.instance === child)
    }

    @Test("returns the root when the root instance matches")
    func findsRoot() {
        let (root, parent, _) = mountParent()
        let anchor = findComponentAnchor(in: root, matching: ObjectIdentifier(parent))
        #expect(anchor === root)
    }

    @Test("returns nil for an instance not in the tree")
    func findsNothing() {
        let (root, _, _) = mountParent()
        let stray = Child()
        #expect(findComponentAnchor(in: root, matching: ObjectIdentifier(stray)) == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScopedRerenderTests`
Expected: FAIL to compile — `cannot find 'findComponentAnchor' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/Swiflow/Diff/ScopedRerender.swift`:

```swift
// Sources/Swiflow/Diff/ScopedRerender.swift
//
// Scoped re-render (issue #89). A single-component @State change should
// re-render only that component's subtree, not the whole tree from the root.
// All decision + execution logic lives here so it is host-testable; the
// WASM-only Renderer/RAFScheduler hold only thin wiring.

/// Walks `node`'s subtree (componentBody + children) and returns the
/// component-anchor `MountNode` whose live instance has identity `id`, or
/// `nil` if no such anchor exists. Pure: it reads the committed tree and
/// holds no state, so it can never go stale.
@MainActor
package func findComponentAnchor(in node: MountNode, matching id: ObjectIdentifier) -> MountNode? {
    if let c = node.component, ObjectIdentifier(c.instance) == id { return node }
    if let body = node.componentBody,
       let found = findComponentAnchor(in: body, matching: id) {
        return found
    }
    for child in node.children {
        if let found = findComponentAnchor(in: child, matching: id) { return found }
    }
    return nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ScopedRerenderTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Diff/ScopedRerender.swift Tests/SwiflowTests/DiffTests/ScopedRerenderTests.swift
git commit -m "feat(perf): findComponentAnchor for scoped re-render (#89)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `hasEnvironmentOverrideAncestor` — env-safety guard

**Files:**
- Modify: `Sources/Swiflow/Diff/ScopedRerender.swift`
- Test: `Tests/SwiflowTests/DiffTests/ScopedRerenderTests.swift`

- [ ] **Step 1: Write the failing test**

Append inside `struct ScopedRerenderTests`:

```swift
    @Test("detects an environmentOverride ancestor")
    func detectsEnvOverrideAncestor() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let child = Child()
        // Wrap the child anchor in an environmentOverride node.
        let v = VNode.environmentOverride(
            EnvironmentValues(),
            .component(.init(Child.self) { child })
        )
        let root = diff(mounted: nil, next: v, handles: handles, handlers: handlers).newMountTree
        let anchor = findComponentAnchor(in: root, matching: ObjectIdentifier(child))
        #expect(anchor != nil)
        #expect(hasEnvironmentOverrideAncestor(anchor!) == true)
    }

    @Test("no false positive without an override ancestor")
    func noEnvOverrideAncestor() {
        let (root, _, child) = mountParent()
        let anchor = findComponentAnchor(in: root, matching: ObjectIdentifier(child))!
        #expect(hasEnvironmentOverrideAncestor(anchor) == false)
    }
```

Note: confirm the `VNode.environmentOverride` associated-value shape by reading `Sources/Swiflow/VNode.swift` and `Sources/Swiflow/DSL/EnvironmentDSL.swift`; the mount arm is `case .environmentOverride(let overrides, let child)` (`Diff.swift:285`). If the public constructor differs, build the override node via the public `.environment(...)` DSL instead and keep the two assertions identical.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScopedRerenderTests`
Expected: FAIL to compile — `cannot find 'hasEnvironmentOverrideAncestor' in scope`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/Swiflow/Diff/ScopedRerender.swift`:

```swift
/// True when `node` has any ancestor (via `parent` pointers) that is an
/// `.environmentOverride` node. A scoped re-render starts the diff at the
/// anchor with a fresh `EnvironmentValues()`, so an anchor beneath an
/// override would lose the ambient environment — such anchors must take the
/// full-render fallback instead. Note: `Theme {}` / `ThemeScope` is a plain
/// `display:contents` div, NOT an environment override, so it does not trip
/// this guard.
@MainActor
package func hasEnvironmentOverrideAncestor(_ node: MountNode) -> Bool {
    var current = node.parent
    while let n = current {
        if case .environmentOverride = n.vnode { return true }
        current = n.parent
    }
    return false
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ScopedRerenderTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Diff/ScopedRerender.swift Tests/SwiflowTests/DiffTests/ScopedRerenderTests.swift
git commit -m "feat(perf): environmentOverride-ancestor guard for scoped re-render (#89)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `planRerender` — the fallback predicate as a pure function

**Files:**
- Modify: `Sources/Swiflow/Diff/ScopedRerender.swift`
- Test: `Tests/SwiflowTests/DiffTests/ScopedRerenderTests.swift`

- [ ] **Step 1: Write the failing test**

Append inside `struct ScopedRerenderTests`:

```swift
    @Test("single dirty nested component → scoped at its anchor")
    func planScopesSingleDirty() {
        let (root, _, child) = mountParent()
        let plan = planRerender(root: root, dirtyIDs: [ObjectIdentifier(child)])
        guard case .scoped(let anchor) = plan else { Issue.record("expected .scoped"); return }
        #expect(anchor.component?.instance === child)
    }

    @Test("more than one dirty component → full")
    func planFullOnMultiDirty() {
        let (root, parent, child) = mountParent()
        let plan = planRerender(root: root, dirtyIDs: [ObjectIdentifier(child), ObjectIdentifier(parent)])
        #expect({ if case .full = plan { return true } else { return false } }())
    }

    @Test("root dirty → full (full render is already minimal for the root)")
    func planFullOnRootDirty() {
        let (root, parent, _) = mountParent()
        let plan = planRerender(root: root, dirtyIDs: [ObjectIdentifier(parent)])
        #expect({ if case .full = plan { return true } else { return false } }())
    }

    @Test("dirty instance absent from tree → full")
    func planFullOnMissing() {
        let (root, _, _) = mountParent()
        let plan = planRerender(root: root, dirtyIDs: [ObjectIdentifier(Child())])
        #expect({ if case .full = plan { return true } else { return false } }())
    }

    @Test("dirty anchor under environmentOverride → full")
    func planFullOnEnvOverride() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let child = Child()
        let v = VNode.environmentOverride(
            EnvironmentValues(),
            .component(.init(Child.self) { child })
        )
        let root = diff(mounted: nil, next: v, handles: handles, handlers: handlers).newMountTree
        let plan = planRerender(root: root, dirtyIDs: [ObjectIdentifier(child)])
        #expect({ if case .full = plan { return true } else { return false } }())
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScopedRerenderTests`
Expected: FAIL to compile — `cannot find 'planRerender'` / `RerenderPlan`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/Swiflow/Diff/ScopedRerender.swift`:

```swift
/// The outcome of the fallback predicate for one flush.
package enum RerenderPlan {
    /// Re-render the whole tree from the root (the proven, unchanged path).
    case full
    /// Re-render only this component anchor's subtree.
    case scoped(MountNode)
}

/// Decides whether a flush can take the scoped fast path. Returns `.scoped`
/// only for the safe, common single-dirty case; everything else falls back
/// to `.full`. Pure so the decision is host-tested rather than buried in the
/// WASM renderer.
///
/// Fallback to `.full` when ANY of:
/// - the dirty set is not exactly one component (multi-dirty / ancestor overlap);
/// - the dirty instance's anchor cannot be located in the tree;
/// - the anchor IS the root (full render is already minimal for the root);
/// - the anchor has an `environmentOverride` ancestor (scoped diff would reset
///   `EnvironmentValues` and lose the ambient overrides).
@MainActor
package func planRerender(root: MountNode, dirtyIDs: Set<ObjectIdentifier>) -> RerenderPlan {
    guard dirtyIDs.count == 1, let only = dirtyIDs.first else { return .full }
    guard let anchor = findComponentAnchor(in: root, matching: only) else { return .full }
    if anchor === root { return .full }
    if hasEnvironmentOverrideAncestor(anchor) { return .full }
    return .scoped(anchor)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ScopedRerenderTests`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Diff/ScopedRerender.swift Tests/SwiflowTests/DiffTests/ScopedRerenderTests.swift
git commit -m "feat(perf): planRerender fallback predicate (#89)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: `scopedRerender` — re-render one subtree (the heart)

**Files:**
- Modify: `Sources/Swiflow/Diff/ScopedRerender.swift`
- Test: `Tests/SwiflowTests/DiffTests/ScopedRerenderTests.swift`

- [ ] **Step 1: Write the failing test**

Add lifecycle-recording test components and tests. Append inside `struct ScopedRerenderTests`:

```swift
    // Lifecycle-recording components. `events` is shared so a test can assert
    // exactly which instances' onChange/onAppear fired during a scoped pass.
    final class RecChild: Component {
        let name: String
        let events: EventLog
        var label = "a"
        init(name: String, events: EventLog) { self.name = name; self.events = events }
        var body: VNode { p(label) }
        func onChange() { events.log.append("change:\(name)") }
        func onAppear() { events.log.append("appear:\(name)") }
    }
    final class EventLog { var log: [String] = [] }

    final class RecParent: Component {
        let events: EventLog
        let child: RecChild
        init(events: EventLog) { self.events = events; self.child = RecChild(name: "child", events: events) }
        var body: VNode {
            div {
                p("parent-chrome")
                VNode.component(.init(RecChild.self) { self.child })
            }
        }
        func onChange() { events.log.append("change:parent") }
    }

    @Test("scopedRerender re-renders only the child subtree and fires only its lifecycle")
    func scopedReRendersChildOnly() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let events = EventLog()
        let parent = RecParent(events: events)
        let root = diff(mounted: nil, next: .component(.init(RecParent.self) { parent }),
                        handles: handles, handlers: handlers).newMountTree
        events.log.removeAll()  // discard first-mount onAppear noise

        // Mutate ONLY the child's body, then scoped-rerender at the child anchor.
        parent.child.label = "b"
        let anchor = findComponentAnchor(in: root, matching: ObjectIdentifier(parent.child))!
        let patches = scopedRerender(anchor: anchor, handles: handles, handlers: handlers, scheduler: nil)

        // (a) patches updated the child's text and nothing else.
        let setTexts: [String] = patches.compactMap {
            if case .setText(_, let t) = $0 { return t } else { return nil }
        }
        #expect(setTexts == ["b"])

        // (b) the reused instance is identical and the anchor object is unchanged.
        #expect(anchor.component?.instance === parent.child)

        // (c) only the child's onChange fired; the parent's did NOT.
        #expect(events.log == ["change:child"])
    }

    @Test("a component mounted DURING the scoped pass fires onAppear, not onChange")
    func scopedFiresAppearForFreshChild() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let events = EventLog()

        // Parent whose child conditionally renders a grandchild.
        final class GrandHolder: Component {
            let events: EventLog
            var showGrand = false
            let grand: RecChild
            init(events: EventLog) { self.events = events; self.grand = RecChild(name: "grand", events: events) }
            var body: VNode {
                if showGrand {
                    return div { VNode.component(.init(RecChild.self) { self.grand }) }
                } else {
                    return div { p("empty") }
                }
            }
            func onChange() { events.log.append("change:holder") }
        }
        let holder = GrandHolder(events: events)
        let root = diff(mounted: nil, next: .component(.init(GrandHolder.self) { holder }),
                        handles: handles, handlers: handlers).newMountTree
        events.log.removeAll()

        holder.showGrand = true
        let anchor = findComponentAnchor(in: root, matching: ObjectIdentifier(holder))!
        _ = scopedRerender(anchor: anchor, handles: handles, handlers: handlers, scheduler: nil)

        // holder survived → onChange; grand is freshly mounted → onAppear.
        #expect(events.log.contains("change:holder"))
        #expect(events.log.contains("appear:grand"))
        #expect(!events.log.contains("change:grand"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScopedRerenderTests`
Expected: FAIL to compile — `cannot find 'scopedRerender' in scope`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/Swiflow/Diff/ScopedRerender.swift`:

```swift
/// Re-renders the subtree rooted at `anchor` (a component-anchor MountNode)
/// and returns the patches to ship. Reuses the live instance via the diff's
/// component-reuse arm, reconciling the body subtree in place, then fires the
/// post-render lifecycle scoped to this subtree only.
///
/// Precondition: `anchor.component != nil` and `anchor` has no
/// `environmentOverride` ancestor (callers gate via `planRerender`). The diff
/// starts with a fresh `EnvironmentValues()`, which reproduces the ambient
/// environment exactly when no override sits above the anchor.
@MainActor
package func scopedRerender(
    anchor: MountNode,
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    scheduler: Scheduler?
) -> [Patch] {
    guard let instance = anchor.component else { return [] }

    // Preserve the anchor's identity (typeID + key) so the reuse arm fires
    // rather than destroy+remount (which would drop the instance's state).
    let key: String?
    if case .component(let desc) = anchor.vnode { key = desc.key } else { key = nil }
    let next = VNode.component(
        ComponentDescription(typeID: instance.typeID, key: key, factory: { instance })
    )

    // Capture instances alive in this subtree BEFORE the diff so the lifecycle
    // walk routes survivors → onChange and fresh mounts → onAppear.
    let preExistingIDs = collectComponentIDs(anchor)

    let result = diff(
        mounted: anchor,
        next: next,
        handles: handles,
        handlers: handlers,
        scheduler: scheduler,
        environment: .init()
    )
    firePostRenderLifecycle(result.newMountTree, preExistingIDs: preExistingIDs)
    return result.patches
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ScopedRerenderTests`
Expected: PASS (12 tests).

- [ ] **Step 5: Run the full core suite to confirm no regression**

Run: `swift test --filter SwiflowTests`
Expected: PASS (no failures introduced; lifecycle/diff suites unaffected).

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/Diff/ScopedRerender.swift Tests/SwiflowTests/DiffTests/ScopedRerenderTests.swift
git commit -m "feat(perf): scopedRerender — single-subtree re-render with scoped lifecycle (#89)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `RAFScheduler` — pass the dirty set to the flush callback

**Files:**
- Modify: `Sources/SwiflowDOM/RAFScheduler.swift`

**WASM-only file — not compiled or tested by `swift test` on host.** Verified by the wasm demo build in Task 8. Keep this change minimal and mechanical.

- [ ] **Step 1: Change the callback type and flush**

In `Sources/SwiflowDOM/RAFScheduler.swift`, change the stored callback, initializer, and `flush()`:

```swift
    /// Invoked once per rAF tick when at least one component is dirty, with
    /// the snapshot of dirty component-instance identities for that tick.
    /// The callback decides per-frame whether to scope the re-render to a
    /// single subtree or fall back to a full-root render.
    private let onFlushBatch: (Set<ObjectIdentifier>) -> Void

    public init(onFlushBatch: @escaping (Set<ObjectIdentifier>) -> Void) {
        self.onFlushBatch = onFlushBatch
    }
```

And `flush()`:

```swift
    public func flush() {
        guard !dirty.isEmpty else { return }
        let batch = dirty
        dirty.removeAll(keepingCapacity: true)
        onFlushBatch(batch)
    }
```

Also update the type-level doc comment that currently says "The callback should perform a full-tree rerender from the root" — replace with: "The callback receives the dirty-instance set and chooses scoped vs full re-render."

- [ ] **Step 2: Commit**

```bash
git add Sources/SwiflowDOM/RAFScheduler.swift
git commit -m "refactor(perf): RAFScheduler hands the dirty set to its flush callback (#89)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: `Renderer` — thin fast-path wiring

**Files:**
- Modify: `Sources/SwiflowDOM/Renderer.swift`

**WASM-only file — not compiled or tested by `swift test` on host.** Verified by the wasm demo build + browser in Task 8.

- [ ] **Step 1: Extract a shared patch-shipping helper from `renderOnce()`**

In `renderOnce()`, the block that encodes patches to a JSArray, calls `swiflow.applyPatches`, and updates `lastPatchCount` is currently inline (`Renderer.swift:166-178`). Extract it into a method so both paths share it. Add to the `Renderer` class:

```swift
    /// Encodes `patches` to a JSArray, ships them via `window.swiflow.applyPatches`,
    /// and records `lastPatchCount` + `renderCount`. Shared by `renderOnce()`
    /// (full render) and `flushDirty(_:)` (scoped render).
    private func shipPatches(_ patches: [Patch]) {
        lastPatchCount = patches.count
        renderCount += 1
        let jsArray = JSObject.global.Array.function!.new()
        for (index, patch) in patches.enumerated() {
            let payload = PatchSerializer.encode(patch)
            jsArray[index] = JSAdapter.toJSValue(payload)
        }
        let swiflowGlobal = JSObject.global.swiflow.object!
        _ = swiflowGlobal.applyPatches!(jsArray)
    }
```

Then in `renderOnce()` replace the inline encode/apply block (and the `lastPatchCount`/`renderCount` lines) with `shipPatches(outgoingPatches)`, keeping the `lastRenderMs` timing and the first-mount `mount(...)` / `replaceMount` logic exactly as-is. (The first-mount `mount` call and `replaceMount` splice stay in `renderOnce()`; only the encode-and-apply moves.)

- [ ] **Step 2: Point the RAFScheduler closure at `flushDirty`**

In `init`, change:

```swift
        let raf = RAFScheduler { [weak self] in
            self?.renderOnce()
        }
```

to:

```swift
        let raf = RAFScheduler { [weak self] dirtyIDs in
            self?.flushDirty(dirtyIDs)
        }
```

- [ ] **Step 3: Add `flushDirty`**

Add to the `Renderer` class:

```swift
    /// Entry point for a scheduler flush. Chooses the scoped fast path when
    /// `planRerender` deems it safe (single dirty component, locatable anchor,
    /// not the root, no environmentOverride ancestor), otherwise falls back to
    /// the unchanged full-root `renderOnce()`.
    func flushDirty(_ dirtyIDs: Set<ObjectIdentifier>) {
        guard let tree = mountTree else { renderOnce(); return }
        switch planRerender(root: tree, dirtyIDs: dirtyIDs) {
        case .full:
            renderOnce()
        case .scoped(let anchor):
            HandlerAmbient.current = handlers
            SwiflowTaskRuntime.currentScope = taskScope
            RenderObserverBox.current = queryClient
            defer {
                HandlerAmbient.current = nil
                SwiflowTaskRuntime.currentScope = nil
                RenderObserverBox.current = nil
            }
            let startMs = JSObject.global.performance.object?.now?().number ?? 0
            let patches = scopedRerender(
                anchor: anchor,
                handles: handles,
                handlers: handlers,
                scheduler: scheduler
            )
            shipPatches(patches)
            lastRenderMs = (JSObject.global.performance.object?.now?().number ?? 0) - startMs
        }
    }
```

Note: the scoped path sets the same ambient context (`HandlerAmbient` / `SwiflowTaskRuntime` / `RenderObserverBox`) that `renderOnce()` establishes, because `scopedRerender` re-evaluates `body` (handlers must register into this root's scope; `.task` and `query()` must reach this root). Do NOT call `firePostRenderLifecycle` here — `scopedRerender` already fires the scoped lifecycle internally. The mount tree is updated in place by the diff (the anchor object is reused), so there is no `mountTree =` reassignment on the scoped path.

- [ ] **Step 4: Verify it compiles for host (stub) and commit**

Run: `swift build`
Expected: PASS — on host, `SwiflowDOM` compiles to the empty `#else` stub, so this verifies the rest of the package still builds. (Real compilation of these symbols happens in the wasm build, Task 8.)

```bash
git add Sources/SwiflowDOM/Renderer.swift
git commit -m "feat(perf): Renderer.flushDirty scoped fast-path wiring (#89)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: `DataTableBox.sortedIndices()` memoization

**Files:**
- Modify: `Sources/SwiflowUI/DataTable.swift:270-282` (the `sortedIndices()` method) and the `DataTableBox` stored-property region (near `Sources/SwiflowUI/DataTable.swift:234-237`).
- Test: `Tests/SwiflowUITests/DataTableTests.swift`

- [ ] **Step 1: Write the failing test**

The existing harness builds boxes via `makeDataTableBox` and renders `box.body` inside `building { }`. We need a comparator-invocation counter to prove the cache. Add a new test that constructs a `DataColumn` with a counting comparator is not possible from outside (DataColumn is internal and built by the factory), so instead drive through the public seam and count via a column `value` keypath is also not directly countable. Use the observable proxy: re-sorting recomputes the order array identity. Add to `Tests/SwiflowUITests/DataTableTests.swift` a test that asserts the cached array is returned by reference identity across a scroll-only change, and recomputed across a sort change.

```swift
    @Test("sortedIndices caches across a scroll-only re-render and recomputes on sort change")
    func sortedIndicesCache() {
        // 3 people; sortable so a comparator exists and a sort can change.
        let order = Binding<SortOrder?>(get: { SortOrder(columnID: "age", ascending: true) }, set: { _ in })
        let b = makeDataTableBox(people, id: \.id, sortable: true, sortOrder: order,
                                 maxHeight: .custom("100px"),
                                 virtualization: .fixed(rowHeight: 20)) {
            Column("Name", value: \.name)
            Column("Age", value: \.age)
        }
        // Prime the cache.
        let first = b.sortedIndices()
        // A scroll-only change must not invalidate the cache → same array contents.
        b.setViewportMetrics(scrollTop: 40, viewportHeight: 100)
        let afterScroll = b.sortedIndices()
        #expect(afterScroll == first)
        #expect(b._sortCacheHitForTesting == true)
    }
```

Note: confirm `makeDataTableBox`'s exact argument labels/order against `Sources/SwiflowUI/DataTable.swift:122-160` and the existing sort tests (`DataTableTests.swift:~110`). If a `Binding<SortOrder?>` overload is required for `sortOrder:`, mirror the existing `box(order)` helper in that file. `Person`/`people` is the existing fixture in this test file (fields `id`, `name`, `age`).

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DataTable`
Expected: FAIL to compile — `value of type 'DataTableBox' has no member '_sortCacheHitForTesting'`.

- [ ] **Step 3: Add the cache fields and rewrite `sortedIndices()`**

In `DataTableBox`, near the other stored properties (after `Sources/SwiflowUI/DataTable.swift:237`), add:

```swift
    // sortedIndices() memo (issue #89). The instance persists across renders,
    // so a plain non-@State cache is safe and invisible to reactivity. A scroll
    // tick changes neither the sort nor the row count → cache hit → no 2000-row
    // rebuild/re-sort in the surviving subtree.
    private var _sortCache: [Int]?
    private var _sortCacheKey: SortCacheKey?
    private struct SortCacheKey: Equatable { let columnID: String?; let ascending: Bool; let rowCount: Int }
    #if DEBUG
    /// Test probe: true when the most recent `sortedIndices()` returned the cache.
    private(set) var _sortCacheHitForTesting = false
    #endif
```

Rewrite `sortedIndices()` (`Sources/SwiflowUI/DataTable.swift:270-282`):

```swift
    func sortedIndices() -> [Int] {
        let active = activeSort()
        let key = SortCacheKey(columnID: active?.columnID, ascending: active?.ascending ?? false, rowCount: rowCount)
        if let cached = _sortCache, _sortCacheKey == key {
            #if DEBUG
            _sortCacheHitForTesting = true
            #endif
            return cached
        }
        #if DEBUG
        _sortCacheHitForTesting = false
        #endif
        let base = Array(0..<rowCount)
        let result: [Int]
        if let order = active,
           let col = columns.first(where: { $0.id == order.columnID }),
           let cmp = col.comparator {
            result = base.sorted { i, j in
                switch cmp(i, j) {
                case .ascending:  return order.ascending
                case .descending: return !order.ascending
                case .same:       return i < j
                }
            }
        } else {
            result = base
        }
        _sortCache = result
        _sortCacheKey = key
        return result
    }
```

This preserves the exact sort semantics of the original (`Sources/SwiflowUI/DataTable.swift:270-282`) — same comparator branches, same stable tie-break — and only adds the key-guarded cache.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DataTable`
Expected: PASS — including the existing sort tests (`ascending`, `descending`, `unsorted`), proving the cache didn't change ordering.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowUI/DataTable.swift Tests/SwiflowUITests/DataTableTests.swift
git commit -m "perf(datatable): memoize sortedIndices() across scroll ticks (#89)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Browser verification + overscan rollback

**Files:**
- Modify: `Sources/SwiflowUI/DataTable.swift` (the `overscan` constant, near `Sources/SwiflowUI/DataTable.swift:239`).
- Reference (no edit unless a regression): `Tests/playwright/datatable.spec.ts`, `examples/SwiflowUIDemo/Sources/App/App.swift`.

This task has no host unit test — it verifies the WASM-only wiring (Tasks 5–6) and the end-to-end win in a real browser. Run e2e **inline, never in a subagent** (port collisions), after building the release CLI.

- [ ] **Step 1: Build the release CLI and the demo (compiles the wasm — this is the real compile gate for Tasks 5–6)**

Run: `swift build -c release --product swiflow`
Then: `swiflow build --path examples/SwiflowUIDemo`
Expected: both succeed. A compile error here means a Task 5/6 mistake in the WASM-only files (which `swift test` cannot catch).

- [ ] **Step 2: Run the existing DataTable e2e (correctness regression)**

Run the Playwright `datatable.spec.ts` suite locally (inline), per the project's e2e procedure. Expected: all DataTable tests pass — windowing, sticky header, single border, horizontal columns, sort, select-all, pager — proving scoped re-render produces identical DOM.

- [ ] **Step 3: Re-measure scroll→DOM latency in the demo**

Serve the demo, open it in chrome-devtools, and instrument scroll→DOM latency with the same `MutationObserver`-on-virtualized-`<tbody>` method used in #88 (8 moderate scroll jumps; report per-jump latency, avg, max). Also read `__swiflow.perf()` to confirm `lastRenderMs` dropped and `lastPatchCount` stays small (the patch set should be the window's ~16–30 rows).

Expected: avg latency ≤1 frame (~16ms) for the window shift, down from the #88 baseline (avg ~46ms / max ~50ms). **Record the before/after numbers in the PR description.**

- [ ] **Step 4: Audit the onChange contract change in the demo**

Confirm the demo's color-scheme sync still works: toggle "Dark mode" and verify the whole demo re-themes (this flips `Demo`'s own `@State`, which marks `Demo` dirty → re-renders and fires `Demo.onChange → syncColorScheme`). Confirm that scrolling the virtualized table no longer fires `Demo.onChange` every tick (that is the intended change). Grep the demo for any other reliance on every-render `onChange`:

Run: `grep -rn "func onChange" examples/SwiflowUIDemo/Sources`
Expected: only `Demo.onChange` (color-scheme sync), which is driven by `Demo`'s own state and unaffected.

- [ ] **Step 5: Roll back overscan 10 → 3 and re-verify**

In `DataTableBox`, change `let overscan = 10` back to `let overscan = 3` (`Sources/SwiflowUI/DataTable.swift:239` region). Rebuild the demo (Step 1) and re-run the latency measurement (Step 3) plus a manual moderate drag. Expected: no visible blank during a moderate drag — confirming the latency win, not just the overscan mask, carries the experience.

If a blank IS visible at overscan 3, leave overscan at a value that is visually clean (document the chosen value and the measured latency in the PR), since the acceptance bar is "no visible blank," not a specific overscan number.

- [ ] **Step 6: Update the DataTable virtualization tests for the overscan change**

The existing virtualization tests derive expected window sizes from `box.overscan` (e.g. `win.count == 10 + 2 * box.overscan`), so they should still pass after the constant changes. Confirm:

Run: `swift test --filter DataTable`
Expected: PASS (tests read `box.overscan`, so they track the new value automatically).

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiflowUI/DataTable.swift
git commit -m "perf(datatable): drop overscan 10→3 now that scoped re-render is cheap (#89)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification (after all tasks)

- [ ] `swift test` — full host suite green (core + SwiflowUI; the scoped-rerender + sortedIndices tests included).
- [ ] `swift build -c release --product swiflow` + `swiflow build --path examples/SwiflowUIDemo` — wasm compiles (the real gate for the WASM-only Renderer/RAFScheduler changes).
- [ ] `datatable.spec.ts` e2e green (run inline).
- [ ] Latency re-measured ≤1 frame; before/after numbers captured for the PR.
- [ ] onChange-contract audit clean; demo dark-mode toggle still re-themes.
- [ ] Open a PR from `perf/scoped-rerender` → `main` referencing issue #89, with the before/after latency numbers. **Do not merge** until the user says "merge it -- CI is green" (merge with `gh pr merge <n> --admin --rebase`).

## Spec coverage check

- Root cause / fast-path / fallback predicate → Tasks 3, 5, 6.
- Scoped subtree re-render via existing diff reuse arm → Task 4.
- onChange fires only on actual re-render → Task 4 (scoped lifecycle) + Task 8 Step 4 (audit).
- environmentOverride-ancestor fallback → Tasks 2, 3.
- Pure tree-walk anchor location → Task 1.
- sortedIndices memo → Task 7.
- Host tests for anchor/env-guard/predicate/scoped-diff/cache → Tasks 1–4, 7.
- Browser latency re-measurement + overscan rollback → Task 8.
- Acceptance criteria 1–6 → Tasks 4/7 (host), Task 8 (browser: latency, onChange, overscan).
