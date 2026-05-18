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
func diffChildrenKeyed(
    mounted: MountNode,
    newChildren: [VNode],
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    into patches: inout [Patch]
) {
    var oldStart = 0
    var newStart = 0
    var oldEnd = mounted.children.count - 1
    var newEnd = newChildren.count - 1

    // 1. Stable prefix.
    while oldStart <= oldEnd, newStart <= newEnd,
          keyOf(mounted.children[oldStart]) == keyOf(newChildren[newStart])
    {
        let oldChild = mounted.children[oldStart]
        let oldHandle = oldChild.handle
        let updatePatchStart = patches.count
        let updated = update(
            mounted: oldChild,
            next: newChildren[newStart],
            into: &patches,
            handles: handles,
            handlers: handlers
        )
        if updated !== oldChild {
            // Cross-kind replacement (same key, different tag/kind).
            // update() emitted destroyNode for the old subtree but did NOT
            // detach the old node from the live DOM. Insert removeChild
            // BEFORE the destroyNode patches so the driver detaches first,
            // then drops the handle from its Map. The replacement still
            // sits at oldStart in mounted.children, so no insertBefore is
            // needed here — but the node IS already detached on the JS
            // side, so we re-attach via insertBefore against the next
            // sibling (or appendChild if it's the tail).
            patches.insert(
                .removeChild(parent: mounted.handle, child: oldHandle),
                at: updatePatchStart
            )
            mounted.replaceChild(at: oldStart, with: updated)
            if oldStart + 1 < mounted.children.count {
                let beforeSibling = mounted.children[oldStart + 1]
                patches.append(.insertBefore(
                    parent: mounted.handle,
                    child: updated.handle,
                    beforeChild: beforeSibling.handle
                ))
            } else {
                patches.append(.appendChild(
                    parent: mounted.handle,
                    child: updated.handle
                ))
            }
        }
        oldStart += 1
        newStart += 1
    }

    // 2. Stable suffix.
    while oldStart <= oldEnd, newStart <= newEnd,
          keyOf(mounted.children[oldEnd]) == keyOf(newChildren[newEnd])
    {
        let oldChild = mounted.children[oldEnd]
        let oldHandle = oldChild.handle
        let updatePatchStart = patches.count
        let updated = update(
            mounted: oldChild,
            next: newChildren[newEnd],
            into: &patches,
            handles: handles,
            handlers: handlers
        )
        if updated !== oldChild {
            // Cross-kind replacement in the suffix scan. Same fix as the
            // prefix scan: detach the old DOM node before its handle is
            // forgotten, then re-attach the fresh one at the same slot.
            patches.insert(
                .removeChild(parent: mounted.handle, child: oldHandle),
                at: updatePatchStart
            )
            mounted.replaceChild(at: oldEnd, with: updated)
            if oldEnd + 1 < mounted.children.count {
                let beforeSibling = mounted.children[oldEnd + 1]
                patches.append(.insertBefore(
                    parent: mounted.handle,
                    child: updated.handle,
                    beforeChild: beforeSibling.handle
                ))
            } else {
                patches.append(.appendChild(
                    parent: mounted.handle,
                    child: updated.handle
                ))
            }
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
        // Anchor is the first node in the stable suffix (which sits at
        // mounted.children[oldStart], because the suffix scan didn't touch
        // the front and oldEnd has now slipped below oldStart).
        let beforeHandle: Int? = (oldStart < mounted.children.count)
            ? mounted.children[oldStart].handle
            : nil
        var insertIndex = oldStart
        for i in newStart...newEnd {
            let child = mount(
                newChildren[i],
                into: &patches,
                handles: handles,
                handlers: handlers
            )
            if let before = beforeHandle {
                patches.append(.insertBefore(parent: mounted.handle, child: child.handle, beforeChild: before))
            } else {
                patches.append(.appendChild(parent: mounted.handle, child: child.handle))
            }
            mounted.insertChild(child, at: insertIndex)
            insertIndex += 1
        }
        return
    }

    // 5. Pure removes (new range exhausted, old range has work).
    if newStart > newEnd {
        for i in stride(from: oldEnd, through: oldStart, by: -1) {
            let removed = mounted.children[i]
            patches.append(.removeChild(parent: mounted.handle, child: removed.handle))
            destroy(removed, into: &patches, handlers: handlers)
            mounted.removeChild(at: i)
        }
        return
    }

    // 6. Map-based middle: bucket old middle by key, tracking each old
    //    child's index so we can compute the longest-increasing-subsequence
    //    of *kept* nodes (those that stay in place need no insertBefore).
    let newMiddleCount = newEnd - newStart + 1
    var keyToOldIndex: [String: Int] = [:]
    for i in oldStart...oldEnd {
        let key = keyOf(mounted.children[i])
        assert(
            keyToOldIndex[key] == nil,
            "Swiflow: duplicate key '\(key)' in keyed children list. " +
            "Each child's `.key(_:)` must be unique within its parent — " +
            "the diff will silently destroy one of the duplicates."
        )
        keyToOldIndex[key] = i
    }

    // Also catch duplicates on the *new* side, where the same destructive
    // effect happens via the reuse loop's `removeValue(forKey:)`.
    #if DEBUG
    var seenNewKeys = Set<String>()
    for i in 0..<newMiddleCount {
        let key = keyOf(newChildren[newStart + i])
        assert(
            seenNewKeys.insert(key).inserted,
            "Swiflow: duplicate key '\(key)' in new keyed children list. " +
            "Each child's `.key(_:)` must be unique within its parent."
        )
    }
    #endif

    // For each position in the new middle, record either the old index it
    // reuses (so LIS can decide whether it must move) or `-1` for a fresh
    // mount. Also resolve the reused/mounted MountNode in `newSlice`.
    var newToOldIndex = [Int](repeating: -1, count: newMiddleCount)
    var newSlice: [MountNode?] = Array(repeating: nil, count: newMiddleCount)
    var reusedOldIndices = Set<Int>()

    for i in 0..<newMiddleCount {
        let newChild = newChildren[newStart + i]
        let key = keyOf(newChild)
        if let oldIndex = keyToOldIndex.removeValue(forKey: key) {
            let reused = mounted.children[oldIndex]
            let updated = update(
                mounted: reused,
                next: newChild,
                into: &patches,
                handles: handles,
                handlers: handlers
            )
            newSlice[i] = updated
            newToOldIndex[i] = oldIndex
            reusedOldIndices.insert(oldIndex)
        } else {
            let fresh = mount(
                newChild,
                into: &patches,
                handles: handles,
                handlers: handlers
            )
            newSlice[i] = fresh
            // newToOldIndex[i] stays -1 to mark "fresh mount, must insert".
        }
    }

    // 7. Destroy any old middle node that wasn't reused.
    for i in oldStart...oldEnd where !reusedOldIndices.contains(i) {
        let leftover = mounted.children[i]
        patches.append(.removeChild(parent: mounted.handle, child: leftover.handle))
        destroy(leftover, into: &patches, handlers: handlers)
    }

    // 8. Compute the LIS over `newToOldIndex`, ignoring fresh mounts (-1).
    //    Any new-position whose old index is in the LIS is already in the
    //    right relative order — no patch needed. Everything else must move
    //    (insertBefore against the next sibling in the new list).
    let lisIndices = longestIncreasingSubsequenceIndices(newToOldIndex)
    let lisSet = Set(lisIndices)

    // 9. Walk the new middle right-to-left so we always have a known anchor
    //    (the new-position to the right is already in its final spot, or
    //    sits inside the stable suffix).
    for i in stride(from: newMiddleCount - 1, through: 0, by: -1) {
        let node = newSlice[i]!
        // Anchor = handle of the next new-middle node (already placed) or
        // the first node of the stable suffix, or nil → appendChild.
        let anchor: Int?
        if i + 1 < newMiddleCount {
            anchor = newSlice[i + 1]!.handle
        } else if oldEnd + 1 < mounted.children.count {
            anchor = mounted.children[oldEnd + 1].handle
        } else {
            anchor = nil
        }

        if newToOldIndex[i] == -1 {
            // Fresh mount: always insert.
            if let before = anchor {
                patches.append(.insertBefore(parent: mounted.handle, child: node.handle, beforeChild: before))
            } else {
                patches.append(.appendChild(parent: mounted.handle, child: node.handle))
            }
        } else if !lisSet.contains(i) {
            // Reused but out of LIS → must move.
            if let before = anchor {
                patches.append(.insertBefore(parent: mounted.handle, child: node.handle, beforeChild: before))
            } else {
                patches.append(.appendChild(parent: mounted.handle, child: node.handle))
            }
        }
        // else: in LIS → already in correct relative position, no patch.
    }

    // 10. Splice mounted.children: [prefix] + newSlice + [suffix].
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
    if case .element(let data) = node.vnode, let key = data.key {
        return key
    }
    return "__noKey_\(node.handle)"
}

/// Returns the key of an incoming VNode for keyed-diff bucketing. See the
/// `keyOf(_: MountNode)` doc for the mixed-keyed/unkeyed re-mount caveat.
func keyOf(_ vnode: VNode) -> String {
    if case .element(let data) = vnode, let key = data.key {
        return key
    }
    return "__noKey_unkeyed"
}
