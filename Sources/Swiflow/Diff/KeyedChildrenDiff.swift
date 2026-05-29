// Sources/Swiflow/Diff/KeyedChildrenDiff.swift

/// Reconciles a list of keyed children. Algorithm:
///
/// 1. Pin the longest stable **prefix**: while `old[start].key == new[start].key`,
///    recurse and advance both pointers.
/// 2. Pin the longest stable **suffix**: same from the right.
/// 3. Anything left in the middle: bucket old by key into a Map, walk the new
///    middle, and either reuse (`insertBefore`) or mount + insert.
/// 4. Whatever stays in the bucket at the end is destroyed.
///
/// For elements without keys mixed into a keyed list, fall through to indexed
/// pairing in that slot. (Phase 1 emits a diagnostic in Phase 4; for now,
/// treat unkeyed children as having key `"__index_<i>"`.)
@MainActor
func diffChildrenKeyed(
    mounted: MountNode,
    newChildren: [VNode],
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    into patches: inout [Patch],
    scheduler: Scheduler? = nil,
    parentPath: String = "",
    environment: EnvironmentValues = .init()
) {
    // Diagnostic pre-pass: detect duplicate keys among the new children.
    // Keys MUST be unique within a parent — duplicates cause the keyed
    // diff to pick wrong moves (last-write-wins on the position map).
    // Both .element and .component children can carry a key; .text and
    // .rawHTML cannot. diagKeyAndIsKeyable() (Diff.swift, internal scope)
    // handles the discrimination.
    #if DEBUG
    do {
        var seen: [String: Int] = [:]
        for (index, child) in newChildren.enumerated() {
            let (key, _) = diagKeyAndIsKeyable(child)
            guard let key else { continue }
            if let firstIndex = seen[key] {
                let parentTag: String
                if case .element(let parentData) = mounted.vnode {
                    parentTag = parentData.tag
                } else {
                    parentTag = "<root>"
                }
                swiflowDiagnostic("Duplicate key '\(key)' among siblings of <\(parentTag)>. Keys must be unique within a parent. Offending positions: \(firstIndex) and \(index).")
            }
            seen[key] = index
        }
    }
    #endif

    // A fragment/anchor parent has no DOM node of its own — its children attach
    // to the nearest DOM-tracked ancestor. nil is unreachable for a child slot;
    // fail loud in debug, no-op in release.
    guard let domParentHandle = domParentHandle(of: mounted) else {
        assertionFailure("diffChildrenKeyed on a structural node with no DOM ancestor")
        return
    }

    var oldStart = 0
    var newStart = 0
    var oldEnd = mounted.children.count - 1
    var newEnd = newChildren.count - 1

    // 1. Stable prefix.
    while oldStart <= oldEnd, newStart <= newEnd,
          keyOf(mounted.children[oldStart]) == keyOf(newChildren[newStart])
    {
        let oldChild = mounted.children[oldStart]
        let oldRoots = collectDOMRoots(oldChild)
        let updatePatchStart = patches.count
        let childPath = parentPath.isEmpty ? String(newStart) : "\(parentPath).\(newStart)"
        let updated = update(
            mounted: oldChild,
            next: newChildren[newStart],
            into: &patches,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler,
            path: childPath,
            environment: environment
        )
        if updated !== oldChild {
            // Cross-kind replacement (same key, different tag/kind).
            // update() emitted destroyNode for the old subtree but did NOT
            // detach the old node from the live DOM. Insert removeChild
            // BEFORE the destroyNode patches so the driver detaches first,
            // then drops the handle from its Map. The replacement still
            // sits at oldStart in mounted.children, so no insertBefore is
            // needed here — but the node IS already detached on the JS
            // side, so we re-attach via placeRoots against the next
            // sibling (or append if it's the tail).
            for root in oldRoots {
                patches.insert(.removeChild(parent: domParentHandle, child: root), at: updatePatchStart)
            }
            mounted.replaceChild(at: oldStart, with: updated)
            let anchor = nextDOMAnchor(after: updated)
            placeRoots(of: updated, parent: domParentHandle, before: anchor, into: &patches)
        }
        oldStart += 1
        newStart += 1
    }

    // 2. Stable suffix.
    while oldStart <= oldEnd, newStart <= newEnd,
          keyOf(mounted.children[oldEnd]) == keyOf(newChildren[newEnd])
    {
        let oldChild = mounted.children[oldEnd]
        let oldRoots = collectDOMRoots(oldChild)
        let updatePatchStart = patches.count
        let childPath = parentPath.isEmpty ? String(newEnd) : "\(parentPath).\(newEnd)"
        let updated = update(
            mounted: oldChild,
            next: newChildren[newEnd],
            into: &patches,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler,
            path: childPath,
            environment: environment
        )
        if updated !== oldChild {
            // Cross-kind replacement in the suffix scan. Same fix as the
            // prefix scan: detach the old DOM node before its handle is
            // forgotten, then re-attach the fresh one at the same slot.
            for root in oldRoots {
                patches.insert(.removeChild(parent: domParentHandle, child: root), at: updatePatchStart)
            }
            mounted.replaceChild(at: oldEnd, with: updated)
            let anchor = nextDOMAnchor(after: updated)
            placeRoots(of: updated, parent: domParentHandle, before: anchor, into: &patches)
        }
        oldEnd -= 1
        newEnd -= 1
    }

    // 3. Both ranges exhausted: stable prefix + suffix covered everything.
    if oldStart > oldEnd && newStart > newEnd {
        return
    }

    // 4. Pure inserts (old range exhausted, new range has work).
    if oldStart > oldEnd {
        // Each new item is inserted just before the stable suffix, left-to-right.
        // nextDOMAnchor(after:) is re-evaluated per item but returns the same
        // value every pass — the suffix's first DOM handle — because the suffix
        // is already fixed and each insert lands ahead of it. The per-iteration
        // re-scan is on a cold path (pure inserts into an exhausted old range),
        // so it's left as-is rather than hoisted.
        var insertIndex = oldStart
        for i in newStart...newEnd {
            let childPath = parentPath.isEmpty ? String(insertIndex) : "\(parentPath).\(insertIndex)"
            let child = mount(
                newChildren[i],
                into: &patches,
                handles: handles,
                handlers: handlers,
                scheduler: scheduler,
                path: childPath,
                environment: environment
            )
            mounted.insertChild(child, at: insertIndex)
            let anchor = nextDOMAnchor(after: child)
            placeRoots(of: child, parent: domParentHandle, before: anchor, into: &patches)
            insertIndex += 1
        }
        return
    }

    // 5. Pure removes (new range exhausted, old range has work).
    if newStart > newEnd {
        for i in stride(from: oldEnd, through: oldStart, by: -1) {
            let removed = mounted.children[i]
            if let comp = removed.component,
               let anim = type(of: comp.instance).exitAnimation {
                let durMs = (type(of: comp.instance).exitDuration ?? 0) * 1000
                patches.append(.animateExit(
                    handle: removed.domHandle,  // domHandle ok: component body is single-rooted (MountTree.domHandle invariant).
                    parentHandle: domParentHandle,
                    animation: anim,
                    durationMs: durMs
                ))
                destroy(removed, into: &patches, handlers: handlers,
                        skipDestroyForHandle: removed.domHandle)
            } else {
                for root in collectDOMRoots(removed) {
                    patches.append(.removeChild(parent: domParentHandle, child: root))
                }
                destroy(removed, into: &patches, handlers: handlers)
            }
            mounted.removeChild(at: i)
        }
        return
    }

    // 6. Map-based middle: bucket old middle by key, tracking each old
    //    child's index so we can compute the longest-increasing-subsequence
    //    of *kept* nodes (those that stay in place need no insertBefore).
    let newMiddleCount = newEnd - newStart + 1
    // Bucket old-side middle children by key (used by the reuse loop below).
    // Detect duplicate keys defensively in debug builds — same gating as the
    // new-side check at lines ~176-186 so both sites have identical behavior
    // across configurations.
    var keyToOldIndex: [String: Int] = [:]
    for i in oldStart...oldEnd {
        keyToOldIndex[keyOf(mounted.children[i])] = i
    }

    // For each position in the new middle, record either the old index it
    // reuses (so LIS can decide whether it must move) or `-1` for a fresh
    // mount. Also resolve the reused/mounted MountNode in `newSlice`.
    var newToOldIndex = [Int](repeating: -1, count: newMiddleCount)
    var newSlice: [MountNode?] = Array(repeating: nil, count: newMiddleCount)
    var reusedOldIndices = Set<Int>()

    for i in 0..<newMiddleCount {
        let newChild = newChildren[newStart + i]
        let key = keyOf(newChild)
        let childPath = parentPath.isEmpty ? String(newStart + i) : "\(parentPath).\(newStart + i)"
        if let oldIndex = keyToOldIndex.removeValue(forKey: key) {
            let reused = mounted.children[oldIndex]
            let oldRoots = collectDOMRoots(reused)
            let updatePatchStart = patches.count
            let updated = update(
                mounted: reused,
                next: newChild,
                into: &patches,
                handles: handles,
                handlers: handlers,
                scheduler: scheduler,
                path: childPath,
                environment: environment
            )
            if updated !== reused {
                // Cross-kind replacement: same key but different tag/kind.
                // update() destroyed the old subtree (destroyNode patches
                // already in `patches`) but did NOT detach the old DOM node
                // from its parent. Insert removeChild ahead of the destroy
                // patches — same fix the prefix/suffix scans already got in
                // Phase 2b.1.
                for root in oldRoots {
                    patches.insert(.removeChild(parent: domParentHandle, child: root), at: updatePatchStart)
                }
                newSlice[i] = updated
                newToOldIndex[i] = -1   // explicit: treated as fresh mount by LIS/placement loop (see comment above)
                // Critical: leave newToOldIndex[i] == -1 so the LIS /
                // placement loop below treats this slot as a fresh mount.
                // The new node's handle was never attached anywhere — it
                // MUST be placed via placeRoots like any other fresh mount.
                // Marking it as "reused" (newToOldIndex[i] = oldIndex) would
                // let the LIS decide "in correct position, no patch" and the
                // new node would never appear in the DOM.
                reusedOldIndices.insert(oldIndex)
            } else {
                newSlice[i] = updated
                newToOldIndex[i] = oldIndex
                reusedOldIndices.insert(oldIndex)
            }
        } else {
            let fresh = mount(
                newChild,
                into: &patches,
                handles: handles,
                handlers: handlers,
                scheduler: scheduler,
                path: childPath,
                environment: environment
            )
            newSlice[i] = fresh
            // newToOldIndex[i] stays -1 to mark "fresh mount, must insert".
        }
    }

    // 7. Destroy any old middle node that wasn't reused.
    for i in oldStart...oldEnd where !reusedOldIndices.contains(i) {
        let leftover = mounted.children[i]
        if let comp = leftover.component,
           let anim = type(of: comp.instance).exitAnimation {
            let durMs = (type(of: comp.instance).exitDuration ?? 0) * 1000
            patches.append(.animateExit(
                handle: leftover.domHandle,  // domHandle ok: component body is single-rooted (MountTree.domHandle invariant).
                parentHandle: domParentHandle,
                animation: anim,
                durationMs: durMs
            ))
            destroy(leftover, into: &patches, handlers: handlers,
                    skipDestroyForHandle: leftover.domHandle)
        } else {
            for root in collectDOMRoots(leftover) {
                patches.append(.removeChild(parent: domParentHandle, child: root))
            }
            destroy(leftover, into: &patches, handlers: handlers)
        }
    }

    // 8. Compute the LIS over `newToOldIndex`, ignoring fresh mounts (-1).
    //    Any new-position whose old index is in the LIS is already in the
    //    right relative order — no patch needed. Everything else must move
    //    (insertBefore against the next sibling in the new list).
    let lisIndices = longestIncreasingSubsequenceIndices(newToOldIndex)
    let lisSet = Set(lisIndices)

    // 9a. Splice mounted.children BEFORE the placement loop so that
    //     nextDOMAnchor(after:) sees the final sibling order when computing
    //     anchors during the right-to-left placement walk.
    let prefix = Array(mounted.children[0..<oldStart])
    let suffix = Array(mounted.children[(oldEnd + 1)..<mounted.children.count])
    let merged = prefix + newSlice.compactMap { $0 } + suffix
    // Detach all then re-attach to refresh parent pointers cleanly.
    while !mounted.children.isEmpty {
        mounted.removeChild(at: mounted.children.count - 1)
    }
    for child in merged {
        mounted.addChild(child)
    }

    // 9b. Walk the new middle right-to-left so we always have a known anchor
    //     (the new-position to the right is already in its final spot, or
    //     sits inside the stable suffix). nextDOMAnchor works correctly here
    //     because mounted.children was already rebuilt above (step 9a).
    for i in stride(from: newMiddleCount - 1, through: 0, by: -1) {
        let node = newSlice[i]!

        if newToOldIndex[i] == -1 {
            // Fresh mount or cross-kind replacement: always insert.
            let anchor = nextDOMAnchor(after: node)
            placeRoots(of: node, parent: domParentHandle, before: anchor, into: &patches)
        } else if !lisSet.contains(i) {
            // Reused but out of LIS → must move.
            let anchor = nextDOMAnchor(after: node)
            placeRoots(of: node, parent: domParentHandle, before: anchor, into: &patches)
        }
        // else: in LIS → already in correct relative position, no patch.
    }
}

/// Computes the indices (into `input`) that form a longest increasing
/// subsequence. Entries equal to `-1` are treated as "not in any
/// subsequence" — they're new mounts and never count as stable. This is the
/// O(n log n) patience-sorting variant used by Vue 3 / Inferno.
func longestIncreasingSubsequenceIndices(_ input: [Int]) -> [Int] {
    // `tails[k]` = the smallest tail value of any increasing subsequence of
    // length k+1 found so far. `tailIndex[k]` = index (into input) of that
    // tail. `prev[i]` = predecessor index of input[i] in the subsequence
    // that ends at i (for reconstruction).
    var tailIndex: [Int] = []
    var prev = [Int](repeating: -1, count: input.count)

    for i in 0..<input.count {
        let value = input[i]
        if value < 0 { continue } // skip fresh mounts entirely
        // Binary-search the first tail value strictly greater than `value`
        // (we want a strictly increasing sequence, since old indices are
        // unique).
        var lo = 0
        var hi = tailIndex.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if input[tailIndex[mid]] < value {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        if lo > 0 {
            prev[i] = tailIndex[lo - 1]
        }
        if lo == tailIndex.count {
            tailIndex.append(i)
        } else {
            tailIndex[lo] = i
        }
    }

    // Reconstruct by walking `prev` from the last tail.
    var result: [Int] = []
    var cursor = tailIndex.last ?? -1
    while cursor != -1 {
        result.append(cursor)
        cursor = prev[cursor]
    }
    return result.reversed()
}

/// Returns the key of a `MountNode` for keyed-diff bucketing.
///
/// **Mixed keyed + unkeyed children re-mount on every render.** The two
/// `keyOf` helpers use different synthetic keys for unkeyed nodes —
/// `"__noKey_<handle>"` for mount nodes (per-instance unique) versus
/// `"__noKey_unkeyed"` for VNodes (constant) — so an old unkeyed mount
/// node can never match an incoming unkeyed VNode. The consequence is that
/// **any unkeyed child sitting inside a list that contains at least one
/// keyed sibling is destroyed and re-mounted on every diff pass**, even if
/// its content is unchanged. This is a known Phase 1 limitation; Phase 4
/// will add positional synthetic keys (`__index_<i>`) and a diagnostic that
/// warns when keyed and unkeyed children are mixed.
///
/// **Workaround:** if you mix keyed and unkeyed children today, give every
/// child a key — using `.key(String(i))` from the loop index is sufficient
/// to opt every child into stable matching.
func keyOf(_ node: MountNode) -> String {
    switch node.vnode {
    case .element(let data): if let k = data.key { return k }
    case .component(let desc): if let k = desc.key { return k }
    // Structural nodes (fragments, env-overrides) carry no user key. They share
    // one sentinel so a SINGLE structural sibling matches itself across renders
    // (reused, not destroyed+remounted). CAVEAT: two structural siblings of the
    // same kind collide — last-write-wins in keyToOldIndex evicts one, forcing a
    // (non-catastrophic) re-mount of its children. Same class as the unkeyed-
    // element caveat above. Today this is DSL-unreachable because
    // ChildrenBuilder.buildOptional/buildArray flatten if/for to []; once the
    // builder emits .fragment, `parent { li(key:"x"); if a; if b }` reaches it.
    // FIX THEN (map-middle only): fold the bucketing index into the sentinel —
    // both the keyToOldIndex build and the new-side keyOf call have the index in
    // scope, so a position-stable structural key applies at the call site
    // without adding a position parameter to keyOf (the prefix/suffix pairwise
    // scans must keep the position-free sentinel so a fragment still matches a
    // fragment at the same position there).
    case .fragment, .environmentOverride: return "__noKey_structural"
    default: break
    }
    return "__noKey_\(node.handle)"
}

/// Returns the key of an incoming VNode for keyed-diff bucketing. See the
/// `keyOf(_: MountNode)` doc for the mixed-keyed/unkeyed re-mount caveat.
func keyOf(_ vnode: VNode) -> String {
    switch vnode {
    case .element(let data): if let k = data.key { return k }
    case .component(let desc): if let k = desc.key { return k }
    // Structural VNodes (fragments, env-overrides) use the same sentinel as
    // the MountNode overload so they can be matched across renders. See the
    // MountNode overload for the caveat about multiple structural siblings.
    case .fragment, .environmentOverride: return "__noKey_structural"
    default: break
    }
    return "__noKey_unkeyed"
}
