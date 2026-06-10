// Sources/SwiflowQuery/Query.swift

/// A typed, self-fetching query: one value carries identity (`queryKey`),
/// behavior (`fetch`), and any captured dependencies (stored properties that
/// are NOT part of `queryKey`).
///
/// `@MainActor`-isolated to match the single-threaded WASM runtime: `fetch`
/// runs on the main actor, so captured dependencies never cross an actor
/// boundary and need not be `Sendable`. `Value` is `Sendable` for hygiene
/// (it may be returned across an `await` suspension) and `Equatable` for
/// forthcoming change-detection.
@MainActor
public protocol Query {
    associatedtype Value: Equatable & Sendable

    /// Hierarchical identity. Determines the cache slot and prefix-cascade
    /// matching. Must exclude captured dependencies.
    var queryKey: QueryKey { get }

    /// Cross-cutting invalidation families. Defaults to empty.
    var tags: Set<QueryTag> { get }

    /// Freshness window from the last successful fetch. Defaults to `.zero`
    /// (every *trigger* revalidates — but a plain re-render is not a trigger).
    var staleTime: Duration { get }

    /// Polling cadence. `nil` (default) = no polling.
    var refetchInterval: Duration? { get }

    /// Whether this query refetches (if stale) when the window regains focus.
    /// Defaults to `true`.
    var refetchOnFocus: Bool { get }

    /// Retry policy for failed fetches. Defaults to `.default`.
    var retry: RetryPolicy { get }

    /// How long a cache entry outlives its last subscriber before being
    /// garbage-collected. Defaults to 5 minutes: long enough that back-nav
    /// remounts hit warm cache, short enough that parameterized keys
    /// (`["users", id]`) don't grow the cache unboundedly.
    var gcTime: Duration { get }

    /// Fetch the value. Cancellation is cooperative via the surrounding Task.
    func fetch() async throws -> Value
}

public extension Query {
    var tags: Set<QueryTag> { [] }
    var staleTime: Duration { .zero }
    var refetchInterval: Duration? { nil }
    var refetchOnFocus: Bool { true }
    var retry: RetryPolicy { .default }
    var gcTime: Duration { .seconds(300) }
}
