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
/// is created ONCE (lazily, on first schedule) and reused for every frame
/// thereafter — see the field's documentation for why a per-frame closure
/// would leak an entry in JavaScriptKit's static `sharedClosures` table on
/// every render. One scheduler ⇒ exactly one registered closure, for life.
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

    /// The ONE rAF callback this scheduler ever creates, built lazily on
    /// first schedule and reused for every subsequent frame.
    ///
    /// This must not be a per-frame allocation: `JSClosure.init`
    /// self-registers into JavaScriptKit's static `sharedClosures` table
    /// and stays there until `release()` — dropping the Swift reference
    /// does NOT unregister it. The previous implementation created a fresh
    /// closure per scheduled frame and nil-ed it after firing, leaking one
    /// pinned closure (plus its JS function object) per render — at
    /// animation-rate renders that ballooned the web process by hundreds
    /// of MB within minutes until Safari killed the page (found via
    /// GridBoard playback). Passing the same function to
    /// `requestAnimationFrame` every frame is standard JS; rAF registers
    /// per call, not per function identity.
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
        #if DEBUG
        RefreshReentrancyGuard.noteDirty(component)
        #endif
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

        if rafClosure == nil {
            rafClosure = JSClosure { [weak self] _ -> JSValue in
                // requestAnimationFrame fires on the main thread; hop onto MainActor
                // explicitly (matching DispatcherBridge.swift / Timing.swift) so the
                // @MainActor scheduler methods are invoked with enforced isolation.
                MainActor.assumeIsolated { self?.rafFired() }
                return .undefined
            }
        }
        _ = JSObject.global.requestAnimationFrame!(JSValue.object(rafClosure!))
    }

    private func rafFired() {
        // Clear scheduling state BEFORE flush so that if onFlushBatch's
        // synchronous work triggers new markDirty calls (e.g. a setState
        // in an effect), they schedule a fresh rAF rather than being
        // silently swallowed by an already-set guard. The closure is NOT
        // dropped — it is this scheduler's permanent, reused callback.
        rafScheduled = false
        flush()
    }
}

#endif
