// Sources/Swiflow/Diff/Diff.swift

/// The output of a single diff pass: the patches to apply, plus the new
/// mount tree to commit as the next render's left-hand side.
public struct DiffResult {
    public let patches: [Patch]
    public let newMountTree: MountNode

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
    }
}

// MARK: - Update (subsequent renders)

/// Reconciles `next` against `mounted`. The returned `MountNode` is the
/// committed mount-tree node for that position (it may be the same object as
/// `mounted` if the diff is in-place, or a fresh replacement if the tag
/// changed — subsequent tasks add the replace path).
func update(
    mounted: MountNode,
    next: VNode,
    into patches: inout [Patch],
    handles: HandleAllocator,
    handlers: HandlerRegistry
) -> MountNode {
    // Task 10 scope: same-tag element with only `attributes` changes.
    // Other bags + text + rawHTML + tag replace are added in Tasks 11–17.
    guard
        case .element(let oldData) = mounted.vnode,
        case .element(let newData) = next,
        oldData.tag == newData.tag
    else {
        // Placeholder: tag-replace and text/rawHTML paths land in Tasks 14–15.
        // For now, fall back to remount (will be replaced).
        fatalError("update path for non-attribute changes not yet implemented")
    }

    diffAttributes(handle: mounted.handle, old: oldData.attributes, new: newData.attributes, into: &patches)
    diffProperties(handle: mounted.handle, old: oldData.properties, new: newData.properties, into: &patches)
    diffStyle(handle: mounted.handle, old: oldData.style, new: newData.style, into: &patches)

    mounted.vnode = next
    return mounted
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
