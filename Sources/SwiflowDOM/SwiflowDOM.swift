// Sources/SwiflowDOM/SwiflowDOM.swift
//
// SwiflowDOM is the WASM renderer layer for Swiflow. The whole file compiles
// on the host too — JavaScriptKit is an unconditional dependency, so
// `canImport(JavaScriptKit)` is always true and the guard below is a marker
// of intent, not a real host/wasm split. Host code must not CALL this API:
// the first `JSObject.global` access traps at runtime (see `render(into:)`).

#if canImport(JavaScriptKit)
import JavaScriptKit
import JavaScriptEventLoop
@_exported import Swiflow
// after()/TimerHandle live in SwiflowTiming; re-exported so app code that
// imports SwiflowDOM keeps them without a second import.
@_exported import SwiflowTiming

// `Swiflow` namespace is declared here (Phase 1 deleted the core placeholder).
// The extension below hangs the renderer API off this enum.
public enum Swiflow {}

/// All live roots, keyed by CSS selector. Package-internal so
/// DevAPI.swift can read it.
@MainActor var renderers: [String: Renderer] = [:]

/// Single shared handle allocator used by all production `Renderer` instances.
/// Guarantees globally unique node handles across all roots so the JS
/// driver's `nodes` Map never has collisions.
@MainActor let sharedHandleAllocator = HandleAllocator()

/// Guards `JavaScriptEventLoop.installGlobalExecutor()` so multi-root apps
/// (multiple `render(into:)` calls) and HMR re-imports install it exactly once.
@MainActor var _swiflowExecutorInstalled = false

public extension Swiflow {
    /// Mounts a Component tree into the DOM node matched by `selector`.
    ///
    /// The factory is invoked exactly once to produce the root Component
    /// instance. Multiple roots can be mounted at different selectors.
    /// Calling `render(into:)` twice with the same selector traps — call
    /// `unmount(into:)` first if you need to replace a root.
    ///
    /// Usage:
    /// ```swift
    /// Swiflow.render(into: "#app") { Counter() }
    /// ```
    @MainActor
    static func render<C: Component>(
        into selector: String,
        _ factory: @escaping @MainActor () -> C
    ) {
        if !_swiflowExecutorInstalled {
            JavaScriptEventLoop.installGlobalExecutor()
            _swiflowExecutorInstalled = true
        }
        precondition(
            renderers[selector] == nil,
            "Swiflow.render(into: \"\(selector)\") was already called. " +
            "Call Swiflow.unmount(into: \"\(selector)\") before mounting a new root at the same selector."
        )

        let root = factory()
        CSSInjector.setup()
        let renderer = Renderer(rootComponent: AnyComponent(root), selector: selector)
        DispatcherBridge.install()
        RegionDecoder.current = SwiflowRegionDecoder()
        // Route Ref resolution through the same driver seam the Renderer uses,
        // so `window.swiflow` is unwrapped (and its absence diagnosed) in one
        // place. Returns nil for an unknown handle; traps with a named cause
        // only if the driver itself is missing (see JSDriver).
        RefResolverInstall.resolver = { handle in
            JSDriver().nodeForHandle(handle)
        }
        renderers[selector] = renderer

#if !SWIFLOW_RELEASE
        // HMR (snapshot export + state restore) is a dev-only feature — there
        // is no hot-swap in a release build. Stripped at compile time.
        let pendingIndex = HMRBridge.pendingRestoreIndex()
        if let index = pendingIndex {
            HMRRestoreInstall.stateFor = { path, typeName, key in
                index[SnapshotKey(path: path, typeName: typeName, key: key)]
            }
        }
        // One aggregating exporter over the global root set. Installed once per
        // module instance (the call is idempotent); the provider closes over
        // `renderers`, not a single root, so every live root — including ones
        // mounted after this call — contributes to a hot-swap snapshot.
        HMRBridge.installSnapshotExporter { renderers.values.compactMap(\.mountTree) }
        // The driver invokes this during a hot swap (after the snapshot) so
        // this module goes permanently quiet before the next one boots —
        // otherwise its revalidation interval / router listeners keep firing
        // and its resync-remount path repaints the stale UI over the new
        // module's DOM. Unmounting every root is exactly the public
        // `unmount(into:)` teardown, applied to a snapshot of the keys
        // (unmount mutates `renderers`).
        HMRBridge.installTeardownHook {
            // Tear down each root directly rather than via unmount(into:):
            // that public path re-installs the DevAPI namespace commands
            // (~5 fresh JSClosures) after EVERY root — pure churn on a
            // module that is being orphaned. The incoming module installs
            // its own commands when it mounts.
            for renderer in renderers.values { renderer.teardown() }
            renderers.removeAll()
        }
#endif

        renderer.renderOnce()

#if !SWIFLOW_RELEASE
        if pendingIndex != nil {
            HMRRestoreInstall.stateFor = nil
        }
#endif

        DevAPI.installAll()
    }

    /// Re-evaluates all mounted roots and applies any resulting patches.
    /// A no-op if no roots have been mounted.
    @MainActor
    static func rerender() {
        renderers.values.forEach { $0.renderOnce() }
    }

    /// Removes the component tree mounted at `selector` from the DOM and
    /// releases all associated state, handlers, and the RAF scheduler.
    ///
    /// A no-op if `selector` was never mounted or has already been unmounted.
    ///
    /// Usage:
    /// ```swift
    /// Swiflow.unmount(into: "#widget")
    /// ```
    @MainActor
    static func unmount(into selector: String) {
        guard let renderer = renderers.removeValue(forKey: selector) else { return }
        renderer.teardown()
        DevAPI.installAll()
    }

}

#endif
