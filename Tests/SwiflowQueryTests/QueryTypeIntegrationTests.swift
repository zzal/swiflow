import Testing
import SwiflowQuery

// End-to-end exercise of the real `@QueryType` macro (declaration + plugin +
// `Query` conformance + `_qkc` + `InitSynthesis`), complementing the
// expansion-level golden tests in `Tests/SwiflowMacrosTests/QueryTypeMacroTests`.
// That this file *compiles* is itself a test: a wrong conformance/init/queryKey
// synthesis would fail to build.

@QueryType struct ITUserByID {
    @Key var id: Int
    var api: Int = 0          // non-@Key dependency, defaulted (the test seam)
    func fetch() async throws -> Int { id }
}

@QueryType(prefix: "users") struct ITPrefixedUser {
    @Key var id: Int
    func fetch() async throws -> Int { id }
}

@QueryType(prefix: "quakes") struct ITQuakeFeed {
    @Key var magnitude: String
    @Key var window: String
    func fetch() async throws -> Int { 0 }
}

// Migration shape: declares `: Query` AND a hand-written `queryKey`/`init`.
// If `@QueryType` double-conformed or duplicated members, this would NOT compile
// — so building this struct verifies the conditional-conformance + suppression
// guards.
@QueryType struct ITExplicit: Query {
    @Key var id: Int
    var queryKey: QueryKey { ["explicit", .int(id)] }
    func fetch() async throws -> Int { id }
    init(id: Int) { self.id = id }
}

@Suite("QueryType integration")
@MainActor
struct QueryTypeIntegrationTests {
    @Test("default prefix = type name; @Key contributes via _qkc")
    func defaultPrefix() {
        #expect(ITUserByID(id: 5).queryKey == ["ITUserByID", .int(5)])
    }

    @Test("the defaulted dependency makes the type constructible from id alone (test seam)")
    func defaultedDependency() {
        #expect(ITUserByID(id: 9).queryKey == ["ITUserByID", .int(9)])
    }

    @Test("custom prefix replaces the type name")
    func customPrefix() {
        #expect(ITPrefixedUser(id: 7).queryKey == ["users", .int(7)])
    }

    @Test("multiple @Key concatenate in source order")
    func multipleKeys() {
        #expect(ITQuakeFeed(magnitude: "M5", window: "day").queryKey
                == ["quakes", .string("M5"), .string("day")])
    }

    @Test("hand-written queryKey is preserved; : Query does not double-conform")
    func explicitConformanceAndQueryKey() {
        #expect(ITExplicit(id: 3).queryKey == ["explicit", .int(3)])
    }

    @Test("a synthesized type is usable everywhere a Query is required")
    func conformsToQuery() {
        func key<Q: Query>(of q: Q) -> QueryKey { q.queryKey }
        #expect(key(of: ITUserByID(id: 1)) == ["ITUserByID", .int(1)])
    }
}
