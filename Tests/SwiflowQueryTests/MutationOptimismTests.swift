// Tests/SwiflowQueryTests/MutationOptimismTests.swift
import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor private final class Dummy: Component { var body: VNode { .text("") } }
private enum Boom: Error { case nope }

/// A deterministic latch so the test can observe state mid-flight. `open()` is
/// safe to call before `wait()` — `wait()` then returns immediately — which
/// removes any ordering race between the test and the spawned mutation task.
@MainActor private final class Gate {
    private var cont: CheckedContinuation<Void, Never>?
    private var opened = false
    func wait() async {
        if opened { return }
        await withCheckedContinuation { cont = $0 }
    }
    func open() {
        opened = true
        cont?.resume(); cont = nil
    }
}

@MainActor private struct ListQuery: Query {
    var queryKey: QueryKey { ["todos"] }
    func fetch() async throws -> [String] { [] }
}

@MainActor private struct AddTodo: Mutation {
    let gate: Gate
    let result: @MainActor @Sendable () async throws -> String
    func perform(_ title: String) async throws -> String { await gate.wait(); return try await result() }
    func optimistic(_ title: String) -> [OptimisticEdit] {
        [.update(ListQuery()) { $0 + ["draft:\(title)"] }]
    }
    func invalidations(input: String, output: String) -> [Invalidation] { [.prefix(["todos"])] }
}

@Suite("Mutation/optimism")
@MainActor
struct MutationOptimismTests {
    private func seedList(_ c: QueryClient, _ items: [String]) async {
        let owner = AnyComponent(Dummy())
        c.reconcile(owner: owner, scheduler: SyncScheduler { _ in },
            observations: [QueryClient.QueryObservation(
                key: ["todos"], tags: [], staleTime: .seconds(9999),
                boxedFetch: { items },
                valuesEqual: { ($0 as? [String]) == ($1 as? [String]) })])
        for t in c.inFlightTasks() { await t.value }
        _ = owner
    }
    private func wired(_ m: AddTodo, _ c: QueryClient) -> MutationHandle<AddTodo> {
        let rt = MutationRuntime<AddTodo>()
        rt.wire(owner: AnyComponent(Dummy()), scheduler: SyncScheduler { _ in }, client: c)
        return MutationHandle(runtime: rt, mutation: m)
    }

    @Test func optimisticValueVisibleBeforePerformResolves() async {
        let client = QueryClient(clock: ManualClock())
        await seedList(client, ["a"])
        let gate = Gate()
        let h = wired(AddTodo(gate: gate) { "saved" }, client)
        h.mutate("b")
        // perform is parked on the gate; optimistic write already applied.
        #expect(client.getQueryData(["todos"], as: [String].self) == ["a", "draft:b"])
        gate.open()
        for t in client.inFlightTasks() { await t.value }
    }

    @Test func rollbackRestoresOnFailure() async {
        let client = QueryClient(clock: ManualClock())
        await seedList(client, ["a"])
        let gate = Gate()
        let h = wired(AddTodo(gate: gate) { throw Boom.nope }, client)
        h.mutate("b")
        #expect(client.getQueryData(["todos"], as: [String].self) == ["a", "draft:b"])  // applied
        gate.open()
        for t in client.inFlightTasks() { await t.value }
        #expect(client.getQueryData(["todos"], as: [String].self) == ["a"])             // rolled back
    }

    @Test func invalidationRefetchesOnSuccess() async {
        let client = QueryClient(clock: ManualClock())
        // A live observer with a fetch counter to prove invalidation refetched.
        let owner = AnyComponent(Dummy())
        var fetches = 0
        client.reconcile(owner: owner, scheduler: SyncScheduler { _ in },
            observations: [QueryClient.QueryObservation(
                key: ["todos"], tags: [], staleTime: .seconds(9999),
                boxedFetch: { fetches += 1; return ["a"] },
                valuesEqual: { ($0 as? [String]) == ($1 as? [String]) })])
        for t in client.inFlightTasks() { await t.value }
        #expect(fetches == 1)

        let gate = Gate()
        let h = wired(AddTodo(gate: gate) { "saved" }, client)
        h.mutate("b"); gate.open()
        for t in client.inFlightTasks() { await t.value }
        #expect(fetches == 2)        // invalidations(.prefix(["todos"])) refetched
        _ = owner
    }
}
