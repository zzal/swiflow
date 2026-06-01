// Sources/Swiflow/Diff/DiffTasks.swift
//
// Bridges the diff's node lifecycle to SwiflowTaskRuntime. mount() calls
// startTasks; the same-tag element update calls reconcileTasks; destroy()
// calls cancelTasks. Identity is per (node, slot index); the stable-slot rule
// requires a node's `.task` count not change between renders.

/// Start every binding as a fresh task slot on `node` (mount time).
@MainActor
func startTasks(on node: MountNode, _ bindings: [TaskBinding]) {
    for binding in bindings {
        let slot = TaskSlot(id: SwiflowTaskRuntime.allocateSlotID())
        slot.dependency = binding.dependency
        node.taskSlots.append(slot)
        SwiflowTaskRuntime.start(slot, body: binding.body)
    }
}

/// Reconcile `node`'s running tasks against a freshly rendered binding list.
/// Per slot: bare `.task` never reruns; `.task(rerunOn:)` reruns when its
/// dependency changed (`!=`). The "before" count is `node.taskSlots.count`,
/// read before any mutation below — there is no need for the caller to pass
/// the old bindings.
@MainActor
func reconcileTasks(on node: MountNode, new: [TaskBinding]) {
    #if DEBUG
    if node.taskSlots.count != new.count {
        swiflowDiagnostic("`.task` count on a node changed between renders (\(node.taskSlots.count) → \(new.count)). The number of `.task` modifiers on a node must be stable across renders — don't put a `.task` behind a conditional that adds or removes it. Use `.task(rerunOn:)` to react to a changing value instead.")
    }
    #endif

    let shared = min(node.taskSlots.count, new.count)
    for i in 0..<shared {
        let slot = node.taskSlots[i]
        let newDep = new[i].dependency
        let changed: Bool
        switch (slot.dependency, newDep) {
        case (nil, nil):       changed = false              // bare task — never reruns
        case let (a?, b?):     changed = !a.equals(b)
        default:               changed = true               // gained/lost a dependency
        }
        if changed {
            slot.dependency = newDep
            SwiflowTaskRuntime.start(slot, body: new[i].body)
        }
    }

    // Count grew (already diagnosed): start the extra slots.
    if new.count > node.taskSlots.count {
        for i in node.taskSlots.count..<new.count {
            let slot = TaskSlot(id: SwiflowTaskRuntime.allocateSlotID())
            slot.dependency = new[i].dependency
            node.taskSlots.append(slot)
            SwiflowTaskRuntime.start(slot, body: new[i].body)
        }
    }
    // Count shrank (already diagnosed): cancel the extras.
    if node.taskSlots.count > new.count {
        for i in new.count..<node.taskSlots.count {
            SwiflowTaskRuntime.cancel(node.taskSlots[i])
        }
        node.taskSlots.removeLast(node.taskSlots.count - new.count)
    }
}

/// Cancel every task on `node` and clear its slots (unmount time).
@MainActor
func cancelTasks(on node: MountNode) {
    for slot in node.taskSlots {
        SwiflowTaskRuntime.cancel(slot)
    }
    node.taskSlots.removeAll()
}
