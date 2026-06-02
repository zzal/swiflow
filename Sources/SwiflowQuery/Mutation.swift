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
    func optimistic(_ input: Input) -> [OptimisticEdit]

    /// What to refresh on success — a function of input AND the server output,
    /// so it can target the freshly-created entity. Defaults to none.
    func invalidations(input: Input, output: Output) -> [Invalidation]
}

public extension Mutation {
    func optimistic(_ input: Input) -> [OptimisticEdit] { [] }
    func invalidations(input: Input, output: Output) -> [Invalidation] { [] }
}
