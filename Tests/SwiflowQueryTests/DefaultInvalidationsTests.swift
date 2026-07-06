// Tests/SwiflowQueryTests/DefaultInvalidationsTests.swift
// Pins the derived default for `Mutation.invalidations`: refetch exactly the
// keys `optimistic(_:)` DECLARES (deduped, declaration order) — so a plain
// optimistic CRUD mutation reconciles with the server without restating keys
// the engine already knows, and "optimistic without invalidations" stops being
// an expressible footgun (it used to be a DEBUG trap; now it can't happen
// unless deliberately opted into with an explicit `[]` override).
import Testing
import Swiflow
@testable import SwiflowQuery

@MainActor private final class DIDummy: Component { var body: VNode { .text("") } }

private struct ListKey: Query {
    var queryKey: QueryKey { ["list"] }
    func fetch() async throws -> [Int] { [] }
}
private struct DetailKey: Query {
    let id: Int
    var queryKey: QueryKey { ["detail", .int(id)] }
    func fetch() async throws -> Int { 0 }
}

/// Optimistic edits, NO `invalidations` override — the shape that used to trap.
private struct DerivedMut: Mutation {
    func perform(_ x: Int) async throws -> Int { x }
    func optimistic(_ x: Int) -> [OptimisticEdit] {
        [.update(ListKey()) { (old: [Int]?) in (old ?? []) + [x] },
         .update(DetailKey(id: x)) { (old: Int?) in x },
         // A second edit on ["list"] — the derived default must dedup it, or
         // the duplicate invalidation cancel-respawns the repair fetch.
         .update(ListKey()) { (old: [Int]?) in old ?? [] }]
    }
}

/// An explicit override — must win over the derived default.
private struct OverrideMut: Mutation {
    func perform(_ x: Int) async throws -> Int { x }
    func optimistic(_ x: Int) -> [OptimisticEdit] {
        [.update(ListKey()) { (old: [Int]?) in old ?? [] }]
    }
    func invalidations(input: Int, output: Int) -> [Invalidation] { [.tag("custom")] }
}

/// No optimistic edits at all — the derived default must stay empty.
private struct PlainMut: Mutation {
    func perform(_ x: Int) async throws -> Int { x }
}

@Suite("Mutation/default invalidations")
@MainActor
struct DefaultInvalidationsTests {
    @Test("the default derives .exact per declared optimistic key, deduped, in declaration order")
    func defaultDerivesDedupedExactKeys() {
        let inv = DerivedMut().invalidations(input: 7, output: 7)
        #expect(inv == [.exact(["list"]), .exact(["detail", .int(7)])])
    }

    @Test("declared-but-skipped edits still contribute their key (derive from declarations, not the rollback stack)")
    func skippedEditsStillContributeTheirKey() {
        // Nothing is cached for either key here, so at apply time BOTH edits
        // would `.noValue`-skip and the rollback stack would be empty. The
        // derived default must come from the DECLARATIONS — a skipped edit's
        // key still needs its refetch, or the server value never lands
        // (deriving from rollback would silently lose exactly these).
        let inv = DerivedMut().invalidations(input: 3, output: 3)
        #expect(inv.count == 2)
        #expect(inv.first == .exact(["list"]))
    }

    @Test("an explicit override wins over the derived default")
    func explicitOverrideWins() {
        #expect(OverrideMut().invalidations(input: 1, output: 1) == [.tag("custom")])
    }

    @Test("no optimistic edits → the derived default is empty")
    func noOptimisticMeansNoDerivedInvalidations() {
        #expect(PlainMut().invalidations(input: 1, output: 1).isEmpty)
    }

    @Test("end-to-end: an optimistic mutation with no override reconciles via the derived refetch")
    func endToEndReconciliation() async {
        let client = QueryClient(clock: ManualClock())
        let owner = AnyComponent(DIDummy())
        var fetches = 0
        client.reconcile(owner: owner, scheduler: SyncScheduler { _ in }, observations: [
            QueryClient.QueryObservation(
                key: ["list"], tags: [], staleTime: .seconds(9999),
                refetchInterval: nil, refetchOnFocus: false, retry: .none,
                boxedFetch: { fetches += 1; return [100] })
        ])
        for t in client.inFlightTasks() { await t.value }
        #expect(fetches == 1)
        #expect(client.getQueryData(["list"], as: [Int].self) == [100])

        let rt = MutationRuntime<DerivedMut>()
        rt.wire(owner: owner, scheduler: SyncScheduler { _ in }, client: client)
        MutationHandle(runtime: rt, mutation: DerivedMut()).mutate(7)
        // Optimistic write is visible immediately…
        #expect(client.getQueryData(["list"], as: [Int].self) == [100, 7])
        for t in client.inFlightTasks() { await t.value }

        // …and the DERIVED invalidation refetched ["list"] on success, exactly
        // once (dedup), replacing the guess with server truth.
        #expect(fetches == 2, "the derived .exact([\"list\"]) invalidation must trigger one repair refetch")
        #expect(client.getQueryData(["list"], as: [Int].self) == [100])
        _ = owner   // retain through settle
    }
}
