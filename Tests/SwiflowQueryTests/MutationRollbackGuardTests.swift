// Tests/SwiflowQueryTests/MutationRollbackGuardTests.swift
import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor private final class RGDummy: Component { var body: VNode { .text("") } }
private enum RGBoom: Error { case nope }

/// A minimal query whose value type is `String`, used as the optimistic-edit
/// target so the type-checked `.update` factory can be called.
@MainActor private struct StringQuery: Query {
    let queryKey: QueryKey
    func fetch() async throws -> String { "" }
}

/// A mutation that writes a single String value to `key` optimistically, then
/// either succeeds or fails depending on the injected `result` closure.
@MainActor private struct StringMutation: Mutation {
    let key: QueryKey
    let optimisticValue: String
    let result: @MainActor @Sendable () async throws -> String

    func perform(_ _: String) async throws -> String { try await result() }

    func optimistic(_ _: String) -> [OptimisticEdit] {
        let q = StringQuery(queryKey: key)
        return [.update(q) { [optimisticValue] _ in optimisticValue }]
    }

    func invalidations(input: String, output: String) -> [Invalidation] { [] }
}

@Suite("Mutation rollback is generation-guarded")
@MainActor
struct MutationRollbackGuardTests {

    /// Seed a String value at `key` by registering a live observer and
    /// awaiting its initial fetch — mirrors the pattern in MutationOptimismTests.
    private func seedString(_ c: QueryClient, key: QueryKey, value: String) async {
        let owner = AnyComponent(RGDummy())
        c.reconcile(owner: owner, scheduler: SyncScheduler { _ in },
            observations: [QueryClient.QueryObservation(
                key: key, tags: [], staleTime: .seconds(9999),
                refetchInterval: nil, refetchOnFocus: true, retry: .default,
                boxedFetch: { value },
                valuesEqual: { ($0 as? String) == ($1 as? String) })])
        for t in c.inFlightTasks() { await t.value }
        _ = owner
    }

    private func wired(_ m: StringMutation, _ c: QueryClient) -> MutationHandle<StringMutation> {
        let rt = MutationRuntime<StringMutation>()
        rt.wire(owner: AnyComponent(RGDummy()), scheduler: SyncScheduler { _ in }, client: c)
        return MutationHandle(runtime: rt, mutation: m)
    }

    // 1. A failed mutation whose optimistic key was SUPERSEDED by a later write
    //    does NOT roll back (the newer value survives).
    @Test func failedRollbackSkipsWhenKeyWasSupersededSinceOptimisticWrite() async {
        let client = QueryClient(clock: ManualClock())
        let key: QueryKey = ["item"]
        let v0 = "original"
        let va = "optimistic-A"
        let vb = "concurrent-B"

        // Seed K = V0.
        await seedString(client, key: key, value: v0)
        #expect(client.getQueryData(key, as: String.self) == v0)

        // Mutation A: beginOptimistic writes VA into K.
        let m = StringMutation(key: key, optimisticValue: va, result: { throw RGBoom.nope })
        let h = wired(m, client)
        // Call beginOptimistic manually so we can interleave a concurrent write
        // before calling finish.
        let rollback = h.runtime.beginOptimistic("x", m)
        #expect(client.getQueryData(key, as: String.self) == va)

        // Simulate a concurrent writer bumping the generation BEFORE A's failure.
        client.setQueryData(key, vb)
        #expect(client.getQueryData(key, as: String.self) == vb)

        // A.finish fails — without the generation guard it would clobber VB
        // back to V0.
        _ = await h.runtime.finish("x", m, rollback)

        // The newer value VB must survive; V0 must NOT be restored.
        #expect(client.getQueryData(key, as: String.self) == vb,
            "rollback must be skipped when key was superseded by a concurrent writer")
    }

    // 2. A failed mutation whose key was NOT touched since its optimistic write
    //    DOES roll back to the prior (control case).
    @Test func failedRollbackRestoresPriorWhenKeyUntouched() async {
        let client = QueryClient(clock: ManualClock())
        let key: QueryKey = ["item"]
        let v0 = "original"

        await seedString(client, key: key, value: v0)
        #expect(client.getQueryData(key, as: String.self) == v0)

        let m = StringMutation(key: key, optimisticValue: "optimistic-A", result: { throw RGBoom.nope })
        let h = wired(m, client)
        let rollback = h.runtime.beginOptimistic("x", m)
        // No concurrent write between beginOptimistic and finish.
        _ = await h.runtime.finish("x", m, rollback)

        #expect(client.getQueryData(key, as: String.self) == v0,
            "rollback must restore the prior when the key was not superseded")
    }
}
