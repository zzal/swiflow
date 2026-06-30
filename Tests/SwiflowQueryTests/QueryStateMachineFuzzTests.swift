// Tests/SwiflowQueryTests/QueryStateMachineFuzzTests.swift
//
// Deterministic property/fuzz suite for the SwiflowQuery cache state machine.
// Drives a real QueryClient + MutationRuntime through op sequences and asserts
// the cache converges to a server-truth oracle at quiescence.
import Testing
import Swiflow
@testable import SwiflowQuery

// MARK: - Seeded PRNG (SplitMix64) — reproducible; Swift has no shrinking, so
// failures print seed + trace and a regression test pins the trace.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@MainActor private final class FuzzSubscriber: Component { var body: VNode { .text("") } }

// MARK: - Server-truth oracle. The cache must converge to `lists` at quiescence.
@MainActor private final class ServerModel {
    var lists: [Int: [Int]] = [:]
    func value(_ id: Int) -> [Int] { lists[id] ?? [] }
    static func key(_ id: Int) -> QueryKey { ["list", .int(id)] }
}

// MARK: - Test query/mutations (plain conformances; no macros).
private struct ListQuery: Query {
    let id: Int
    let model: ServerModel
    var queryKey: QueryKey { ServerModel.key(id) }
    var tags: Set<QueryTag> { ["lists"] }
    func fetch() async throws -> [Int] { model.value(id) }
}

private struct AppendMut: Mutation {
    let id: Int; let model: ServerModel
    func perform(_ v: Int) async throws -> Int { model.lists[id, default: []].append(v); return v }
    func optimistic(_ v: Int) -> [OptimisticEdit] { [.update(ListQuery(id: id, model: model)) { $0 + [v] }] }
    func invalidations(input: Int, output: Int) -> [Invalidation] { [.exact(ServerModel.key(id))] }
}

private struct RemoveLastMut: Mutation {
    let id: Int; let model: ServerModel
    func perform(_ ignored: Int) async throws -> Int {
        if !(model.lists[id]?.isEmpty ?? true) { model.lists[id]!.removeLast() }
        return 0
    }
    func optimistic(_ ignored: Int) -> [OptimisticEdit] {
        [.update(ListQuery(id: id, model: model)) { $0.isEmpty ? $0 : Array($0.dropLast()) }]
    }
    func invalidations(input: Int, output: Int) -> [Invalidation] { [.exact(ServerModel.key(id))] }
}

private struct FailAppendMut: Mutation {
    struct Boom: Error {}
    let id: Int; let model: ServerModel
    func perform(_ v: Int) async throws -> Int { throw Boom() }   // never mutates truth
    func optimistic(_ v: Int) -> [OptimisticEdit] { [.update(ListQuery(id: id, model: model)) { $0 + [v] }] }
    // no invalidations — it fails
}

// MARK: - The world: a QueryClient + clock + model + helpers.
@MainActor private final class MarkCounter { var n = 0 }

@MainActor private final class FuzzWorld {
    let model = ServerModel()
    let clock = ManualClock()
    let client: QueryClient
    let scheduler: SyncScheduler
    let owner = AnyComponent(FuzzSubscriber())
    private let markCounter = MarkCounter()
    private(set) var subscribed: Set<Int> = []

    init() {
        let counter = markCounter
        self.scheduler = SyncScheduler { _ in counter.n += 1 }
        self.client = QueryClient(clock: clock)
    }
    func currentMarks() -> Int { markCounter.n }

    // Accumulated observations: reconcile() REPLACES an owner's observation set
    // (dropped keys are unsubscribed), so every subscribe re-sends the FULL set.
    private var observations: [Int: QueryClient.QueryObservation] = [:]
    func subscribe(_ id: Int) {
        guard observations[id] == nil else { return }
        let model = self.model
        observations[id] = QueryClient.QueryObservation(
            key: ServerModel.key(id), tags: ["lists"], staleTime: .zero,
            refetchInterval: .seconds(5), refetchOnFocus: true, retry: .none,
            boxedFetch: { model.value(id) },
            valuesEqual: { ($0 as? [Int]) == ($1 as? [Int]) })
        subscribed.insert(id)
        client.reconcile(owner: owner, scheduler: scheduler, observations: Array(observations.values))
    }

    func mutate<M: Mutation>(_ m: M, _ input: M.Input) {
        let rt = MutationRuntime<M>()
        rt.wire(owner: owner, scheduler: scheduler, client: client)
        MutationHandle(runtime: rt, mutation: m).mutate(input)
    }

    /// Drain every in-flight fetch + mutation, repeatedly (a mutation's success
    /// fires an invalidation → a refetch → a new in-flight task). Bounded.
    func settle() async {
        for _ in 0..<200 {
            let tasks = client.inFlightTasks()
            if tasks.isEmpty {
                scheduler.flush()   // run queued markDirty callbacks so currentMarks() is meaningful
                return
            }
            for t in tasks { await t.value }
        }
        Issue.record("settle() did not quiesce within 200 drains")
    }

    /// Assert every subscribed key's cached value equals the server truth.
    func assertConverged(_ ctx: @autoclosure () -> String) {
        for id in subscribed {
            let cached = client.getQueryDataErased(ServerModel.key(id)) as? [Int]
            #expect(cached == model.value(id), "convergence failed for list \(id): cache=\(cached ?? []) truth=\(model.value(id)) — \(ctx())")
        }
    }
}

@Suite("Query state machine — fuzz")
@MainActor
struct QueryStateMachineFuzzTests {

    @Test("scripted sequence converges (harness smoke test)")
    func scriptedConverges() async {
        let w = FuzzWorld()
        w.subscribe(1); await w.settle()
        let marksBefore = w.currentMarks()
        w.mutate(AppendMut(id: 1, model: w.model), 10); await w.settle()
        #expect(w.currentMarks() > marksBefore)   // notification invariant: a commit marked the subscriber dirty
        w.mutate(AppendMut(id: 1, model: w.model), 20); await w.settle()
        w.mutate(FailAppendMut(id: 1, model: w.model), 99); await w.settle()   // optimistic then rollback
        w.mutate(RemoveLastMut(id: 1, model: w.model), 0); await w.settle()
        w.client.invalidate(["list"], exact: false); await w.settle()
        w.assertConverged("scripted")
        #expect(w.model.value(1) == [10])   // 10,20 appended; 99 rolled back; 20 removed
    }
}
