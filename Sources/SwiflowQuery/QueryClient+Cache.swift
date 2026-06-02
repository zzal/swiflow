// Sources/SwiflowQuery/QueryClient+Cache.swift
import Swiflow

// Package-internal cache read/write used by the mutation engine (§11). NOT a
// public imperative-cache-surgery surface in v1.
extension QueryClient {
    /// Typed read of the current cached value at `key`.
    package func getQueryData<V>(_ key: QueryKey, as _: V.Type) -> V? {
        entries[key]?.value as? V
    }

    /// Type-erased read used by the optimistic engine for snapshots.
    package func getQueryDataErased(_ key: QueryKey) -> Any? {
        entries[key]?.value
    }

    /// Write `value` into the entry at `key`, supersede any in-flight fetch, and
    /// notify observers. No-op when no entry exists. Leaves the entry stale so a
    /// later `invalidate` still refetches (the optimistic value is provisional).
    ///
    /// The generation bump + cancel mirror `forceStaleAndRefetch`: a concurrent
    /// fetch that resolves afterward is dropped by `commitFetch`'s generation
    /// guard, so it can't clobber the optimistic value (spec §11, B3).
    package func setQueryData(_ key: QueryKey, _ value: Any?) {
        guard let entry = entries[key] else { return }
        entry.generation += 1
        entry.inFlight?.cancel()
        entry.inFlight = nil
        entry.value = value
        entry.error = nil
        entry.lastFetched = nil
        notify(key)
    }

    package func nextMutationTaskToken() -> Int {
        defer { nextMutationToken += 1 }
        return nextMutationToken
    }

    package func storeMutationTask(_ token: Int, _ task: Task<Void, Never>) {
        mutationTasks[token] = task
    }

    package func removeMutationTask(_ token: Int) {
        mutationTasks[token] = nil
    }
}
