// Tests/SwiflowQueryTests/MutationResetTests.swift
// Pre-launch audit Wave-2 regression gates: reset() must detach the handle's
// LOCAL state from an in-flight mutation without skipping the CACHE effects
// (a detached failure still rolls back its optimistic edit; a detached success
// still dispatches invalidations). The optimistic-without-invalidations
// diagnostic that used to live here was retired when the default
// `invalidations` began deriving from `optimistic(_:)`'s declared keys — the
// footgun it warned about is now inexpressible (see DefaultInvalidationsTests).
import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor private final class ResetDummy: Component { var body: VNode { .text("") } }

@MainActor private final class ResetGate {
    private var cont: CheckedContinuation<Void, Never>?
    private var opened = false
    func wait() async { if opened { return }; await withCheckedContinuation { cont = $0 } }
    func open() { opened = true; cont?.resume(); cont = nil }
}

private struct MKey: Query {
    var queryKey: QueryKey { ["m"] }
    func fetch() async throws -> Int { 0 }
}

@MainActor private final class CallBox { var invalidationsAsked = false }

private enum ResetBoom: Error { case fail }

private struct GatedMut: Mutation {
    let gate: ResetGate
    let fail: Bool
    let box: CallBox
    func perform(_ x: Int) async throws -> Int {
        await gate.wait()
        if fail { throw ResetBoom.fail }
        return x
    }
    func optimistic(_ x: Int) -> [OptimisticEdit] {
        [.update(MKey()) { (old: Int?) in (old ?? 0) + 1 }]
    }
    func invalidations(input: Int, output: Int) -> [Invalidation] {
        box.invalidationsAsked = true
        return [.exact(["m"])]
    }
}

@Suite("Mutation reset epoch")
@MainActor
struct MutationResetTests {
    private func world() async -> (QueryClient, MutationRuntime<GatedMut>, ResetGate, CallBox) {
        let client = QueryClient(clock: ManualClock())
        let rt = MutationRuntime<GatedMut>()
        let owner = AnyComponent(ResetDummy())
        rt.wire(owner: owner, scheduler: SyncScheduler { _ in }, client: client)
        // setQueryData no-ops without an entry: create one via a real observation
        // whose fetch seeds the value 10, then drain it.
        client.reconcile(owner: owner, scheduler: SyncScheduler { _ in }, observations: [
            QueryClient.QueryObservation(
                key: ["m"], tags: [], staleTime: .seconds(9999),
                refetchInterval: nil, refetchOnFocus: false, retry: .none,
                boxedFetch: { 10 })
        ])
        for t in client.inFlightTasks() { await t.value }
        return (client, rt, ResetGate(), CallBox())
    }
    private func settle(_ client: QueryClient) async {
        for t in client.inFlightTasks() { await t.value }
    }

    @Test("a reset handle stays idle when the detached mutation later succeeds — cache effects still run")
    func resetDetachesLateSuccess() async {
        let (client, rt, gate, box) = await world()
        let m = GatedMut(gate: gate, fail: false, box: box)
        MutationHandle(runtime: rt, mutation: m).mutate(5)
        #expect(rt.status == .pending)

        rt.reset()
        #expect(rt.status == .idle)

        gate.open()
        await settle(client)
        #expect(rt.status == .idle, "a detached success must not resurrect the handle")
        #expect(rt.data == nil)
        #expect(box.invalidationsAsked, "cache effects (invalidations) run regardless of reset")
    }

    @Test("a detached FAILURE still rolls back its optimistic edit")
    func resetPreservesFailureRollback() async {
        let (client, rt, gate, box) = await world()
        let m = GatedMut(gate: gate, fail: true, box: box)
        MutationHandle(runtime: rt, mutation: m).mutate(5)
        #expect(client.getQueryDataErased(["m"]) as? Int == 11)   // optimistic applied

        rt.reset()
        gate.open()
        await settle(client)
        #expect(client.getQueryDataErased(["m"]) as? Int == 10,
                "the optimistic edit must roll back even though the handle was reset")
        #expect(rt.status == .idle, "a detached failure must not resurrect the handle either")
        #expect(rt.error == nil)
    }
}

