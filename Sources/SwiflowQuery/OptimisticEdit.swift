// Sources/SwiflowQuery/OptimisticEdit.swift

/// One declarative cache edit applied before a mutation's `perform` resolves.
/// Constructed from a typed `Query` so the transform is fully type-checked; the
/// query instance supplies both the cache key and the value type.
///
/// `@MainActor`-isolated (like `QueryEntry`/`QueryClient`): it wraps a
/// non-`Sendable` `apply` closure and is only ever created/consumed on the main
/// actor (`Mutation.optimistic` → `MutationRuntime.run`), so isolation keeps it
/// clean under the v6 language mode without an `@unchecked Sendable` band-aid.
@MainActor
public struct OptimisticEdit {
    let key: QueryKey
    /// Type-erased transform: current value (`Any?`) → new value, or `nil` to
    /// skip the write (no entry / type mismatch). `nil` ⇒ no snapshot recorded.
    let apply: (Any?) -> Any?

    /// Transform the cached value of `query`. No-op when the entry holds no
    /// value of `Q.Value`.
    @MainActor
    public static func update<Q: Query>(
        _ query: Q,
        _ transform: @escaping (Q.Value) -> Q.Value
    ) -> OptimisticEdit {
        let key = query.queryKey
        return OptimisticEdit(key: key) { current in
            guard let value = current as? Q.Value else { return nil }
            return transform(value)
        }
    }
}
