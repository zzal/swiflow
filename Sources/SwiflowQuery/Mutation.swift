// Sources/SwiflowQuery/Mutation.swift

/// A typed, self-describing write. Mirrors `Query`: one value carries behavior
/// (`perform`), captured dependencies (stored properties), and declarations of
/// its effects (`optimistic`, `invalidations`). `@MainActor`-isolated so
/// captured dependencies never cross an actor boundary.
@MainActor
public protocol Mutation {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    /// Run the write. Cancellation is cooperative via the surrounding Task.
    func perform(_ input: Input) async throws -> Output

    /// Cache edits applied before `perform` resolves; the engine snapshots,
    /// applies, and rolls them back on failure. Defaults to none.
    ///
    /// Keep this a PURE declaration of edits: the default `invalidations`
    /// re-reads it on success to learn the touched keys, so side effects in
    /// the declaration itself run more than once per mutation. Effects that
    /// must run once (e.g. allocating an optimistic temp id) belong inside
    /// the edit's transform closure, which only runs when the edit is applied.
    func optimistic(_ input: Input) -> [OptimisticEdit]

    /// What to refresh on success — a function of input AND the server output,
    /// so it can target the freshly-created entity.
    ///
    /// Defaults to refetching exactly the keys `optimistic(_:)` DECLARES
    /// (deduped, in declaration order) — a plain optimistic CRUD mutation
    /// reconciles with the server without restating keys the engine already
    /// knows. Derived from the declarations, not the applied edits: an edit
    /// skipped because nothing was cached still gets its refetch, so the
    /// server value lands either way. Override to refetch more (tags,
    /// prefixes, related queries) or deliberately less (an explicit `[]`
    /// keeps the optimistic guess until something else revalidates).
    func invalidations(input: Input, output: Output) -> [Invalidation]
}

public extension Mutation {
    func optimistic(_ input: Input) -> [OptimisticEdit] { [] }

    /// Derived default: `.exact` per key declared by `optimistic(_:)`,
    /// deduped in declaration order. Dedup matters — duplicate invalidations
    /// of one key would cancel-respawn its repair fetch.
    func invalidations(input: Input, output: Output) -> [Invalidation] {
        var seen = Set<QueryKey>()
        return optimistic(input).compactMap { edit in
            seen.insert(edit.key).inserted ? .exact(edit.key) : nil
        }
    }
}
