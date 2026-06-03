import Testing
@testable import SwiflowQuery

@MainActor
private struct Echo: Query {
    let id: Int
    var queryKey: QueryKey { ["echo", .int(id)] }
    func fetch() async throws -> Int { id * 10 }
}

@Suite("Query")
@MainActor
struct QueryProtocolTests {
    @Test func defaultsAreEmptyTagsAndZeroStaleTime() {
        let q = Echo(id: 3)
        #expect(q.tags.isEmpty)
        #expect(q.staleTime == .zero)
        #expect(q.queryKey == ["echo", 3])
    }

    @Test func fetchReturnsValue() async throws {
        let v = try await Echo(id: 3).fetch()
        #expect(v == 30)
    }

    @Test func queryStateDefaultsAndSuccess() {
        let empty = QueryState<Int>()
        #expect(empty.data == nil)
        #expect(!empty.isSuccess)

        let loaded = QueryState<Int>(data: 42, isFetching: false)
        #expect(loaded.isSuccess)
        #expect(loaded.data == 42)
    }

    @Test func backgroundConfigDefaults() {
        let p = PlainQ()
        #expect(p.refetchInterval == nil)
        #expect(p.refetchOnFocus == true)
        #expect(p.retry == .default)
    }

    @Test func backgroundConfigOverrides() {
        let t = TunedQ()
        #expect(t.refetchInterval == .seconds(5))
        #expect(t.refetchOnFocus == false)
        #expect(t.retry == .none)
    }
}

@MainActor private struct PlainQ: Query {
    var queryKey: QueryKey { ["p"] }
    func fetch() async throws -> Int { 0 }
}

@MainActor private struct TunedQ: Query {
    var queryKey: QueryKey { ["t"] }
    var refetchInterval: Duration? { .seconds(5) }
    var refetchOnFocus: Bool { false }
    var retry: RetryPolicy { .none }
    func fetch() async throws -> Int { 0 }
}
