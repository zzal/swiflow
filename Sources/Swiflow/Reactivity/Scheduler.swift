// Sources/Swiflow/Reactivity/Scheduler.swift

/// Coordinates Component re-renders. `@State` mutations call `markDirty`
/// on the active Scheduler; the Scheduler batches and eventually invokes
/// the per-component rerender callback.
///
/// Two conformances ship with Swiflow:
/// - `SyncScheduler` (this file): synchronous flush, used by tests
///   and any headless render path.
/// - `RAFScheduler` (`SwiflowWeb/RAFScheduler.swift`, Task 8): batches per
///   `requestAnimationFrame` for the browser Renderer.
///
/// Conforming types are expected to be class-only (the protocol is
/// `AnyObject`-bound) so the Renderer can hold a reference without
/// copy-on-mutation surprises.
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
/// any headless context. The `rerenderCallback` is invoked once per dirty
/// component at flush time, in the order components were first marked.
///
/// **Reentrancy:** marks made WHILE a callback runs are deferred to the
/// next flush. The "current batch" snapshot is taken at the start of
/// `flush()` and is consumed monolithically; any `markDirty` during
/// callback execution populates a fresh dirty set for the next batch.
/// A reentrant `flush()` is a no-op (guard at the start) so callbacks
/// can safely chain into other code that might itself flush.
public final class SyncScheduler: Scheduler {
    private var dirty: [ObjectIdentifier: AnyComponent] = [:]
    private var insertionOrder: [ObjectIdentifier] = []
    private let rerenderCallback: (AnyComponent) -> Void
    private var isFlushing = false

    public init(rerenderCallback: @escaping (AnyComponent) -> Void) {
        self.rerenderCallback = rerenderCallback
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

        isFlushing = true
        defer { isFlushing = false }
        for component in batch {
            rerenderCallback(component)
        }
    }
}
