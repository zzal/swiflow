// Sources/Swiflow/ScopeID.swift

/// Stable identifier for a handler scope opened by `HandlerRegistry.openScope(debugName:)`.
///
/// A distinct type prevents handler IDs (plain `Int`) and scope IDs from being
/// silently swapped at call sites. Opaque outside the `Swiflow` module —
/// callers store and return `ScopeID` values but never inspect the underlying
/// integer.
package struct ScopeID: Hashable, Sendable {
    /// `internal` so that `HandlerRegistry` (a separate file in the same module)
    /// can create and index into its dictionaries by this value. Not accessible
    /// from `SwiflowWeb` or application code.
    let raw: Int
}
