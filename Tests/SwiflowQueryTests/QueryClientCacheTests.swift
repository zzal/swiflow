// Tests/SwiflowQueryTests/QueryClientCacheTests.swift
import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor
private final class Dummy: Component { var body: VNode { .text("") } }

@Suite("QueryClient/cache")
@MainActor
struct QueryClientCacheTests {
    /// Seed an entry by reconciling a single observation for `key` with value V.
    private func seed(_ client: QueryClient, _ key: QueryKey, _ value: Int) async {
        let owner = AnyComponent(Dummy())
        client.reconcile(owner: owner, scheduler: SyncScheduler { _ in },
            observations: [QueryClient.QueryObservation(
                key: key, tags: [], staleTime: .zero,
                refetchInterval: nil, refetchOnFocus: true, retry: .default,
                boxedFetch: { value },
                valuesEqual: { ($0 as? Int) == ($1 as? Int) })])
        for t in client.inFlightTasks() { await t.value }   // let the fetch settle
        _ = owner   // retain through settle
    }

    @Test("setQueryData is readable back through both the typed and erased getters") func setThenGet() async {
        let client = QueryClient(clock: ManualClock())
        await seed(client, ["n"], 1)
        client.setQueryData(["n"], 42)
        #expect(client.getQueryData(["n"], as: Int.self) == 42)
        #expect(client.getQueryDataErased(["n"]) as? Int == 42)
    }

    @Test("setQueryData on a key with no entry is a no-op") func setIsNoOpOnAbsentEntry() {
        let client = QueryClient(clock: ManualClock())
        client.setQueryData(["missing"], 99)               // no entry → no-op
        #expect(client.getQueryData(["missing"], as: Int.self) == nil)
    }

    @Test("setQueryData bumps the generation, drops in-flight work, and leaves the entry stale") func setBumpsGenerationAndCancelsInFlight() async {
        let client = QueryClient(clock: ManualClock())
        await seed(client, ["n"], 1)
        let entry = client.entries[["n"]]!
        let genBefore = entry.generation
        client.setQueryData(["n"], 7)
        #expect(entry.generation == genBefore + 1)         // superseded
        #expect(entry.inFlight == nil)
        #expect(entry.lastFetched == nil)                  // left stale
    }
}
