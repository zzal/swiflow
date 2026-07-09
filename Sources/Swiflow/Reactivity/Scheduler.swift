// Sources/Swiflow/Reactivity/Scheduler.swift

/// Coordinates Component re-renders. `@State` mutations call `markDirty`
/// on the active Scheduler; the Scheduler batches and eventually invokes
/// the per-component rerender callback.
///
/// Two conformances ship with Swiflow:
/// - `SyncScheduler` (this file): synchronous flush, used by tests
///   and any headless render path.
/// - `RAFScheduler` (`SwiflowDOM/RAFScheduler.swift`, Task 8): batches per
///   `requestAnimationFrame` for the browser Renderer.
///
/// Conforming types are expected to be class-only (the protocol is
/// `AnyObject`-bound) so the Renderer can hold a reference without
/// copy-on-mutation surprises.
@MainActor
public protocol Scheduler: AnyObject {
    /// Marks `component` as needing re-render. Idempotent within a batch:
    /// the same component marked N times before the next flush produces
    /// exactly one rerender callback invocation.
    func markDirty(_ component: AnyComponent)

    /// Synchronously rerender every dirty component, then clear the dirty
    /// set. Marks accumulated during callback execution are deferred and
    /// are NOT automatically flushed by this call — they form the next
    /// batch. Callers (or the implementation's own scheduling trigger) are
    /// responsible for invoking `flush()` again when the deferred batch
    /// should be processed. Implementations may auto-trigger this (e.g.
    /// `RAFScheduler` re-arms `requestAnimationFrame` after each flush);
    /// `SyncScheduler` does not.
    func flush()
}

/// Synchronous, no-rAF implementation of `Scheduler`. Used by tests and
/// any headless context. Two callback modes over ONE flush core:
///
/// - `batching(onFlushBatch:)` — `RAFScheduler`'s contract: a SINGLE
///   callback per flush carrying that batch's dirty-instance set, exactly
///   what the browser delivers per rAF tick. Render roots use this so a
///   multi-dirty interaction produces one render, not one per component
///   (audit VI Wave-2 #4 — the harness used to double-diff and double-fire
///   `onChange` where the browser fired once).
/// - `init(rerenderCallback:)` — one callback per dirty component, in the
///   order components were first marked; a thin adapter over the batch
///   core, kept for observers that want per-component signals (the
///   QueryClient suites). A factory (not an init overload) provides the
///   batch mode because two single-closure inits would make the common
///   `SyncScheduler { _ in }` spelling ambiguous.
///
/// **Reentrancy:** marks made WHILE a callback runs are deferred to the
/// next flush. The "current batch" snapshot is taken at the start of
/// `flush()` and is consumed monolithically; any `markDirty` during
/// callback execution populates a fresh dirty set for the next batch.
/// A reentrant `flush()` is a no-op (guard at the start) so callbacks
/// can safely chain into other code that might itself flush.
@MainActor
public final class SyncScheduler: Scheduler {
    private var dirty: [ObjectIdentifier: AnyComponent] = [:]
    private var insertionOrder: [ObjectIdentifier] = []
    private let flushBatch: ([AnyComponent]) -> Void
    private var isFlushing = false

    private init(flushBatch: @escaping ([AnyComponent]) -> Void) {
        self.flushBatch = flushBatch
    }

    public convenience init(rerenderCallback: @escaping (AnyComponent) -> Void) {
        self.init(flushBatch: { batch in
            for component in batch { rerenderCallback(component) }
        })
    }

    /// The batch mode: `onFlushBatch` is invoked at most ONCE per `flush()`,
    /// with the dirty component-instance identities of that batch — the same
    /// shape `RAFScheduler` hands `Renderer.flushDirty(_:)` each frame, so
    /// the two schedulers cannot drift. Never invoked for an empty batch.
    public static func batching(
        onFlushBatch: @escaping (Set<ObjectIdentifier>) -> Void
    ) -> SyncScheduler {
        SyncScheduler(flushBatch: { batch in
            onFlushBatch(Set(batch.map { ObjectIdentifier($0.instance) }))
        })
    }

    public func markDirty(_ component: AnyComponent) {
        // Key by component-instance identity (not the outer AnyComponent
        // wrapper, and not the typeID used by the diff). Each live
        // component object is uniquely 1:1 with one AnyComponent wrapper
        // in the mount tree, but multiple call sites could theoretically
        // produce different wrappers around the same instance — dedup
        // by inner identity prevents double-scheduling in that case.
        // This is distinct from `ObjectIdentifier(C.self)` (the type-level
        // identity used by ComponentDescription for diff reuse).
        let id = ObjectIdentifier(component.instance)
        if dirty[id] == nil {
            insertionOrder.append(id)
        }
        dirty[id] = component
    }

    public func flush() {
        guard !isFlushing else { return }
        let batchIDs = insertionOrder
        let batch = batchIDs.compactMap { dirty[$0] }
        dirty.removeAll(keepingCapacity: true)
        insertionOrder.removeAll(keepingCapacity: true)
        // Mirrors RAFScheduler's empty-set guard: neither callback mode is
        // ever invoked for a flush with nothing dirty.
        guard !batch.isEmpty else { return }

        isFlushing = true
        defer { isFlushing = false }
        flushBatch(batch)
    }
}
