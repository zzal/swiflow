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
}
