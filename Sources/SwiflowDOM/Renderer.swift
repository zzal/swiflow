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
    init(rootComponent: AnyComponent, selector: String, handles: HandleAllocator = sharedHandleAllocator) {
        self.rootComponent = rootComponent
        self.selector = selector
        self.handles = handles
        self.handlers = HandlerRegistry()
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
        HandlerAmbient.current = handlers
        SwiflowTaskRuntime.currentScope = taskScope
        RenderObserverBox.current = queryClient
        defer {
            HandlerAmbient.current = nil
            SwiflowTaskRuntime.currentScope = nil
            RenderObserverBox.current = nil
        }

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

        let renderStartMs = JSObject.global.performance.object?.now?().number ?? 0
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
        var outgoingPatches = result.patches
        if let preDOMHandle = preDiffRootDOMHandle,
           preDOMHandle != result.newMountTree.domHandle {
            // Root DOM identity changed across renders — emit a swap. Placed
            // at the END of the patch list so all preceding createElement
            // patches for the new root have populated `nodes[newHandle]`.
            outgoingPatches.append(.replaceMount(
                selector: selector,
                newHandle: result.newMountTree.domHandle
            ))
        }
        lastRenderMs = (JSObject.global.performance.object?.now?().number ?? 0) - renderStartMs
        shipPatches(outgoingPatches)

        let isFirstMount = (mountTree == nil)
        mountTree = result.newMountTree

        if isFirstMount {
            // The mount tree root is the component anchor whose `handle` is
            // structural-only; `domHandle` is the body's real DOM handle,
            // which is what the driver attaches at `selector`.
            let mountHandle = result.newMountTree.domHandle
            let swiflowGlobal = JSObject.global.swiflow.object!
            _ = swiflowGlobal.mount!(
                JSValue.number(Double(mountHandle)),
                JSValue.string(selector)
            )
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
            HandlerAmbient.current = handlers
            SwiflowTaskRuntime.currentScope = taskScope
            RenderObserverBox.current = queryClient
            defer {
                HandlerAmbient.current = nil
                SwiflowTaskRuntime.currentScope = nil
                RenderObserverBox.current = nil
            }
            let startMs = JSObject.global.performance.object?.now?().number ?? 0
            let scoped = scopedRerender(
                anchor: anchor,
                handles: handles,
                handlers: handlers,
                scheduler: scheduler
            )
            // Measure render compute BEFORE shipping, matching renderOnce() so
            // lastRenderMs is comparable across the two paths.
            lastRenderMs = (JSObject.global.performance.object?.now?().number ?? 0) - startMs
            shipPatches(scoped.patches)
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
    private func shipPatches(_ patches: [Patch]) {
        lastPatchCount = patches.count
        renderCount += 1
        let jsArray = JSObject.global.Array.function!.new()
        for (index, patch) in patches.enumerated() {
            let payload = PatchSerializer.encode(patch)
            jsArray[index] = JSAdapter.toJSValue(payload)
        }
        let swiflowGlobal = JSObject.global.swiflow.object!
        _ = swiflowGlobal.applyPatches!(jsArray)
    }

    /// Destroys the mounted tree, emits remove patches to the JS driver,
    /// and cancels the RAF scheduler. Called by `Swiflow.unmount(into:)`.
    /// Safe to call on an already-torn-down renderer (no-op if mountTree is nil).
    func teardown() {
        guard let tree = mountTree else { return }

        var patches: [Patch] = []
        destroy(tree, into: &patches, handlers: handlers)

        let jsArray = JSObject.global.Array.function!.new()
        for (index, patch) in patches.enumerated() {
            let payload = PatchSerializer.encode(patch)
            jsArray[index] = JSAdapter.toJSValue(payload)
        }
        let swiflowGlobal = JSObject.global.swiflow.object!
        _ = swiflowGlobal.applyPatches!(jsArray)

        // Stop background revalidation triggers before releasing the scheduler.
        backgroundRevalidation?.stop()
        backgroundRevalidation = nil
        // Nil out the scheduler to prevent any pending RAF from triggering
        // a render on a torn-down tree. The weak-self capture in the RAF
        // closure means it becomes a no-op once the RAFScheduler is released.
        _schedulerBox.value = nil
        mountTree = nil
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
