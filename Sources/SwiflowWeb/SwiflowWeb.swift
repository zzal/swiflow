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

// Module-internal ambient renderer — single root per app in Phase 2a.
// `internal` (not `private`) so AttributeModifiers.swift can reach it
// when registering handlers during a render cycle.
nonisolated(unsafe) var ambientRenderer: Renderer?

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
        precondition(
            ambientRenderer == nil,
            "Swiflow.render(into:_:) was already called. v1 supports a single root per app; " +
            "a second render would silently drop event dispatch for new handlers because the JS " +
            "dispatcher remains bound to the first registry."
        )

        // Phase 8: if the dev server staged a pending HMR snapshot in
        // window.__swiflowPendingSnapshot, decode it now. We install
        // the diff's restore hook BEFORE constructing the root
        // component so the very first wireState call gets the chance
        // to restore.
        let pendingIndex = HMRBridge.takePendingSnapshot()
        if let index = pendingIndex {
            HMRRestoreInstall.restore = { component, path, key in
                HMRWalker.applyRestore(index: index, to: component, at: path, key: key)
            }
        }

        let root = factory()
        let renderer = Renderer(rootComponent: AnyComponent(root), selector: selector)
        ambientRenderer = renderer
        DispatcherBridge.installIfNeeded(registry: renderer.handlers)
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
            HMRRestoreInstall.restore = nil
        }
    }

    /// Re-evaluates the registered view producer and applies any resulting
    /// patches. A no-op if `render(into:_:)` has not been called.
    @MainActor
    static func rerender() {
        ambientRenderer?.renderOnce()
    }

}

#else

// No-op stub for non-WASM platforms. Lets the host package compile.
public enum Swiflow {}

#endif
