// Sources/Swiflow/Diff/IndexedChildrenDiff.swift

/// Pairs `oldChildren[i]` with `newChildren[i]` and recurses via `update`.
/// For length deltas, emits appends for surplus new children and
/// `removeChild` + `destroyNode` for surplus old children. Mutates
/// `mounted.children` in place.
///
/// Fragment-aware: all DOM placement and removal routes through
/// `collectDOMRoots` / `firstDOMHandle` / `nextDOMAnchor` (DOMAnchors.swift)
/// so that structural nodes (fragments, component anchors) are never
/// referenced directly in `removeChild` / `insertBefore` patches.
@MainActor
func diffChildrenIndexed(
    mounted: MountNode,
    newChildren: [VNode],
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    into patches: inout [Patch],
    scheduler: Scheduler? = nil,
    parentPath: String = "",
    environment: EnvironmentValues = .init()
) {
    // When `mounted` itself is a structural node (e.g. a fragment slot whose
    // children are being reconciled), the real DOM parent is the first
    // non-structural ancestor — not `mounted.handle`, which is never sent to
    // the driver.  For ordinary element parents, `mounted.handle` is the
    // correct DOM parent and `domAncestorHandle` is not called.
    let domParentHandle: Int = isStructural(mounted)
        ? (domAncestorHandle(of: mounted) ?? mounted.handle)
        : mounted.handle

    let oldCount = mounted.children.count
    let newCount = newChildren.count
    let commonCount = min(oldCount, newCount)

    // 1. Reconcile common prefix (left-to-right is safe here: a same-kind
    //    update never changes a node's position; only a cross-kind replace
    //    re-places, and it re-places against the already-correct next sibling).
    for i in 0..<commonCount {
        let oldChild = mounted.children[i]
        let oldRoots = collectDOMRoots(oldChild)
        let updatePatchStart = patches.count
        let childPath = parentPath.isEmpty ? String(i) : "\(parentPath).\(i)"
        let newChild = update(
            mounted: oldChild, next: newChildren[i], into: &patches,
            handles: handles, handlers: handlers, scheduler: scheduler,
            path: childPath, environment: environment
        )
        if newChild !== oldChild {
            // Cross-kind replace: detach every old DOM root before its handle is
            // dropped, swap the slot, then place the new node's roots before the
            // next sibling's first DOM node (or append).
            for root in oldRoots {
                patches.insert(.removeChild(parent: domParentHandle, child: root), at: updatePatchStart)
            }
            mounted.replaceChild(at: i, with: newChild)
            let anchor = nextDOMAnchor(after: newChild)
            for root in collectDOMRoots(newChild) {
                if let before = anchor {
                    patches.append(.insertBefore(parent: domParentHandle, child: root, beforeChild: before))
                } else {
                    patches.append(.appendChild(parent: domParentHandle, child: root))
                }
            }
        }
    }

    // 2. Append surplus new children.
    if newCount > oldCount {
        for i in oldCount..<newCount {
            let childPath = parentPath.isEmpty ? String(i) : "\(parentPath).\(i)"
            let childMount = mount(
                newChildren[i], into: &patches, handles: handles,
                handlers: handlers, scheduler: scheduler, path: childPath,
                environment: environment
            )
            mounted.addChild(childMount)
            let anchor = nextDOMAnchor(after: childMount)
            for root in collectDOMRoots(childMount) {
                if let before = anchor {
                    patches.append(.insertBefore(parent: domParentHandle, child: root, beforeChild: before))
                } else {
                    patches.append(.appendChild(parent: domParentHandle, child: root))
                }
            }
        }
    }

    // 3. Remove surplus old children (forward document order). Each
    //    splice happens at `newCount` because removing index `newCount`
    //    shifts the next surplus child down into that slot.
    if oldCount > newCount {
        for _ in newCount..<oldCount {
            let removed = mounted.children[newCount]
            if let comp = removed.component,
               let anim = type(of: comp.instance).exitAnimation {
                let durMs = (type(of: comp.instance).exitDuration ?? 0) * 1000
                patches.append(.animateExit(
                    handle: removed.domHandle, parentHandle: domParentHandle,
                    animation: anim, durationMs: durMs))
                destroy(removed, into: &patches, handlers: handlers, skipDestroyForHandle: removed.domHandle)
            } else {
                for root in collectDOMRoots(removed) {
                    patches.append(.removeChild(parent: domParentHandle, child: root))
                }
                destroy(removed, into: &patches, handlers: handlers)
            }
            mounted.removeChild(at: newCount)
        }
    }
}
