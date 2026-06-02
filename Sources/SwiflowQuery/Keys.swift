// Sources/SwiflowQuery/Keys.swift

/// One level of a hierarchical query key. A closed, `Sendable`, `Hashable`
/// enum — the type-safe alternative to `AnyHashable` (no Int/Int64/String
/// confusion, debuggable, prefix-cascadable). Bools/enums/structs encode their
/// identity into a `.string` or `.int` component.
public enum QueryKeyComponent: Hashable, Sendable {
    case string(String)
    case int(Int)
}

extension QueryKeyComponent: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension QueryKeyComponent: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

/// A hierarchical path identifying a query. `["users"]` is the 1-element case.
public typealias QueryKey = [QueryKeyComponent]

/// A cross-cutting invalidation family label.
public typealias QueryTag = String

extension Array where Element == QueryKeyComponent {
    /// True iff `self` starts with `prefix` (the positional-cascade rule).
    func hasPrefix(_ prefix: QueryKey) -> Bool {
        guard prefix.count <= count else { return false }
        return Array(self.prefix(prefix.count)) == prefix
    }
}
