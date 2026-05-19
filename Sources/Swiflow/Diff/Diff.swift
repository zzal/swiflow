// Sources/Swiflow/Diff/Diff.swift

/// The output of a single diff pass: the patches to apply, plus the new
/// mount tree to commit as the next render's left-hand side.
public struct DiffResult {
    /// Patches to ship across the JS bridge, in apply order.
    public let patches: [Patch]
    /// The mount tree the caller must commit as the next render's baseline.
    public let newMountTree: MountNode

    /// Wraps the two outputs of a diff pass.
    public init(patches: [Patch], newMountTree: MountNode) {
        self.patches = patches
        self.newMountTree = newMountTree
    }
}

/// Diffs `next` against `mounted`, producing the patches the renderer must
/// apply and the new mount tree to commit. When `mounted` is `nil`, the
/// function treats every node as fresh and emits `create…` patches for the
/// entire tree.
public func diff(
    mounted: MountNode?,
    next: VNode,
    handles: HandleAllocator,
    handlers: HandlerRegistry
) -> DiffResult {
    var patches: [Patch] = []
    let root: MountNode
    if let mounted = mounted {
        root = update(
            mounted: mounted,
            next: next,
            into: &patches,
            handles: handles,
            handlers: handlers
        )
    } else {
        root = mount(next, into: &patches, handles: handles, handlers: handlers)
    }
    return DiffResult(patches: patches, newMountTree: root)
}

// MARK: - Mount helpers (first render only — Task 9 scope)

/// Creates the DOM-side node and (recursively) all children, appending patches
/// in document order. Returns the new `MountNode` describing the freshly
/// mounted subtree.
func mount(
    _ vnode: VNode,
    into patches: inout [Patch],
    handles: HandleAllocator,
    handlers: HandlerRegistry
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

        for childVNode in data.children {
            let childMount = mount(
                childVNode,
                into: &patches,
                handles: handles,
                handlers: handlers
            )
            patches.append(.appendChild(parent: h, child: childMount.handle))
            mountNode.addChild(childMount)
        }

        return mountNode

    case .component:
        // Phase 3 (Tasks 4–5) will instantiate the component, mount its body,
        // and store an AnyComponent on the MountNode. For now, reaching this
        // path is a programming error — callers should not diff component trees
        // before the reconciler is wired up.
        fatalError("VNode.component mount not yet implemented (Task 4)")
    }
}

// MARK: - Update (subsequent renders)

/// Reconciles `next` against `mounted`. The returned `MountNode` is the
/// committed mount-tree node for that position. If the diff replaces the
/// node (different case kind, or different element tag — see Task 15), the
/// returned `MountNode` is a fresh object with a new handle and the caller
/// is responsible for any parent-level `insertBefore` / `appendChild`
/// rewiring (for the root, the renderer reattaches to the selector).
func update(
    mounted: MountNode,
    next: VNode,
    into patches: inout [Patch],
    handles: HandleAllocator,
    handlers: HandlerRegistry
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
            into: &patches
        )
        mounted.vnode = next
        return mounted

    // Any other transition: destroy the old subtree and mount fresh.
    default:
        destroy(mounted, into: &patches, handlers: handlers)
        return mount(next, into: &patches, handles: handles, handlers: handlers)
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
/// Also drops every handler ID from the registry.
func destroy(
    _ node: MountNode,
    into patches: inout [Patch],
    handlers: HandlerRegistry
) {
    for child in node.children {
        destroy(child, into: &patches, handlers: handlers)
    }
    for (_, handlerID) in node.handlerIds {
        handlers.remove(id: handlerID)
    }
    patches.append(.destroyNode(handle: node.handle))
}

/// Dispatches between the indexed and keyed children-diff strategies. If
/// **any** child in the old or new lists carries a key, the keyed path is
/// used (Task 17); otherwise pair-by-index (Task 16).
func diffChildren(
    mounted: MountNode,
    newChildren: [VNode],
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    into patches: inout [Patch]
) {
    if hasAnyKey(mounted.children) || hasAnyKey(newChildren) {
        diffChildrenKeyed(
            mounted: mounted,
            newChildren: newChildren,
            handles: handles,
            handlers: handlers,
            into: &patches
        )
    } else {
        diffChildrenIndexed(
            mounted: mounted,
            newChildren: newChildren,
            handles: handles,
            handlers: handlers,
            into: &patches
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
