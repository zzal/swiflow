import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor
private final class Dummy: Component { var body: VNode { .text("") } }

@Suite("QueryClient/fetch")
@MainActor
struct QueryClientFetchTests {
    private func awaitInFlight(_ client: QueryClient) async {
        for t in client.inFlightTasks() { await t.value }
    }

    @Test("startFetch commits the value, clears inFlight, and marks subscribers dirty") func startFetchPopulatesEntryAndNotifies() async {
        var marks = 0
        let scheduler = SyncScheduler { _ in marks += 1 }
        let client = QueryClient(clock: ManualClock())
        let owner = AnyComponent(Dummy())

        let entry = QueryEntry(valuesEqual: { ($0 as? Int) == ($1 as? Int) })
        entry.boxedFetch = { 99 }
        client.entries[["n"]] = entry
        client.subscribe(owner: owner, scheduler: scheduler, to: ["n"])

        client.startFetch(for: ["n"], entry: entry)
        await awaitInFlight(client)
        scheduler.flush()   // markDirty only queues; flush runs the callback

        #expect(entry.value as? Int == 99)
        #expect(entry.inFlight == nil)
        #expect(entry.lastFetched != nil)
        #expect(marks >= 1)
    }

    @Test("A second startFetch while one is in flight is ignored") func secondStartFetchDedupes() async {
        var calls = 0
        let client = QueryClient(clock: ManualClock())
        let entry = QueryEntry(valuesEqual: { ($0 as? Int) == ($1 as? Int) })
        entry.boxedFetch = { calls += 1; return 1 }
        client.entries[["n"]] = entry

        client.startFetch(for: ["n"], entry: entry)
        client.startFetch(for: ["n"], entry: entry)   // in-flight → ignored
        await awaitInFlight(client)
        #expect(calls == 1)
    }

    @Test("A fetch result superseded by a generation bump is dropped, not committed") func supersededResultIsDropped() async {
        let client = QueryClient(clock: ManualClock())
        let entry = QueryEntry(valuesEqual: { ($0 as? Int) == ($1 as? Int) })
        entry.boxedFetch = { 1 }
        client.entries[["n"]] = entry

        client.startFetch(for: ["n"], entry: entry)
        entry.generation += 1                 // supersede before commit
        await awaitInFlight(client)
        #expect(entry.value == nil)           // stale result dropped by the guard
    }

    // Regression (C1): an `invalidate` that installs a NEW in-flight fetch while
    // the OLD one is still completing must not let the old fetch's commit nil
    // out the new fetch's `inFlight` handle (which would break dedup + settle).
    @Test("The superseding fetch's inFlight handle survives the stale fetch's completion") func supersedingFetchSurvivesStaleCompletion() async {
        let client = QueryClient(clock: ManualClock())
        let owner = AnyComponent(Dummy())
        let sched = SyncScheduler { _ in }

        let gateA = Gate()
        let gateB = Gate()
        var started = 0
        let entry = QueryEntry(valuesEqual: { ($0 as? Int) == ($1 as? Int) })
        entry.boxedFetch = {
            started += 1
            let n = started
            await (n == 1 ? gateA : gateB).wait()   // suspend until released
            return n
        }
        client.entries[["k"]] = entry
        client.subscribe(owner: owner, scheduler: sched, to: ["k"])

        client.startFetch(for: ["k"], entry: entry)   // Fetch A (generation 0)
        client.invalidate(["k"])                       // supersede → installs Fetch B (generation 1)
        #expect(entry.inFlight != nil)                 // B is in flight

        gateA.open()                                   // let the stale Fetch A complete
        await Task.yield()
        await Task.yield()
        #expect(entry.inFlight != nil)                 // B's handle MUST survive A's stale commit
        #expect(entry.value == nil)                    // A's value dropped by the generation guard

        gateB.open()
        await awaitInFlight(client)
        #expect(entry.value as? Int == 2)              // B committed normally
    }
}

/// A one-shot main-actor gate: `wait()` suspends until `open()` is called.
@MainActor
private final class Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var opened = false
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let pending = waiters
        waiters = []
        for c in pending { c.resume() }
    }
}
