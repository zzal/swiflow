# Phase 18 — `onChange` for Nested Components Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fire `onChange()` on every nested component after a re-render (not just root), and fire `onAppear()` on components mounted mid-render (not just at first mount).

**Architecture:** Add two pure-Swift helpers — `collectComponentIDs(_:)` captures the set of live component ObjectIdentifiers pre-diff; `firePostRenderLifecycle(_:preExistingIDs:)` walks the post-diff mount tree children-first and fires `onChange` for IDs in the set, `onAppear` for IDs not in it. The Web renderer's two-branch lifecycle dispatch collapses into a single call. `fireOnAppearTree(_:)` is removed (replaced by `firePostRenderLifecycle(_, preExistingIDs: [])`).

**Tech Stack:** Swift (Swiflow module — pure, no JavaScriptKit), swift-testing (`@Suite`/`@Test`), SwiftPM. Tests run on macOS/Linux for fast feedback; Renderer integration is exercised by existing Playwright suites.

**Spec:** `docs/superpowers/specs/2026-05-27-phase18-onchange-nested-design.md` (commit `436926d`)

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `Sources/Swiflow/Diff/Diff.swift` | Pure-Swift VDOM diff + lifecycle walkers | Add `collectComponentIDs`, add `firePostRenderLifecycle`, remove `fireOnAppearTree` |
| `Sources/SwiflowWeb/Renderer.swift` | WASM/JS-bridge owner of render state | Collapse two-branch lifecycle dispatch into single call |
| `Tests/SwiflowTests/Reactivity/RendererComponentTests.swift` | Pure-Swift lifecycle/scheduler tests | Add `CollectComponentIDsTests`, `FirePostRenderLifecycleTests`, `NestedOnChangeTests`, `MidRenderMountTests`; port `OnAppearTreeWalkTests` to new helper |
| `CHANGELOG.md` | Release notes | Add Phase 18 entry under "Behavior changes" |

---

## Task 1: `collectComponentIDs` helper

**Files:**
- Modify: `Sources/Swiflow/Diff/Diff.swift` (add at end of file)
- Test: `Tests/SwiflowTests/Reactivity/RendererComponentTests.swift` (new suite)

- [ ] **Step 1: Write the failing test**

Append to `Tests/SwiflowTests/Reactivity/RendererComponentTests.swift`:

```swift
// MARK: - collectComponentIDs

@Suite("collectComponentIDs walks the mount tree and gathers every live component instance ID")
@MainActor
struct CollectComponentIDsTests {

    final class A: Component { var body: VNode { .text("a") } }
    final class B: Component { var body: VNode { embed { C() } } }
    final class C: Component { var body: VNode { .text("c") } }

    @Test("returns an empty set for nil input (used to seed the first-mount case)")
    func nilReturnsEmpty() {
        #expect(collectComponentIDs(nil) == Set<ObjectIdentifier>())
    }

    @Test("collects the root component anchor's instance ID")
    func collectsRoot() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v = VNode.component(.init(A.self) { A() })
        let r = diff(mounted: nil, next: v, handles: handles, handlers: handlers)
        let instance = r.newMountTree.component!.instance
        let ids = collectComponentIDs(r.newMountTree)
        #expect(ids == [ObjectIdentifier(instance)])
    }

    @Test("collects every component anchor in a nested tree (parent and child)")
    func collectsNested() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v = VNode.component(.init(B.self) { B() })
        let r = diff(mounted: nil, next: v, handles: handles, handlers: handlers)
        let parent = r.newMountTree.component!.instance        // B
        let child = r.newMountTree.componentBody!.component!.instance  // C
        let ids = collectComponentIDs(r.newMountTree)
        #expect(ids == [ObjectIdentifier(parent), ObjectIdentifier(child)])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CollectComponentIDsTests`
Expected: FAIL — `cannot find 'collectComponentIDs' in scope`.

- [ ] **Step 3: Implement the helper**

Append to `Sources/Swiflow/Diff/Diff.swift`:

```swift
/// Collects the `ObjectIdentifier` of every live component instance reachable
/// from `node`. Returns an empty set when `node` is nil — used to seed the
/// first-mount case where no instances existed before this diff, so every
/// component in the new tree is treated as freshly mounted.
@MainActor
package func collectComponentIDs(_ node: MountNode?) -> Set<ObjectIdentifier> {
    var ids: Set<ObjectIdentifier> = []
    func walk(_ n: MountNode) {
        if let any = n.component {
            ids.insert(ObjectIdentifier(any.instance))
        }
        if let body = n.componentBody { walk(body) }
        for child in n.children { walk(child) }
    }
    if let node { walk(node) }
    return ids
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CollectComponentIDsTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Diff/Diff.swift Tests/SwiflowTests/Reactivity/RendererComponentTests.swift
git commit -m "$(cat <<'EOF'
feat(diff): add collectComponentIDs walker for lifecycle partitioning

First half of Phase 18's reused-vs-fresh primitive. Walks a mount tree
and returns the set of ObjectIdentifiers of every live component
instance, including nested anchors. Used pre-diff to snapshot which
instances exist; post-diff to decide whether each component in the new
tree gets onChange (reused) or onAppear (freshly mounted).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `firePostRenderLifecycle` walker

**Files:**
- Modify: `Sources/Swiflow/Diff/Diff.swift` (add after `collectComponentIDs`)
- Test: `Tests/SwiflowTests/Reactivity/RendererComponentTests.swift` (new suite)

- [ ] **Step 1: Write the failing test**

Append to `Tests/SwiflowTests/Reactivity/RendererComponentTests.swift`:

```swift
// MARK: - firePostRenderLifecycle

/// Records ordering + which hook fired across nested components for the
/// firePostRenderLifecycle walker tests. Class so multiple components can
/// share by reference.
@MainActor
private final class LifecycleLog {
    var calls: [String] = []  // entries shaped like "outer.appear", "inner.change"
}

@Suite("firePostRenderLifecycle partitions components into onAppear (new) vs onChange (reused), children-first")
@MainActor
struct FirePostRenderLifecycleTests {

    final class Inner: Component {
        fileprivate let log: LifecycleLog
        fileprivate let name: String
        fileprivate init(log: LifecycleLog, name: String) { self.log = log; self.name = name }
        var body: VNode { .text("inner") }
        func onAppear() { log.calls.append("\(name).appear") }
        func onChange() { log.calls.append("\(name).change") }
    }

    final class Outer: Component {
        fileprivate let log: LifecycleLog
        fileprivate let inner: Inner
        fileprivate init(log: LifecycleLog, inner: Inner) { self.log = log; self.inner = inner }
        var body: VNode { embed { self.inner } }
        func onAppear() { log.calls.append("outer.appear") }
        func onChange() { log.calls.append("outer.change") }
    }

    @Test("empty preExistingIDs (first-mount case) fires onAppear on every component, children-first")
    func emptyPreExistingFiresOnAppearOnAll() {
        let log = LifecycleLog()
        let inner = Inner(log: log, name: "inner")
        let outer = Outer(log: log, inner: inner)

        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v = VNode.component(.init(Outer.self) { outer })
        let r = diff(mounted: nil, next: v, handles: handles, handlers: handlers)

        firePostRenderLifecycle(r.newMountTree, preExistingIDs: [])

        #expect(log.calls == ["inner.appear", "outer.appear"])
    }

    @Test("preExistingIDs covering every component fires onChange on each, children-first; no onAppear")
    func allReusedFiresOnChangeOnAll() {
        let log = LifecycleLog()
        let inner = Inner(log: log, name: "inner")
        let outer = Outer(log: log, inner: inner)

        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v = VNode.component(.init(Outer.self) { outer })
        let r = diff(mounted: nil, next: v, handles: handles, handlers: handlers)
        let allIDs = collectComponentIDs(r.newMountTree)

        firePostRenderLifecycle(r.newMountTree, preExistingIDs: allIDs)

        #expect(log.calls == ["inner.change", "outer.change"])
    }

    @Test("mixed tree: reused parent fires onChange, freshly-mounted child fires onAppear (child first)")
    func mixedTreeFiresCorrectHookPerComponent() {
        let log = LifecycleLog()
        let inner = Inner(log: log, name: "inner")
        let outer = Outer(log: log, inner: inner)

        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v = VNode.component(.init(Outer.self) { outer })
        let r = diff(mounted: nil, next: v, handles: handles, handlers: handlers)
        // Only outer is "pre-existing" — inner is "new" (mid-render mount semantics).
        let preIDs: Set<ObjectIdentifier> = [ObjectIdentifier(outer)]

        firePostRenderLifecycle(r.newMountTree, preExistingIDs: preIDs)

        #expect(log.calls == ["inner.appear", "outer.change"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FirePostRenderLifecycleTests`
Expected: FAIL — `cannot find 'firePostRenderLifecycle' in scope`.

- [ ] **Step 3: Implement the walker**

Append to `Sources/Swiflow/Diff/Diff.swift` (after `collectComponentIDs`):

```swift
/// Children-first walk over `node` and its entire subtree. For each component
/// anchor encountered:
///   - if its instance's `ObjectIdentifier` is in `preExistingIDs`, fire `onChange()`
///   - otherwise, fire `onAppear()`
///
/// Children-first ordering means a parent's hook observes a fully
/// mounted/committed subtree. Matches React's commit-phase invariant: a
/// child's `componentDidMount` runs before its parent's `componentDidUpdate`.
///
/// `preExistingIDs == []` on first mount (no instances existed before this
/// diff) reproduces the previous `fireOnAppearTree` behavior exactly: every
/// component is treated as new and gets `onAppear`.
@MainActor
package func firePostRenderLifecycle(_ node: MountNode, preExistingIDs: Set<ObjectIdentifier>) {
    if let body = node.componentBody {
        firePostRenderLifecycle(body, preExistingIDs: preExistingIDs)
    }
    for child in node.children {
        firePostRenderLifecycle(child, preExistingIDs: preExistingIDs)
    }
    if let any = node.component {
        if preExistingIDs.contains(ObjectIdentifier(any.instance)) {
            any.instance.onChange()
        } else {
            any.instance.onAppear()
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FirePostRenderLifecycleTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Diff/Diff.swift Tests/SwiflowTests/Reactivity/RendererComponentTests.swift
git commit -m "$(cat <<'EOF'
feat(diff): add firePostRenderLifecycle children-first walker

Second half of Phase 18's primitive. Walks the post-diff mount tree
children-first and partitions component anchors by whether their
instance ID was in the pre-diff snapshot: reused instances fire
onChange(), freshly-mounted instances fire onAppear(). Empty
preExistingIDs reproduces fireOnAppearTree exactly (every component
treated as new).

fireOnAppearTree is not yet removed — Renderer still references it.
Removal lands once the Renderer call site is migrated.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Port `OnAppearTreeWalkTests` to new helper

**Files:**
- Modify: `Tests/SwiflowTests/Reactivity/RendererComponentTests.swift:251-295`

- [ ] **Step 1: Update the existing test in place**

Replace the body of `onAppearFiresChildrenFirst` (around line 272) — only the assertion-section call changes from `fireOnAppearTree(result.newMountTree)` to the new helper:

```swift
    @Test("firePostRenderLifecycle with empty preExistingIDs fires onAppear on Outer AND Inner; Inner before Outer (children-first)")
    func onAppearFiresChildrenFirst() {
        let log = OnAppearLog()
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        // Build a mount tree containing Outer → (componentBody) → Inner.
        let v = VNode.component(.init(Outer.self) { Outer(log: log) })
        let result = diff(mounted: nil, next: v, handles: handles, handlers: handlers)

        // Sanity: confirm tree shape matches the destroy-nested test's precedent.
        #expect(result.newMountTree.component != nil, "Outer anchor expected at the root")
        #expect(result.newMountTree.componentBody?.component != nil, "Inner anchor expected as Outer's body")

        // Pre-condition: no lifecycle hook has fired yet.
        #expect(log.calls.isEmpty)

        // Act: empty preExistingIDs is the first-mount case — every component is "new".
        firePostRenderLifecycle(result.newMountTree, preExistingIDs: [])

        // Children-first ordering — symmetric inverse of destroy's parent-first.
        // Matches React/SwiftUI: a parent's onAppear sees its subtree fully mounted.
        #expect(log.calls == ["inner", "outer"])
    }
```

Also rename the `@Suite` annotation on line 251 from `"Lifecycle: onAppear fires on every component in the tree, children-first"` to `"Lifecycle: first-mount onAppear via firePostRenderLifecycle, children-first"`.

- [ ] **Step 2: Run test to verify it still passes (functionality preserved)**

Run: `swift test --filter OnAppearTreeWalkTests`
Expected: PASS — same observable behavior; only the helper name and `@Test` description changed.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiflowTests/Reactivity/RendererComponentTests.swift
git commit -m "$(cat <<'EOF'
test(lifecycle): port OnAppearTreeWalkTests to firePostRenderLifecycle

Same children-first invariant verified through the unified walker
(passing preExistingIDs: [] reproduces the old first-mount semantics).
fireOnAppearTree still exists but has one fewer caller; Renderer
migration in the next commit makes it dead code.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Renderer integration — collapse two-branch lifecycle dispatch

**Files:**
- Modify: `Sources/SwiflowWeb/Renderer.swift:195-221`

- [ ] **Step 1: Replace the lifecycle block in `renderOnce()`**

In `Sources/SwiflowWeb/Renderer.swift`, locate the block that runs from `let isFirstMount = (mountTree == nil)` through the closing brace of the `else` branch that calls `root.instance.onChange()`. Replace lines 195–221:

**Before:**
```swift
        let isFirstMount = (mountTree == nil)
        mountTree = result.newMountTree

        if isFirstMount {
            // Use domHandle (not handle): for a Component-root tree, the mount
            // tree root is the component anchor whose `handle` is structural-
            // only (the driver never saw a create* patch for it). The body's
            // DOM handle is what the driver needs to attach at `selector`.
            // For a viewProducer tree, domHandle == handle (no anchor layer),
            // so this is correct in both modes.
            let mountHandle = result.newMountTree.domHandle
            _ = swiflowGlobal.mount!(
                JSValue.number(Double(mountHandle)),
                JSValue.string(selector)
            )
            // Lifecycle: walk the mount tree children-first and fire onAppear
            // on every component anchor. Nested components (e.g. Link inside a
            // Page inside RouterRoot) rely on onAppear to attach DOM listeners
            // via Ref<JSObject>; firing only on the root would silently break
            // them. Symmetric inverse of destroy()'s parent-first onDisappear.
            fireOnAppearTree(result.newMountTree)
        } else {
            // Lifecycle: fire onChange on the root component.
            if let root = rootComponent {
                root.instance.onChange()
            }
        }
```

**After:**
```swift
        // Snapshot the set of component instance IDs alive BEFORE this diff,
        // so the lifecycle walker below can partition each anchor in the new
        // tree into reused (→ onChange) vs freshly-mounted (→ onAppear).
        // Captured before mountTree is reassigned. Empty on first render.
        let preExistingIDs = collectComponentIDs(mountTree)
        let isFirstMount = (mountTree == nil)
        mountTree = result.newMountTree

        if isFirstMount {
            // Use domHandle (not handle): for a Component-root tree, the mount
            // tree root is the component anchor whose `handle` is structural-
            // only (the driver never saw a create* patch for it). The body's
            // DOM handle is what the driver needs to attach at `selector`.
            // For a viewProducer tree, domHandle == handle (no anchor layer),
            // so this is correct in both modes.
            let mountHandle = result.newMountTree.domHandle
            _ = swiflowGlobal.mount!(
                JSValue.number(Double(mountHandle)),
                JSValue.string(selector)
            )
        }

        // Lifecycle: walk the post-diff tree children-first. On first mount
        // preExistingIDs is empty so every anchor fires onAppear (matches the
        // prior fireOnAppearTree behavior). On re-render, anchors whose
        // instance survived from the previous tree fire onChange; anchors
        // freshly created during this diff fire onAppear (closes the
        // mid-render-mount lifecycle gap).
        firePostRenderLifecycle(result.newMountTree, preExistingIDs: preExistingIDs)
```

- [ ] **Step 2: Verify the Swift package still builds**

Run: `swift build`
Expected: success. (`SwiflowWeb` is gated by `#if canImport(JavaScriptKit)`; on macOS this whole module is excluded from the build, so the change is verified by the WASM cross-compile step in CI and by Playwright e2e runs. The local `swift build` still validates that `Sources/Swiflow/Diff/Diff.swift` compiles — that's where `firePostRenderLifecycle` and `collectComponentIDs` live.)

- [ ] **Step 3: Run the full Swift test suite to ensure no regression**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiflowWeb/Renderer.swift
git commit -m "$(cat <<'EOF'
feat(renderer): fire onChange on every nested component, onAppear on mid-render mounts

Phase 18: Renderer's lifecycle dispatch was two-branched and
root-only — first-mount called fireOnAppearTree, re-render called
onChange on the root instance only. Components mounted mid-render
silently never saw onAppear; nested components never saw onChange.

Collapses both into a single firePostRenderLifecycle call with a
preExistingIDs snapshot captured before mountTree is reassigned.
Reused instances fire onChange; freshly-mounted instances fire
onAppear. Behavior on first mount is byte-identical to before (empty
preExistingIDs → all onAppear).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Remove dead `fireOnAppearTree`

**Files:**
- Modify: `Sources/Swiflow/Diff/Diff.swift:685-712`

- [ ] **Step 1: Confirm the function has no remaining callers**

Run: `grep -rn "fireOnAppearTree" Sources Tests`
Expected: zero matches outside `Sources/Swiflow/Diff/Diff.swift` itself.

- [ ] **Step 2: Delete the function and its doc comment**

In `Sources/Swiflow/Diff/Diff.swift`, remove the block from the `///` comment opening at line 685 through the closing `}` of `fireOnAppearTree` at line 712 (28 lines total). Leave the surrounding helpers (`domAncestorHandle` above, `diffChildren` below) intact.

- [ ] **Step 3: Verify build + tests still green**

Run: `swift build && swift test`
Expected: success; all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/Swiflow/Diff/Diff.swift
git commit -m "$(cat <<'EOF'
refactor(diff): remove fireOnAppearTree — superseded by firePostRenderLifecycle

firePostRenderLifecycle(_, preExistingIDs: []) reproduces the
first-mount semantics fireOnAppearTree provided; no remaining callers.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Integration test — nested `onChange` via real diff() reuse

**Files:**
- Modify: `Tests/SwiflowTests/Reactivity/RendererComponentTests.swift` (append at end)

This catches the wiring: when `diff()` reuses a component instance across renders, the same `ObjectIdentifier` appears in both `collectComponentIDs(oldTree)` and the new tree, so `firePostRenderLifecycle` routes it through `onChange`. The lower-level Task 2 tests fed `preExistingIDs` by hand; this test feeds it from a real prior-render snapshot.

- [ ] **Step 1: Write the failing test**

Append to `Tests/SwiflowTests/Reactivity/RendererComponentTests.swift`:

```swift
// MARK: - Nested onChange (end-to-end via diff() instance reuse)

@Suite("Nested onChange fires on every reused component anchor after re-render, children-first")
@MainActor
struct NestedOnChangeTests {

    final class Inner: Component {
        fileprivate let log: LifecycleLog
        fileprivate init(log: LifecycleLog) { self.log = log }
        var body: VNode { .text("inner") }
        func onChange() { log.calls.append("inner.change") }
    }

    final class Outer: Component {
        fileprivate let log: LifecycleLog
        fileprivate let inner: Inner
        fileprivate init(log: LifecycleLog, inner: Inner) { self.log = log; self.inner = inner }
        var body: VNode { embed { self.inner } }
        func onChange() { log.calls.append("outer.change") }
    }

    @Test("re-render of an unchanged nested tree fires onChange on Inner AND Outer (Inner first)")
    func reRenderFiresOnChangeNestedChildrenFirst() {
        let log = LifecycleLog()
        let inner = Inner(log: log)
        let outer = Outer(log: log, inner: inner)
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        // First render — mounts Outer → Inner.
        let v1 = VNode.component(.init(Outer.self) { outer })
        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)

        // Snapshot pre-existing instances, then re-render with the SAME outer
        // instance (factory returns the same reference, so diff's reuse arm
        // keeps Outer's instance and re-runs its body, which re-embeds inner).
        let preIDs = collectComponentIDs(first.newMountTree)
        let v2 = VNode.component(.init(Outer.self) { outer })
        let second = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        firePostRenderLifecycle(second.newMountTree, preExistingIDs: preIDs)

        #expect(log.calls == ["inner.change", "outer.change"])
    }

    /// Sanity check that `onChange(of:_:perform:)` (the existing
    /// `OnChangeStorage`-backed convenience extension) still works correctly
    /// when invoked from a NESTED component's `onChange()` override. Pre-Phase-18
    /// no nested component's `onChange()` fired at all, so this code path was
    /// silently dead for nested usage.
    final class FilteredInner: Component {
        fileprivate var trackedValue: Int = 0
        fileprivate var performCalls: [Int] = []
        var body: VNode { .text("filtered") }
        func onChange() {
            onChange(of: trackedValue) { newValue in
                performCalls.append(newValue)
            }
        }
    }

    final class FilteredOuter: Component {
        fileprivate let inner: FilteredInner
        fileprivate init(inner: FilteredInner) { self.inner = inner }
        var body: VNode { embed { self.inner } }
    }

    @Test("onChange(of:) convenience on a nested component fires perform only on actual value changes")
    func onChangeOfFiltersValueChangesOnNestedComponent() {
        let inner = FilteredInner()
        let outer = FilteredOuter(inner: inner)
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        // First render. inner.trackedValue == 0; onChange does not fire on
        // first mount (only onAppear), so performCalls stays empty.
        let v1 = VNode.component(.init(FilteredOuter.self) { outer })
        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)
        firePostRenderLifecycle(first.newMountTree, preExistingIDs: [])
        #expect(inner.performCalls == [], "first mount fires onAppear, not onChange")

        // Re-render with trackedValue unchanged. onChange fires (nested!), but
        // onChange(of:) sees no diff vs seeded value → perform does not run.
        let preIDs1 = collectComponentIDs(first.newMountTree)
        let v2 = VNode.component(.init(FilteredOuter.self) { outer })
        let second = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)
        firePostRenderLifecycle(second.newMountTree, preExistingIDs: preIDs1)
        #expect(inner.performCalls == [], "value unchanged — perform suppressed by onChange(of:) filter")

        // Mutate then re-render. onChange fires; onChange(of:) sees 0 → 42; perform runs.
        inner.trackedValue = 42
        let preIDs2 = collectComponentIDs(second.newMountTree)
        let v3 = VNode.component(.init(FilteredOuter.self) { outer })
        let third = diff(mounted: second.newMountTree, next: v3, handles: handles, handlers: handlers)
        firePostRenderLifecycle(third.newMountTree, preExistingIDs: preIDs2)
        #expect(inner.performCalls == [42], "value changed 0 → 42 — perform fires once with the new value")
    }
}
```

- [ ] **Step 2: Run test to verify it passes (the helpers from Tasks 1–2 already implement the contract)**

Run: `swift test --filter NestedOnChangeTests`
Expected: PASS. (If it fails, the reuse path in `diff()` isn't producing a tree whose Inner anchor's instance ID matches the pre-snapshot — that's a regression worth investigating before continuing.)

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiflowTests/Reactivity/RendererComponentTests.swift
git commit -m "$(cat <<'EOF'
test(lifecycle): nested onChange fires children-first via diff() reuse

End-to-end coverage that the pre-diff ID snapshot + post-diff walker
correctly identify reused nested instances and route them through
onChange (not onAppear). Complements Task 2's white-box tests of
firePostRenderLifecycle.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Integration test — mid-render new mount fires `onAppear` not `onChange`

**Files:**
- Modify: `Tests/SwiflowTests/Reactivity/RendererComponentTests.swift` (append at end)

- [ ] **Step 1: Write the failing test**

Append to `Tests/SwiflowTests/Reactivity/RendererComponentTests.swift`:

```swift
// MARK: - Mid-render mount (conditional reveal)

@Suite("Component mounted mid-render fires onAppear (not onChange) on that render; reused parent fires onChange")
@MainActor
struct MidRenderMountTests {

    final class Inner: Component {
        fileprivate let log: LifecycleLog
        fileprivate init(log: LifecycleLog) { self.log = log }
        var body: VNode { .text("inner") }
        func onAppear() { log.calls.append("inner.appear") }
        func onChange() { log.calls.append("inner.change") }
    }

    /// Container whose body conditionally embeds Inner. The flag is mutated
    /// directly between renders — no @State / scheduler — so the test can
    /// drive the lifecycle path without involving the WASM-only Renderer.
    final class Container: Component {
        fileprivate let log: LifecycleLog
        fileprivate var showInner: Bool = false
        fileprivate init(log: LifecycleLog) { self.log = log }
        var body: VNode {
            if showInner {
                return embed { Inner(log: self.log) }
            } else {
                return .text("hidden")
            }
        }
        func onAppear() { log.calls.append("container.appear") }
        func onChange() { log.calls.append("container.change") }
    }

    @Test("conditional reveal: Inner fires onAppear once, Container fires onChange once, both in the same re-render")
    func conditionalRevealFiresAppearOnNewAndChangeOnReused() {
        let log = LifecycleLog()
        let container = Container(log: log)
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        // First render: showInner == false, no Inner mounted.
        let v1 = VNode.component(.init(Container.self) { container })
        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)
        firePostRenderLifecycle(first.newMountTree, preExistingIDs: [])
        #expect(log.calls == ["container.appear"], "first mount: only Container fires onAppear")

        // Flip the flag — Container's next body returns embed { Inner }.
        container.showInner = true
        log.calls.removeAll()

        // Re-render: same Container instance reused; Inner is newly mounted.
        let preIDs = collectComponentIDs(first.newMountTree)
        let v2 = VNode.component(.init(Container.self) { container })
        let second = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)
        firePostRenderLifecycle(second.newMountTree, preExistingIDs: preIDs)

        // Children-first → Inner's appear runs before Container's change.
        #expect(log.calls == ["inner.appear", "container.change"])
    }

    @Test("conditional reveal: Inner does NOT fire onChange on the render it was mounted")
    func newlyMountedInnerDoesNotFireOnChange() {
        let log = LifecycleLog()
        let container = Container(log: log)
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        let v1 = VNode.component(.init(Container.self) { container })
        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)
        firePostRenderLifecycle(first.newMountTree, preExistingIDs: [])

        container.showInner = true
        log.calls.removeAll()
        let preIDs = collectComponentIDs(first.newMountTree)
        let v2 = VNode.component(.init(Container.self) { container })
        let second = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)
        firePostRenderLifecycle(second.newMountTree, preExistingIDs: preIDs)

        let innerChangeCount = log.calls.filter { $0 == "inner.change" }.count
        #expect(innerChangeCount == 0, "Inner was freshly mounted this render — it must fire onAppear, never onChange")
    }
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `swift test --filter MidRenderMountTests`
Expected: PASS (2 tests).

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiflowTests/Reactivity/RendererComponentTests.swift
git commit -m "$(cat <<'EOF'
test(lifecycle): mid-render new mounts fire onAppear, reused parent fires onChange

Covers the second lifecycle gap closed by Phase 18: when a component's
body conditionally introduces a new nested component (if/else flip,
list growth), that new component now sees onAppear exactly once on
the render it was mounted, never onChange. The reused parent fires
onChange once. Children-first ordering preserved.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: CHANGELOG entry

**Files:**
- Modify: `CHANGELOG.md` (insert above the topmost existing entry)

- [ ] **Step 1: Read the existing CHANGELOG to find the right insertion point**

Run: `head -40 CHANGELOG.md`
Expected: First entry should be `[v0.1.3]` or `[Phase 17]` (per session summary). Note the heading style used.

- [ ] **Step 2: Insert the Phase 18 entry**

Insert a new section immediately above the topmost existing entry, using the same heading style observed in Step 1. Content:

```markdown
## [Phase 18] — `onChange` for nested components

### Behavior changes
- `Component.onChange()` now fires on **every** component in the tree after each re-render, not just the root. Components that override `onChange()` on a nested component will now see the hook fire as documented (the prior root-only behavior was a bug). React `componentDidUpdate` semantics: fires once per reused instance per render, regardless of whether body output changed. Users who want value-aware filtering should use the existing `onChange(of:_:perform:)` convenience extension from inside their `onChange()` override.
- `Component.onAppear()` now fires on components mounted **mid-render** (e.g. revealed by a conditional `if/else` branch flip, or appended to a list during a re-render). Previously `onAppear` only fired on the components present at first mount; mid-render new mounts silently skipped it.

### Internals
- New helpers `collectComponentIDs(_:)` and `firePostRenderLifecycle(_:preExistingIDs:)` in `Sources/Swiflow/Diff/Diff.swift` partition components per render into reused (→ `onChange`) vs freshly mounted (→ `onAppear`). The Renderer's two-branch lifecycle dispatch collapsed into a single call. `fireOnAppearTree` removed (replaced by `firePostRenderLifecycle(_, preExistingIDs: [])`).
- No public API changes. No JS driver changes. No patch protocol changes.
```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs(changelog): document Phase 18 lifecycle fixes

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Final verification (after all tasks)

Run the full suite manually before declaring complete:

- [ ] `swift test` — every Swift test passes, including the new suites added in Tasks 1, 2, 6, 7.
- [ ] `cd js-driver && npm test` — JS driver tests unaffected (this change is Swift-only); expect green.
- [ ] `npm run test:counter && npm run test:router && npm run test:sw` — three Playwright suites stay green. Per the `feedback_playwright_ci_gap` memory, run these locally; CI runs them PR-only and we push to main. Counter and Router exercise nested components extensively; if either flakes, investigate before declaring done — that's a regression in the lifecycle change.

If any Playwright test fails, the root-cause investigation skill applies. The most likely culprit: a user component override that previously relied on `onChange()` being a silent no-op (now firing) or `onAppear()` being skipped on mid-render mounts (now firing). Audit the failing component for re-entrant state mutations inside the hook.
