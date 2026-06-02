import Testing
@testable import SwiflowQuery

@Suite("QueryClient/staleness")
@MainActor
struct QueryClientStalenessTests {
    @Test func neverFetchedAlwaysNeedsFetch() {
        let client = QueryClient(clock: ManualClock())
        let e = QueryEntry(valuesEqual: { _, _ in true })
        #expect(client.needsFetch(e, staleTime: .seconds(30)))
    }

    @Test func zeroStaleTimeIsAlwaysStale() {
        let clock = ManualClock(.seconds(100))
        let client = QueryClient(clock: clock)
        let e = QueryEntry(valuesEqual: { _, _ in true })
        e.lastFetched = .seconds(100)
        #expect(client.needsFetch(e, staleTime: .zero))
    }

    @Test func freshWithinStaleTimeDoesNotFetch() {
        let clock = ManualClock(.seconds(100))
        let client = QueryClient(clock: clock)
        let e = QueryEntry(valuesEqual: { _, _ in true })
        e.lastFetched = .seconds(90)                 // 10s ago
        #expect(!client.needsFetch(e, staleTime: .seconds(30)))   // still fresh
        clock.advance(by: .seconds(25))              // now 35s old
        #expect(client.needsFetch(e, staleTime: .seconds(30)))    // now stale
    }
}
