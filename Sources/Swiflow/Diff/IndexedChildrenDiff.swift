// Sources/Swiflow/Diff/IndexedChildrenDiff.swift

/// Pairs `oldChildren[i]` with `newChildren[i]` and recurses via `update`.
/// For length deltas, emits appends for surplus new children and
/// `removeChild` + `destroyNode` for surplus old children. Mutates
/// `mounted.children` in place.
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
    let oldCount = mounted.children.count
    let newCount = newChildren.count
    let commonCount = min(oldCount, newCount)

    // 1. Reconcile common prefix.
    for i in 0..<commonCount {
        let oldChild = mounted.children[i]
        let oldHandle = oldChild.domHandle
        let updatePatchStart = patches.count
        let childPath = parentPath.isEmpty ? String(i) : "\(parentPath).\(i)"
        let newChild = update(
            mounted: oldChild,
            next: newChildren[i],
            into: &patches,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler,
            path: childPath,
            environment: environment
        )
        if newChild !== oldChild {
            // The update returned a fresh node (cross-kind / tag replace).
            // update() emitted destroyNode for the old subtree but did NOT
            // detach the old node from the live DOM. Insert removeChild
            // BEFORE the destroyNode patches so the driver detaches first,
            // then drops the handle from its Map. Final patch order:
            // removeChild → destroyNode(subtree) → createX(new) → placement.
            patches.insert(
                .removeChild(parent: mounted.handle, child: oldHandle),
                at: updatePatchStart
            )
            mounted.replaceChild(at: i, with: newChild)
            // Position the new node: insertBefore the next sibling
            // (if any) or appendChild.
            if i + 1 < oldCount {
                let beforeSibling = mounted.children[i + 1]
                patches.append(.insertBefore(
                    parent: mounted.handle,
                    child: newChild.domHandle,
                    beforeChild: beforeSibling.domHandle
                ))
            } else {
                patches.append(.appendChild(
                    parent: mounted.handle,
                    child: newChild.domHandle
                ))
            }
        }
    }

    // 2. Append surplus new children.
    if newCount > oldCount {
        for i in oldCount..<newCount {
            let childPath = parentPath.isEmpty ? String(i) : "\(parentPath).\(i)"
            let childMount = mount(
                newChildren[i],
                into: &patches,
                handles: handles,
                handlers: handlers,
                scheduler: scheduler,
                path: childPath,
                environment: environment
            )
            patches.append(.appendChild(parent: mounted.handle, child: childMount.domHandle))
            mounted.addChild(childMount)
        }
    }

    // 3. Remove surplus old children. Patches are emitted in *forward*
    //    document order to match how the JS driver applies them. Each
    //    splice happens at `newCount` because removing index `newCount`
    //    shifts the next surplus child down into that slot.
    if oldCount > newCount {
        for _ in newCount..<oldCount {
            let removed = mounted.children[newCount]
            patches.append(.removeChild(parent: mounted.handle, child: removed.domHandle))
            destroy(removed, into: &patches, handlers: handlers)
            mounted.removeChild(at: newCount)
        }
    }
}
