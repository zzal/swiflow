// Tests/SwiflowTests/Reactivity/RendererComponentTests.swift
//
// These tests verify the pure-Swift (Swiflow-module) behaviors that Task 8
// wires together in the Renderer: Component lifecycle hooks (onMount,
// onUpdate, onUnmount) and the Scheduler coalescing contract.
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

// MARK: - onUnmount tests

@Suite("Lifecycle: onUnmount fires via destroy()")
struct OnUnmountTests {

    /// A component that records whether onUnmount was called.
    final class Tracked: Component {
        var unmountCalled = false
        var body: VNode { .text("tracked") }
        func onUnmount() { unmountCalled = true }
    }

    @Test("onUnmount fires when a component is replaced by a different type (diff default arm)")
    func onUnmountFiresOnTypeReplacement() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        // First render: mount a Tracked component.
        let v1 = VNode.component(.init(Tracked.self) { Tracked() })
        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)

        // Capture the instance so we can assert on it after the second diff.
        let instance = first.newMountTree.component?.instance as? Tracked
        #expect(instance != nil)
        #expect(instance?.unmountCalled == false, "onUnmount must not fire during mount")

        // Second render: replace with a plain element — forces destroy(old) + mount(new).
        let v2 = VNode.element(ElementData(tag: "p"))
        _ = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        #expect(instance?.unmountCalled == true, "onUnmount must fire when the component is destroyed")
    }

    @Test("onUnmount fires on nested component anchors when a parent is replaced")
    func onUnmountFiresOnNestedComponent() {
        final class Inner: Component {
            var unmountCalled = false
            var body: VNode { .text("inner") }
            func onUnmount() { unmountCalled = true }
        }
        final class Outer: Component {
            var unmountCalled = false
            var body: VNode { component({ Inner() }) }
            func onUnmount() { unmountCalled = true }
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
        // entire subtree and fire onUnmount on both components.
        let v2 = VNode.element(ElementData(tag: "section"))
        _ = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        #expect(outerInstance?.unmountCalled == true, "Outer's onUnmount must fire")
        #expect(innerInstance?.unmountCalled == true, "Inner's onUnmount must fire (destroy walks componentBody)")
    }

    @Test("onUnmount does NOT fire when a component is updated (same type, same key)")
    func onUnmountDoesNotFireOnUpdate() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        let v1 = VNode.component(.init(Tracked.self) { Tracked() })
        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)
        let instance = first.newMountTree.component?.instance as? Tracked
        #expect(instance != nil)

        // Same description — the reuse arm is taken, destroy() is never called.
        let v2 = VNode.component(.init(Tracked.self) { Tracked() })
        _ = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        #expect(instance?.unmountCalled == false, "onUnmount must NOT fire during a component update (reuse path)")
    }
}

// MARK: - Scheduler coalescing contract

@Suite("RAFScheduler contract (InProcessScheduler used as stand-in)")
struct SchedulerCoalescingTests {
    // RAFScheduler is JavaScriptKit-only and therefore not available in this
    // test target. The InProcessScheduler is used here to verify that the
    // Scheduler protocol contract — as used by the Renderer — correctly
    // marks dirty components and integrates with the diff.
    //
    // RAFScheduler-specific behaviors (rAF deduplication, one-callback-per-
    // flush semantics) are exercised by the WASM-side e2e harness.

    final class Counter: Component {
        @State var n: Int = 0
        var body: VNode { .text("n=\(n)") }
    }

    @Test("InProcessScheduler marks dirty exactly once per unique component regardless of mutation count")
    func deduplicatesMarksForSameComponent() {
        var renderCount = 0
        let scheduler = InProcessScheduler { _ in renderCount += 1 }
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        let v = VNode.component(.init(Counter.self) { Counter() })
        let result = diff(mounted: nil, next: v, handles: handles, handlers: handlers, scheduler: scheduler)

        let counter = result.newMountTree.component?.instance as? Counter
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

        let v = VNode.component(.init(Counter.self) { Counter() })
        let result = diff(mounted: nil, next: v, handles: handles, handlers: handlers, scheduler: scheduler)

        let counter = result.newMountTree.component?.instance as? Counter
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

        let v = VNode.component(.init(Counter.self) { Counter() })
        let result = diff(mounted: nil, next: v, handles: handles, handlers: handlers, scheduler: nil)

        let counter = result.newMountTree.component?.instance as? Counter
        counter?.n = 99  // must not crash, no scheduler to call
        #expect(counter?.n == 99)
    }
}

// MARK: - onMount / onUpdate via ComponentDescription factory

@Suite("Lifecycle: onMount and onUpdate via standard diff")
struct MountUpdateLifecycleTests {
    // Note: onMount and onUpdate are RENDERER-level lifecycle hooks — they fire
    // in Renderer.renderOnce() after patches are applied, not inside diff().
    // These tests therefore verify only that the Component protocol methods
    // are callable on a concrete instance (the existential dispatch pattern
    // used by Renderer). Full integration (hooks fire at the right time with
    // DOM live) is exercised by the WASM e2e harness.

    final class LifecycleTracker: Component {
        var mountCalled = false
        var updateCallCount = 0
        var body: VNode { .text("tracker") }

        func onMount() { mountCalled = true }
        func onUpdate(prev: LifecycleTracker) { updateCallCount += 1 }
        func onUnmount() {}
    }

    @Test("onMount can be called directly on an existential component instance")
    func onMountCallable() {
        let tracker = LifecycleTracker()
        let any: any Component = tracker
        any.onMount()
        #expect(tracker.mountCalled)
    }

    @Test("onUpdate requires a generic trampoline — matches Renderer's callOnUpdate pattern")
    func onUpdateViaTrampolineCallable() {
        let tracker = LifecycleTracker()

        // The trampoline that Renderer uses (reproduced here for verification).
        func callOnUpdate<C: Component>(_ c: C) { c.onUpdate(prev: c) }

        let any: any Component = tracker
        // Implicit existential opening (SE-0352): passing `any Component` to
        // a generic `C: Component` parameter opens the existential.
        callOnUpdate(any)
        #expect(tracker.updateCallCount == 1)
    }
}
