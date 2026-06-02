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
}
