// Sources/SwiflowDOM/RAFScheduler.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// A `Scheduler` implementation that batches dirty-component notifications
/// per `requestAnimationFrame` tick.
///
/// Unlike `SyncScheduler` (which fires a callback once per dirty
/// component on `flush()`), `RAFScheduler` fires a SINGLE `onFlushBatch`
/// callback per rAF tick, passing the whole dirty-instance set for that tick.
/// The Renderer's callback (`flushDirty(_:)`) inspects that set and chooses
/// per-frame between a scoped subtree re-render (the common single-dirty case)
/// and a full-root render (multi-dirty / ambiguous frames). Batching to one
/// callback per flush — rather than one per component — lets that decision see
/// the entire frame's dirty set at once.
///
/// **Closure lifetime:** `RAFScheduler` is owned by `Renderer`. The
/// `onFlushBatch` closure typically captures `Renderer` weakly. `rafClosure`
/// is retained on `self` for ownership clarity, not because that's what
/// keeps the callback callable — `JSClosure.init` self-registers into a
/// static `sharedClosures` table, so JS can invoke it regardless of this
/// field. `rafFired()` nils `rafClosure` once the frame it was scheduled
/// for has fired, since `requestAnimationFrame` only calls a given callback
/// once; the field never needs an explicit `cancelAnimationFrame`.
///
/// **Single-root assumption:** Phase 3 v1 assumes one ambient `Renderer` per
/// app. If multi-root support lands in a future phase, each Renderer would
/// own its own `RAFScheduler` (already the case — `RAFScheduler` is not a
/// global singleton).
@MainActor
final class RAFScheduler: Scheduler {
    /// Tracks component-instance identity of components that have been
    /// marked dirty since the last flush. Deduplicates multiple `markDirty`
    /// calls for the same component within one frame.
    private var dirty: Set<ObjectIdentifier> = []

    /// `true` between `scheduleRAFIfNeeded()` and `rafFired()`. Guards
    /// against scheduling more than one rAF callback per frame.
    private var rafScheduled = false

    /// Held from scheduling until the frame fires, for ownership clarity
    /// (so it's obvious exactly one rAF closure is outstanding at a time).
    /// `JSClosure` self-registers into JavaScriptKit's static
    /// `sharedClosures` table on init, so it stays callable from JS whether
    /// or not this field holds it; nil-ing it here does not stop or cancel
    /// anything — `requestAnimationFrame` already only fires once.
    private var rafClosure: JSClosure?

    /// Invoked once per rAF tick when at least one component is dirty, with
    /// the snapshot of dirty component-instance identities for that tick. The
    /// callback decides per-frame whether to scope the re-render to a single
    /// subtree or fall back to a full-root render. Intentionally one-call-per-
    /// flush rather than one-call-per-component — see type-level documentation.
    private let onFlushBatch: @MainActor (Set<ObjectIdentifier>) -> Void

    /// Creates a scheduler that fires `onFlushBatch` at most once per
    /// `requestAnimationFrame` when any component has been marked dirty.
    ///
    /// - Parameter onFlushBatch: called once per frame if the dirty set is
    ///   non-empty after the rAF fires, receiving that frame's dirty-instance
    ///   set. Typically a closure that calls `Renderer.flushDirty(_:)` with a
    ///   weak self capture.
    init(onFlushBatch: @escaping @MainActor (Set<ObjectIdentifier>) -> Void) {
        self.onFlushBatch = onFlushBatch
    }

    /// Records `component` as needing re-render and schedules a rAF
    /// callback if one is not already pending.
    func markDirty(_ component: AnyComponent) {
        dirty.insert(ObjectIdentifier(component.instance))
        scheduleRAFIfNeeded()
    }

    /// Immediately executes the flush: if the dirty set is non-empty,
    /// clears it and invokes `onFlushBatch` once. A no-op when the
    /// dirty set is empty.
    ///
    /// This method is called by the rAF callback but can also be called
    /// directly in tests or synchronous contexts.
    func flush() {
        guard !dirty.isEmpty else { return }
        let batch = dirty
        dirty.removeAll(keepingCapacity: true)
        onFlushBatch(batch)
    }

    // MARK: - Private

    private func scheduleRAFIfNeeded() {
        guard !rafScheduled else { return }
        rafScheduled = true

        // Create and retain the closure before passing it to JS. The
        // JSClosure must outlive the rAF callback invocation.
        let closure = JSClosure { [weak self] _ -> JSValue in
            // requestAnimationFrame fires on the main thread; hop onto MainActor
            // explicitly (matching DispatcherBridge.swift / Timing.swift) so the
            // @MainActor scheduler methods are invoked with enforced isolation.
            MainActor.assumeIsolated { self?.rafFired() }
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
