// Tests/SwiflowQueryTests/QueryEntrySupersedeTests.swift
import Testing
import Swiflow
@testable import SwiflowQuery

/// Pins the supersede contract — the "invalidate this entry's in-flight world"
/// transition shared by `forceStaleAndRefetch` and `setQueryData` — and the one
/// DELIBERATE difference between its two callers: what happens to a held error.
/// The two sites had drifted apart hand-written (audit Part II Wave-1 #2);
/// these tests make each policy an explicit, guarded decision.
@Suite("QueryEntry/supersede")
@MainActor
struct QueryEntrySupersedeTests {
    @Test("invalidate keeps the last error visible until the refetch settles")
    func invalidateKeepsErrorUntilSettle() async {
        let bg = BG(retry: .none)
        await bg.settle()                                  // initial fetch succeeds
        bg.probe.failuresRemaining = 1
        bg.client.invalidate(["k"])                        // refetch → fails
        await bg.settle()
        #expect(bg.entry.error != nil)

        // Invalidate again; the next fetch will succeed. While it is in
        // flight the last-known error must stay visible in snapshots — an
        // invalidate has no new truth yet, so the error is kept alongside
        // the stale data (SWR) until the refetch settles and overwrites both.
        bg.client.invalidate(["k"])
        let mid = makeSnapshot(from: bg.entry, as: [String].self)
        #expect(mid.error != nil)                          // kept during refetch
        #expect(mid.isFetching)
        await bg.settle()                                  // success overwrites it
        #expect(bg.entry.error == nil)
    }

    @Test("setQueryData clears a held error — the optimistic write IS the new truth")
    func setQueryDataClearsError() async {
        let bg = BG(retry: .none)
        bg.probe.failuresRemaining = 1
        await bg.settle()                                  // initial fetch fails
        #expect(bg.entry.error != nil)

        bg.client.setQueryData(["k"], ["optimistic"])
        #expect(bg.entry.error == nil)                     // a lingering error would contradict the write
        #expect(bg.entry.value as? [String] == ["optimistic"])
    }

    @Test("supersede bumps the generation, cancels in-flight, voids the retry ladder, and forces stale")
    func supersedeContract() {
        let e = QueryEntry()
        e.lastFetched = .seconds(5)
        e.generation = 3
        e.failureCount = 2
        e.nextRetryDue = .seconds(9)
        e.error = FetchProbe.Boom.fail
        let inFlight: Task<Void, Never> = Task {}
        e.inFlight = inFlight

        e.supersede(clearError: false)
        #expect(e.generation == 4)                         // a resolving fetch commits only on match
        #expect(e.inFlight == nil)
        #expect(inFlight.isCancelled)
        #expect(e.lastFetched == nil)                      // forced stale
        #expect(e.failureCount == 0)
        #expect(e.nextRetryDue == nil)
        #expect(e.error != nil)                            // clearError: false keeps it

        e.supersede(clearError: true)
        #expect(e.error == nil)                            // clearError: true voids it
        #expect(e.generation == 5)
    }
}
