// Sources/Swiflow/Diff/IndexedChildrenDiff.swift

/// Pairs `oldChildren[i]` with `newChildren[i]` and recurses via `update`.
/// For length deltas, emits appends for surplus new children and
/// `removeChild` + `destroyNode` for surplus old children. Mutates
/// `mounted.children` in place.
///
/// Fragment-aware: all DOM placement and removal routes through
/// `collectDOMRoots` / `nextDOMAnchor` (DOMAnchors.swift)
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
    // A fragment/anchor has no DOM node of its own — its children attach to the
    // nearest DOM-tracked ancestor. nil is unreachable here (the only structural
    // node the child-diff runs on is a fragment child slot, which always has an
    // element/component ancestor); fail loud in debug, no-op in release.
    guard let domParentHandle = domParentHandle(of: mounted) else {
        assertionFailure("diffChildrenIndexed on a structural node with no DOM ancestor")
        return
    }

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
            placeRoots(of: newChild, parent: domParentHandle, before: anchor, into: &patches)
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
            placeRoots(of: childMount, parent: domParentHandle, before: anchor, into: &patches)
        }
    }

    // 3. Remove surplus old children (forward document order). Each
    //    splice happens at `newCount` because removing index `newCount`
    //    shifts the next surplus child down into that slot.
    if oldCount > newCount {
        for _ in newCount..<oldCount {
            let removed = mounted.children[newCount]
            // animateExit targets a single component body, which is single-rooted
            // by invariant (MountTree.domHandle), so domHandle is correct here.
            // Exit-anim vs plain removal now lives in removeAndDestroyChild —
            // previously copy-pasted x3 with the fragment-body phantom-handle bug.
            removeAndDestroyChild(removed, parentDOMHandle: domParentHandle,
                                  handlers: handlers, into: &patches)
            mounted.removeChild(at: newCount)
        }
    }
}
