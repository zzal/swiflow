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

#if DEBUG
/// `true` when a keyable child carries a key AND is an embedded component.
/// A keyed component among unkeyed siblings is the dominant way the
/// mixed-keying trap fires: passing `key:` to an `embed`/component to force
/// remount-on-change (the [[embed-props-need-rekey]] fix) makes it a keyed
/// sibling, which traps if the siblings aren't keyed too.
private func diagIsKeyedComponent(_ child: VNode) -> Bool {
    switch child {
    case .component(let desc): return desc.key != nil
    case .environmentOverride(_, let inner): return diagIsKeyedComponent(inner)
    default: return false
    }
}

/// The mixed-keying diagnostic for a parent whose keyable children are part
/// keyed / part unkeyed, or `nil` when the children are consistent. Both the
/// mount-time and re-render checks share this one message so they can't drift.
/// When a keyed *component* is present, the message names that specific cause
/// and the isolate-in-a-container fix; otherwise it gives the generic guidance.
func mixedKeyingDiagnostic(parentTag: String, children: [VNode]) -> String? {
    var keyedCount = 0, unkeyedCount = 0, keyedComponentCount = 0
    for child in children {
        let (key, isKeyable) = diagKeyAndIsKeyable(child)
        guard isKeyable else { continue }
        if key != nil {
            keyedCount += 1
            if diagIsKeyedComponent(child) { keyedComponentCount += 1 }
        } else {
            unkeyedCount += 1
        }
    }
    guard keyedCount > 0 && unkeyedCount > 0 else { return nil }
    let base = "Children of <\(parentTag)> mix keyed (\(keyedCount)) and unkeyed (\(unkeyedCount)) entries. Either key every child or key none."
    guard keyedComponentCount > 0 else { return base }
    return base + " A keyed embedded component needs keyed siblings — if you passed `key:` to force a remount-on-change, isolate that component in its own single-child container (e.g. `VStack { … }`) so it doesn't mix with unkeyed siblings."
}

/// An `<option>`'s effective value: its explicit `value` attribute, else its
/// text content (the browser's own fallback). Only inspects direct text
/// children — good enough for the guardrail's static read.
private func diagOptionValue(_ data: ElementData) -> String {
    if let v = data.attributes["value"] { return v }
    return data.children.reduce(into: "") { acc, child in
        if case .text(let t) = child { acc += t }
    }
}

/// Diagnostic for the silent `<select>` mount-order trap, or `nil` when the
/// bound value will land correctly. `.selection($state)` sets the select's
/// `value` property before its `<option>` children attach at first mount, so
/// the browser resets to the first option and the DOM stays wrong until the
/// state next changes ([[select-initial-value-mount-order]]). It only bites
/// when the bound value isn't the first option AND the matching option carries
/// no `selected` attribute (the workaround) — so we warn on exactly that.
func selectMountOrderDiagnostic(_ data: ElementData) -> String? {
    guard data.tag == "select",
          case .string(let bound)? = data.properties["value"],
          !bound.isEmpty else { return nil }

    // Direct `<option>` children (transparent through fragment/env wrappers).
    func options(_ children: [VNode]) -> [ElementData] {
        children.flatMap { child -> [ElementData] in
            switch child {
            case .element(let d) where d.tag == "option": return [d]
            case .environmentOverride(_, let inner): return options([inner])
            case .fragment(let kids): return options(kids)
            default: return []
            }
        }
    }
    let opts = options(data.children)
    guard let first = opts.first else { return nil }        // no options to reason about
    if diagOptionValue(first) == bound { return nil }        // first option matches → browser default lands right
    // A matching option carrying `selected` makes the browser honor it
    // regardless of mount order — that's the intended fix, so stay quiet.
    let match = opts.first { diagOptionValue($0) == bound }
    if let match, match.attributes["selected"] != nil { return nil }
    guard match != nil else { return nil }                   // no matching option at all → a different problem; don't false-warn

    return "<select> bound to '\(bound)' via .selection(...) won't show that value at first mount — the value is applied before the <option> children attach, so the browser resets to the first option. Add `.attr(\"selected\", \"\")` to the <option> whose value is '\(bound)'."
}
#endif

// MARK: - CSS scope-class helpers

/// Prepends `scopeClass` to the `class` attribute of a VNode's root element.
///
/// A non-element root (an embedded component, fragment, or text) has no
/// attribute to carry the class. That only matters when the component
/// declares `scopedStyles` — its injected sheet is scoped under
/// `.swiflow-<Type>`, so a missing carrier makes every rule silently
/// unmatchable. `hasScopedStyles` opts such roots into a layout-neutral
/// `display: contents` carrier element instead (the `ThemeScope` wrapper
/// technique). Components without scopedStyles keep their exact DOM shape:
/// non-element roots pass through unchanged, as before.
@MainActor
func addScopeClass(_ vnode: VNode, scopeClass: String, hasScopedStyles: Bool) -> VNode {
    if case .element(var data) = vnode {
        if let existing = data.attributes["class"], !existing.isEmpty {
            data.attributes["class"] = "\(scopeClass) \(existing)"
        } else {
            data.attributes["class"] = scopeClass
        }
        return .element(data)
    }
    guard hasScopedStyles else { return vnode }
    return .element(ElementData(
        tag: "div",
        attributes: ["class": scopeClass],
        style: ["display": "contents"],
        children: [vnode]
    ))
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
        // `.task` bodies are async — they run after this synchronous mount
        // returns, so starting them here (before children mount) is immaterial
        // to ordering. Symmetric cancel lives in `destroy()`.
        startTasks(on: mountNode, data.taskBindings)

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
            if let message = mixedKeyingDiagnostic(parentTag: data.tag, children: data.children) {
                swiflowDiagnostic(message)
            }
            // The <select> mount-order trap is silent and recoverable (add a
            // `selected` attr), so warn rather than trap.
            if let message = selectMountOrderDiagnostic(data) {
                swiflowWarn(message)
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
            RenderObserverBox.current?.willEvaluate(owner: instance, scheduler: scheduler)
            defer {
                AmbientEnvironment.current = previousEnv
                RenderObserverBox.current?.didEvaluate()
            }
            return instance.instance.body
        }
        // Notify the CSS injector so scoped styles are injected into
        // <head> the first time this component type mounts.
        let componentType = type(of: instance.instance)
        onComponentTypeMount?(componentType)
        let scopeClass = "swiflow-\(String(describing: componentType))"
        let bodyMount = mount(
            addScopeClass(bodyVNode, scopeClass: scopeClass,
                          hasScopedStyles: componentType.scopedStyles != nil),
            into: &patches,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler,
            depth: depth + 1,
            path: path,
            environment: environment
        )
        // Diagnostic: a bare-fragment body has no single DOM node — exit
        // animations can't target it and identity swaps degrade to remove+
        // append of every root. Wrap multi-root bodies in one element. This
        // was the diff's only unguarded footgun (every sibling hazard traps).
        #if DEBUG
        if bodyIsFragmentRooted(bodyMount) {
            swiflowDiagnostic("Component \(String(describing: componentType))'s body is a bare fragment (multiple roots / no single DOM node). Wrap the body in a single element (div, VStack, ...): fragment bodies get no exit animation, and body identity swaps degrade to removing and re-appending every root.")
        }
        #endif
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
        // Memoization bail (#91): if both elements carry a non-nil, equal
        // memoKey, the caller declares the element + subtree unchanged. Skip all
        // reconciliation and keep the mounted node as-is. (mounted.vnode stays
        // the prior value, which equals `next` by the caller's contract.)
        // This also skips `Ref` re-binding and `.task(rerunOn:)` reconciliation
        // for the whole subtree — the new VNode's ref/task bindings are never
        // even inspected. Don't pair `.memoKey` with `.ref`/`.task(rerunOn:)`
        // expecting them to pick up live updates on a memo hit.
        //
        // The discarded subtree's handlers were already registered during
        // body build (`.on` registers eagerly, before the diff runs). They
        // must be evicted here or every memo hit leaks its subtree's handler
        // registrations into the owning scope until the component unmounts —
        // at animation-rate render frequencies that grew the scope by
        // hundreds of IDs per second and degraded every later eviction
        // (found via GridBoard playback: 60 → 6 fps over minutes).
        if let oldKey = oldData.memoKey, let newKey = newData.memoKey, oldKey == newKey {
            evictDiscardedHandlers(of: next, handlers: handlers)
            return mounted
        }
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
        reconcileTasks(on: mounted, new: newData.taskBindings)
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
        // Escape hatch: an `.unmanagedChildren()` element owns its own subtree — Swiflow mounted
        // its initial children once and never reconciles inside it again. The shell (the four bags,
        // diffed above) stays reactive; only children are left alone, so foreign-managed DOM
        // (custom-element shadow/light children, a WASM-painted <canvas>, third-party widgets)
        // survives every re-render.
        if !newData.managesOwnChildren {
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
        }
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
        #if DEBUG
        // Guardrail (audit V Wave-2 #6): the factory ran at FIRST MOUNT only,
        // so init content froze — a changed contentKey digest under this
        // unchanged (typeID, key) identity means the reused instance is
        // showing stale first-mount data. `refresh:` present = the caller
        // threads data live, so it's exempt. Warns once per change:
        // `mounted.vnode = next` below stores THIS description, so the next
        // render compares against the new digest.
        if let oldCK = oldDesc.contentKey, let newCK = newDesc.contentKey,
           oldCK != newCK, newDesc.refresh == nil {
            swiflowWarn(
                "\(type(of: instance.instance))'s embedded content changed but its key "
                    + "didn't — the reused instance still shows its FIRST-MOUNT data. "
                    + "Pass a key: that changes with the content, or push it live with refresh:."
            )
        }
        #endif
        // Push refreshed props into the reused instance BEFORE re-evaluating its
        // body, so the body reflects the parent's current data (see
        // `embed(_:refresh:)`). The closure comes from THIS render's description
        // (`newDesc`), so it carries the parent's latest values; the factory in
        // `newDesc` is deliberately NOT called (that would remount and reset
        // `@State`). Runs only on reuse — first mount already has current props
        // from the factory. Contract: the closure targets plain stored props,
        // never `@State` (assigning `@State` here re-enters the scheduler every
        // render → a render loop).
        #if DEBUG
        // Mark this instance's refresh as running so the scheduler can catch a
        // `@State` assignment inside the closure (the documented render-loop
        // footgun). Cleared immediately after — refresh is non-throwing.
        RefreshReentrancyGuard.activeInstanceID = ObjectIdentifier(instance.instance)
        newDesc.refresh?(instance)
        RefreshReentrancyGuard.activeInstanceID = nil
        #else
        newDesc.refresh?(instance)
        #endif
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
            RenderObserverBox.current?.willEvaluate(owner: instance, scheduler: scheduler)
            defer {
                AmbientEnvironment.current = previousEnv
                RenderObserverBox.current?.didEvaluate()
            }
            return instance.instance.body
        }
        // Ensure the scope class stays on the body root across re-renders.
        let componentType = type(of: instance.instance)
        let scopeClass = "swiflow-\(String(describing: componentType))"
        // Reconcile the new body VNode against the previously-mounted body
        // subtree — shared with the environmentOverride arm below (both
        // anchor a single body slot the same way; see the shared function's
        // doc for the double-splice invariant this protects).
        reconcileStructuralBody(
            anchor: mounted,
            oldBody: oldBody,
            bodyNext: addScopeClass(newBodyVNode, scopeClass: scopeClass,
                                    hasScopedStyles: componentType.scopedStyles != nil),
            into: &patches,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler,
            path: path,
            bodyEnvironment: environment
        )
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
        // The env override is a structural-only anchor with exactly the
        // same single-body-slot shape as the component reuse arm above —
        // share its reconcile-and-splice logic rather than re-copying it.
        reconcileStructuralBody(
            anchor: mounted,
            oldBody: oldBody,
            bodyNext: nextChild,
            into: &patches,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler,
            path: path,
            bodyEnvironment: environment.merging(nextOverrides)
        )
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

/// Reconciles a structural anchor's single body slot against `bodyNext`,
/// splicing a DOM-level remove+append if the body root was replaced
/// wholesale. Shared by the `.component` reuse arm and the
/// `.environmentOverride` arm — both anchor exactly one body subtree the
/// same way, and previously hand-copied this dance (extracted after the two
/// copies were found to have drifted; see the audit's sibling-inconsistency
/// note). `bodyNext` is the VNode to diff the anchor's existing body
/// against — the re-rendered, scope-classed body for a component; the
/// wrapped child for an environment override. `bodyEnvironment` is whatever
/// environment the recursive `update` should see (unchanged for a
/// component; merged with the override's for an environmentOverride).
///
/// Assumes the body renders in place, directly under the anchor's nearest
/// real DOM ancestor (`domAncestorHandle(of: anchor)`) — true for both
/// current callers, which are DOM-transparent. A structural anchor that
/// relocates its body elsewhere (e.g. a future portal) cannot reuse this
/// helper as-is: it would splice at the wrong parent.
@MainActor
func reconcileStructuralBody(
    anchor: MountNode,
    oldBody: MountNode,
    bodyNext: VNode,
    into patches: inout [Patch],
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    scheduler: Scheduler?,
    path: String,
    bodyEnvironment: EnvironmentValues
) {
    // Snapshot the body's DOM identity before the recursive update so we
    // can detect a same-anchor / different-body-element swap (e.g. a route
    // change inside a nested structural anchor) and emit the DOM-level
    // removeChild+appendChild that the recursive default arm leaves to the
    // caller.
    let oldBodyRoots = collectDOMRoots(oldBody)
    let bodyUpdateStart = patches.count
    let newBody = update(
        mounted: oldBody,
        next: bodyNext,
        into: &patches,
        handles: handles,
        handlers: handlers,
        scheduler: scheduler,
        path: path,
        environment: bodyEnvironment
    )
    // If the body was replaced WHOLESALE (update returned a fresh MountNode
    // — type or tag swap at the body root), splice removeChild+appendChild
    // patches into the anchor's DOM ancestor. For a root-level swap (no DOM
    // ancestor in the mount tree), the Renderer detects the root-handle
    // change post-diff and emits a `replaceMount` patch covering the same
    // job.
    //
    // The gate is REFERENCE identity, not a roots comparison: a
    // same-reference return means any DOM-root change happened deeper
    // inside a nested structural arm (component/environmentOverride) that
    // already spliced at this same ancestor — re-splicing here would issue
    // a second removeChild for a node the first splice already detached.
    // That throws NotFoundError in the driver; the driver's per-patch
    // try/catch logs and skips it rather than aborting the whole batch, so
    // the redundant removal itself is harmless. The paired duplicate
    // appendChild is the real residual risk: unlike removeChild it does
    // NOT throw on an already-attached node — DOM `appendChild` just
    // relocates it to the end of its parent's children — so a parent with
    // other children after that position would see them silently
    // reordered. Latent while routers sat at the render root; exposed the
    // first time a router gained a DOM ancestor (#137's scope-class
    // carrier).
    // Roots are still collected as the full collectDOMRoots list, not a
    // single domHandle: a fragment body has 0..N real roots and NO
    // representable single handle.
    let newBodyRoots = collectDOMRoots(newBody)
    if newBody !== oldBody,
       let domParentHandle = domAncestorHandle(of: anchor) {
        patches.insert(
            contentsOf: oldBodyRoots.map {
                .removeChild(parent: domParentHandle, child: $0)
            },
            at: bodyUpdateStart
        )
        patches.append(contentsOf: newBodyRoots.map {
            .appendChild(parent: domParentHandle, child: $0)
        })
    }
    anchor.setComponentBody(newBody)
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

/// Evicts every handler registered by a discarded VNode subtree — the
/// new tree a memoKey hit throws away. `.on` closures register with the
/// `HandlerRegistry` while the component body is being BUILT, so by diff
/// time the discarded tree's handlers are already in the registry; without
/// this walk they'd stay there (attributed to the owning scope) until the
/// component unmounts.
///
/// `.component` nodes are deliberately not recursed into: an embedded
/// child's body has not been evaluated for the discarded tree (body
/// evaluation happens during the component's own mount/update), so it has
/// registered nothing yet.
@MainActor
func evictDiscardedHandlers(of vnode: VNode, handlers: HandlerRegistry) {
    switch vnode {
    case .element(let data):
        for (_, handler) in data.handlers {
            handlers.remove(id: handler.id)
        }
        for child in data.children {
            evictDiscardedHandlers(of: child, handlers: handlers)
        }
    case .fragment(let children):
        for child in children {
            evictDiscardedHandlers(of: child, handlers: handlers)
        }
    case .environmentOverride(_, let child):
        evictDiscardedHandlers(of: child, handlers: handlers)
    case .text, .rawHTML, .component:
        return
    }
}

/// True when this anchor's body chain ends at a `.fragment` — the case
/// `MountTree.domHandle` cannot represent (a fragment maps to 0..N DOM
/// nodes, so no single handle exists). Diagnosed at component mount; the
/// splice/removal paths below route through `collectDOMRoots` so release
/// builds degrade safely instead of emitting phantom handles.
@MainActor
func bodyIsFragmentRooted(_ node: MountNode) -> Bool {
    if case .fragment = node.vnode { return true }
    if let body = node.componentBody { return bodyIsFragmentRooted(body) }
    return false
}

/// Remove one child subtree from the DOM and destroy it, honoring the
/// component's exit animation when — and only when — the subtree has exactly
/// one real DOM root. A fragment-bodied component has 0..N roots: there is no
/// single node to animate, so it degrades to plain removal of every root (see
/// FragmentBodyTests). Shared by the keyed differ's two removal paths and the
/// indexed differ — previously copy-pasted ×3, and all three carried the
/// phantom-handle bug (`removed.domHandle` on a fragment body).
@MainActor
func removeAndDestroyChild(
    _ removed: MountNode,
    parentDOMHandle: Int,
    handlers: HandlerRegistry,
    into patches: inout [Patch]
) {
    let roots = collectDOMRoots(removed)
    if let comp = removed.component,
       let anim = type(of: comp.instance).exitAnimation,
       roots.count == 1, let only = roots.first {
        let durMs = (type(of: comp.instance).exitDuration ?? 0) * 1000
        patches.append(.animateExit(
            handle: only,
            parentHandle: parentDOMHandle,
            animation: anim,
            durationMs: durMs
        ))
        destroy(removed, into: &patches, handlers: handlers, skipDestroyForHandle: only)
    } else {
        for root in roots {
            patches.append(.removeChild(parent: parentDOMHandle, child: root))
        }
        destroy(removed, into: &patches, handlers: handlers)
    }
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
package
func destroy(
    _ node: MountNode,
    into patches: inout [Patch],
    handlers: HandlerRegistry,
    skipDestroyForHandle: Int? = nil,
    preserveInstance: ObjectIdentifier? = nil
) {
    // Fire onDisappear on the component instance at this anchor, if any.
    // This is done BEFORE recursing so the parent component's onDisappear
    // runs before any child component's onDisappear — parent-first ordering.
    if let any = node.component {
        // A resync (Renderer.resyncFullRemount) tears down the whole tree
        // but REUSES the root component instance in the fresh diff that
        // immediately follows — exactly as a normal re-render reuses it. For
        // that one surviving instance we must NOT run the "this instance is
        // going away" teardown: firing onDisappear() with no paired onAppear()
        // would silently drop root-managed resources (listeners, timers, query
        // subscriptions) — the very silent-divergence class the resync exists
        // to fix — and wiping its onChange(of:) baselines / dropping its query
        // subscriptions would make the resync observably diverge from a normal
        // render. The fresh diff re-fires onChange() (not onAppear, since the
        // instance is in preExistingIDs) and reconciles its queries in place,
        // so skipping these leaves the root exactly where a normal render
        // would. `preserveInstance` only ever matches this top-level anchor —
        // descendants are genuinely unmounted and must tear down fully — so
        // the flag is deliberately NOT threaded into the recursive calls below.
        let isPreservedRoot = preserveInstance == ObjectIdentifier(any.instance)
        if !isPreservedRoot {
            any.instance.onDisappear()
        }
        // Close the handler scope that was opened when this component mounted.
        // Uses the stable frame ID (not stack position) so sibling components
        // can be destroyed in any order without cross-contaminating each other's
        // handler registrations. This runs for the preserved root too: the
        // fresh diff opens a BRAND-NEW handler scope (new handler IDs), so the
        // old scope must close or its handler closures leak.
        if let scopeID = node.scopeID {
            handlers.closeScope(scopeID)
        }
        if !isPreservedRoot {
            OnChangeStorage.remove(for: ObjectIdentifier(any.instance))
            RenderObserverBox.current?.componentDidUnmount(any)
        }
        // Symmetric with the register call in mount(): drop this instance
        // from the reused-instance diagnostic tracker. This runs for the
        // preserved root too — the fresh diff re-registers it, and skipping
        // the unregister here would make that re-register trip the
        // already-mounted diagnostic on every resync.
        #if DEBUG
        MountedInstances.unregister(any.instance)
        #endif
    }

    // Cancel any `.task` effects on this node before tearing it down so late
    // writes from in-flight tasks are dropped (dead-slot guard).
    cancelTasks(on: node)

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
            any.instance._swiflowDidMount()
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
        let parentTag: String
        if case .element(let parentData) = mounted.vnode {
            parentTag = parentData.tag
        } else {
            parentTag = "<root>"
        }
        if let message = mixedKeyingDiagnostic(parentTag: parentTag, children: newChildren) {
            swiflowDiagnostic(message)
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

/// Returns true if any element in `vnodes` is an `.element` or `.component`
/// with a non-nil key.
func hasAnyKey(_ vnodes: [VNode]) -> Bool {
    for v in vnodes {
        if case .element(let data) = v, data.key != nil { return true }
        if case .component(let desc) = v, desc.key != nil { return true }
    }
    return false
}

/// Same predicate, for `MountNode` (whose `.vnode` carries the key).
func hasAnyKey(_ nodes: [MountNode]) -> Bool {
    for n in nodes {
        if case .element(let data) = n.vnode, data.key != nil { return true }
        if case .component(let desc) = n.vnode, desc.key != nil { return true }
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
