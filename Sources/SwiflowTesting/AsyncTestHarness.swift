// Sources/SwiflowTesting/AsyncTestHarness.swift
import Swiflow
import SwiflowQuery

/// A test harness for components that use `.task` async effects. `settle()`
/// drives all in-flight tasks to completion and flushes the resulting
/// re-renders to a fixed point, so assertions see settled state deterministically.
@MainActor
public struct AsyncTestHarness {
    let renderer: TestRenderer
    let harness: TestHarness
    let clock: ManualClock
    /// True only for `init(_:clock:)`, where `clock` actually backs the client.
    /// `advance(by:)` requires it — the `init(_:queryClient:)` path stores a
    /// placeholder clock disconnected from the shared client's clock.
    private let ownsClock: Bool

    public init<C: Component>(_ component: C, clock: ManualClock = ManualClock()) {
        self.clock = clock
        self.ownsClock = true
        let r = TestRenderer(component, queryClient: QueryClient(clock: clock))
        self.renderer = r
        self.harness = TestHarness(r)
    }

    /// Use this overload when multiple harnesses must share one `QueryClient`
    /// (e.g. to verify cross-component invalidation). The harness's `clock`
    /// property is a no-op placeholder in this path; use `queryClient.tick`
    /// directly if you need background-revalidation control.
    public init<C: Component>(_ component: C, queryClient: QueryClient) {
        self.clock = ManualClock()
        self.ownsClock = false
        let r = TestRenderer(component, queryClient: queryClient)
        self.renderer = r
        self.harness = TestHarness(r)
    }

    /// The query client owned by this harness. Use from tests to call
    /// `invalidate`, `reconcile`, or other client-level APIs.
    public var queryClient: QueryClient { renderer.queryClient }

    /// Await every in-flight `.task` *for this harness's render root*, flush
    /// resulting re-renders, and repeat until none remain. Throws `SettleError`
    /// if it cannot reach a fixed point within `maxRounds` (a task that reruns
    /// every render, or two tasks that retrigger each other). Scoping to this
    /// root's `TaskScope` keeps `settle()` from awaiting tasks owned by other
    /// (e.g. concurrently running) test renderers in the same process.
    public func settle(maxRounds: Int = 100) async throws {
        var rounds = 0
        while true {
            let taskHandles = renderer.taskScope.inFlightTasks()
            let queryHandles = renderer.queryClient.inFlightTasks()
            if taskHandles.isEmpty && queryHandles.isEmpty { break }
            rounds += 1
            if rounds > maxRounds { throw SettleError.exceededMaxRounds(maxRounds) }
            for t in taskHandles { await t.value }
            for t in queryHandles { await t.value }
            renderer.scheduler.flush()
        }
        // Final flush: if the in-flight set drained between a task's last
        // `@State` write and this loop's check, the dirty mark is queued but no
        // round ran to flush it. An empty flush is a no-op, so this is always
        // safe and makes `settle()` correct regardless of call timing.
        renderer.scheduler.flush()
    }

    public enum SettleError: Error, CustomStringConvertible {
        case exceededMaxRounds(Int)
        public var description: String {
            switch self {
            case .exceededMaxRounds(let n):
                return "AsyncTestHarness.settle() exceeded \(n) rounds — a `.task` likely reruns every render (a rerunOn value that changes on every pass) or two tasks retrigger each other."
            }
        }
    }

    /// Flush pending synchronous re-renders (e.g. after directly mutating a
    /// component's `@State` from a test). Use before `settle()` when a state
    /// change must take effect — e.g. so a `rerunOn` change is reconciled —
    /// before in-flight tasks are awaited.
    public func flush() { renderer.scheduler.flush() }

    /// Advance the test clock, fire one `tick`, and settle resulting refetches.
    public func advance(by delta: Duration) async throws {
        precondition(ownsClock, "advance(by:) is unavailable on a harness built with init(_:queryClient:) — its clock is a placeholder disconnected from the shared client. Drive time via queryClient.tick(now:) with the clock that built the shared client.")
        clock.advance(by: delta)
        renderer.queryClient.tick(now: clock.now())
        try await settle()
    }

    /// Simulate the window regaining focus, then settle resulting refetches.
    public func focus() async throws {
        renderer.queryClient.focusChanged(visible: true)
        try await settle()
    }

    // MARK: - Query / interaction passthrough

    public var allText: String { harness.allText }
    public func find(_ tag: String, text: String? = nil) -> TestNode? { harness.find(tag, text: text) }
    public func findAll(_ tag: String, text: String? = nil) -> [TestNode] { harness.findAll(tag, text: text) }
    public func exists(_ tag: String, text: String? = nil) -> Bool { harness.exists(tag, text: text) }
    public func click(_ tag: String, text: String? = nil) { harness.click(tag, text: text) }
    public func input(_ tag: String = "input", at index: Int = 0, value: String) { harness.input(tag, at: index, value: value) }
    public func blur(_ tag: String = "input", at index: Int = 0) { harness.blur(tag, at: index) }
    public func change(_ tag: String = "select", at index: Int = 0, value: String) { harness.change(tag, at: index, value: value) }
}
