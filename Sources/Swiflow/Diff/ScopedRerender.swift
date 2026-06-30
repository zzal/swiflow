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
///   `EnvironmentValues` and lose the ambient overrides);
/// - the anchor has NO DOM-tracked ancestor (its body attaches at the selector
///   root through structural-only nodes). A scoped diff that swaps the body's
///   root element type then has nowhere to splice the new node — only
///   `renderOnce()` emits the `replaceMount` patch that covers that. Such
///   anchors (a root that simply forwards to a single child component, no
///   element wrapper) must take the full path. Anchors nested under any real
///   element — the overwhelmingly common case, including the demo table — have
///   a DOM ancestor and still scope.
@MainActor
package func planRerender(root: MountNode, dirtyIDs: Set<ObjectIdentifier>) -> RerenderPlan {
    guard dirtyIDs.count == 1, let only = dirtyIDs.first else { return .full }
    guard let anchor = findComponentAnchor(in: root, matching: only) else { return .full }
    if anchor === root { return .full }
    if hasEnvironmentOverrideAncestor(anchor) { return .full }
    if domAncestorHandle(of: anchor) == nil { return .full }
    return .scoped(anchor)
}

/// The outputs of a scoped subtree re-render. The caller must ship `patches`
/// to the driver and THEN fire the post-render lifecycle on `newMountTree`
/// with `preExistingIDs` — in that order, so `onAppear`/`onChange` observe a
/// DOM the patches have already been applied to (e.g. `Ref.wrappedValue` is
/// only resolvable after its `createElement` patch has shipped). This mirrors
/// `renderOnce()`'s ship-then-fire ordering.
package struct ScopedRenderResult {
    package let patches: [Patch]
    package let newMountTree: MountNode
    package let preExistingIDs: Set<ObjectIdentifier>
}

/// Re-renders the subtree rooted at `anchor` (a component-anchor MountNode) and
/// returns the patches to ship plus the data the caller needs to fire the
/// scoped post-render lifecycle AFTER shipping. Reuses the live instance via
/// the diff's component-reuse arm, reconciling the body subtree in place.
///
/// Does NOT fire lifecycle itself — see `ScopedRenderResult` for why ordering
/// is the caller's responsibility.
///
/// Precondition: `anchor.component != nil`, `anchor` has no `environmentOverride`
/// ancestor, and `anchor` has a DOM-tracked ancestor (callers gate via
/// `planRerender`). The diff starts with a fresh `EnvironmentValues()`, which
/// reproduces the ambient environment exactly when no override sits above the
/// anchor.
@MainActor
package func scopedRerender(
    anchor: MountNode,
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    scheduler: Scheduler?
) -> ScopedRenderResult {
    guard let instance = anchor.component else {
        return ScopedRenderResult(patches: [], newMountTree: anchor, preExistingIDs: [])
    }

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
    return ScopedRenderResult(
        patches: result.patches,
        newMountTree: result.newMountTree,
        preExistingIDs: preExistingIDs
    )
}
