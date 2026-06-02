// Sources/SwiflowQuery/InFlightRegistry.swift

/// Tracks fire-and-forget driving tasks so the async test harness can await
/// "everything still in flight" through `QueryClient.inFlightTasks()`.
///
/// One responsibility — task lifecycle, not cached values — so it lives apart
/// from `QueryClient`, which is about the query cache. Mirrors the in-flight
/// registry `SwiflowTaskRuntime` keeps in the core module. Tasks self-remove on
/// completion, keyed by an opaque token (NOT an index — index removal would
/// race a concurrent removal).
@MainActor
final class InFlightRegistry {
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var nextToken = 0

    /// Spawn `work` as a tracked task that removes itself from the registry when
    /// it completes. The registry owns the task's lifetime.
    func track(_ work: @escaping () async -> Void) {
        let token = nextToken
        nextToken += 1
        tasks[token] = Task { [weak self] in
            await work()
            self?.tasks[token] = nil
        }
    }

    /// Every task still running, for the harness to await.
    func current() -> [Task<Void, Never>] { Array(tasks.values) }
}
