// Tests/SwiflowQueryTests/InvalidationTests.swift
import Testing
@testable import SwiflowQuery

/// A fixed-key query standing in for `@Query(prefix: "todos")`.
@MainActor private struct TodosQuery: Query {
    var queryKey: QueryKey { ["todos"] }
    func fetch() async throws -> [String] { [] }
}

/// A parameterized query standing in for `@Query(prefix: "users") + @Key id`.
@MainActor private struct UserQuery: Query {
    let id: Int
    var queryKey: QueryKey { ["users", .int(id)] }
    func fetch() async throws -> String { "" }
}

/// Pins the type-referenced overloads of the `Invalidation` case names: they
/// must produce values IDENTICAL to the raw-key spellings, so the fully-tested
/// dispatch machinery behind those cases is provably shared — the overloads
/// only move key ownership from a restated literal to the query type.
@Suite("Invalidation/type-referenced")
@MainActor
struct InvalidationTests {
    @Test("exact(query) is the same value as exact(query's raw key)")
    func exactResolvesToTheQueryKey() {
        #expect(Invalidation.exact(TodosQuery()) == .exact(["todos"]))
        #expect(Invalidation.exact(UserQuery(id: 7)) == .exact(["users", .int(7)]))
        // NOT the prefix case, and not some other key.
        #expect(Invalidation.exact(TodosQuery()) != .prefix(["todos"]))
        #expect(Invalidation.exact(UserQuery(id: 7)) != .exact(["users", .int(8)]))
    }

    @Test("prefix(query) is the same value as prefix(query's raw key)")
    func prefixResolvesToTheQueryKey() {
        #expect(Invalidation.prefix(TodosQuery()) == .prefix(["todos"]))
        #expect(Invalidation.prefix(UserQuery(id: 7)) == .prefix(["users", .int(7)]))
        #expect(Invalidation.prefix(TodosQuery()) != .exact(["todos"]))
    }

    @Test("the raw-key spellings still resolve to the cases (no overload capture)")
    func rawKeySpellingsStillResolveToTheCases() {
        // Array literals must keep resolving to the QueryKey cases, not get
        // captured by the generic overloads (a literal can't be a Query —
        // pinned here so a future overload change can't regress call sites).
        let exact: Invalidation = .exact(["todos"])
        let prefix: Invalidation = .prefix(["users", .int(1)])
        if case .exact(let k) = exact { #expect(k == ["todos"]) } else { Issue.record("not .exact") }
        if case .prefix(let k) = prefix { #expect(k == ["users", .int(1)]) } else { Issue.record("not .prefix") }
    }
}
