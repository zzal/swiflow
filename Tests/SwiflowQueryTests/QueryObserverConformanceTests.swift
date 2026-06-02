import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor
private final class Dummy: Component { var body: VNode { .text("") } }

@MainActor
private struct N: Query {
    let id: Int
    var queryKey: QueryKey { ["n", .int(id)] }
    func fetch() async throws -> Int { id }
}

@Suite("QueryClient/observer")
@MainActor
struct QueryObserverConformanceTests {
    @Test func willObserveDidReconcilesAndFetches() async {
        let client = QueryClient(clock: ManualClock())
        let owner = AnyComponent(Dummy())

        client.willEvaluate(owner: owner, scheduler: SyncScheduler { _ in })
        let snap = client.observe(N(id: 5))
        #expect(snap.isLoading)
        client.didEvaluate()

        for t in client.inFlightTasks() { await t.value }
        #expect(client.entries[["n", 5]]?.value as? Int == 5)
    }

    @Test func queryWithoutActiveClientReturnsLoading() {
        RenderObserverBox.current = nil
        let owner = Dummy()
        let snap = owner.query(N(id: 1))
        #expect(snap.isLoading)
    }
}
