import Testing
@testable import SwiflowQuery

@Suite("QueryEntry")
@MainActor
struct QueryEntryTests {
    @Test("A snapshot of an absent entry reads as loading and fetching with no data") func absentEntryReadsAsLoading() {
        let s = makeSnapshot(from: nil, as: Int.self)
        #expect(s.data == nil)
        #expect(s.isLoading)
        #expect(s.isFetching)
    }

    @Test("A fetched value with nothing in flight snapshots as settled success") func presentValueNotFetchingIsSettled() {
        let e = QueryEntry(valuesEqual: { ($0 as? Int) == ($1 as? Int) })
        e.value = 7
        e.lastFetched = .zero
        let s = makeSnapshot(from: e, as: Int.self)
        #expect(s.data == 7)
        #expect(!s.isLoading)
        #expect(!s.isFetching)
        #expect(s.isSuccess)
    }

    @Test("Existing data plus an in-flight task snapshots as background fetching, not loading") func inFlightFetchWithDataIsBackgroundFetching() {
        let e = QueryEntry(valuesEqual: { ($0 as? Int) == ($1 as? Int) })
        e.value = 7
        e.lastFetched = .zero
        e.inFlight = Task<Void, Never> {}   // a revalidation is running in the background
        let s = makeSnapshot(from: e, as: Int.self)
        #expect(s.data == 7)
        #expect(!s.isLoading)
        #expect(s.isFetching)
    }

    @Test("A new entry starts with default background config and clean retry bookkeeping") func backgroundStateDefaults() {
        let e = QueryEntry(valuesEqual: { ($0 as? Int) == ($1 as? Int) })
        #expect(e.staleTime == .zero)
        #expect(e.refetchInterval == nil)
        #expect(e.refetchOnFocus == true)
        #expect(e.retry == .default)
        #expect(e.failureCount == 0)
        #expect(e.nextRetryDue == nil)
    }
}
