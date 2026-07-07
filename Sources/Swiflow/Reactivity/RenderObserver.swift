// Sources/Swiflow/Reactivity/RenderObserver.swift

/// A general, query-agnostic boundary hook the diff fires around each
/// component's `body` evaluation, plus on unmount. `SwiflowQuery` installs an
/// observer to drive per-render subscription reconciliation; core knows nothing
/// about queries. Mirrors `AmbientEnvironment` — installed per render root,
/// save/restored around each render.
@MainActor
package protocol RenderObserver: AnyObject {
    /// Before a component's `body` getter runs.
    func willEvaluate(owner: AnyComponent, scheduler: (any Scheduler)?)
    /// After that getter returns (in a `defer`, mirroring the env restore).
    func didEvaluate()
    /// When a component anchor is destroyed.
    func componentDidUnmount(_ owner: AnyComponent)
}

/// The active render observer. Save/restored by each render root around its
/// render, exactly like `SwiflowTaskRuntime.currentScope`.
package enum RenderObserverBox {
    @MainActor package static var current: (any RenderObserver)?

    /// The most recently RENDERED root's observer — the handler-time fallback.
    ///
    /// `current` is render-scoped (uninstalled after every diff pass), but
    /// imperative APIs like `Component.invalidate` are naturally called from
    /// event handlers, where `current` is nil. `installRenderContext` records
    /// every non-nil observer here and `uninstallRenderContext` leaves it, so
    /// after the first render a handler can still reach its root's observer.
    ///
    /// Single-root apps (every Swiflow app today): always the right observer.
    /// Multiple render roots: the most recently rendered one — a documented
    /// degradation, same class as the other per-process globals. `weak`: the
    /// slot must not keep a torn-down root's observer alive; it self-clears.
    @MainActor package static weak var lastRendered: (any RenderObserver)?
}
