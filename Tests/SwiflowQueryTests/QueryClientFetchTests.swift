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

    @Test func startFetchPopulatesEntryAndNotifies() async {
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

    @Test func secondStartFetchDedupes() async {
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

    @Test func supersededResultIsDropped() async {
        let client = QueryClient(clock: ManualClock())
        let entry = QueryEntry(valuesEqual: { ($0 as? Int) == ($1 as? Int) })
        entry.boxedFetch = { 1 }
        client.entries[["n"]] = entry

        client.startFetch(for: ["n"], entry: entry)
        entry.generation += 1                 // supersede before commit
        await awaitInFlight(client)
        #expect(entry.value == nil)           // stale result dropped by the guard
    }
}
