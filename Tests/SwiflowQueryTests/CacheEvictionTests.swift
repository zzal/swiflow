// Tests/SwiflowQueryTests/CacheEvictionTests.swift
import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor private final class Dummy: Component { var body: VNode { .text("") } }

/// Zero-observer cache eviction: an entry that has lost its last live
/// subscriber is kept for `gcTime` (so a back-nav remount within the window
/// reuses the warm cache), then garbage-collected by `tick`'s GC sweep.
@Suite("QueryClient/eviction")
@MainActor
struct CacheEvictionTests {
    private func awaitInFlight(_ c: QueryClient) async {
        for t in c.inFlightTasks() { await t.value }
    }

    /// One observation wired to drive a settling fetch, with a tunable gcTime.
    private func obs(_ key: QueryKey,
                     gcTime: Duration = .seconds(300),
                     boxedFetch: @escaping @MainActor () async throws -> Any
                        = { 1 }) -> QueryClient.QueryObservation {
        QueryClient.QueryObservation(
            key: key, tags: [], staleTime: .seconds(9999),
            refetchInterval: nil, refetchOnFocus: true, retry: .none,
            gcTime: gcTime,
            boxedFetch: boxedFetch,
            valuesEqual: { ($0 as? Int) == ($1 as? Int) }
        )
    }

    // 1. After the last subscriber drops, the entry survives one stamping tick
    //    and is evicted only once the clock has advanced past gcTime.
    @Test func entryIsEvictedGCTimeAfterLastSubscriberDrops() async {
        let clock = ManualClock()
        let client = QueryClient(clock: clock)
        let owner = AnyComponent(Dummy())
        client.reconcile(owner: owner, scheduler: SyncScheduler { _ in },
                         observations: [obs(["users", "7"], gcTime: .seconds(300))])
        await awaitInFlight(client)
        #expect(client.entries[["users", "7"]] != nil)

        client.dropComponent(owner)               // no live subscribers now
        #expect(!client.hasLiveSubscribers(["users", "7"]))

        client.tick(now: clock.now())             // STAMPS unobservedSince, no evict
        #expect(client.entries[["users", "7"]] != nil)

        clock.advance(by: .seconds(301))          // past gcTime
        client.tick(now: clock.now())             // evict
        #expect(client.entries[["users", "7"]] == nil)
        _ = owner
    }

    // 2. An entry with a live subscriber is never evicted, no matter how long
    //    the clock advances.
    @Test func entryWithLiveSubscriberIsNeverEvicted() async {
        let clock = ManualClock()
        let client = QueryClient(clock: clock)
        let owner = AnyComponent(Dummy())
        client.reconcile(owner: owner, scheduler: SyncScheduler { _ in },
                         observations: [obs(["todos", "1"], gcTime: .seconds(300))])
        await awaitInFlight(client)

        clock.advance(by: .seconds(10_000))       // way past gcTime
        client.tick(now: clock.now())
        #expect(client.entries[["todos", "1"]] != nil)
        _ = owner                                  // keep the subscriber alive
    }

    // 3. Re-observing the same key within the gcTime window keeps the entry and
    //    its cached value — the warm-cache back-nav path.
    @Test func reObservationWithinGCTimeKeepsTheCachedValue() async {
        let clock = ManualClock()
        let client = QueryClient(clock: clock)
        let sched = SyncScheduler { _ in }
        let owner1 = AnyComponent(Dummy())
        client.reconcile(owner: owner1, scheduler: sched,
                         observations: [obs(["users", "7"], gcTime: .seconds(300),
                                            boxedFetch: { 42 })])
        await awaitInFlight(client)
        #expect(client.entries[["users", "7"]]?.value as? Int == 42)

        client.dropComponent(owner1)
        client.tick(now: clock.now())             // STAMPS unobservedSince

        clock.advance(by: .seconds(100))          // < gcTime
        let owner2 = AnyComponent(Dummy())
        client.reconcile(owner: owner2, scheduler: sched,
                         observations: [obs(["users", "7"], gcTime: .seconds(300),
                                            boxedFetch: { 42 })])
        await awaitInFlight(client)
        client.tick(now: clock.now())

        let entry = client.entries[["users", "7"]]
        #expect(entry != nil)                      // entry survived
        #expect(entry?.value as? Int == 42)        // cached value survived
        _ = owner1; _ = owner2
    }

    // 4. Eviction cancels an in-flight fetch. The fetch hangs via `Task.sleep`,
    //    which throws on cancellation; the surrounding `inFlight` task is the
    //    one the GC sweep cancels, so awaiting it afterward reports cancelled.
    @Test func evictionCancelsAnInFlightFetch() async {
        let clock = ManualClock()
        let client = QueryClient(clock: clock)
        let owner = AnyComponent(Dummy())
        client.reconcile(owner: owner, scheduler: SyncScheduler { _ in },
                         observations: [obs(["users", "9"], gcTime: .seconds(300),
                                            boxedFetch: {
                                                try await Task.sleep(for: .seconds(3600))
                                                return 1
                                            })])
        // Do NOT settle: the fetch is intentionally hanging.
        let inFlight = client.entries[["users", "9"]]?.inFlight
        #expect(inFlight != nil)

        client.dropComponent(owner)
        client.tick(now: clock.now())             // STAMPS unobservedSince

        clock.advance(by: .seconds(301))          // past gcTime
        client.tick(now: clock.now())             // evict → cancels in-flight task
        #expect(client.entries[["users", "9"]] == nil)

        await inFlight?.value                       // let the cancelled task finish
        #expect(inFlight?.isCancelled == true)
        _ = owner
    }
}
