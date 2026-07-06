// Tests/SwiflowTests/Reactivity/EmbedRefreshTests.swift
//
// `embed(_:refresh:)` — the additive prop-push that flows changed parent data
// into a REUSED embedded instance without the remount that re-keying forces.
// Exercised at the host-testable Diff layer (the Renderer is JavaScriptKit-only):
// mount → mutate a stand-in for preserved state → re-render with a refresh that
// pushes a new prop → assert the SAME instance now renders the new value with
// its state intact and no remount lifecycle churn.

import Testing
@testable import Swiflow

@Suite("embed(refresh:) pushes props into the reused instance without remounting")
@MainActor
struct EmbedRefreshTests {

    /// A child with a plain `var` prop (pushed via refresh) and a plain `var`
    /// standing in for `@State` that must survive across re-renders.
    final class RefreshChild: Component {
        var label: String
        var survivorTag: Int = 0
        var appearCount = 0
        var disappearCount = 0
        init(label: String) { self.label = label }
        var body: VNode { .text("label=\(label)") }
        func onAppear() { appearCount += 1 }
        func onDisappear() { disappearCount += 1 }
    }

    /// Pulls the text out of the child's body mount node so we can assert the
    /// re-rendered body reflects the pushed prop (proves refresh ran BEFORE body).
    private func bodyText(_ tree: MountNode) -> String? {
        guard let body = tree.componentBody else { return nil }
        if case .text(let s) = body.vnode { return s }
        return nil
    }

    @Test("keyed embed(refresh:): a changed prop reaches the reused instance; @State-stand-in survives; no remount")
    func keyedRefreshPushesPropAndPreservesInstance() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let child = RefreshChild(label: "A")

        // First mount: factory supplies "A"; refresh must NOT run here.
        var refreshRuns = 0
        let v1 = embed("card") { child } refresh: { c in refreshRuns += 1; c.label = "A" }
        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)
        firePostRenderLifecycle(first.newMountTree, preExistingIDs: [])

        #expect(first.newMountTree.component?.instance === child, "the factory instance is mounted")
        #expect(refreshRuns == 0, "refresh must not run at first mount — the factory already carries current props")
        #expect(bodyText(first.newMountTree) == "label=A")
        #expect(child.appearCount == 1 && child.disappearCount == 0)

        // Accumulate some instance state that a remount would wipe.
        child.survivorTag = 99

        // Re-render with a refresh that pushes a new prop value.
        let preIDs = collectComponentIDs(first.newMountTree)
        let v2 = embed("card") { child } refresh: { c in refreshRuns += 1; c.label = "B" }
        let second = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)
        firePostRenderLifecycle(second.newMountTree, preExistingIDs: preIDs)

        #expect(refreshRuns == 1, "refresh runs exactly once on the reuse re-render")
        #expect(child.label == "B", "the new prop reached the reused instance")
        #expect(bodyText(second.newMountTree) == "label=B", "refresh ran BEFORE body eval — the body reflects the pushed prop")
        #expect(child.survivorTag == 99, "the reused instance's own state survives (no remount)")
        #expect(second.newMountTree.component?.instance === child, "still the SAME instance")
        #expect(child.appearCount == 1 && child.disappearCount == 0, "no remount lifecycle churn (onChange, not onAppear/onDisappear)")
    }

    @Test("without refresh, a reused embedded instance keeps its stale prop (the gap this API closes)")
    func withoutRefreshPropGoesStale() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let child = RefreshChild(label: "A")

        let v1 = embed("card") { child }
        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)

        // Re-render the SAME (type, key) with no refresh — factory is skipped,
        // so nothing pushes a new value; the instance keeps "A".
        let v2 = embed("card") { child }
        let second = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        #expect(child.label == "A", "no refresh → the reused instance never learns the parent's new value")
        #expect(bodyText(second.newMountTree) == "label=A")
    }

    @Test("unkeyed embed(refresh:) pushes props into the reused instance too")
    func unkeyedRefreshPushesProp() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let child = RefreshChild(label: "A")

        let v1 = embed { child } refresh: { $0.label = "A" }
        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)

        let v2 = embed { child } refresh: { $0.label = "B" }
        let second = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        #expect(child.label == "B")
        #expect(bodyText(second.newMountTree) == "label=B")
        #expect(second.newMountTree.component?.instance === child, "unkeyed reuse also keeps the same instance")
    }
}
