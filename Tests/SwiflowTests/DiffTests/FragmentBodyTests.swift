// Tests/SwiflowTests/DiffTests/FragmentBodyTests.swift
// Pre-launch audit Wave-3 (the "fragment-body family", one root cause): a
// component/env-override body that is a bare `.fragment` has NO single DOM
// handle, but `MountTree.domHandle` returned the fragment's STRUCTURAL handle
// — one the JS driver never saw. Consequences: the component-arm's identity
// splice emitted removeChild/appendChild with a phantom handle (driver throw →
// patch batch abort), and exit-animation removal silently no-opped + destroyed
// children immediately. This was the diff's ONLY unguarded footgun.
//
// Now: a DEBUG diagnostic fires at mount (wrap multi-root bodies in an
// element), and the splice/removal paths route through collectDOMRoots so
// they degrade safely (real handles only; no animation for fragment bodies).
import Testing
@testable import Swiflow

@MainActor private final class FragBody: Component {
    var toggle = false
    var body: VNode {
        toggle
            ? .element(ElementData(tag: "p", children: [.text("single")]))
            : .fragment([
                .element(ElementData(tag: "span", children: [.text("a")])),
                .element(ElementData(tag: "b", children: [.text("b")])),
            ])
    }
}

@MainActor private final class FragAnim: Component {
    var body: VNode {
        .fragment([
            .element(ElementData(tag: "span", children: [.text("x")])),
            .element(ElementData(tag: "i", children: [.text("y")])),
        ])
    }
    static var exitAnimation: String? = "out 1s"
    static var exitDuration: Double? = 0.1
}

/// Every DOM-referencing patch must use a handle the driver KNOWS — one that
/// appeared in a create* patch (or is the given root container handle).
@MainActor private func assertNoPhantomHandles(_ patches: [Patch], container: Int? = nil) {
    var known = Set<Int>()
    var removedChildren = Set<Int>()
    if let container { known.insert(container) }
    for p in patches {
        switch p {
        case .createElement(let h, _), .createText(let h, _), .createRawHTML(let h, _):
            known.insert(h)
        case .removeChild(let parent, let child):
            #expect(known.contains(parent), "removeChild parent \(parent) never created")
            #expect(known.contains(child), "removeChild child \(child) never created (phantom)")
            #expect(!removedChildren.contains(child), "removeChild \(child) emitted twice")
            removedChildren.insert(child)
        case .appendChild(let parent, let child):
            #expect(known.contains(parent), "appendChild parent \(parent) never created")
            #expect(known.contains(child), "appendChild child \(child) never created (phantom)")
        case .animateExit(let handle, let parentHandle, _, _):
            #expect(known.contains(handle), "animateExit handle \(handle) never created (phantom)")
            #expect(known.contains(parentHandle), "animateExit parent never created")
        default: break
        }
    }
}

@Suite("Fragment-bodied components (diff degrade + diagnostic)")
@MainActor
struct FragmentBodyTests {

    @Test("mounting a fragment-bodied component fires the DEBUG diagnostic")
    func mountDiagnoses() {
        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let parent = VNode.element(ElementData(tag: "div", children: [
            .component(ComponentDescription(FragBody.self, factory: { FragBody() })),
        ]))
        _ = diff(mounted: nil, next: parent, handles: handles, handlers: handlers)
        #expect(captured.contains { $0.contains("fragment") },
                "a bare .fragment body must be diagnosed (wrap it in an element)")
    }

    @Test("body identity swap through a fragment emits no phantom handles")
    func spliceDegradesSafely() {
        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        var patches: [Patch] = []
        let root = VNode.element(ElementData(tag: "div", children: [
            .component(ComponentDescription(FragBody.self, factory: { FragBody() })),
        ]))
        let mounted = mount(root, into: &patches, handles: handles, handlers: handlers, scheduler: SyncScheduler { _ in })
        // Flip the body fragment → single element and re-diff.
        (mounted.children[0].component!.instance as! FragBody).toggle = true
        var updatePatches: [Patch] = []
        _ = update(mounted: mounted.children[0],
                   next: .component(ComponentDescription(FragBody.self, factory: { FragBody() })),
                   into: &updatePatches,
                   handles: handles, handlers: handlers, scheduler: SyncScheduler { _ in })
        assertNoPhantomHandles(patches + updatePatches)
    }

    @Test("removing a fragment-bodied component with exitAnimation degrades: real handles, no phantom animateExit")
    func removalDegradesSafely() {
        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        var patches: [Patch] = []
        let two = VNode.element(ElementData(tag: "div", children: [
            .component(ComponentDescription(FragAnim.self, key: "a", factory: { FragAnim() })),
            .component(ComponentDescription(FragAnim.self, key: "b", factory: { FragAnim() })),
        ]))
        let mounted = mount(two, into: &patches, handles: handles, handlers: handlers, scheduler: SyncScheduler { _ in })
        var updatePatches: [Patch] = []
        let one = VNode.element(ElementData(tag: "div", children: [
            .component(ComponentDescription(FragAnim.self, key: "b", factory: { FragAnim() })),
        ]))
        _ = update(mounted: mounted, next: one,
                   into: &updatePatches,
                   handles: handles, handlers: handlers, scheduler: SyncScheduler { _ in })
        assertNoPhantomHandles(patches + updatePatches)
        // Degrade contract: fragment bodies get NO exit animation (no single node to animate).
        let anims = updatePatches.filter { if case .animateExit = $0 { return true }; return false }
        #expect(anims.isEmpty, "no animateExit for a multi-root body")
    }
}
