// Sources/Swiflow/Diff/DOMAnchors.swift
//
// The three pure, total functions through which ALL fragment-aware DOM
// placement flows. Keeping placement behind these (and always placing
// right-to-left — see KeyedChildrenDiff/IndexedChildrenDiff) is what makes
// pure-virtual fragments rock-solid: empty/nested fragments simply yield no
// handle and are skipped, never mispositioned. See the design spec §3.3.

/// True for structural mount nodes that have NO DOM element of their own:
/// component anchors, environment-override anchors, and fragments. Their DOM
/// presence is their descendants'.
@MainActor
func isStructural(_ node: MountNode) -> Bool {
    if node.component != nil { return true }
    switch node.vnode {
    case .environmentOverride, .fragment: return true
    case .element, .text, .rawHTML, .component: return false
    }
}

/// All top-level real DOM-node handles of a subtree, in document order,
/// descending through structural nodes. For a single-node slot this is just
/// `[node.handle]`, so existing single-root call sites generalize unchanged.
@MainActor
func collectDOMRoots(_ node: MountNode) -> [Int] {
    switch node.vnode {
    case .element, .text, .rawHTML:
        return [node.handle]
    case .component, .environmentOverride:
        // Single-rooted body lives in the componentBody slot.
        return node.componentBody.map(collectDOMRoots) ?? []
    case .fragment:
        return node.children.flatMap(collectDOMRoots)
    }
}

extension MountNode {
    /// The single DOM handle for a node that must attach as exactly one root —
    /// the ROOT mount tree, whose handle feeds the driver's `mount` /
    /// `replaceMount` (each of which attaches ONE node at the mount selector).
    ///
    /// Unlike `domHandle`, this descends through fragments (via `collectDOMRoots`)
    /// and **traps in all builds** if the node resolves to anything other than a
    /// single DOM root. A fragment / multi-root ROOT body therefore fails loudly
    /// with actionable guidance, instead of feeding the bogus structural handle
    /// `domHandle` returns for a fragment to the driver in RELEASE — where the
    /// DEBUG bare-fragment-body diagnostic (`Diff.swift`) is compiled out and the
    /// mount would silently attach a node the DOM never renders.
    @MainActor
    package var singleRootDOMHandle: Int {
        let roots = collectDOMRoots(self)
        precondition(
            roots.count == 1,
            "Swiflow: the root component's body must resolve to exactly one DOM "
            + "node to attach at the mount point, but it produced \(roots.count) "
            + "(a bare fragment / multiple top-level roots). Wrap the body in a "
            + "single element — div, VStack, … — so there is one node to mount."
        )
        return roots[0]
    }
}

/// First real DOM-node handle of a subtree, or nil if it contributes none
/// (e.g. an empty fragment). Short-circuits without building the full list —
/// semantically `collectDOMRoots(node).first`, kept separate to avoid the
/// allocation on the hot placement path. Keep its structural-descent cases in
/// lock-step with `collectDOMRoots`.
@MainActor
func firstDOMHandle(_ node: MountNode) -> Int? {
    switch node.vnode {
    case .element, .text, .rawHTML:
        return node.handle
    case .component, .environmentOverride:
        return node.componentBody.flatMap(firstDOMHandle)
    case .fragment:
        for child in node.children {
            if let h = firstDOMHandle(child) { return h }
        }
        return nil
    }
}

/// The handle that should come immediately AFTER everything `node` owns — the
/// `beforeChild` for an `insertBefore`, or nil to append. Scans forward among
/// `node`'s siblings; if none yields a DOM node and the parent is itself
/// structural (a fragment), ascends and continues among the parent's siblings.
/// Stops (returns nil = append) on reaching a real-element parent with nothing
/// after it. Relies on callers placing right-to-left so siblings to the right
/// are already in their final DOM position.
@MainActor
func nextDOMAnchor(after node: MountNode) -> Int? {
    var current = node
    while let parent = current.parent {
        // O(siblings) per ascent — acceptable because sibling counts are small;
        // revisit only if profiling flags it on very large keyed lists.
        guard let idx = parent.children.firstIndex(where: { $0 === current }) else { return nil }
        var i = idx + 1
        while i < parent.children.count {
            if let h = firstDOMHandle(parent.children[i]) { return h }
            i += 1
        }
        // Nothing after `current` at this level. A fragment parent is
        // transparent, so the search continues among the fragment's siblings.
        if case .fragment = parent.vnode {
            current = parent
            continue
        }
        return nil   // real-element (or other single-root) parent → append
    }
    return nil
}

/// The DOM-tracked parent that `node`'s children attach to. For a real element
/// it's the element's own handle; for a structural node (fragment / component
/// anchor / env override) it's the nearest DOM-tracked ancestor. Returns nil
/// ONLY for a structural node with no element ancestor (a root-level structural
/// node) — not reachable for a fragment child slot, which is the only structural
/// node the child-diff runs on. Callers must handle nil explicitly.
@MainActor
func domParentHandle(of node: MountNode) -> Int? {
    isStructural(node) ? domAncestorHandle(of: node) : node.handle
}

/// Place every DOM root of `node` (in document order) before `anchor`, or
/// append when `anchor` is nil. Single-rooted nodes emit exactly one patch.
@MainActor
func placeRoots(of node: MountNode, parent: Int, before anchor: Int?, into patches: inout [Patch]) {
    for root in collectDOMRoots(node) {
        if let before = anchor {
            patches.append(.insertBefore(parent: parent, child: root, beforeChild: before))
        } else {
            patches.append(.appendChild(parent: parent, child: root))
        }
    }
}
