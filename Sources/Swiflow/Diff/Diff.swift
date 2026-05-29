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
    scheduler: Scheduler? = nil,
    environment: EnvironmentValues = .init()
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
            scheduler: scheduler,
            environment: environment
        )
    } else {
        root = mount(next, into: &patches, handles: handles, handlers: handlers, scheduler: scheduler, path: "", environment: environment)
    }
    return DiffResult(patches: patches, newMountTree: root)
}

// MARK: - Diagnostic helpers (debug key-validation, shared across Diff.swift
//         and KeyedChildrenDiff.swift)

/// Returns the key and keyability of a VNode for sibling-key diagnostics.
/// `.element` and `.component` children can carry a key; `.text` and `.rawHTML`
/// cannot. The "isKeyable" flag lets callers skip non-keyable children cleanly.
/// `.environmentOverride` is transparent: recurse into the child.
func diagKeyAndIsKeyable(_ child: VNode) -> (key: String?, isKeyable: Bool) {
    switch child {
    case .element(let data): return (data.key, true)
    case .component(let desc): return (desc.key, true)
    case .text, .rawHTML: return (nil, false)
    case .environmentOverride(_, let child): return diagKeyAndIsKeyable(child)
    case .fragment: return (nil, false)
    }
}

// MARK: - CSS scope-class helpers

/// Prepends `scopeClass` to the `class` attribute of a VNode's root element.
/// If the VNode is not an `.element`, it is returned unchanged.
@MainActor
func addScopeClass(_ vnode: VNode, scopeClass: String) -> VNode {
    guard case .element(var data) = vnode else { return vnode }
    if let existing = data.attributes["class"], !existing.isEmpty {
        data.attributes["class"] = "\(scopeClass) \(existing)"
    } else {
        data.attributes["class"] = scopeClass
    }
    return .element(data)
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
    path: String = "",
    environment: EnvironmentValues = .init()
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
                path: childPath,
                environment: environment
            )
            // Use collectDOMRoots so a fragment child appends all its real DOM
            // roots (there may be zero, one, or many). For an ordinary element
            // or text this is equivalent to the previous single-handle append.
            for root in collectDOMRoots(childMount) {
                patches.append(.appendChild(parent: h, child: root))
            }
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
        // Open a handler scope for this component and capture the stable ID.
        // The scope is closed in `destroy()` when the component unmounts,
        // ensuring handler closures cannot outlive their owning Component.
        // `withScope(_:_:)` pins handler registration to this component's own
        // scope during body evaluation, regardless of which sibling or child
        // scopes are currently open.
        let scopeID = handlers.openScope(debugName: path)
        let bodyVNode = handlers.withScope(scopeID) {
            let previousEnv = AmbientEnvironment.current
            AmbientEnvironment.current = environment
            defer { AmbientEnvironment.current = previousEnv }
            return instance.instance.body
        }
        // Notify the CSS injector so scoped styles are injected into
        // <head> the first time this component type mounts.
        let componentType = type(of: instance.instance)
        onComponentTypeMount?(componentType)
        let scopeClass = "swiflow-\(String(describing: componentType))"
        let bodyMount = mount(
            addScopeClass(bodyVNode, scopeClass: scopeClass),
            into: &patches,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler,
            depth: depth + 1,
            path: path,
            environment: environment
        )
        return MountNode(
            handle: anchorHandle,
            vnode: vnode,
            component: instance,
            componentBody: bodyMount,
            scopeID: scopeID
        )

    case .environmentOverride(let overrides, let child):
        let h = handles.next()
        let merged = environment.merging(overrides)
        let childMount = mount(
            child,
            into: &patches,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler,
            depth: depth,
            path: path,
            environment: merged
        )
        return MountNode(handle: h, vnode: vnode, componentBody: childMount)

    case .fragment(let children):
        let h = handles.next()                       // structural handle (never sent to driver)
        let node = MountNode(handle: h, vnode: vnode)
        for (i, childVNode) in children.enumerated() {
            let childPath = path.isEmpty ? String(i) : "\(path).\(i)"
            let childMount = mount(
                childVNode, into: &patches, handles: handles, handlers: handlers,
                scheduler: scheduler, depth: depth, path: childPath, environment: environment
            )
            node.addChild(childMount)
        }
        return node
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
    path: String = "",
    environment: EnvironmentValues = .init()
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
            parentPath: path,
            environment: environment
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
            return mount(next, into: &patches, handles: handles, handlers: handlers, scheduler: scheduler, path: path, environment: environment)
        }
        // Snapshot the body's DOM identity before the recursive update so we
        // can detect a same-anchor / different-body-element swap (e.g. a
        // route change inside an env-override inside this component) and
        // emit the DOM-level removeChild+appendChild that the recursive
        // default arm leaves to the caller.
        let oldBodyDOMHandleForComponentArm = oldBody.domHandle
        let bodyUpdateStartForComponentArm = patches.count
        // Re-render: call body on the reused instance so any state
        // mutations since the last render (e.g. n = 42 on a Counter)
        // are reflected in the new body VNode.
        //
        // `withScope(_:_:)` pins handler registration to this component's own
        // scope for the duration of the body call. Without this, handlers would
        // land in the top-of-open-scopes entry — which may belong to a child
        // component (e.g. Toast) that is about to be destroyed in this same
        // diff pass, taking the new handlers with it and silently dropping all
        // future events for this component.
        let newBodyVNode = handlers.withScope(mounted.scopeID) {
            let previousEnv = AmbientEnvironment.current
            AmbientEnvironment.current = environment
            defer { AmbientEnvironment.current = previousEnv }
            return instance.instance.body
        }
        // Ensure the scope class stays on the body root across re-renders.
        let componentType = type(of: instance.instance)
        let scopeClass = "swiflow-\(String(describing: componentType))"
        // Reconcile the new body VNode against the previously-mounted body
        // subtree. The returned MountNode may be the same reference (if the
        // body root type/tag matched) or a fresh one (if the body root
        // itself was replaced wholesale). Either way it becomes the new body.
        let newBodyMount = update(
            mounted: oldBody,
            next: addScopeClass(newBodyVNode, scopeClass: scopeClass),
            into: &patches,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler,
            path: path,
            environment: environment
        )
        // If the body's DOM-level identity changed (type or tag swap),
        // splice removeChild+appendChild patches into the parent's DOM
        // ancestor. For a root-level swap (no DOM ancestor in the mount
        // tree), the Renderer detects the root-handle change post-diff
        // and emits a `replaceMount` patch covering the same job.
        if newBodyMount.domHandle != oldBodyDOMHandleForComponentArm,
           let domParentHandle = domAncestorHandle(of: mounted) {
            patches.insert(
                .removeChild(parent: domParentHandle, child: oldBodyDOMHandleForComponentArm),
                at: bodyUpdateStartForComponentArm
            )
            patches.append(.appendChild(parent: domParentHandle, child: newBodyMount.domHandle))
        }
        mounted.componentBody = newBodyMount
        // Commit the new vnode description so the next render's left-hand
        // side reflects the description that was actually diffed.
        mounted.vnode = next
        return mounted

    // EnvironmentOverride → EnvironmentOverride: merge the new overrides into
    // the ambient environment and recurse into the child. The structural handle
    // allocated at mount time is preserved; only the child subtree is updated.
    case (.environmentOverride(_, _), .environmentOverride(let nextOverrides, let nextChild)):
        guard let oldBody = mounted.componentBody else {
            destroy(mounted, into: &patches, handlers: handlers)
            return mount(next, into: &patches, handles: handles, handlers: handlers, scheduler: scheduler, path: path, environment: environment)
        }
        // Snapshot — mirror of the Component reuse arm above. The env
        // override is a structural-only anchor; if its body's DOM identity
        // changes between frames, the surrounding DOM ancestor needs a
        // removeChild + appendChild splice.
        let oldBodyDOMHandleForEnvArm = oldBody.domHandle
        let bodyUpdateStartForEnvArm = patches.count
        let merged = environment.merging(nextOverrides)
        let updatedBody = update(
            mounted: oldBody,
            next: nextChild,
            into: &patches,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler,
            path: path,
            environment: merged
        )
        if updatedBody.domHandle != oldBodyDOMHandleForEnvArm,
           let domParentHandle = domAncestorHandle(of: mounted) {
            patches.insert(
                .removeChild(parent: domParentHandle, child: oldBodyDOMHandleForEnvArm),
                at: bodyUpdateStartForEnvArm
            )
            patches.append(.appendChild(parent: domParentHandle, child: updatedBody.domHandle))
        }
        mounted.componentBody = updatedBody
        mounted.vnode = next
        return mounted

    // Fragment → fragment: reconcile the held children. The fragment itself is
    // a structural slot with no DOM node, so there is nothing to patch at this
    // level; child placement flows through the DOM-anchor primitives.
    case (.fragment, .fragment(let newChildren)):
        diffChildren(
            mounted: mounted,
            newChildren: newChildren,
            handles: handles,
            handlers: handlers,
            into: &patches,
            scheduler: scheduler,
            parentPath: path,
            environment: environment
        )
        mounted.vnode = next
        return mounted

    // Any other transition: destroy the old subtree and mount fresh.
    default:
        destroy(mounted, into: &patches, handlers: handlers)
        return mount(next, into: &patches, handles: handles, handlers: handlers, scheduler: scheduler, path: path, environment: environment)
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
@MainActor
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
package func destroy(
    _ node: MountNode,
    into patches: inout [Patch],
    handlers: HandlerRegistry,
    skipDestroyForHandle: Int? = nil
) {
    // Fire onDisappear on the component instance at this anchor, if any.
    // This is done BEFORE recursing so the parent component's onDisappear
    // runs before any child component's onDisappear — parent-first ordering.
    if let any = node.component {
        any.instance.onDisappear()
        // Close the handler scope that was opened when this component mounted.
        // Uses the stable frame ID (not stack position) so sibling components
        // can be destroyed in any order without cross-contaminating each other's
        // handler registrations.
        if let scopeID = node.scopeID {
            handlers.closeScope(scopeID)
        }
        OnChangeStorage.remove(for: ObjectIdentifier(any.instance))
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
    // only (never sent to the driver via a create* patch). An environmentOverride
    // node also has a structural-only handle (never sent to the driver via a
    // create* patch). Emit destroyNode ONLY for nodes the driver actually knows
    // about (everything except anchors and environment-override nodes).
    if node.component == nil {
        if case .environmentOverride = node.vnode {
            // Structural handle — no destroyNode patch.
        } else if case .fragment = node.vnode {
            // Structural handle — no destroyNode patch; children handled below.
        } else if node.handle != skipDestroyForHandle {
            patches.append(.destroyNode(handle: node.handle))
        }
    }
}

/// Walks `node.parent` upward until a DOM-tracked ancestor is found, and
/// returns its handle. Component anchors and environment-override nodes
/// have **structural** handles (the JS driver never sees them via a
/// `create*` patch), so they're skipped; the first ancestor whose handle
/// is in the driver's `nodes` map is the one DOM ops like `removeChild` /
/// `appendChild` should reference.
///
/// Returns `nil` when the walk reaches the mount-tree root without finding
/// a DOM-tracked ancestor — which is the case for the root component's own
/// body. The Renderer handles that case by emitting a `replaceMount` patch
/// using the selector that the initial `mount` patch attached to.
@MainActor
package func domAncestorHandle(of node: MountNode) -> Int? {
    var current = node.parent
    while let candidate = current {
        if candidate.component != nil {
            // Component anchor — structural handle, skip.
        } else if case .environmentOverride = candidate.vnode {
            // Environment-override anchor — structural handle, skip.
        } else if case .fragment = candidate.vnode {
            // Fragment — structural handle, skip.
        } else {
            // Element / text / rawHTML — handle is in the driver's nodes map.
            return candidate.handle
        }
        current = candidate.parent
    }
    return nil
}


/// Children-first walk over `node` and its entire subtree. For each component
/// anchor encountered:
///   - if its instance's `ObjectIdentifier` is in `preExistingIDs`, fire `onChange()`
///   - otherwise, fire `onAppear()`
///
/// Children-first ordering means a parent's hook observes a fully
/// mounted/committed subtree. Matches React's commit-phase invariant: a
/// child's `componentDidMount` runs before its parent's `componentDidUpdate`.
///
/// `preExistingIDs == []` on first mount (no instances existed before this
/// diff) reproduces the previous `fireOnAppearTree` behavior exactly: every
/// component is treated as new and gets `onAppear`.
@MainActor
package func firePostRenderLifecycle(_ node: MountNode, preExistingIDs: Set<ObjectIdentifier>) {
    if let body = node.componentBody {
        firePostRenderLifecycle(body, preExistingIDs: preExistingIDs)
    }
    for child in node.children {
        firePostRenderLifecycle(child, preExistingIDs: preExistingIDs)
    }
    if let any = node.component {
        if preExistingIDs.contains(ObjectIdentifier(any.instance)) {
            any.instance.onChange()
        } else {
            any.instance.onAppear()
        }
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
    parentPath: String = "",
    environment: EnvironmentValues = .init()
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
            parentPath: parentPath,
            environment: environment
        )
    } else {
        diffChildrenIndexed(
            mounted: mounted,
            newChildren: newChildren,
            handles: handles,
            handlers: handlers,
            into: &patches,
            scheduler: scheduler,
            parentPath: parentPath,
            environment: environment
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

/// Collects the `ObjectIdentifier` of every live component instance reachable
/// from `node`. Returns an empty set when `node` is nil — used to seed the
/// first-mount case where no instances existed before this diff, so every
/// component in the new tree is treated as freshly mounted.
@MainActor
package func collectComponentIDs(_ node: MountNode?) -> Set<ObjectIdentifier> {
    var ids: Set<ObjectIdentifier> = []
    func walk(_ n: MountNode) {
        if let any = n.component {
            ids.insert(ObjectIdentifier(any.instance))
        }
        if let body = n.componentBody { walk(body) }
        for child in n.children { walk(child) }
    }
    if let node { walk(node) }
    return ids
}
