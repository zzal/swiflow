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

@Suite("Mutation rollback is generation- and identity-guarded")
@MainActor
struct MutationRollbackGuardTests {

    /// Seed a String value at `key` by registering a live observer and
    /// awaiting its initial fetch — mirrors the pattern in MutationOptimismTests.
    /// Pass (and KEEP a reference to) an explicit `owner` when the test needs
    /// to control the subscriber's lifecycle: letting the owner dealloc leaks
    /// its `observed` set (only `dropComponent` cleans it), and a later owner
    /// allocated at the same address inherits it via ObjectIdentifier collision
    /// — silently suppressing the remount's initial fetch.
    private func seedString(_ c: QueryClient, key: QueryKey, value: String,
                            owner: AnyComponent = AnyComponent(RGDummy())) async {
        c.reconcile(owner: owner, scheduler: SyncScheduler { _ in },
            observations: [QueryClient.QueryObservation(
                key: key, tags: [], staleTime: .seconds(9999),
                refetchInterval: nil, refetchOnFocus: true, retry: .default,
                boxedFetch: { value })])
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
    @Test("Rollback is skipped when a concurrent write superseded the key after the optimistic write") func failedRollbackSkipsWhenKeyWasSupersededSinceOptimisticWrite() async {
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
        _ = await h.runtime.finish("x", m, rollback, epoch: h.runtime.epoch)

        // The newer value VB must survive; V0 must NOT be restored.
        #expect(client.getQueryData(key, as: String.self) == vb,
            "rollback must be skipped when key was superseded by a concurrent writer")
    }

    // 2. A failed mutation whose key was NOT touched since its optimistic write
    //    DOES roll back to the prior (control case).
    @Test("Rollback restores the prior value when the key was untouched since the optimistic write") func failedRollbackRestoresPriorWhenKeyUntouched() async {
        let client = QueryClient(clock: ManualClock())
        let key: QueryKey = ["item"]
        let v0 = "original"

        await seedString(client, key: key, value: v0)
        #expect(client.getQueryData(key, as: String.self) == v0)

        let m = StringMutation(key: key, optimisticValue: "optimistic-A", result: { throw RGBoom.nope })
        let h = wired(m, client)
        let rollback = h.runtime.beginOptimistic("x", m)
        // No concurrent write between beginOptimistic and finish.
        _ = await h.runtime.finish("x", m, rollback, epoch: h.runtime.epoch)

        #expect(client.getQueryData(key, as: String.self) == v0,
            "rollback must restore the prior when the key was not superseded")
    }

    // 3. THE RECYCLE HOLE (audit II Wave-2 #2): generation alone cannot detect
    //    an evicted-then-recycled entry, because fresh entries restart at
    //    generation 0 and can climb back to the recorded number while the
    //    mutation is still in flight. The rollback guard needs commitFetch's
    //    IDENTITY check too — this is the missing-sibling-guard defect shape.
    @Test("Rollback is skipped when the entry was evicted and recycled to a matching generation") func failedRollbackSkipsWhenEntryRecycledAtSameGeneration() async {
        let clock = ManualClock()
        let client = QueryClient(clock: clock)
        let key: QueryKey = ["item"]

        // Seed with an explicitly-held subscriber, then unmount it properly
        // (dropComponent) so the entry becomes GC-eligible.
        let owner1 = AnyComponent(RGDummy())
        await seedString(client, key: key, value: "v0", owner: owner1)

        // Slow mutation A: optimistic write bumps generation 0 → 1; the
        // rollback record captures gen 1 against THIS entry incarnation.
        let m = StringMutation(key: key, optimisticValue: "OPT", result: { throw RGBoom.nope })
        let h = wired(m, client)
        let rollback = h.runtime.beginOptimistic("x", m)
        #expect(client.getQueryData(key, as: String.self) == "OPT")

        // Unmount, then evict: one tick stamps unobservedSince, a second past
        // gcTime evicts.
        client.dropComponent(owner1)
        clock.advance(by: .seconds(1)); client.tick(now: clock.now())
        clock.advance(by: .seconds(400)); client.tick(now: clock.now())
        #expect(client.getQueryData(key, as: String.self) == nil)

        // Recycle: remount the query — a FRESH entry at generation 0 commits
        // the current server truth.
        let owner2 = AnyComponent(RGDummy())
        await seedString(client, key: key, value: "server-truth", owner: owner2)
        #expect(client.getQueryData(key, as: String.self) == "server-truth")
        #expect(client.generation(of: key) == 0)

        // One legitimate supersede brings the RECYCLED entry to generation 1 —
        // the same number the rollback recorded against the previous
        // incarnation.
        client.setQueryData(key, "newer")
        #expect(client.generation(of: key) == 1)

        // A's failure must NOT resurrect the previous incarnation's snapshot
        // ("v0") into the recycled entry — the generations collide, but the
        // identity differs.
        _ = await h.runtime.finish("x", m, rollback, epoch: h.runtime.epoch)
        #expect(client.getQueryData(key, as: String.self) == "newer",
            "rollback must not resurrect a previous incarnation's snapshot into a recycled entry")
        _ = owner2
    }

    // 4. Benign self-healing pin: after a clean eviction (no recycle), a failed
    //    mutation's rollback is a no-op — nothing is resurrected — and a later
    //    remount refetches server truth.
    @Test("Rollback after clean eviction is a no-op; a remount refetches server truth") func failedRollbackAfterEvictionIsNoOp() async {
        let clock = ManualClock()
        let client = QueryClient(clock: clock)
        let key: QueryKey = ["item"]

        let owner1 = AnyComponent(RGDummy())
        await seedString(client, key: key, value: "v0", owner: owner1)
        let m = StringMutation(key: key, optimisticValue: "OPT", result: { throw RGBoom.nope })
        let h = wired(m, client)
        let rollback = h.runtime.beginOptimistic("x", m)

        client.dropComponent(owner1)
        clock.advance(by: .seconds(1)); client.tick(now: clock.now())
        clock.advance(by: .seconds(400)); client.tick(now: clock.now())
        #expect(client.getQueryData(key, as: String.self) == nil)   // evicted

        _ = await h.runtime.finish("x", m, rollback, epoch: h.runtime.epoch)
        #expect(client.getQueryData(key, as: String.self) == nil,
            "rollback into a missing entry must stay a no-op (nothing resurrected)")

        // Self-healing: the next mount fetches fresh server truth.
        let owner2 = AnyComponent(RGDummy())
        await seedString(client, key: key, value: "fresh", owner: owner2)
        #expect(client.getQueryData(key, as: String.self) == "fresh")
        _ = owner2
    }
}
