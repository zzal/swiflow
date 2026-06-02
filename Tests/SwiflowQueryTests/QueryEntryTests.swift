import Testing
@testable import SwiflowQuery

@Suite("QueryEntry")
@MainActor
struct QueryEntryTests {
    @Test func absentEntryReadsAsLoading() {
        let s = makeSnapshot(from: nil, as: Int.self)
        #expect(s.data == nil)
        #expect(s.isLoading)
        #expect(s.isFetching)
    }

    @Test func presentValueNotFetchingIsSettled() {
        let e = QueryEntry(valuesEqual: { ($0 as? Int) == ($1 as? Int) })
        e.value = 7
        e.lastFetched = .zero
        let s = makeSnapshot(from: e, as: Int.self)
        #expect(s.data == 7)
        #expect(!s.isLoading)
        #expect(!s.isFetching)
        #expect(s.isSuccess)
    }

    @Test func inFlightFetchWithDataIsBackgroundFetching() {
        let e = QueryEntry(valuesEqual: { ($0 as? Int) == ($1 as? Int) })
        e.value = 7
        e.lastFetched = .zero
        e.inFlight = Task<Void, Never> {}   // a revalidation is running in the background
        let s = makeSnapshot(from: e, as: Int.self)
        #expect(s.data == 7)
        #expect(!s.isLoading)
        #expect(s.isFetching)
    }
}
