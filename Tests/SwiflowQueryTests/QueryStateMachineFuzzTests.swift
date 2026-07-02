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

    @Test("randomized op sequences converge to server truth")
    func randomizedConverges() async {
        let baseSeed: UInt64 = 0xDEAD_BEEF_CAFE_F00D
        let sequences = 200
        let opsPerSequence = 40
        let listIDs = [1, 2, 3]   // enough for prefix/tag fan-out

        for seq in 0..<sequences {
            var rng = SplitMix64(seed: baseSeed &+ UInt64(seq))
            let w = FuzzWorld()
            var trace: [String] = []
            // Subscribe all list IDs upfront so every mutation targets a cached
            // key (OptimisticEdit.update requires a cache entry to transform).
            for lid in listIDs { w.subscribe(lid); trace.append("subscribe \(lid)") }
            await w.settle()

            for _ in 0..<opsPerSequence {
                let id = listIDs.randomElement(using: &rng)!
                let pick = Int.random(in: 0..<7, using: &rng)
                switch pick {
                case 0:
                    w.subscribe(id); trace.append("subscribe \(id)")
                case 1:
                    let v = Int.random(in: 1...999, using: &rng)
                    w.mutate(AppendMut(id: id, model: w.model), v); trace.append("append \(id) \(v)")
                case 2:
                    w.mutate(RemoveLastMut(id: id, model: w.model), 0); trace.append("removeLast \(id)")
                case 3:
                    let v = Int.random(in: 1...999, using: &rng)
                    w.mutate(FailAppendMut(id: id, model: w.model), v); trace.append("failAppend \(id) \(v)")
                case 4:
                    let exact = Bool.random(using: &rng)
                    if exact { w.client.invalidate(ServerModel.key(id), exact: true); trace.append("invalidate.exact \(id)") }
                    else { w.client.invalidate(["list"], exact: false); trace.append("invalidate.prefix") }
                case 5:
                    w.client.invalidate(tag: "lists"); trace.append("invalidate.tag lists")
                case 6:
                    w.clock.advance(by: .seconds(6)); w.client.tick(now: w.clock.now()); trace.append("tick +6s")
                default: break
                }
                await w.settle()
                w.assertConverged("seq=\(seq) seed=\(baseSeed &+ UInt64(seq)) trace=\(trace)")
            }
        }
    }

    @Test("a failed, non-superseded mutation rolls back to the exact prior value")
    func rollbackExactness() async {
        let w = FuzzWorld()
        w.subscribe(1); await w.settle()
        w.mutate(AppendMut(id: 1, model: w.model), 7); await w.settle()
        let before = w.client.getQueryDataErased(ServerModel.key(1)) as? [Int]
        #expect(before == [7])

        w.mutate(FailAppendMut(id: 1, model: w.model), 999); await w.settle()
        let after = w.client.getQueryDataErased(ServerModel.key(1)) as? [Int]
        #expect(after == [7], "failed mutation must restore the exact prior value")
        #expect(w.model.value(1) == [7])   // truth never changed
    }

    @Test("invalidate supersedes the prior generation; the refetched truth wins")
    func generationSupersedeWins() async {
        let w = FuzzWorld()
        w.model.lists[1] = [1]
        w.subscribe(1); await w.settle()
        #expect(w.client.getQueryDataErased(ServerModel.key(1)) as? [Int] == [1])
        // Truth moves on, then an exact invalidate bumps the generation and
        // refetches; the newer truth must win (and any prior in-flight result is
        // dropped by commitFetch's generation guard).
        w.model.lists[1] = [1, 2]
        w.client.invalidate(ServerModel.key(1), exact: true)
        await w.settle()
        #expect(w.client.getQueryDataErased(ServerModel.key(1)) as? [Int] == [1, 2])
    }

    @Test("a stale in-flight fetch from an older generation never clobbers a newer commit")
    func staleInFlightFetchDropped() async {
        // Stresses commitFetch's generation guard, which the steady-state
        // convergence fuzz cannot reach: settle() drains each op before the next,
        // so a prior-generation fetch can never arrive late. Here we deliberately
        // interleave — park fetch #1 (carrying a stale snapshot), let an
        // invalidate-driven fetch #2 commit the fresh value, THEN release fetch #1
        // and assert it is dropped rather than clobbering the newer value.
        let model = ServerModel()
        model.lists[1] = [1]
        let client = QueryClient(clock: ManualClock())
        let owner = AnyComponent(FuzzSubscriber())
        let gate = FetchGate()
        var callCount = 0
        var fetch1Resumed = false

        client.reconcile(owner: owner, scheduler: SyncScheduler { _ in }, observations: [
            QueryClient.QueryObservation(
                key: ServerModel.key(1), tags: ["lists"], staleTime: .zero,
                refetchInterval: nil, refetchOnFocus: true, retry: .none,
                boxedFetch: {
                    callCount += 1
                    if callCount == 1 {
                        let snapshot = model.value(1)   // captures the OLD truth [1]
                        await gate.wait()               // park fetch #1 until released
                        fetch1Resumed = true
                        return snapshot                  // resolves stale [1] late, under the OLD generation
                    }
                    return model.value(1)               // fetch #2 reads the FRESH truth
                },
                valuesEqual: { ($0 as? [Int]) == ($1 as? [Int]) })
        ])

        // Let fetch #1 enter boxedFetch (and park on the gate).
        while callCount < 1 { await Task.yield() }

        // Truth advances; an exact invalidate bumps the generation and starts
        // fetch #2 (not gated).
        model.lists[1] = [1, 2]
        client.invalidate(ServerModel.key(1), exact: true)

        // Wait for fetch #2 to commit the fresh value under the NEW generation.
        while (client.getQueryDataErased(ServerModel.key(1)) as? [Int]) != [1, 2] { await Task.yield() }

        // Release the stale fetch #1 and let its commitFetch run.
        gate.open()
        while !fetch1Resumed { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }

        // The generation guard must have dropped the stale [1]; [1,2] stands.
        #expect(client.getQueryDataErased(ServerModel.key(1)) as? [Int] == [1, 2],
                "a superseded (older-generation) fetch must not clobber the newer committed value")
    }

    @Test("optimistic edit on an unsubscribed query skips silently (no trap, no diagnostic)")
    func optimisticNoValueSkipsSilently() async {
        await DiagnosticOverrideLock.shared.acquire()
        defer { DiagnosticOverrideLock.shared.release() }
        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        let w = FuzzWorld()
        // id 7 is never subscribed → its query holds no cached value → .noValue.
        w.mutate(AppendMut(id: 7, model: w.model), 42)
        await w.settle()

        // Silent skip: no "no cached value" diagnostic is emitted (before the fix,
        // this string was passed to swiflowDiagnostic, which traps in DEBUG).
        #expect(!captured.contains { $0.contains("no cached value") })
        // The mutation's perform still ran and reconciled the server truth.
        #expect(w.model.value(7) == [42])
    }
}

/// One-shot gate to deterministically park an async fetch until released.
@MainActor private final class FetchGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}
