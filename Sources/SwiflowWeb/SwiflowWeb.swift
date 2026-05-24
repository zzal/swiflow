// Sources/SwiflowWeb/SwiflowWeb.swift
//
// SwiflowWeb is the WASM-only renderer layer for Swiflow. All public API
// lives behind a `#if canImport(JavaScriptKit)` so the target compiles
// (empty) on platforms without WASM support — this lets `swift build` and
// `swift test` work on macOS/Linux developer machines while CI's WASM job
// builds the real symbols.

#if canImport(JavaScriptKit)
import JavaScriptKit
@_exported import Swiflow

// `Swiflow` namespace is declared here (Phase 1 deleted the core placeholder).
// The extension below hangs the renderer API off this enum.
public enum Swiflow {}

/// All live roots, keyed by CSS selector. Package-internal so
/// AttributeModifiers.swift and DevAPI.swift can read it.
nonisolated(unsafe) var renderers: [String: Renderer] = [:]

/// Set to the active `Renderer` at the start of each `renderOnce()` call
/// and restored to `nil` in a defer. Lets `.on(_:perform:)` modifiers
/// find the correct registry during both initial renders and RAF re-renders.
nonisolated(unsafe) var _currentRenderingRenderer: Renderer?

/// Single shared handle allocator used by all production `Renderer` instances.
/// Guarantees globally unique node handles across all roots so the JS
/// driver's `nodes` Map never has collisions.
nonisolated(unsafe) let sharedHandleAllocator = HandleAllocator()

public extension Swiflow {
    /// Mounts a Component tree into the DOM node matched by `selector`.
    ///
    /// The factory is invoked exactly once to produce the root Component
    /// instance. A `RAFScheduler` is created and wired into the diff so
    /// `@State` mutations on any component in the tree automatically
    /// schedule re-renders via `requestAnimationFrame`.
    ///
    /// **Single-root:** the v1 implementation supports a single root per
    /// app. Calling `render` twice traps with a clear error — multi-root
    /// support is a future-phase item.
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
        // Phase 8: if the dev server staged a pending HMR snapshot in
        // window.__swiflowPendingSnapshot, decode it now. We install
        // the diff's restore hook BEFORE constructing the root
        // component so the very first wireState call gets the chance
        // to restore.
        let pendingIndex = HMRBridge.takePendingSnapshot()
        if let index = pendingIndex {
            HMRRestoreInstall.stateFor = { path, typeName, key in
                let lookupKey = SnapshotKey(path: path, typeName: typeName, key: key)
                return index[lookupKey]
            }
        }

        let root = factory()
        CSSInjector.setup()
        let renderer = Renderer(rootComponent: AnyComponent(root), selector: selector)
        DispatcherBridge.install()
        // Install the Ref resolver so `ref.wrappedValue` can map a Swiflow
        // handle to the live JS DOM node via `window.swiflow.nodeForHandle`.
        // Closure-installs into the non-generic `RefResolverInstall.resolver`
        // shim (not a static on `Ref<Element>` — generic-statics are
        // per-specialization and would force a separate install per `E`).
        RefResolverInstall.resolver = { handle in
            guard let swiflowGlobal = JSObject.global.swiflow.object else {
                return nil
            }
            // Mirror the Renderer's call pattern (`swiflowGlobal.mount!(…)`):
            // member-access on `JSObject` produces a bound function, the
            // `!` unwraps it, and calling it with `JSValue`s returns a
            // `JSValue`. `nodeForHandle` returns the DOM node (a JSObject)
            // or `null` for an unknown handle — `.object` is nil in the
            // null case, which propagates out as `nil` here.
            let result = swiflowGlobal.nodeForHandle!(JSValue.number(Double(handle)))
            return result.object
        }

        // Phase 8: install the snapshot exporter so the JS driver can
        // call window.__swiflow.hmrSnapshot() before the next swap.
        // The exporter walks `renderer.mountTree` at call time, so it
        // always reports the current tree even after many re-renders.
        HMRBridge.installSnapshotExporter { [weak renderer] in
            renderer?.mountTree
        }

        renderer.renderOnce()

        // Phase 8: clear the install slot after the first render
        // completes. Subsequent reactivity-driven renders should
        // not re-restore.
        if pendingIndex != nil {
            HMRRestoreInstall.stateFor = nil
        }

        // Phase 9: install devtools API (no-op in production).
        DevAPI.install(renderer: renderer)
    }

    /// Re-evaluates the registered view producer and applies any resulting
    /// patches. A no-op if `render(into:_:)` has not been called.
    @MainActor
    static func rerender() {
        // ambientRenderer removed in Task 3 — will be properly replaced in Task 5.
    }

}

#else

// No-op stub for non-WASM platforms. Lets the host package compile.
public enum Swiflow {}

#endif
