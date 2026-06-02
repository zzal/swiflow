// Sources/SwiflowQuery/OptimisticEdit.swift

/// The result of evaluating one `OptimisticEdit` against the current cached
/// value for its key. Separates a benign skip (nothing to update) from a
/// programmer error (the edit targets a query whose cached value is a different
/// type) so the engine can stay quiet for the former and shout for the latter.
enum OptimisticOutcome {
    /// No value is cached for the key (absent entry, or an entry holding `nil`).
    /// Nothing to transform — skipped silently; nothing on screen reads it.
    case noValue
    /// An entry holds a value of a DIFFERENT type than the edit's query expects.
    /// This can only mean the edit targets the wrong query — a bug. Carries the
    /// expected/actual type names for the diagnostic.
    case typeMismatch(expected: String, actual: String)
    /// The new value to write into the cache.
    case write(Any?)
}

/// One declarative cache edit applied before a mutation's `perform` resolves.
/// Constructed from a typed `Query` so the transform is fully type-checked; the
/// query instance supplies both the cache key and the value type.
///
/// `@MainActor`-isolated (like `QueryEntry`/`QueryClient`): it wraps a
/// non-`Sendable` `apply` closure and is only ever created/consumed on the main
/// actor (`Mutation.optimistic` → `MutationRuntime.beginOptimistic`), so
/// isolation keeps it clean under the v6 language mode without an
/// `@unchecked Sendable` band-aid.
@MainActor
public struct OptimisticEdit {
    let key: QueryKey
    /// Type-erased transform: current cached value (`Any?`) → an
    /// `OptimisticOutcome` telling the engine to write, skip, or flag a bug.
    let apply: (Any?) -> OptimisticOutcome

    /// Transform the cached value of `query`. Skips when no value is cached;
    /// flags a type mismatch when a cached value isn't a `Q.Value` (which can
    /// only mean the edit targets the wrong query).
    @MainActor
    public static func update<Q: Query>(
        _ query: Q,
        _ transform: @escaping (Q.Value) -> Q.Value
    ) -> OptimisticEdit {
        let key = query.queryKey
        return OptimisticEdit(key: key) { current in
            guard let current else { return .noValue }
            guard let value = current as? Q.Value else {
                return .typeMismatch(
                    expected: String(reflecting: Q.Value.self),
                    actual: String(reflecting: type(of: current)))
            }
            return .write(transform(value))
        }
    }
}
