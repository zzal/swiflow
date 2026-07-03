// Tests/SwiflowQueryTests/MutationIntegrationTests.swift
import Testing
import Swiflow
import SwiflowTesting
@testable import SwiflowQuery

// MARK: - Shared helpers

@MainActor private final class DummyComponent: Component { var body: VNode { .text("") } }

// MARK: - Shared gate for this file

/// A deterministic latch so a test can observe state mid-flight.
/// `open()` before `wait()` is safe — `wait()` returns immediately.
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

// MARK: - Shared query / mutation types

@MainActor private struct TodoList: Query {
    let load: @MainActor @Sendable () -> [String]
    var queryKey: QueryKey { ["todos"] }
    var staleTime: Duration { .seconds(9999) }
    func fetch() async throws -> [String] { load() }
}

private enum Boom: Error { case nope }

/// Mutation with optional gate so the test can park `perform` mid-flight.
@MainActor private struct AddTodo: Mutation {
    let gate: Gate?
    let outcome: @MainActor @Sendable (String) async throws -> String
    func perform(_ title: String) async throws -> String {
        if let g = gate { await g.wait() }
        return try await outcome(title)
    }
    func optimistic(_ title: String) -> [OptimisticEdit] {
        [.update(TodoList(load: { [] })) { $0 + ["draft:\(title)"] }]
    }
    func invalidations(input: String, output: String) -> [Invalidation] { [.prefix(["todos"])] }
}

// MARK: - Components

// A component that DOES reference $add in body — the normal pattern.
@Component private final class Board {
    let load: @MainActor @Sendable () -> [String]
    @MutationState var add: AddTodo
    init(
        load: @escaping @MainActor @Sendable () -> [String],
        outcome: @escaping @MainActor @Sendable (String) async throws -> String,
        gate: Gate? = nil
    ) {
        self.load = load
        self.add = AddTodo(gate: gate, outcome: outcome)
    }
    var body: VNode {
        let todos = query(TodoList(load: load))
        return div {
            for t in todos.data ?? [] { p(t) }
            button("Add",
                   .attr("disabled", $add.isPending),
                   .on(.click) { self.$add.mutate("x") })
        }
    }
}

// A component that NEVER references $add in body — the B1 regression case.
@Component private final class FireOnly {
    @MutationState var add: AddTodo
    init(outcome: @escaping @MainActor @Sendable (String) async throws -> String) {
        self.add = AddTodo(gate: nil, outcome: outcome)
    }
    var body: VNode { div { p("static") } }   // never reads $add
}

// COMPILE-ONLY GATE for the @MutationState half of the bare-@Component isolation
// fix (companion to Tests/SwiflowTests/.../BareComponentIsolationTests.swift,
// which covers @State + @ReducerState). NO explicit @MainActor here: if the
// @MutationState peer outputs (`_add_mutationRuntime`, `$add`) are not
// main-actor, this reference to `$add.isPending` from the (now @MainActor)
// body fails to type-check and this test target fails to BUILD. `init` is
// user-written, so no init is synthesized; the memberAttribute role stamps it.
@Component private final class BareMutationComp {
    @MutationState var add: AddTodo
    init(outcome: @escaping @MainActor @Sendable (String) async throws -> String) {
        self.add = AddTodo(gate: nil, outcome: outcome)
    }
    var body: VNode { div { p($add.isPending ? "pending" : "idle") } }
}

// MARK: - Tests

@Suite("Mutation/integration")
@MainActor
struct MutationIntegrationTests {

    // After an optimistic append, on success the list should contain the real
    // server value (not the draft) once the invalidation refetch settles.
    @Test("On success the invalidation refetch replaces the optimistic draft with server truth") func optimisticThenInvalidationReconciles() async throws {
        var server = ["a"]
        let h = AsyncTestHarness(
            Board(load: { server }, outcome: { title in server.append(title); return title }),
            clock: ManualClock())
        try await h.settle()
        #expect(h.allText.contains("a"))

        h.click("button")              // fires $add.mutate("x")
        try await h.settle()
        // Optimistic draft was replaced by the server truth after invalidation refetch.
        #expect(h.allText.contains("x"))
        #expect(!h.allText.contains("draft:x"))
    }

    // On failure the optimistic entry is rolled back; the prior list is preserved.
    @Test("On failure the optimistic draft rolls back and the prior list is preserved") func rollbackOnFailureKeepsPriorList() async throws {
        let h = AsyncTestHarness(
            Board(load: { ["a"] }, outcome: { _ in throw Boom.nope }),
            clock: ManualClock())
        try await h.settle()
        h.click("button")
        try await h.settle()
        #expect(h.allText.contains("a"))
        #expect(!h.allText.contains("draft:x"))   // rolled back
    }

    // B1: a component whose body NEVER reads $add still has its MutationRuntime
    // wired at mount (because @Component.bind() always fires at wireState time,
    // regardless of body content). This means the very first mutate — with no
    // prior re-render — correctly invalidates the shared query client.
    @Test("@MutationState is wired at mount even when body never reads the handle, so the first mutate invalidates") func mountWiresClientEvenWithoutBodyReference() async throws {
        var fetches = 0

        // Mount a Board so ["todos"] has a live observer on the shared client.
        let board = Board(load: { fetches += 1; return ["a"] }, outcome: { $0 })
        let h = AsyncTestHarness(board, clock: ManualClock())
        try await h.settle()
        #expect(fetches == 1)

        // Mount FireOnly on the SAME client. Its @MutationState is wired at
        // mount even though body never references $add.
        let fire = FireOnly(outcome: { $0 })
        let fireHarness = AsyncTestHarness(fire, queryClient: h.queryClient)

        // First mutate with NO prior re-render of FireOnly — relies on mount wiring.
        fire.$add.mutate("z")
        try await fireHarness.settle()
        try await h.settle()

        // The invalidation from FireOnly's success should have triggered a
        // re-fetch of ["todos"], bumping the counter from 1 → 2.
        #expect(fetches == 2)
        _ = fireHarness   // retain
    }

    // §10 reset() contract: reset() returns published state to .idle immediately,
    // but does NOT cancel the in-flight perform. The outstanding task still
    // completes and applies its success/invalidation side-effects.
    //
    // Approach: wire a MutationRuntime directly (as in MutationOptimismTests) so
    // we fully control the gate and the live observer's fetch closure. The Board
    // component's query reconcile would overwrite the entry's boxedFetch, making
    // fetch counting unreliable, so we use the lower-level wired-runtime pattern.
    @Test("reset() returns state to .idle but the in-flight perform still completes and invalidates") func resetDoesNotCancelInFlightPerform() async throws {
        let client = QueryClient(clock: ManualClock())

        // Seed ["todos"] with a live observer that counts fetches.
        let observer = AnyComponent(DummyComponent())
        var fetches = 0
        client.reconcile(
            owner: observer,
            scheduler: SyncScheduler { _ in },
            observations: [QueryClient.QueryObservation(
                key: ["todos"], tags: [], staleTime: .seconds(9999),
                refetchInterval: nil, refetchOnFocus: true, retry: .default,
                boxedFetch: { fetches += 1; return ["a"] },
                valuesEqual: { ($0 as? [String]) == ($1 as? [String]) })])
        for t in client.inFlightTasks() { await t.value }
        #expect(fetches == 1)
        _ = observer   // retain the weak reference in QueryClient

        // Wire a MutationRuntime manually (same as MutationOptimismTests).
        let rt = MutationRuntime<AddTodo>()
        rt.wire(
            owner: AnyComponent(DummyComponent()),
            scheduler: SyncScheduler { _ in },
            client: client)

        // Gate the perform so we can call reset() while it's in-flight.
        let gate = Gate()
        let mutation = AddTodo(gate: gate, outcome: { title in title })
        let handle = MutationHandle(runtime: rt, mutation: mutation)

        // Trigger mutate — perform parks on the gate; optimism applied synchronously.
        handle.mutate("z")
        // status is immediately .pending (set in beginOptimistic before the task yields).
        #expect(rt.status == .pending)

        // reset() returns state to .idle. The spawned task still lives.
        handle.reset()
        #expect(rt.status == .idle)

        // Unpark the perform — it completes and fires .prefix(["todos"]) invalidation.
        gate.open()
        for t in client.inFlightTasks() { await t.value }

        // The invalidation must have triggered a refetch of the live observer.
        #expect(fetches == 2)   // initial + 1 post-success invalidation
        _ = observer            // retain through end of test
    }
}
