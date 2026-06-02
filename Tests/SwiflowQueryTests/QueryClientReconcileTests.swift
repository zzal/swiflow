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
}
