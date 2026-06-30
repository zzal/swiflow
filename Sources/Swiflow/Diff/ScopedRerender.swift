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
///   `EnvironmentValues` and lose the ambient overrides).
@MainActor
package func planRerender(root: MountNode, dirtyIDs: Set<ObjectIdentifier>) -> RerenderPlan {
    guard dirtyIDs.count == 1, let only = dirtyIDs.first else { return .full }
    guard let anchor = findComponentAnchor(in: root, matching: only) else { return .full }
    if anchor === root { return .full }
    if hasEnvironmentOverrideAncestor(anchor) { return .full }
    return .scoped(anchor)
}
