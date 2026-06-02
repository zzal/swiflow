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
            boxedFetch: { counter(); return 1 },
            valuesEqual: { ($0 as? Int) == ($1 as? Int) }
        )
    }

    @Test func newKeySubscribesAndFetches() async {
        let client = QueryClient(clock: ManualClock())
        let owner = AnyComponent(Dummy())
        var calls = 0
        client.reconcile(owner: owner, scheduler: SyncScheduler { _ in },
                         observations: [obs(["a"], { calls += 1 })])
        await awaitInFlight(client)
        #expect(calls == 1)
        #expect(client.hasLiveSubscribers(["a"]))
    }

    @Test func droppedKeyUnsubscribes() async {
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

    @Test func retainedKeyDoesNotRefetch() async {
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

    @Test func dropComponentUnsubscribesAll() async {
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
    // the entry stuck in `hasPendingFetch` (which would wedge isFetching=true
    // after the fetch resolves).
    @Test func secondSubscriberMidFlightDoesNotStickFetching() async {
        let client = QueryClient(clock: ManualClock())
        let a = AnyComponent(Dummy())
        let b = AnyComponent(Dummy())
        let sched = SyncScheduler { _ in }
        var calls = 0
        func make() -> QueryClient.QueryObservation {
            QueryClient.QueryObservation(
                key: ["x"], tags: [], staleTime: .zero,
                boxedFetch: { calls += 1; return 1 },
                valuesEqual: { ($0 as? Int) == ($1 as? Int) }
            )
        }
        client.reconcile(owner: a, scheduler: sched, observations: [make()])  // triggers fetch
        client.reconcile(owner: b, scheduler: sched, observations: [make()])  // dedups mid-flight
        await awaitInFlight(client)

        #expect(calls == 1)                                  // deduped to one fetch
        let entry = client.entries[["x"]]!
        #expect(!entry.hasPendingFetch)                      // not wedged
        #expect(makeSnapshot(from: entry, as: Int.self).isFetching == false)
    }
}
