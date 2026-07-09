// Sources/SwiflowQuery/MutationState.swift
import Swiflow

public enum MutationStatus: Sendable { case idle, pending, success, error }

/// Reads the render-active `QueryClient` from the package-internal
/// `RenderObserverBox`. PUBLIC so `@Component`-emitted code in a user module
/// (which cannot reach the `package` box itself) can call it; the actual box
/// access happens here, inside the SwiflowQuery/Swiflow package.
@MainActor
public func _currentRenderQueryClient() -> QueryClient? {
    RenderObserverBox.current as? QueryClient
}

/// One optimistic write's undo record. Captures the written entry's IDENTITY
/// (weakly) alongside the post-write generation: the rollback guard mirrors
/// `commitFetch`'s double guard, because an evicted-then-recycled entry shares
/// the key and — fresh entries restart at generation 0 — can climb back to the
/// recorded generation while a slow mutation is still in flight. Generation
/// alone would let that rollback resurrect the previous incarnation's snapshot
/// into the recycled entry (clobbering newer truth and cancelling its
/// in-flight fetch); identity can never be forged by recycling.
struct OptimisticRollback {
    let key: QueryKey
    let prior: Any?
    let gen: Int?
    weak var entry: QueryEntry?
}

/// Persistent, per-component reactive state for one `@MutationState`. A class so
/// it survives across renders with the component instance. Wired once at mount
/// by `@Component`'s `bind` (§8).
@MainActor
public final class MutationRuntime<M: Mutation> {
    private(set) var status: MutationStatus = .idle
    private(set) var data: M.Output?
    private(set) var error: (any Error)?

    private weak var owner: AnyComponent?
    private var scheduler: (any Scheduler)?
    private weak var client: QueryClient?

    public init() {}

    /// Injected at mount. `client` is only overwritten with a non-nil value.
    public func wire(owner: AnyComponent, scheduler: any Scheduler, client: QueryClient?) {
        self.owner = owner
        self.scheduler = scheduler
        if let client { self.client = client }
    }

    private func markDirty() {
        if let owner, let scheduler { scheduler.markDirty(owner) }
    }

    /// Bumped by `reset()`: an in-flight `finish` compares the epoch it was
    /// spawned under and, when superseded, skips the LOCAL state writes — the
    /// handle stays `.idle` — while its CACHE effects (success invalidations,
    /// failure rollback) still run: cache correctness is independent of
    /// whether anyone is still watching this handle. Mirrors the query
    /// cache's generation guard.
    private(set) var epoch = 0

    func reset() {
        epoch += 1
        status = .idle; data = nil; error = nil
        markDirty()
    }

    /// Synchronous prologue, run on the caller's tick (inside `mutate` /
    /// `mutateAsync`, NOT inside the spawned task): apply the optimistic cache
    /// edits and enter `.pending`. Returning here means the cache + status
    /// reflect the optimistic update immediately — synchronous code after
    /// `mutate` sees it, and the next render shows it without a microtask gap.
    ///
    /// Returns the rollback stack (prior values, in apply order) for `finish`
    /// to restore on failure. The stack is local to one mutation call, so
    /// concurrent mutations never share rollback state.
    func beginOptimistic(_ input: M.Input, _ mutation: M) -> [OptimisticRollback] {
        var rollback: [OptimisticRollback] = []
        if let client {
            for edit in mutation.optimistic(input) {
                let prior = client.getQueryDataErased(edit.key)
                switch edit.apply(prior) {
                case .write(let next):
                    client.setQueryData(edit.key, next)
                    // Record the post-write generation AND the entry's identity
                    // so `finish` can detect whether a LATER write superseded
                    // this key — or the entry itself was evicted and recycled —
                    // before rolling back (which would otherwise clobber the
                    // newer value and cancel its repair fetch).
                    rollback.append(OptimisticRollback(
                        key: edit.key, prior: prior,
                        gen: client.generation(of: edit.key),
                        entry: client.liveEntry(edit.key)))
                case .noValue:
                    // The query isn't loaded yet — there is nothing to optimistically
                    // transform. Skip this optimistic layer silently (per
                    // OptimisticEdit's .noValue contract: "skipped silently"); the
                    // mutation's perform() and the post-success invalidation/refetch
                    // reconcile the cache. (Previously this trapped via swiflowDiagnostic.)
                    break
                case .typeMismatch(let expected, let actual):
                    // Never intentional: the edit targets the wrong query. Trap
                    // in DEBUG; degrade to a skipped edit in release (the write
                    // still runs in `finish`).
                    assertionFailure(
                        "OptimisticEdit.update: type mismatch for key \(edit.key) — expected a cached value of type \(expected) but found \(actual). The optimistic edit targets the wrong query; edit skipped.")
                }
            }
        } else {
            // B1 guarantees mount-time wiring; this is a hand-rolled /
            // direct-construction safety net. Loud in DEBUG, degraded in
            // release — the write still runs (in `finish`); only optimism and
            // invalidation are skipped. Never a silently-wrong write.
            assertionFailure("MutationRuntime: no QueryClient wired. Either the enclosing class is missing @Component (which wires @MutationState at mount), or the component wasn't mounted through the renderer.")
        }
        status = .pending; markDirty()
        return rollback
    }

    /// Async remainder: run `perform`, then on success set `data` + invalidate,
    /// or on failure roll back `rollback` and surface the error. NEVER throws —
    /// returns a `Result` so `.error` is set in exactly one place and
    /// `mutateAsync` rethrows the same stored error.
    func finish(_ input: M.Input, _ mutation: M,
                _ rollback: [OptimisticRollback],
                epoch startEpoch: Int) async -> Result<M.Output, any Error> {
        let result: Result<M.Output, any Error>
        do { result = .success(try await mutation.perform(input)) }
        catch { result = .failure(error) }

        // `reset()` during the await detaches this mutation from the handle:
        // local state stays wherever reset put it. Cache effects below run
        // regardless — a detached failure must still roll back its optimistic
        // edit, and a detached success must still invalidate.
        let detached = startEpoch != epoch

        switch result {
        case .success(let out):
            if !detached { status = .success; data = out }
            if let client {
                // No optimistic-without-invalidations diagnostic here anymore:
                // the default `invalidations` derives from `optimistic(_:)`'s
                // declared keys, so the "cache keeps the guess forever" misuse
                // is inexpressible unless deliberately opted into (an explicit
                // `[]` override).
                for inv in mutation.invalidations(input: input, output: out) {
                    dispatch(inv, client)
                }
            }
        case .failure(let err):
            if let client {
                for r in rollback.reversed() {
                    // Double guard, mirroring commitFetch (identity first, then
                    // generation): the live entry must BE the instance the
                    // optimistic write touched — an evicted-then-recycled entry
                    // shares the key and, since fresh entries restart at
                    // generation 0, can even reach the same generation — AND
                    // nothing may have superseded the key since our write. If
                    // either fails, a newer owner holds the value; rolling back
                    // would clobber it (and cancel its in-flight fetch), so we
                    // skip.
                    if let live = client.liveEntry(r.key), live === r.entry,
                       client.generation(of: r.key) == r.gen {
                        client.setQueryData(r.key, r.prior)
                    }
                }
            }
            if !detached { status = .error; error = err }
        }
        if !detached { markDirty() }
        return result
    }

    private func dispatch(_ inv: Invalidation, _ client: QueryClient) {
        switch inv {
        case .prefix(let k): client.invalidate(k, exact: false)
        case .exact(let k):  client.invalidate(k, exact: true)
        case .tag(let t):    client.invalidate(tag: t)
        }
    }

    /// Register a fire-and-forget driving task with the client's in-flight
    /// registry so `settle()` awaits it; the task self-removes on completion.
    func register(_ work: @escaping () async -> Void) {
        guard let client else { Task { await work() }; return }
        client.inFlightMutations.track(work)
    }
}

/// The `$`-projection a component uses to trigger and observe a mutation. A
/// lightweight value over the persistent runtime plus a snapshot of the current
/// `Mutation` definition (so a reassigned `create` is picked up).
@MainActor
public struct MutationHandle<M: Mutation> {
    let runtime: MutationRuntime<M>
    let mutation: M

    public init(runtime: MutationRuntime<M>, mutation: M) {
        self.runtime = runtime
        self.mutation = mutation
    }

    public var isIdle: Bool { runtime.status == .idle }
    public var isPending: Bool { runtime.status == .pending }
    public var isSuccess: Bool { runtime.status == .success }
    public var isError: Bool { runtime.status == .error }
    public var data: M.Output? { runtime.data }
    public var error: (any Error)? { runtime.error }

    /// Fire-and-forget — the UI reacts through the published state. Optimism +
    /// `.pending` are applied synchronously here; only `perform` + resolution
    /// run in the spawned task.
    public func mutate(_ input: M.Input) {
        let rt = runtime, m = mutation
        let rollback = rt.beginOptimistic(input, m)        // synchronous: optimism + pending
        let epoch = rt.epoch
        rt.register { _ = await rt.finish(input, m, rollback, epoch: epoch) }
    }

    /// Awaitable — for sequencing side effects at the call site. Optimism +
    /// `.pending` apply synchronously before the `await`.
    public func mutateAsync(_ input: M.Input) async throws -> M.Output {
        let rt = runtime, m = mutation
        let rollback = rt.beginOptimistic(input, m)        // synchronous: optimism + pending
        let epoch = rt.epoch
        let task = Task { await rt.finish(input, m, rollback, epoch: epoch) }   // typed result
        rt.register { _ = await task.value }                       // Void wrapper for settle()
        switch await task.value {
        case .success(let out): return out
        case .failure(let err): throw err
        }
    }

    public func reset() { runtime.reset() }
}
