// Sources/SwiflowDOM/RAFScheduler.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// A `Scheduler` implementation that batches dirty-component notifications
/// per `requestAnimationFrame` tick.
///
/// Unlike `SyncScheduler` (which fires a callback once per dirty
/// component on `flush()`), `RAFScheduler` fires a SINGLE `onFlushBatch`
/// callback per rAF tick regardless of how many components were marked dirty.
/// This is intentional for Phase 3 v1: the Renderer always rerenders the
/// entire tree from the root component, so per-component dispatch would
/// trigger N redundant full-tree rerenders per frame for N dirty components.
/// A single callback per flush is correct and optimal for this architecture.
///
/// **Retain-cycle safety:** `RAFScheduler` is owned by `Renderer`. The
/// `onFlushBatch` closure typically captures `Renderer` weakly. The rAF
/// closure (`rafClosure`) is kept alive on `self` until the frame fires;
/// after `rafFired()` clears it, the JSClosure is eligible for deallocation.
///
/// **Single-root assumption:** Phase 3 v1 assumes one ambient `Renderer` per
/// app. If multi-root support lands in a future phase, each Renderer would
/// own its own `RAFScheduler` (already the case — `RAFScheduler` is not a
/// global singleton).
public final class RAFScheduler: Scheduler {
    /// Tracks component-instance identity of components that have been
    /// marked dirty since the last flush. Deduplicates multiple `markDirty`
    /// calls for the same component within one frame.
    private var dirty: Set<ObjectIdentifier> = []

    /// `true` between `scheduleRAFIfNeeded()` and `rafFired()`. Guards
    /// against scheduling more than one rAF callback per frame.
    private var rafScheduled = false

    /// Keeps the rAF closure alive from the time it is scheduled until
    /// after the frame fires. `JSClosure` is reference-counted by
    /// `JavaScriptKit`; clearing this field allows deallocation once the
    /// JS engine no longer holds a reference either.
    private var rafClosure: JSClosure?

    /// Invoked once per rAF tick when at least one component is dirty.
    /// The callback should perform a full-tree rerender from the root.
    /// Intentionally one-call-per-flush rather than one-call-per-component
    /// — see type-level documentation for rationale.
    private let onFlushBatch: () -> Void

    /// Creates a scheduler that fires `onFlushBatch` at most once per
    /// `requestAnimationFrame` when any component has been marked dirty.
    ///
    /// - Parameter onFlushBatch: called once per frame if the dirty set is
    ///   non-empty after the rAF fires. Typically a closure that calls
    ///   `Renderer.renderOnce()` with a weak self capture.
    public init(onFlushBatch: @escaping () -> Void) {
        self.onFlushBatch = onFlushBatch
    }

    /// Records `component` as needing re-render and schedules a rAF
    /// callback if one is not already pending.
    public func markDirty(_ component: AnyComponent) {
        dirty.insert(ObjectIdentifier(component.instance))
        scheduleRAFIfNeeded()
    }

    /// Immediately executes the flush: if the dirty set is non-empty,
    /// clears it and invokes `onFlushBatch` once. A no-op when the
    /// dirty set is empty.
    ///
    /// This method is called by the rAF callback but can also be called
    /// directly in tests or synchronous contexts.
    public func flush() {
        guard !dirty.isEmpty else { return }
        dirty.removeAll(keepingCapacity: true)
        onFlushBatch()
    }

    // MARK: - Private

    private func scheduleRAFIfNeeded() {
        guard !rafScheduled else { return }
        rafScheduled = true

        // Create and retain the closure before passing it to JS. The
        // JSClosure must outlive the rAF callback invocation.
        let closure = JSClosure { [weak self] _ -> JSValue in
            self?.rafFired()
            return .undefined
        }
        rafClosure = closure
        _ = JSObject.global.requestAnimationFrame!(JSValue.object(closure))
    }

    private func rafFired() {
        // Clear scheduling state BEFORE flush so that if onFlushBatch's
        // synchronous work triggers new markDirty calls (e.g. a setState
        // in an effect), they schedule a fresh rAF rather than being
        // silently swallowed by an already-set guard.
        rafScheduled = false
        rafClosure = nil
        flush()
    }
}

#endif
