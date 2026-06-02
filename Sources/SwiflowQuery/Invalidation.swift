// Sources/SwiflowQuery/Invalidation.swift

/// A declarative invalidation target a `Mutation` runs on success. Maps onto
/// the shipped `QueryClient.invalidate(_:exact:)` / `invalidate(tag:)`.
public enum Invalidation: Equatable, Sendable {
    case prefix(QueryKey)
    case exact(QueryKey)
    case tag(QueryTag)
}
