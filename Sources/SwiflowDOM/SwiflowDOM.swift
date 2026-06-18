// Sources/SwiflowDOM/SwiflowDOM.swift
//
// SwiflowDOM is the WASM-only renderer layer for Swiflow. All public API
// lives behind a `#if canImport(JavaScriptKit)` so the target compiles
// (empty) on platforms without WASM support — this lets `swift build` and
// `swift test` work on macOS/Linux developer machines while CI's WASM job
// builds the real symbols.

#if canImport(JavaScriptKit)
import JavaScriptKit
import JavaScriptEventLoop
@_exported import Swiflow

// `Swiflow` namespace is declared here (Phase 1 deleted the core placeholder).
// The extension below hangs the renderer API off this enum.
public enum Swiflow {}

/// All live roots, keyed by CSS selector. Package-internal so
/// DevAPI.swift can read it.
nonisolated(unsafe) var renderers: [String: Renderer] = [:]

/// Single shared handle allocator used by all production `Renderer` instances.
/// Guarantees globally unique node handles across all roots so the JS
/// driver's `nodes` Map never has collisions.
nonisolated(unsafe) let sharedHandleAllocator = HandleAllocator()

/// Guards `JavaScriptEventLoop.installGlobalExecutor()` so multi-root apps
/// (multiple `render(into:)` calls) and HMR re-imports install it exactly once.
nonisolated(unsafe) var _swiflowExecutorInstalled = false

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
        RefResolverInstall.resolver = { handle in
            guard let swiflowGlobal = JSObject.global.swiflow.object else { return nil }
            let result = swiflowGlobal.nodeForHandle!(JSValue.number(Double(handle)))
            return result.object
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

#else

// No-op stub for non-WASM platforms. Lets the host package compile.
public enum Swiflow {}

#endif
