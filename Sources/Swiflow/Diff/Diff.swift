// Sources/Swiflow/Diff/Diff.swift

/// The output of a single diff pass: the patches to apply, plus the new
/// mount tree to commit as the next render's left-hand side.
package struct DiffResult {
    /// Patches to ship across the JS bridge, in apply order.
    package let patches: [Patch]
    /// The mount tree the caller must commit as the next render's baseline.
    package let newMountTree: MountNode

    /// Wraps the two outputs of a diff pass.
    package init(patches: [Patch], newMountTree: MountNode) {
        self.patches = patches
        self.newMountTree = newMountTree
    }
}

/// Diffs `next` against `mounted`, producing the patches the renderer must
/// apply and the new mount tree to commit. When `mounted` is `nil`, the
/// function treats every node as fresh and emits `create…` patches for the
/// entire tree.
///
/// The optional `scheduler` parameter is threaded through the entire diff
/// tree. When non-nil, it is wired into every `@State` property on newly
/// mounted `Component` instances so that state mutations automatically call
/// `scheduler.markDirty(owner)`. Existing callers that omit this parameter
/// continue to work unchanged — the default `nil` preserves the previous
/// silent-mutation behaviour.
@MainActor
package func diff(
    mounted: MountNode?,
    next: VNode,
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    scheduler: Scheduler? = nil
) -> DiffResult {
    var patches: [Patch] = []
    let root: MountNode
    if let mounted = mounted {
        root = update(
            mounted: mounted,
            next: next,
            into: &patches,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler
        )
    } else {
        root = mount(next, into: &patches, handles: handles, handlers: handlers, scheduler: scheduler, path: "")
    }
    return DiffResult(patches: patches, newMountTree: root)
}

// MARK: - Diagnostic helpers (debug key-validation, shared across Diff.swift
//         and KeyedChildrenDiff.swift)

/// Returns the key and keyability of a VNode for sibling-key diagnostics.
/// `.element` and `.component` children can carry a key; `.text` and `.rawHTML`
/// cannot. The "isKeyable" flag lets callers skip non-keyable children cleanly.
func diagKeyAndIsKeyable(_ child: VNode) -> (key: String?, isKeyable: Bool) {
    switch child {
    case .element(let data): return (data.key, true)
    case .component(let desc): return (desc.key, true)
    case .text, .rawHTML: return (nil, false)
    }
}

// MARK: - Mount helpers (first render only — Task 9 scope)

/// Creates the DOM-side node and (recursively) all children, appending patches
/// in document order. Returns the new `MountNode` describing the freshly
/// mounted subtree.
@MainActor
func mount(
    _ vnode: VNode,
    into patches: inout [Patch],
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    scheduler: Scheduler? = nil,
    depth: Int = 0,
    path: String = ""
) -> MountNode {
    switch vnode {
    case .text(let value):
        let h = handles.next()
        patches.append(.createText(handle: h, text: value))
        return MountNode(handle: h, vnode: vnode)

    case .rawHTML(let html):
        let h = handles.next()
        patches.append(.createRawHTML(handle: h, html: html))
        return MountNode(handle: h, vnode: vnode)

    case .element(let data):
        let h = handles.next()
        patches.append(.createElement(handle: h, tag: data.tag))

        // Ref bindings fire BEFORE child mounts so a parent Component's
        // `onAppear` — which runs after the whole tree's first commit —
        // sees populated refs even on transitively nested elements. The
        // bindings produce no patches; they only write into the user's
        // `Ref<E>.handle` slot. Symmetric clear lives in `destroy()`.
        for binding in data.refBindings {
            binding.setHandle(h)
        }

        // Bag iteration order: attributes → properties → style → handlers
        // (matches Snabbdom/Inferno). The driver applies patches in arrival
        // order; properties intentionally come AFTER attributes so DOM-property
        // semantics (e.g. `input.value` override) win when a name appears in
        // both bags. Update paths in Tasks 10–13 preserve this same ordering.
        for (name, value) in data.attributes {
            patches.append(.setAttribute(handle: h, name: name, value: value))
        }
        for (name, value) in data.properties {
            patches.append(.setProperty(handle: h, name: name, value: value))
        }
        for (name, value) in data.style {
            patches.append(.setStyle(handle: h, name: name, value: value))
        }
        var handlerIds: [String: Int] = [:]
        for (eventName, handler) in data.handlers {
            patches.append(.addHandler(
                handle: h,
                event: eventName,
                handlerId: handler.id
            ))
            handlerIds[eventName] = handler.id
        }

        let mountNode = MountNode(
            handle: h,
            vnode: vnode,
            handlerIds: handlerIds
        )

        // Diagnostic: validate children key consistency on initial mount.
        // (On re-render, diffChildren/diffChildrenKeyed carry these checks.)
        // Both .element and .component children can carry a key; .text and
        // .rawHTML cannot. diagKeyAndIsKeyable() handles the discrimination.
        #if DEBUG
        do {
            var seenKeys: [String: Int] = [:]
            for (index, child) in data.children.enumerated() {
                let (key, _) = diagKeyAndIsKeyable(child)
                guard let key else { continue }
                if let firstIndex = seenKeys[key] {
                    swiflowDiagnostic("Duplicate key '\(key)' among siblings of <\(data.tag)>. Keys must be unique within a parent. Offending positions: \(firstIndex) and \(index).")
                }
                seenKeys[key] = index
            }
            var keyedCount = 0
            var unkeyedCount = 0
            for child in data.children {
                let (key, isKeyable) = diagKeyAndIsKeyable(child)
                guard isKeyable else { continue }
                if key != nil { keyedCount += 1 } else { unkeyedCount += 1 }
            }
            if keyedCount > 0 && unkeyedCount > 0 {
                swiflowDiagnostic("Children of <\(data.tag)> mix keyed (\(keyedCount)) and unkeyed (\(unkeyedCount)) entries. Either key every child or key none.")
            }
        }
        #endif

        for (i, childVNode) in data.children.enumerated() {
            let childPath = path.isEmpty ? String(i) : "\(path).\(i)"
            let childMount = mount(
                childVNode,
                into: &patches,
                handles: handles,
                handlers: handlers,
                scheduler: scheduler,
                depth: depth,
                path: childPath
            )
            // domHandle (not handle): if the child is a component anchor,
            // the anchor's own handle has no DOM counterpart — we need
            // the body's handle instead. See MountNode.domHandle.
            patches.append(.appendChild(parent: h, child: childMount.domHandle))
            mountNode.addChild(childMount)
        }

        return mountNode

    case .component(let desc):
        // Diagnostic: depth guard catches `body` cycles like
        // `component({ self })` or A.body → component(B); B.body → component(A).
        // 32 nested anchors is already absurd — cycles always exceed it.
        #if DEBUG
        if depth >= 32 {
            swiflowDiagnostic("Component anchor depth exceeded 32. This usually means a component's body returned a VNode.component anchor cycle (e.g. body returns `component({ self })`). Bodies must terminate at non-component VNodes.")
        }
        #endif
        // Anchor handle allocated FIRST (parent-before-child, matching the
        // .element branch's allocation order). The anchor handle is
        // structural-only — the JS driver never sees it; the body's
        // domHandle is what propagates to parent appendChild patches.
        let instance = desc.instantiate()
        // Diagnostic: detect `embed { self.existingCounter }` — a factory
        // that returns an already-mounted instance. The Mirror-based
        // @State owner wiring is keyed by the component the framework
        // believes lives at this slot, so reusing a mounted instance
        // silently corrupts state lifecycle. See ComponentDSL.swift for
        // the factory contract.
        #if DEBUG
        if !MountedInstances.register(instance.instance) {
            swiflowDiagnostic("embed { } factory returned an already-mounted Component instance. Factories must allocate a fresh instance per call — `{ Counter() }`, not `{ self.existingCounter }`. See Sources/Swiflow/DSL/ComponentDSL.swift for the factory contract.")
        }
        #endif
        // Fused owner-wiring + HMR restore in one Mirror walk.
        // `stateFor` returns the snapshot state map for this component
        // when an HMR swap is pending; nil otherwise (scheduler-only wiring).
        let typeName = String(reflecting: type(of: instance.instance))
        let stateMap = HMRRestoreInstall.stateFor?(path, typeName, desc.key)
        wireStateAndRestore(on: instance, scheduler: scheduler, stateMap: stateMap, path: path)
        let anchorHandle = handles.next()
        // Open a handler scope so every `.on(_:perform:)` call inside this
        // component's body is tracked against this component anchor. The scope
        // is closed in `destroy()` when the component unmounts, ensuring
        // handler closures cannot outlive their owning Component instance.
        handlers.openScope()
        let bodyVNode = instance.instance.body
        let bodyMount = mount(
            bodyVNode,
            into: &patches,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler,
            depth: depth + 1,
            path: path
        )
        return MountNode(
            handle: anchorHandle,
            vnode: vnode,
            component: instance,
            componentBody: bodyMount
        )
    }
}

// MARK: - Update (subsequent renders)

/// Reconciles `next` against `mounted`. The returned `MountNode` is the
/// committed mount-tree node for that position. If the diff replaces the
/// node (different case kind, or different element tag — see Task 15), the
/// returned `MountNode` is a fresh object with a new handle and the caller
/// is responsible for any parent-level `insertBefore` / `appendChild`
/// rewiring (for the root, the renderer reattaches to the selector).
@MainActor
func update(
    mounted: MountNode,
    next: VNode,
    into patches: inout [Patch],
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    scheduler: Scheduler? = nil,
    path: String = ""
) -> MountNode {
    switch (mounted.vnode, next) {
    // Same-kind, same-content: nothing to do.
    case (.text(let oldText), .text(let newText)) where oldText == newText:
        return mounted
    case (.rawHTML(let oldHTML), .rawHTML(let newHTML)) where oldHTML == newHTML:
        return mounted

    // Text → text value change.
    case (.text, .text(let newText)):
        patches.append(.setText(handle: mounted.handle, text: newText))
        mounted.vnode = next
        return mounted

    // RawHTML → rawHTML value change.
    case (.rawHTML, .rawHTML(let newHTML)):
        patches.append(.setRawHTML(handle: mounted.handle, html: newHTML))
        mounted.vnode = next
        return mounted

    // Element → element, same tag: per-bag diff (Tasks 10–13, 16–17).
    case (.element(let oldData), .element(let newData)) where oldData.tag == newData.tag:
        // Refs: clear old bindings, then re-bind new bindings to the
        // surviving handle. The DOM node didn't move (same-tag in-place
        // update), so each binding gets the existing `mounted.handle`.
        // Old bindings whose underlying `Ref<E>` instance is also in
        // newData will be cleared and immediately re-set with the same
        // handle — a no-op net effect, which is correct.
        for binding in oldData.refBindings {
            binding.clearHandle()
        }
        for binding in newData.refBindings {
            binding.setHandle(mounted.handle)
        }
        diffAttributes(handle: mounted.handle, old: oldData.attributes, new: newData.attributes, into: &patches)
        diffProperties(handle: mounted.handle, old: oldData.properties, new: newData.properties, into: &patches)
        diffStyle(handle: mounted.handle, old: oldData.style, new: newData.style, into: &patches)
        mounted.handlerIds = diffHandlers(
            handle: mounted.handle,
            old: mounted.handlerIds,
            new: newData.handlers,
            handlers: handlers,
            into: &patches
        )
        // Children diff lands in Tasks 16–17.
        diffChildren(
            mounted: mounted,
            newChildren: newData.children,
            handles: handles,
            handlers: handlers,
            into: &patches,
            scheduler: scheduler,
            parentPath: path
        )
        mounted.vnode = next
        return mounted

    // Component → component, same description (same typeID + key):
    // reuse the existing instance, re-render the body, and reconcile
    // the body subtree.
    //
    // Why reconcile rather than always mount fresh? Instance state (and,
    // later, @State) lives on the AnyComponent reference. Destroying and
    // remounting would reset that state. The reuse path keeps the instance
    // alive and lets the body subtree diff produce the minimal patch set.
    case (.component(let oldDesc), .component(let newDesc)) where oldDesc == newDesc:
        // Defensive: a component-anchor mount node should always have both
        // component and componentBody (Task 4's mount() invariant). If
        // either is nil — which shouldn't happen in normal operation —
        // fall through to the destroy+remount safety net rather than crash.
        guard let instance = mounted.component, let oldBody = mounted.componentBody else {
            destroy(mounted, into: &patches, handlers: handlers)
            return mount(next, into: &patches, handles: handles, handlers: handlers, scheduler: scheduler, path: path)
        }
        // Re-render: call body on the reused instance so any state
        // mutations since the last render (e.g. n = 42 on a Counter)
        // are reflected in the new body VNode.
        let newBodyVNode = instance.instance.body
        // Reconcile the new body VNode against the previously-mounted body
        // subtree. The returned MountNode may be the same reference (if the
        // body root type/tag matched) or a fresh one (if the body root
        // itself was replaced wholesale). Either way it becomes the new body.
        let newBodyMount = update(
            mounted: oldBody,
            next: newBodyVNode,
            into: &patches,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler,
            path: path
        )
        mounted.componentBody = newBodyMount
        // Commit the new vnode description so the next render's left-hand
        // side reflects the description that was actually diffed.
        mounted.vnode = next
        return mounted

    // Any other transition: destroy the old subtree and mount fresh.
    default:
        destroy(mounted, into: &patches, handlers: handlers)
        return mount(next, into: &patches, handles: handles, handlers: handlers, scheduler: scheduler, path: path)
    }
}

/// Emits `setAttribute` / `removeAttribute` patches for the symmetric
/// difference between two attribute dictionaries.
func diffAttributes(
    handle: Int,
    old: [String: String],
    new: [String: String],
    into patches: inout [Patch]
) {
    // Sets and changes.
    for (name, newValue) in new {
        if old[name] != newValue {
            patches.append(.setAttribute(handle: handle, name: name, value: newValue))
        }
    }
    // Removals.
    for name in old.keys where new[name] == nil {
        patches.append(.removeAttribute(handle: handle, name: name))
    }
}

/// Emits `setProperty` / `removeProperty` patches for the symmetric
/// difference between two property dictionaries.
func diffProperties(
    handle: Int,
    old: [String: PropertyValue],
    new: [String: PropertyValue],
    into patches: inout [Patch]
) {
    for (name, newValue) in new {
        if old[name] != newValue {
            patches.append(.setProperty(handle: handle, name: name, value: newValue))
        }
    }
    for name in old.keys where new[name] == nil {
        patches.append(.removeProperty(handle: handle, name: name))
    }
}

/// Emits `setStyle` / `removeStyle` patches for the symmetric difference
/// between two style dictionaries.
func diffStyle(
    handle: Int,
    old: [String: String],
    new: [String: String],
    into patches: inout [Patch]
) {
    for (name, newValue) in new {
        if old[name] != newValue {
            patches.append(.setStyle(handle: handle, name: name, value: newValue))
        }
    }
    for name in old.keys where new[name] == nil {
        patches.append(.removeStyle(handle: handle, name: name))
    }
}

/// Emits `addHandler` / `removeHandler` patches for the symmetric difference
/// between two handler dictionaries. Removed handlers are dropped from the
/// `HandlerRegistry` so their closures can be released. Returns the new
/// `handlerIds` map to commit on the mount node.
func diffHandlers(
    handle: Int,
    old: [String: Int],
    new: [String: EventHandler],
    handlers: HandlerRegistry,
    into patches: inout [Patch]
) -> [String: Int] {
    var nextIDs: [String: Int] = [:]

    // Additions and swaps.
    for (event, newHandler) in new {
        if let oldID = old[event], oldID == newHandler.id {
            // Unchanged.
            nextIDs[event] = oldID
        } else {
            if let oldID = old[event] {
                patches.append(.removeHandler(handle: handle, event: event))
                handlers.remove(id: oldID)
            }
            patches.append(.addHandler(handle: handle, event: event, handlerId: newHandler.id))
            nextIDs[event] = newHandler.id
        }
    }

    // Pure removals (event no longer present in new).
    for (event, oldID) in old where new[event] == nil {
        patches.append(.removeHandler(handle: handle, event: event))
        handlers.remove(id: oldID)
    }

    return nextIDs
}

/// Emits `destroyNode` for `node` and recursively for every descendant.
/// Also drops every handler ID from the registry and fires `onDisappear`
/// on any Component instance encountered.
///
/// Lifecycle ordering: `onDisappear` is called on the component BEFORE
/// recursing into its body subtree — symmetric with how mount-time hooks
/// fire (parent component first, then children). This mirrors React's
/// "parent unmount before child unmount" ordering, so the parent can
/// still read state from children before they are torn down.
@MainActor
func destroy(
    _ node: MountNode,
    into patches: inout [Patch],
    handlers: HandlerRegistry
) {
    // Fire onDisappear on the component instance at this anchor, if any.
    // This is done BEFORE recursing so the parent component's onDisappear
    // runs before any child component's onDisappear — parent-first ordering.
    if let any = node.component {
        any.instance.onDisappear()
        // Close the handler scope that was opened when this component mounted.
        // This evicts every handler registered during the component's `body`
        // evaluation, preventing closures from outliving their Component instance.
        handlers.closeScope()
        // Symmetric with the register call in mount(): drop this instance
        // from the reused-instance diagnostic tracker.
        #if DEBUG
        MountedInstances.unregister(any.instance)
        #endif
    }

    // Symmetric with mount: clear every Ref binding so post-unmount
    // `wrappedValue` reads return nil. Done BEFORE recursing into
    // children so a parent component's `onDisappear` sees consistent
    // already-cleared refs on its descendants (parent-first teardown
    // mirrors parent-first mount).
    if case .element(let data) = node.vnode {
        for binding in data.refBindings {
            binding.clearHandle()
        }
    }

    // Recurse into the parallel component-anchor body slot, if any.
    // componentBody is NOT in node.children — it hangs off its own slot,
    // and forgetting to walk it leaks body DOM nodes when a component
    // anchor is unmounted (e.g. via update()'s default arm on a type
    // mismatch). The leaf body's destroy() invocation emits the actual
    // destroyNode patches; this anchor-level traversal just routes.
    if let body = node.componentBody {
        destroy(body, into: &patches, handlers: handlers)
    }
    for child in node.children {
        destroy(child, into: &patches, handlers: handlers)
    }
    for (_, handlerID) in node.handlerIds {
        handlers.remove(id: handlerID)
    }
    // A component anchor has component != nil and its handle is structural-
    // only (never sent to the driver via a create* patch). Emit destroyNode
    // ONLY for nodes the driver actually knows about (everything except
    // anchors).
    if node.component == nil {
        patches.append(.destroyNode(handle: node.handle))
    }
}

/// Dispatches between the indexed and keyed children-diff strategies. If
/// **any** child in the old or new lists carries a key, the keyed path is
/// used (Task 17); otherwise pair-by-index (Task 16).
@MainActor
func diffChildren(
    mounted: MountNode,
    newChildren: [VNode],
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    into patches: inout [Patch],
    scheduler: Scheduler? = nil,
    parentPath: String = ""
) {
    // Diagnostic: detect mixed keyed/unkeyed siblings. Either every
    // sibling has a key, or none — partial keying gives unkeyed
    // children unstable identity and they re-render as recreated.
    // Both .element and .component children can carry a key; .text and
    // .rawHTML cannot. diagKeyAndIsKeyable() handles the discrimination.
    #if DEBUG
    do {
        var keyedCount = 0
        var unkeyedCount = 0
        for child in newChildren {
            let (key, isKeyable) = diagKeyAndIsKeyable(child)
            guard isKeyable else { continue }
            if key != nil { keyedCount += 1 } else { unkeyedCount += 1 }
        }
        if keyedCount > 0 && unkeyedCount > 0 {
            let parentTag: String
            if case .element(let parentData) = mounted.vnode {
                parentTag = parentData.tag
            } else {
                parentTag = "<root>"
            }
            swiflowDiagnostic("Children of <\(parentTag)> mix keyed (\(keyedCount)) and unkeyed (\(unkeyedCount)) entries. Either key every child or key none.")
        }
    }
    #endif

    if hasAnyKey(mounted.children) || hasAnyKey(newChildren) {
        diffChildrenKeyed(
            mounted: mounted,
            newChildren: newChildren,
            handles: handles,
            handlers: handlers,
            into: &patches,
            scheduler: scheduler,
            parentPath: parentPath
        )
    } else {
        diffChildrenIndexed(
            mounted: mounted,
            newChildren: newChildren,
            handles: handles,
            handlers: handlers,
            into: &patches,
            scheduler: scheduler,
            parentPath: parentPath
        )
    }
}

/// Returns true if any element in `vnodes` is an `.element` with a non-nil
/// key.
func hasAnyKey(_ vnodes: [VNode]) -> Bool {
    for v in vnodes {
        if case .element(let data) = v, data.key != nil {
            return true
        }
    }
    return false
}

/// Same predicate, for `MountNode` (whose `.vnode` carries the key).
func hasAnyKey(_ nodes: [MountNode]) -> Bool {
    for n in nodes {
        if case .element(let data) = n.vnode, data.key != nil {
            return true
        }
    }
    return false
}
