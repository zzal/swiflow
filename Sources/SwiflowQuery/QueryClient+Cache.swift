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

    /// The entry's current supersede `generation` (bumped by `setQueryData` /
    /// `forceStaleAndRefetch`). `nil` when no entry exists. Used by the
    /// mutation engine to detect whether a key was superseded between an
    /// optimistic write and a rollback.
    package func generation(of key: QueryKey) -> Int? {
        entries[key]?.generation
    }

    /// Write `value` into the entry at `key`, supersede any in-flight fetch, and
    /// notify observers. No-op when no entry exists. Leaves the entry stale so a
    /// later `invalidate` still refetches (the optimistic value is provisional).
    ///
    /// Shares `QueryEntry.supersede` with `forceStaleAndRefetch`: a concurrent
    /// fetch that resolves afterward is dropped by `commitFetch`'s generation
    /// guard, so it can't clobber the optimistic value (spec §11, B3).
    package func setQueryData(_ key: QueryKey, _ value: Any?) {
        guard let entry = entries[key] else { return }
        // clearError: true — the optimistic write IS the new truth; a
        // lingering error would contradict it. See `QueryEntry.supersede`.
        entry.supersede(clearError: true)
        entry.value = value
        notify(key)
    }
}
