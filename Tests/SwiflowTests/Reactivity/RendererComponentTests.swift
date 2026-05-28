// Tests/SwiflowTests/Reactivity/RendererComponentTests.swift
//
// These tests verify the pure-Swift (Swiflow-module) behaviors that Task 8
// wires together in the Renderer: Component lifecycle hooks (onAppear,
// onChange, onDisappear) and the Scheduler coalescing contract.
//
// The Renderer itself (SwiflowWeb module) requires JavaScriptKit and can only
// be exercised in a WASM/browser environment. These tests target the Swiflow
// module (no JavaScriptKit dependency) and therefore compile and run on
// macOS/Linux for fast feedback during development.
//
// Renderer-specific construction tests (init shape, schedulerBox wiring) are
// integration tests covered by the WASM-side e2e harness.

import Testing
@testable import Swiflow

// MARK: - Helpers

/// A Scheduler that records every call so tests can assert call counts.
private final class RecordingScheduler: Scheduler {
    var markCount = 0
    var flushCount = 0
    var lastMarked: AnyComponent?

    func markDirty(_ component: AnyComponent) {
        markCount += 1
        lastMarked = component
    }

    func flush() {
        flushCount += 1
    }
}

// MARK: - onDisappear tests

@Suite("Lifecycle: onDisappear fires via destroy()")
@MainActor
struct OnDisappearTests {

    /// A component that records whether onDisappear was called.
    final class Tracked: Component {
        var disappearCalled = false
        var body: VNode { .text("tracked") }
        func onDisappear() { disappearCalled = true }
    }

    @Test("onDisappear fires when a component is replaced by a different type (diff default arm)")
    func onDisappearFiresOnTypeReplacement() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        // First render: mount a Tracked component.
        let v1 = VNode.component(.init(Tracked.self) { Tracked() })
        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)

        // Capture the instance so we can assert on it after the second diff.
        let instance = first.newMountTree.component?.instance as? Tracked
        #expect(instance != nil)
        #expect(instance?.disappearCalled == false, "onDisappear must not fire during mount")

        // Second render: replace with a plain element — forces destroy(old) + mount(new).
        let v2 = VNode.element(ElementData(tag: "p"))
        _ = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        #expect(instance?.disappearCalled == true, "onDisappear must fire when the component is destroyed")
    }

    @Test("onDisappear fires on nested component anchors when a parent is replaced")
    func onDisappearFiresOnNestedComponent() {
        final class Inner: Component {
            var disappearCalled = false
            var body: VNode { .text("inner") }
            func onDisappear() { disappearCalled = true }
        }
        final class Outer: Component {
            var disappearCalled = false
            var body: VNode { embed { Inner() } }
            func onDisappear() { disappearCalled = true }
        }

        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        // Mount Outer (which mounts Inner as its body).
        let v1 = VNode.component(.init(Outer.self) { Outer() })
        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)

        let outerInstance = first.newMountTree.component?.instance as? Outer
        // Inner lives inside the componentBody subtree of the outer anchor.
        // Navigate: outerAnchor.componentBody is the Inner anchor.
        let innerAnchor = first.newMountTree.componentBody
        let innerInstance = innerAnchor?.component?.instance as? Inner

        #expect(outerInstance != nil)
        #expect(innerInstance != nil)

        // Replace Outer with a plain element — destroy() should walk the
        // entire subtree and fire onDisappear on both components.
        let v2 = VNode.element(ElementData(tag: "section"))
        _ = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        #expect(outerInstance?.disappearCalled == true, "Outer's onDisappear must fire")
        #expect(innerInstance?.disappearCalled == true, "Inner's onDisappear must fire (destroy walks componentBody)")
    }

    @Test("onDisappear does NOT fire when a component is updated (same type, same key)")
    func onDisappearDoesNotFireOnUpdate() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        let v1 = VNode.component(.init(Tracked.self) { Tracked() })
        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)
        let instance = first.newMountTree.component?.instance as? Tracked
        #expect(instance != nil)

        // Same description — the reuse arm is taken, destroy() is never called.
        let v2 = VNode.component(.init(Tracked.self) { Tracked() })
        _ = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        #expect(instance?.disappearCalled == false, "onDisappear must NOT fire during a component update (reuse path)")
    }
}

// MARK: - Scheduler coalescing contract

@MainActor @Component
private final class RC_Counter {
    @State var n: Int = 0
    var body: VNode { .text("n=\(n)") }
}

@Suite("RAFScheduler contract (SyncScheduler used as stand-in)")
@MainActor
struct SchedulerCoalescingTests {
    // RAFScheduler is JavaScriptKit-only and therefore not available in this
    // test target. The SyncScheduler is used here to verify that the
    // Scheduler protocol contract — as used by the Renderer — correctly
    // marks dirty components and integrates with the diff.
    //
    // RAFScheduler-specific behaviors (rAF deduplication, one-callback-per-
    // flush semantics) are exercised by the WASM-side e2e harness.

    @Test("SyncScheduler marks dirty exactly once per unique component regardless of mutation count")
    func deduplicatesMarksForSameComponent() {
        var renderCount = 0
        let scheduler = SyncScheduler { _ in renderCount += 1 }
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        let v = VNode.component(.init(RC_Counter.self) { RC_Counter() })
        let result = diff(mounted: nil, next: v, handles: handles, handlers: handlers, scheduler: scheduler)

        let counter = result.newMountTree.component?.instance as? RC_Counter
        #expect(counter != nil)

        // Mark the same component dirty three times before any flush.
        counter?.n = 1
        counter?.n = 2
        counter?.n = 3

        // Flush should rerender exactly once (scheduler deduplicates).
        scheduler.flush()
        #expect(renderCount == 1, "One flush should produce exactly one rerender callback regardless of mutation count")
    }

    @Test("Scheduler receives the correct AnyComponent instance when @State mutates")
    func schedulerReceivesCorrectComponent() {
        let scheduler = RecordingScheduler()
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        let v = VNode.component(.init(RC_Counter.self) { RC_Counter() })
        let result = diff(mounted: nil, next: v, handles: handles, handlers: handlers, scheduler: scheduler)

        let counter = result.newMountTree.component?.instance as? RC_Counter
        let any = result.newMountTree.component

        counter?.n = 7

        // The scheduler must have been called with an AnyComponent wrapping
        // the same Counter instance.
        #expect(scheduler.markCount == 1)
        #expect(scheduler.lastMarked?.instance === counter, "markDirty must be called with the AnyComponent for this Counter instance")
        #expect(scheduler.lastMarked?.instance === any?.instance)
    }

    @Test("diff() with nil scheduler does not mark dirty on @State mutation")
    func nilSchedulerSilent() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        let v = VNode.component(.init(RC_Counter.self) { RC_Counter() })
        let result = diff(mounted: nil, next: v, handles: handles, handlers: handlers, scheduler: nil)

        let counter = result.newMountTree.component?.instance as? RC_Counter
        counter?.n = 99  // must not crash, no scheduler to call
        #expect(counter?.n == 99)
    }
}

// MARK: - onAppear / onChange via ComponentDescription factory

@Suite("Lifecycle: onAppear and onChange via standard diff")
@MainActor
struct AppearChangeLifecycleTests {
    // Note: onAppear and onChange are RENDERER-level lifecycle hooks — they
    // fire in Renderer.renderOnce() after patches are applied, not inside
    // diff(). These tests verify that the Component protocol methods are
    // callable directly on an `any Component` existential (no trampoline
    // needed since neither hook has a Self-typed parameter). Full integration
    // (hooks fire at the right time with DOM live) is exercised by the WASM
    // e2e harness.

    final class LifecycleTracker: Component {
        var appearCalled = false
        var changeCallCount = 0
        var body: VNode { .text("tracker") }

        func onAppear() { appearCalled = true }
        func onChange() { changeCallCount += 1 }
    }

    @Test("onAppear can be called directly on an existential component instance")
    func onAppearCallable() {
        let tracker = LifecycleTracker()
        let any: any Component = tracker
        any.onAppear()
        #expect(tracker.appearCalled)
    }

    @Test("onChange can be called directly on an existential component instance (no trampoline needed)")
    func onChangeCallable() {
        let tracker = LifecycleTracker()
        let any: any Component = tracker
        any.onChange()
        #expect(tracker.changeCallCount == 1)
    }
}

// MARK: - onAppear via tree walk

/// Records ordering of onAppear calls across nested components.
/// Class (not struct) so multiple components can share the same instance by reference.
@MainActor
private final class OnAppearLog {
    var calls: [String] = []
}

@Suite("Lifecycle: first-mount onAppear via firePostRenderLifecycle, children-first")
@MainActor
struct OnAppearTreeWalkTests {

    /// Inner component, mounted as Outer's body. Appended "inner" to the log on appear.
    final class Inner: Component {
        fileprivate let log: OnAppearLog
        fileprivate init(log: OnAppearLog) { self.log = log }
        var body: VNode { .text("inner") }
        func onAppear() { log.calls.append("inner") }
    }

    /// Outer component, embeds Inner. Appended "outer" to the log on appear.
    final class Outer: Component {
        fileprivate let log: OnAppearLog
        fileprivate init(log: OnAppearLog) { self.log = log }
        var body: VNode { embed { Inner(log: self.log) } }
        func onAppear() { log.calls.append("outer") }
    }

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
}

// MARK: - Component type-swap → removeChild/appendChild patches

/// Phase 17: when a component's body returns a different component type
/// between renders, the diff must emit a removeChild + appendChild pair on
/// the surrounding DOM ancestor so the JS driver detaches the old root and
/// attaches the new one. Without this, the mount tree updates but the DOM
/// stays stuck on the original component (and routers / conditional UIs
/// silently appear frozen).
@Suite("Component type-swap inside an element parent emits DOM-level swap patches")
@MainActor
struct ComponentTypeSwapTests {

    final class PageA: Component {
        var body: VNode { .text("A") }
    }
    final class PageB: Component {
        var body: VNode { .text("B") }
    }

    @Test("Element child component swap emits removeChild + appendChild on the DOM ancestor")
    func componentTypeSwapEmitsRemoveAndAppend() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        // Mount: <div>{ PageA() }</div>
        let elementVNode = VNode.element(ElementData(
            tag: "div",
            children: [.component(.init(PageA.self) { PageA() })]
        ))
        let first = diff(mounted: nil, next: elementVNode, handles: handles, handlers: handlers)

        let divHandle = first.newMountTree.handle
        let oldChildAnchor = first.newMountTree.children[0]
        let oldChildDomHandle = oldChildAnchor.domHandle

        // Re-render: <div>{ PageB() }</div> — different component type at the
        // same child slot. IndexedChildrenDiff's existing remove/append logic
        // covers this case (component anchors inside an element parent are
        // tracked as children of that element).
        let nextVNode = VNode.element(ElementData(
            tag: "div",
            children: [.component(.init(PageB.self) { PageB() })]
        ))
        let second = diff(mounted: first.newMountTree, next: nextVNode, handles: handles, handlers: handlers)

        let newChildAnchor = second.newMountTree.children[0]
        let newChildDomHandle = newChildAnchor.domHandle

        // Must have a removeChild for the old child and an appendChild/insertBefore
        // for the new child, both parented at the surrounding <div>.
        let hasRemoveChild = second.patches.contains(where: {
            if case .removeChild(let parent, let child) = $0 {
                return parent == divHandle && child == oldChildDomHandle
            }
            return false
        })
        let hasAppendOrInsert = second.patches.contains(where: {
            if case .appendChild(let parent, let child) = $0 {
                return parent == divHandle && child == newChildDomHandle
            }
            if case .insertBefore(let parent, let child, _) = $0 {
                return parent == divHandle && child == newChildDomHandle
            }
            return false
        })
        #expect(hasRemoveChild, "Expected removeChild(parent: div, child: oldChild) in diff patches")
        #expect(hasAppendOrInsert, "Expected appendChild/insertBefore(parent: div, child: newChild) in diff patches")
    }

    @Test("EnvironmentOverride body type-swap emits DOM-level swap at the surrounding element")
    func envOverrideBodyTypeSwapEmitsSwap() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        // Mount: <div>{ withEnvironment(\.locale, "en") { PageA() } }</div>
        // The env override's body is the component anchor. Across renders,
        // we keep the same env override outer but swap the inner component
        // type — the env-override arm must propagate the swap to the
        // surrounding <div>.
        let initial = VNode.element(ElementData(
            tag: "div",
            children: [.environmentOverride(
                EnvironmentValues(),
                .component(.init(PageA.self) { PageA() })
            )]
        ))
        let first = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
        let divHandle = first.newMountTree.handle
        let envOverrideNode = first.newMountTree.children[0]
        let oldBodyDomHandle = envOverrideNode.domHandle

        // Same env-override outer, swapped inner component type.
        let next = VNode.element(ElementData(
            tag: "div",
            children: [.environmentOverride(
                EnvironmentValues(),
                .component(.init(PageB.self) { PageB() })
            )]
        ))
        let second = diff(mounted: first.newMountTree, next: next, handles: handles, handlers: handlers)
        let updatedEnvNode = second.newMountTree.children[0]
        let newBodyDomHandle = updatedEnvNode.domHandle

        // Body identity changed; outer env-override node is preserved.
        #expect(oldBodyDomHandle != newBodyDomHandle, "Inner body should have changed DOM handle on type swap")
        let hasRemove = second.patches.contains(where: {
            if case .removeChild(let parent, let child) = $0 {
                return parent == divHandle && child == oldBodyDomHandle
            }
            return false
        })
        let hasAttach = second.patches.contains(where: {
            if case .appendChild(let parent, let child) = $0 {
                return parent == divHandle && child == newBodyDomHandle
            }
            return false
        })
        #expect(hasRemove, "EnvironmentOverride body swap must emit removeChild on the surrounding <div>")
        #expect(hasAttach, "EnvironmentOverride body swap must emit appendChild on the surrounding <div>")
    }
}

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
        defer { OnChangeStorage.remove(for: ObjectIdentifier(inner)) }
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
