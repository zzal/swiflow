import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor
private final class Dummy: Component { var body: VNode { .text("") } }

@Suite("QueryClient/reconcile")
@MainActor
struct QueryClientReconcileTests {
    private func awaitInFlight(_ c: QueryClient) async {
        for t in c.inFlightTasks() { await t.value }
    }
    private func obs(_ key: QueryKey, _ counter: @escaping () -> Void) -> QueryClient.QueryObservation {
        QueryClient.QueryObservation(
            key: key, tags: [], staleTime: .zero,
            refetchInterval: nil, refetchOnFocus: true, retry: .default,
            boxedFetch: { counter(); return 1 }
        )
    }

    @Test("A newly observed key subscribes the owner and triggers an initial fetch") func newKeySubscribesAndFetches() async {
        let client = QueryClient(clock: ManualClock())
        let owner = AnyComponent(Dummy())
        var calls = 0
        client.reconcile(owner: owner, scheduler: SyncScheduler { _ in },
                         observations: [obs(["a"], { calls += 1 })])
        await awaitInFlight(client)
        #expect(calls == 1)
        #expect(client.hasLiveSubscribers(["a"]))
    }

    @Test("A key dropped from the observation set loses its subscription") func droppedKeyUnsubscribes() async {
        let client = QueryClient(clock: ManualClock())
        let owner = AnyComponent(Dummy())
        let sched = SyncScheduler { _ in }
        client.reconcile(owner: owner, scheduler: sched, observations: [obs(["a"], {})])
        await awaitInFlight(client)
        client.reconcile(owner: owner, scheduler: sched, observations: [obs(["b"], {})])
        await awaitInFlight(client)
        #expect(!client.hasLiveSubscribers(["a"]))
        #expect(client.hasLiveSubscribers(["b"]))
    }

    @Test("Re-reconciling a retained key does not fetch again") func retainedKeyDoesNotRefetch() async {
        let client = QueryClient(clock: ManualClock())
        let owner = AnyComponent(Dummy())
        let sched = SyncScheduler { _ in }
        var calls = 0
        client.reconcile(owner: owner, scheduler: sched, observations: [obs(["a"], { calls += 1 })])
        await awaitInFlight(client)
        client.reconcile(owner: owner, scheduler: sched, observations: [obs(["a"], { calls += 1 })])
        await awaitInFlight(client)
        #expect(calls == 1)
    }

    @Test("dropComponent unsubscribes the owner from every key it observed") func dropComponentUnsubscribesAll() async {
        let client = QueryClient(clock: ManualClock())
        let owner = AnyComponent(Dummy())
        client.reconcile(owner: owner, scheduler: SyncScheduler { _ in },
                         observations: [obs(["a"], {}), obs(["b"], {})])
        await awaitInFlight(client)
        client.dropComponent(owner)
        #expect(!client.hasLiveSubscribers(["a"]))
        #expect(!client.hasLiveSubscribers(["b"]))
    }

    // Regression: a second component newly-observing a key while the first
    // component's fetch for it is still in flight must dedup AND must not leave
    // the entry reporting `isFetching` after that fetch resolves.
    @Test("A second subscriber arriving mid-flight dedups and does not leave isFetching wedged") func secondSubscriberMidFlightDoesNotStickFetching() async {
        let client = QueryClient(clock: ManualClock())
        let a = AnyComponent(Dummy())
        let b = AnyComponent(Dummy())
        let sched = SyncScheduler { _ in }
        var calls = 0
        func make() -> QueryClient.QueryObservation {
            QueryClient.QueryObservation(
                key: ["x"], tags: [], staleTime: .zero,
                refetchInterval: nil, refetchOnFocus: true, retry: .default,
                boxedFetch: { calls += 1; return 1 }
            )
        }
        client.reconcile(owner: a, scheduler: sched, observations: [make()])  // triggers fetch
        client.reconcile(owner: b, scheduler: sched, observations: [make()])  // dedups mid-flight
        await awaitInFlight(client)

        #expect(calls == 1)                                  // deduped to one fetch
        let entry = client.entries[["x"]]!
        #expect(makeSnapshot(from: entry, as: Int.self).isFetching == false)  // not wedged
    }
}

@MainActor private struct TunedQuery: Query {
    var queryKey: QueryKey { ["tuned"] }
    var staleTime: Duration { .seconds(7) }
    var refetchInterval: Duration? { .seconds(5) }
    var refetchOnFocus: Bool { false }
    var retry: RetryPolicy { .none }
    func fetch() async throws -> Int { 1 }
}

extension QueryClientReconcileTests {
    @Test("Reconcile copies the query's background config onto its entry") func reconcileCopiesBackgroundConfigOntoEntry() async {
        let client = QueryClient(clock: ManualClock())
        let owner = AnyComponent(Dummy())
        client.willEvaluate(owner: owner, scheduler: SyncScheduler { _ in })
        _ = client.observe(TunedQuery())
        client.didEvaluate()
        for t in client.inFlightTasks() { await t.value }

        let entry = client.entries[["tuned"]]!
        #expect(entry.staleTime == .seconds(7))
        #expect(entry.refetchInterval == .seconds(5))
        #expect(entry.refetchOnFocus == false)
        #expect(entry.retry == .none)
        _ = owner
    }
}
