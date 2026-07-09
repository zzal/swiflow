// Tests/SwiflowTests/DiffTests/TeardownRoutineTests.swift
//
// Audit VI Wave-2 #3: ONE teardown routine for every render root.
// `destroy` gates its componentDidUnmount notification on
// `RenderObserverBox.current` — the browser Renderer.teardown() called it
// with NO observer installed while TestRenderer.unmount() installed one, so
// query-subscription cleanup fired in tests but NEVER in the browser.
// `teardownMountTree` is the shared routine both roots now call; these
// tests pin its observer contract.
import Testing
@testable import Swiflow

@MainActor
private final class Leaf: Component {
    var body: VNode { .text("leaf") }
}

@MainActor
private final class Parent: Component {
    var body: VNode {
        element("div", attributes: [], children: [
            .component(ComponentDescription(Leaf.self) { Leaf() })
        ])
    }
}

@MainActor
private final class Recorder: RenderObserver {
    var unmounted: [ObjectIdentifier] = []
    func willEvaluate(owner: AnyComponent, scheduler: (any Scheduler)?) {}
    func didEvaluate() {}
    func componentDidUnmount(_ owner: AnyComponent) {
        unmounted.append(ObjectIdentifier(owner.instance))
    }
}

@Suite("teardownMountTree — the shared root-teardown routine")
@MainActor
struct TeardownRoutineTests {

    private func mountTree(_ vnode: VNode, handlers: HandlerRegistry) -> MountNode {
        var patches: [Patch] = []
        return mount(vnode, into: &patches, handles: HandleAllocator(),
                     handlers: handlers, scheduler: nil, depth: 0, path: "",
                     environment: .init())
    }

    @Test("notifies componentDidUnmount for EVERY component in the tree")
    func notifiesAllUnmounts() {
        let handlers = HandlerRegistry()
        let tree = mountTree(
            .component(ComponentDescription(Parent.self) { Parent() }),
            handlers: handlers
        )

        let rec = Recorder()
        _ = teardownMountTree(tree, handlers: handlers, observer: rec)
        #expect(rec.unmounted.count == 2, "parent + leaf")
    }

    @Test("the observer is installed only for the teardown — ambient is nil after")
    func ambientScoped() {
        let handlers = HandlerRegistry()
        let tree = mountTree(
            .component(ComponentDescription(Leaf.self) { Leaf() }),
            handlers: handlers
        )

        _ = teardownMountTree(tree, handlers: handlers, observer: Recorder())
        #expect(RenderObserverBox.current == nil)
    }

    @Test("a nil observer tears down without notifications and without crashing")
    func nilObserver() {
        let handlers = HandlerRegistry()
        let tree = mountTree(
            .component(ComponentDescription(Leaf.self) { Leaf() }),
            handlers: handlers
        )
        _ = teardownMountTree(tree, handlers: handlers, observer: nil)
        #expect(RenderObserverBox.current == nil)
    }
}
