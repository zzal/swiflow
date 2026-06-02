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

    func reset() {
        status = .idle; data = nil; error = nil
        markDirty()
    }

    /// The single engine path: drives published state (pending → success/error,
    /// optimism + rollback + invalidation) and reports the outcome. NEVER throws
    /// — returns a `Result` so `.error` is set in exactly one place and
    /// `mutateAsync` rethrows the same stored error.
    func run(_ input: M.Input, _ mutation: M) async -> Result<M.Output, any Error> {
        guard let client else {
            // B1 guarantees mount-time wiring; this path is a hand-rolled /
            // direct-construction safety net. Loud in DEBUG, degraded (no
            // optimism/invalidation) in release — never a silently-wrong write.
            assertionFailure("MutationRuntime.run: no QueryClient wired (was the component mounted through the renderer?)")
            return await performOnly(input, mutation)
        }

        // 1. Optimism: snapshot prior, apply, stash for rollback.
        var rollback: [(key: QueryKey, prior: Any?)] = []
        for edit in mutation.optimistic(input) {
            let prior = client.getQueryDataErased(edit.key)
            if let next = edit.apply(prior) {
                client.setQueryData(edit.key, next)
                rollback.append((edit.key, prior))
            } else {
                #if DEBUG
                swiflowDiagnostic("OptimisticEdit.update: no cache entry for key \(edit.key) — edit skipped.")
                #endif
            }
        }

        // 2. Pending (synchronous, before the first suspension).
        status = .pending; markDirty()

        // 3. Perform.
        let result: Result<M.Output, any Error>
        do { result = .success(try await mutation.perform(input)) }
        catch { result = .failure(error) }

        // 4–6.
        switch result {
        case .success(let out):
            status = .success; data = out
            for inv in mutation.invalidations(input: input, output: out) { dispatch(inv, client) }
        case .failure(let err):
            for r in rollback.reversed() { client.setQueryData(r.key, r.prior) }
            status = .error; error = err
        }
        markDirty()
        return result
    }

    private func performOnly(_ input: M.Input, _ mutation: M) async -> Result<M.Output, any Error> {
        status = .pending; markDirty()
        let result: Result<M.Output, any Error>
        do { result = .success(try await mutation.perform(input)) }
        catch { result = .failure(error) }
        switch result {
        case .success(let out): status = .success; data = out
        case .failure(let err): status = .error; error = err
        }
        markDirty()
        return result
    }

    private func dispatch(_ inv: Invalidation, _ client: QueryClient) {
        switch inv {
        case .prefix(let k): client.invalidate(k, exact: false)
        case .exact(let k):  client.invalidate(k, exact: true)
        case .tag(let t):    client.invalidate(tag: t)
        }
    }

    /// Register a fire-and-forget driving task with the client so `settle()`
    /// awaits it; the task self-removes by token on completion.
    func register(_ work: @escaping () async -> Void) {
        guard let client else { Task { await work() }; return }
        let token = client.nextMutationTaskToken()
        let task = Task<Void, Never> {
            await work()
            client.removeMutationTask(token)
        }
        client.storeMutationTask(token, task)
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

    /// Fire-and-forget — the UI reacts through the published state.
    public func mutate(_ input: M.Input) {
        let rt = runtime, m = mutation
        rt.register { _ = await rt.run(input, m) }
    }

    /// Awaitable — for sequencing side effects at the call site.
    public func mutateAsync(_ input: M.Input) async throws -> M.Output {
        let rt = runtime, m = mutation
        let task = Task { await rt.run(input, m) }   // typed result
        rt.register { _ = await task.value }          // Void wrapper registered for settle()
        switch await task.value {
        case .success(let out): return out
        case .failure(let err): throw err
        }
    }

    public func reset() { runtime.reset() }
}
