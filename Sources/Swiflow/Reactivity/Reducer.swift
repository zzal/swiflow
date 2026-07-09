// Sources/Swiflow/Reactivity/Reducer.swift
//
// A local, per-component reducer primitive (B4 slice). Models app-level CLIENT
// state with several fields + many actions sharing invariants (wizards, queues,
// multi-step flows) — between per-component @State and the SwiflowQuery cache.
// The reducer is PURE/synchronous/total; effects live at the call site.
// Wired into a component exactly like @MutationState (see @ReducerState).

/// A typed, pure state transition. Conform a value type; an FSM is just a
/// `State` enum whose `reduce` only writes valid transitions.
@MainActor
public protocol Reducer {
    associatedtype State
    associatedtype Action
    /// The state a fresh cell starts at.
    var initialState: State { get }
    /// Pure, synchronous, total: mutate `state` for `action`. No I/O, no async.
    func reduce(into state: inout State, _ action: Action)
}

/// Persistent, per-component reactive state for one `@ReducerState`. A class so
/// it survives across renders with the component instance. Wired once at mount
/// by `@Component`'s `bind`. Mirrors `MutationRuntime`.
@MainActor
public final class ReducerRuntime<R: Reducer> {
    private var _state: R.State?
    private weak var owner: AnyComponent?
    private var scheduler: (any Scheduler)?
    private var didWarnUnwired = false

    public init() {}

    /// Injected at mount by the synthesized `bind`.
    public func wire(owner: AnyComponent, scheduler: any Scheduler) {
        self.owner = owner
        self.scheduler = scheduler
    }

    /// Current state, lazily seeded from `reducer.initialState` on first access
    /// (the runtime is constructed before the reducer instance is assigned).
    public func seededState(_ reducer: R) -> R.State {
        if _state == nil { _state = reducer.initialState }
        return _state!
    }

    /// Apply `action` via `reducer`, then mark the owner dirty so it re-renders.
    public func send(_ reducer: R, _ action: R.Action) {
        if _state == nil { _state = reducer.initialState }
        reducer.reduce(into: &_state!, action)
        if let owner, let scheduler {
            scheduler.markDirty(owner)
        } else if !didWarnUnwired {
            // Unwired: the reduce ran (state changed) but there is no owner to
            // mark dirty, so the view will never re-render. In a real app this
            // means @ReducerState is declared on a class without @Component
            // (which wires the runtime at mount). Warn, don't trap — a bare
            // runtime is also the legitimate way to unit-test reduce logic in
            // isolation, and at this site the two cases are indistinguishable.
            didWarnUnwired = true
            swiflowWarn("@ReducerState dispatched an action but its runtime is unwired: the state changed, but the view won't re-render. Is the enclosing class missing @Component? (@Component wires @ReducerState at mount.)")
        }
    }
}

/// The `$`-projection a component uses to read state and dispatch actions.
/// A lightweight value over the persistent runtime + a snapshot of the current
/// `Reducer` definition. Mirrors `MutationHandle`.
@MainActor
public struct ReducerHandle<R: Reducer> {
    let runtime: ReducerRuntime<R>
    let reducer: R

    public init(runtime: ReducerRuntime<R>, reducer: R) {
        self.runtime = runtime
        self.reducer = reducer
    }

    /// The current reduced state.
    public var state: R.State { runtime.seededState(reducer) }

    /// Dispatch an action: reduces + re-renders the owner.
    public func send(_ action: R.Action) { runtime.send(reducer, action) }
}
