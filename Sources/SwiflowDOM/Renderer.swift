// Sources/SwiflowDOM/Renderer.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow
import SwiflowQuery

/// Owns Swiflow's per-application render state in a WASM/browser environment.
///
/// One Renderer is created per mounted root by `Swiflow.render(into:_:)` and
/// stored in the module-global `renderers` dict keyed by selector. It wraps a
/// live Component instance and wires a `RAFScheduler` so `@State` mutations
/// schedule re-renders via `requestAnimationFrame` automatically.
@MainActor
final class Renderer {
    // MARK: - Stored properties

    /// The live Component instance this renderer renders.
    let rootComponent: AnyComponent

    /// The CSS selector the JS driver uses to attach the root DOM node.
    let selector: String

    /// Allocates monotonically-increasing integer handles for new DOM nodes.
    let handles: HandleAllocator

    /// Stores event-handler closures by ID; wired into the JS dispatcher.
    let handlers: HandlerRegistry

    /// The typed `window.swiflow` driver seam — every Swift → driver call
    /// (`mount`, `applyPatches`) routes through here. Defaults to `JSDriver`
    /// (the live global); injectable so a BridgeJS/mock driver can swap in.
    let driver: any SwiflowDriver

    /// The committed mount tree from the last `renderOnce()`, or `nil` before
    /// the first render.
    var mountTree: MountNode?

    /// Owns this root's in-flight `.task` runs (Phase 20). Installed as
    /// `SwiflowTaskRuntime.currentScope` around each render so tasks started by
    /// this root's diff are tracked here, isolated from other roots.
    let taskScope = TaskScope()

    /// This root's query client, installed as the render observer around each
    /// render so `query()` during `body` reaches it.
    let queryClient = QueryClient()

    /// Cumulative count of `renderOnce()` calls since this Renderer was created.
    /// Read by `DevAPI` to populate `__swiflow.perf().renders`.
    private(set) var renderCount: Int = 0

    /// Count of patches emitted by the most recent `renderOnce()` call.
    /// Read by `DevAPI` to populate `__swiflow.perf().lastPatchCount`.
    private(set) var lastPatchCount: Int = 0

    /// Wall-clock duration of the most recent `renderOnce()` call, in milliseconds.
    /// Measured via `window.performance.now()`. Read by `DevAPI` to populate
    /// `__swiflow.perf().lastRenderMs`.
    private(set) var lastRenderMs: Double = 0

    /// Heap-allocated cell that allows the init to assign the `RAFScheduler`
    /// after `self` is fully initialised — required because the scheduler
    /// closure needs a weak reference to `self`, which can only be formed once
    /// all stored properties are set.
    private let _schedulerBox: MutableBox<(any Scheduler)?> = MutableBox(nil)

    /// The background-revalidation driver for this root (setInterval tick +
    /// visibilitychange/focus listeners). Started in `init`; torn down in
    /// `teardown()`.
    private var backgroundRevalidation: BackgroundRevalidation?

    /// The active `Scheduler`, if any. Exposed as a computed property so tests
    /// and internal callers get a clean `Scheduler?` type without reaching
    /// into the box.
    var scheduler: (any Scheduler)? { _schedulerBox.value }

    // MARK: - Initializers

    /// Wraps a live Component instance and wires a `RAFScheduler` so `@State`
    /// mutations automatically schedule re-renders without any manual
    /// `rerender()` call.
    ///
    /// The `RAFScheduler` captures `self` weakly to avoid a retain cycle:
    /// Renderer → _schedulerBox → RAFScheduler → closure → Renderer.
    init(rootComponent: AnyComponent, selector: String, handles: HandleAllocator = sharedHandleAllocator, driver: any SwiflowDriver = JSDriver()) {
        self.rootComponent = rootComponent
        self.selector = selector
        self.handles = handles
        self.handlers = HandlerRegistry()
        self.driver = driver
        self.mountTree = nil
        // _schedulerBox is default-initialised to nil above (let constant
        // with a default value). At this point all stored properties are
        // set and `self` is fully initialised — safe to form a weak capture.
        let raf = RAFScheduler { [weak self] dirtyIDs in
            self?.flushDirty(dirtyIDs)
        }
        _schedulerBox.value = raf
        let bg = BackgroundRevalidation(client: queryClient, clock: queryClient.clock)
        bg.start()
        backgroundRevalidation = bg
    }

    // MARK: - Render

    /// Re-renders the root component, diffs against the current mount tree,
    /// encodes patches into a JSArray, hands the array to
    /// `window.swiflow.applyPatches`, and — on first call — tells the driver
    /// to attach the root node at `selector`. Also fires lifecycle hooks on
    /// the root component when applicable.
    func renderOnce() {
        installRenderContext(handlers: handlers, taskScope: taskScope, observer: queryClient)
        defer { uninstallRenderContext() }

        // Wrap the live component instance in a VNode.component description
        // whose factory returns THE SAME instance rather than constructing a
        // fresh one. Critical for the diff's reuse arm: on first render
        // `desc.instantiate()` is called once in `mount()`, yielding the
        // already-live instance; on subsequent renders the same-typeID path
        // reuses the mount-tree node and calls `body` on the existing
        // instance — the factory is never called again.
        let root = rootComponent
        let nextVNode: VNode = .component(
            ComponentDescription(typeID: root.typeID, key: nil, factory: { root })
        )

        let renderStartMs = nowMs()
        // Capture the previously-mounted root's DOM handle before the diff
        // mutates `mountTree.componentBody` in place. If a re-render swaps
        // the root component's body to a different element type, the diff
        // can't emit the parent-level removeChild/appendChild because the
        // root's parent in DOM is the selector target (`#app`), which has
        // no entry in the mount tree. We splice a `replaceMount` patch
        // here at the Renderer level to cover that case; the JS driver
        // detaches the previously-mounted node via `mountedRoots[selector]`
        // and attaches the new root.
        let preDiffRootDOMHandle = mountTree?.domHandle
        // Snapshot the set of component instance IDs alive BEFORE this diff,
        // so the lifecycle walker below can partition each anchor in the new
        // tree into reused (→ onChange) vs freshly-mounted (→ onAppear). The
        // diff mutates `mountTree`'s nodes in-place (see Diff.swift's update()
        // returning `mounted` after mutating its componentBody/vnode), so this
        // MUST be captured BEFORE `diff()` runs — otherwise nested components
        // mounted mid-render would appear in the snapshot and incorrectly
        // route to onChange instead of onAppear. Empty on first render.
        let preExistingIDs = collectComponentIDs(mountTree)
        let result = diff(
            mounted: mountTree,
            next: nextVNode,
            handles: handles,
            handlers: handlers,
            scheduler: _schedulerBox.value,
            environment: .init()
        )
        // The root's single DOM handle — GUARDED: `singleRootDOMHandle` traps in
        // all builds if the root body is a bare fragment / multi-root (which
        // `domHandle` would silently resolve to a bogus structural handle the
        // DOM never renders). Computed once per render and reused below.
        let newRootHandle = result.newMountTree.singleRootDOMHandle
        var outgoingPatches = result.patches
        if let preDOMHandle = preDiffRootDOMHandle,
           preDOMHandle != newRootHandle {
            // Root DOM identity changed across renders — emit a swap. Placed
            // at the END of the patch list so all preceding createElement
            // patches for the new root have populated `nodes[newHandle]`.
            outgoingPatches.append(.replaceMount(
                selector: selector,
                newHandle: newRootHandle
            ))
        }
        lastRenderMs = nowMs() - renderStartMs
        guard shipPatches(outgoingPatches) else {
            // One or more patches failed to apply — the DOM and the tree
            // we just computed may have silently diverged. Don't commit a
            // known-divergent tree for the next diff to build on; discard
            // it and do a full resync instead (see resyncFullRemount's doc).
            resyncFullRemount()
            return
        }

        let isFirstMount = (mountTree == nil)
        mountTree = result.newMountTree

        if isFirstMount {
            // Attach the root's single DOM node (guarded above) at `selector`.
            driver.mount(rootHandle: newRootHandle, selector: selector)
        }

        // Lifecycle: walk the post-diff tree children-first. On first mount
        // preExistingIDs is empty so every anchor fires onAppear (matches the
        // prior fireOnAppearTree behavior). On re-render, anchors whose
        // instance survived from the previous tree fire onChange; anchors
        // freshly created during this diff fire onAppear (closes the
        // mid-render-mount lifecycle gap).
        firePostRenderLifecycle(result.newMountTree, preExistingIDs: preExistingIDs)
    }

    /// Entry point for a scheduler flush (issue #89). Chooses the scoped fast
    /// path when `planRerender` deems it safe — exactly one dirty component
    /// whose anchor is locatable, is not the root, and has no
    /// `environmentOverride` ancestor — otherwise falls back to the unchanged
    /// full-root `renderOnce()`.
    func flushDirty(_ dirtyIDs: Set<ObjectIdentifier>) {
        guard let tree = mountTree else { renderOnce(); return }
        switch planRerender(root: tree, dirtyIDs: dirtyIDs) {
        case .full:
            renderOnce()
        case .scoped(let anchor):
            // Establish the same ambient context renderOnce() sets, because
            // scopedRerender re-evaluates `body`: handlers must register into
            // this root's scope, and `.task` / `query()` must reach this root.
            installRenderContext(handlers: handlers, taskScope: taskScope, observer: queryClient)
            defer { uninstallRenderContext() }
            let startMs = nowMs()
            let scoped = scopedRerender(
                anchor: anchor,
                handles: handles,
                handlers: handlers,
                scheduler: scheduler
            )
            // Measure render compute BEFORE shipping, matching renderOnce() so
            // lastRenderMs is comparable across the two paths.
            lastRenderMs = nowMs() - startMs
            guard shipPatches(scoped.patches) else {
                // The scoped diff already mutated the anchor's subtree in
                // place (the reuse arm) — unlike renderOnce()'s
                // not-yet-committed result, there is no "don't commit"
                // option here: the mutation already happened. A failed
                // patch means the DOM may not reflect it. Fall back to the
                // same full resync renderOnce() uses.
                resyncFullRemount()
                return
            }
            // Fire lifecycle AFTER patches reach the driver (matching
            // renderOnce()'s ship-then-fire order) so onAppear/onChange observe
            // the applied DOM — e.g. Ref.wrappedValue resolves for refs mounted
            // in this scoped subtree.
            firePostRenderLifecycle(scoped.newMountTree, preExistingIDs: scoped.preExistingIDs)
            // The diff mutates the anchor in place (reuse arm), so the mount
            // tree stays valid — no `mountTree =` reassignment on this path.
        }
    }

    /// Encodes `patches` to a JSArray, ships them via `window.swiflow.applyPatches`,
    /// and records `lastPatchCount` + `renderCount`. Shared by `renderOnce()`
    /// (full render) and `flushDirty(_:)` (scoped render).
    ///
    /// Returns whether every patch in the batch applied without error (the
    /// driver's own per-patch try/catch is what makes this a meaningful
    /// question rather than an all-or-nothing outcome — see its doc on
    /// `applyPatches`). `false` means the DOM and this renderer's mount
    /// tree may have silently diverged; callers should not commit the
    /// result they just computed as the next diff's baseline — see
    /// `resyncFullRemount()`. Defaults to `true` if the driver's return
    /// value isn't a proper boolean (an unexpected JS-interop shape),
    /// rather than triggering a resync on ambiguous data.
    @discardableResult
    private func shipPatches(_ patches: [Patch]) -> Bool {
        lastPatchCount = patches.count
        renderCount += 1
        return driver.applyPatches(patches)
    }

    /// Discards the current mount tree and does a full, from-scratch mount —
    /// the coarse fallback when `shipPatches` reports a failure. Ships
    /// destroyNode patches for whatever Swift currently believes is mounted
    /// (best-effort cleanup — the driver's per-patch try/catch means even a
    /// still-inconsistent old tree gets cleaned up on whatever handles
    /// still resolve), builds a completely fresh tree via
    /// `diff(mounted: nil, ...)`, and atomically swaps the DOM via
    /// `replaceMount` — which detaches whatever the driver's `mountedRoots`
    /// map currently tracks at this selector, regardless of what Swift's
    /// own records say. That decoupling (see the driver's own comment on
    /// `mountedRoots`) is the resilience property this resync depends on:
    /// it doesn't need to know exactly what went wrong to recover from it.
    ///
    /// Sacrifices `@State` on every nested/embedded component in the tree —
    /// their factory closures re-run as fresh first-mounts, since `diff`
    /// has no prior tree to reconcile against. The root component's OWN
    /// instance survives (the fresh diff's factory closure returns the
    /// same persistent `rootComponent`, exactly like every normal render),
    /// so it fires `onChange()` rather than `onAppear()` — but every
    /// descendant is reset. This is the accepted tradeoff for guaranteeing
    /// DOM/tree consistency over a silent, compounding divergence.
    ///
    /// Never recurses on its own patch failures: if THIS batch also fails
    /// to apply cleanly, the fresh tree is still committed as the new
    /// baseline rather than trying again — bounded to one resync attempt
    /// per triggering failure, so a persistently broken environment
    /// degrades to "imperfect once" rather than looping forever.
    private func resyncFullRemount() {
        let renderStartMs = nowMs()
        var patches: [Patch] = []
        let preExistingIDs = collectComponentIDs(mountTree)
        if let oldTree = mountTree {
            // Preserve the root instance across the teardown: the fresh diff
            // below reuses `rootComponent` (factory { root }), so — like a
            // normal re-render — it must not observe onDisappear(), lose its
            // onChange(of:) baselines, or drop its query subscriptions. See
            // destroy(preserveInstance:); it re-fires onChange() (not onAppear)
            // via firePostRenderLifecycle since the root is in preExistingIDs.
            destroy(oldTree, into: &patches, handlers: handlers,
                    preserveInstance: ObjectIdentifier(rootComponent.instance))
        }

        let root = rootComponent
        let nextVNode: VNode = .component(
            ComponentDescription(typeID: root.typeID, key: nil, factory: { root })
        )
        let result = diff(
            mounted: nil,
            next: nextVNode,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler,
            environment: .init()
        )
        patches.append(contentsOf: result.patches)
        // Same single-root guard as renderOnce — a fragment root would resync to
        // a bogus handle just as silently.
        patches.append(.replaceMount(selector: selector, newHandle: result.newMountTree.singleRootDOMHandle))
        lastRenderMs = nowMs() - renderStartMs

        shipPatches(patches)

        mountTree = result.newMountTree
        firePostRenderLifecycle(result.newMountTree, preExistingIDs: preExistingIDs)
    }

    /// Destroys the mounted tree, emits remove patches to the JS driver,
    /// and cancels the RAF scheduler. Called by `Swiflow.unmount(into:)`.
    /// Safe to call on an already-torn-down renderer (no-op if mountTree is nil).
    func teardown() {
        guard let tree = mountTree else { return }

        var patches: [Patch] = []
        destroy(tree, into: &patches, handlers: handlers)
        driver.applyPatches(patches)

        // Stop background revalidation triggers before releasing the scheduler.
        backgroundRevalidation?.stop()
        backgroundRevalidation = nil
        // Nil out the scheduler to prevent any pending RAF from triggering
        // a render on a torn-down tree. The weak-self capture in the RAF
        // closure means it becomes a no-op once the RAFScheduler is released.
        _schedulerBox.value = nil
        mountTree = nil
    }

    // MARK: - Private

    /// `performance.now()`, or `0` if the global isn't available (e.g. a
    /// non-browser JS host). Used to time render passes for `lastRenderMs`.
    private func nowMs() -> Double {
        JSObject.global.performance.object?.now?().number ?? 0
    }
}

// MARK: - Mutable box for two-phase scheduler init

/// Heap-allocated mutable cell. Used by `Renderer` to store the `RAFScheduler`
/// after `self` is fully initialised, working around Swift's `let` stored
/// property constraint in two-phase initialisation. This is the same pattern
/// as `State<T>`'s `Box<T>` in the core module.
private final class MutableBox<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

#endif
