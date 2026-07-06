// Sources/SwiflowQuery/Invalidation.swift

/// A declarative invalidation target a `Mutation` runs on success. Maps onto
/// the shipped `QueryClient.invalidate(_:exact:)` / `invalidate(tag:)`.
public enum Invalidation: Equatable, Sendable {
    case prefix(QueryKey)
    case exact(QueryKey)
    case tag(QueryTag)
}

// MARK: - Type-referenced targets

/// Overloads of the case names that take the typed owner of the key instead of
/// restating it. Inside one mutation the same query is referenced type-safely
/// in `optimistic` (`.update(TodoList())`) — these let `invalidations` rhyme
/// (`.exact(TodoList())`) rather than drop to a raw key (`.exact(["todos"])`)
/// that silently breaks when the query's key changes. The raw-key cases remain
/// for keys no `Query` type owns.
///
/// `@MainActor` because `Query.queryKey` is (the whole protocol is) — matching
/// `OptimisticEdit.update`. Resolved eagerly: the returned value is a plain
/// `.exact`/`.prefix` over the query's current key.
public extension Invalidation {
    /// Invalidate exactly `query`'s cache slot: `.exact(query.queryKey)`.
    @MainActor
    static func exact<Q: Query>(_ query: Q) -> Invalidation {
        .exact(query.queryKey)
    }

    /// Invalidate `query`'s slot and every key under it:
    /// `.prefix(query.queryKey)`.
    @MainActor
    static func prefix<Q: Query>(_ query: Q) -> Invalidation {
        .prefix(query.queryKey)
    }
}
