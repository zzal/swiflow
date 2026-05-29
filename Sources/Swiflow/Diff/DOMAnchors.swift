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

/// First real DOM-node handle of a subtree, or nil if it contributes none
/// (e.g. an empty fragment). Short-circuits without building the full list.
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
