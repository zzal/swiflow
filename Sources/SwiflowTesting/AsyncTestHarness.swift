// Sources/SwiflowTesting/AsyncTestHarness.swift
import Swiflow
import Testing
import SwiflowQuery

/// A test harness for components that use `.task` async effects. `settle()`
/// drives all in-flight tasks to completion and flushes the resulting
/// re-renders to a fixed point, so assertions see settled state deterministically.
@MainActor
public struct AsyncTestHarness {
    let renderer: TestRenderer
    let harness: TestHarness
    /// The manual clock driving this harness's client, when there is one:
    /// always for `init(_:clock:)`; for `init(_:queryClient:)` it is the
    /// shared client's OWN clock when that client was built with a
    /// `ManualClock` (audit VI Wave-3 — this path used to store a
    /// disconnected placeholder and `advance(by:)` crashed on a
    /// precondition). `nil` means the client runs on a non-manual clock and
    /// `advance(by:)` throws `ClockError`.
    private let manualClock: ManualClock?

    public init<C: Component>(_ component: C, clock: ManualClock = ManualClock()) {
        self.manualClock = clock
        let r = TestRenderer(component, queryClient: QueryClient(clock: clock))
        self.renderer = r
        self.harness = TestHarness(r)
    }

    /// Use this overload when multiple harnesses must share one `QueryClient`
    /// (e.g. to verify cross-component invalidation). `advance(by:)` works
    /// whenever the shared client was built with a `ManualClock` — the
    /// harness drives the client's own clock. With any other clock,
    /// `advance(by:)` throws `ClockError`.
    public init<C: Component>(_ component: C, queryClient: QueryClient) {
        self.manualClock = queryClient.clock as? ManualClock
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
        // Flush FIRST (audit VI Wave-1): a direct @State mutation from test
        // code queues a dirty mark but starts no task — without this, the
        // caller had to remember a manual `flush()` before every settle().
        // An empty flush is a no-op, so this is always safe.
        renderer.scheduler.flush()
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

    /// Thrown by `advance(by:)` when the harness's client is not driven by a
    /// `ManualClock` — there is no test clock to advance. Build the shared
    /// client with `QueryClient(clock: ManualClock())` to keep time control.
    public enum ClockError: Error, CustomStringConvertible {
        case clockNotManual
        public var description: String {
            "advance(by:) needs a ManualClock behind the query client. This harness's "
                + "client runs on a non-manual clock — build the shared client with "
                + "QueryClient(clock: ManualClock()) to keep time control."
        }
    }

    /// Advance the test clock, fire one `tick`, and settle resulting
    /// refetches. Works for `init(_:clock:)` harnesses and for shared-client
    /// harnesses whose client was built with a `ManualClock`; throws
    /// `ClockError` otherwise (audit VI Wave-3 — this was a precondition
    /// crash that killed the whole test process).
    public func advance(by delta: Duration) async throws {
        guard let manualClock else { throw ClockError.clockNotManual }
        manualClock.advance(by: delta)
        renderer.queryClient.tick(now: manualClock.now())
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
    public func find(role: String, label: String? = nil) -> TestNode? { harness.find(role: role, label: label) }
    public func findAll(role: String, label: String? = nil) -> [TestNode] { harness.findAll(role: role, label: label) }
    public func find(class className: String) -> TestNode? { harness.find(class: className) }
    public func findAll(class className: String) -> [TestNode] { harness.findAll(class: className) }
    public func find(label: String) -> TestNode? { harness.find(label: label) }
    public func findAll(label: String) -> [TestNode] { harness.findAll(label: label) }
    public func exists(_ tag: String, text: String? = nil) -> Bool { harness.exists(tag, text: text) }
    public func click(_ tag: String, text: String? = nil, sourceLocation: SourceLocation = #_sourceLocation) { harness.click(tag, text: text, sourceLocation: sourceLocation) }
    public func clickIfPresent(_ tag: String, text: String? = nil) { harness.clickIfPresent(tag, text: text) }
    public func input(_ tag: String = "input", at index: Int = 0, value: String, sourceLocation: SourceLocation = #_sourceLocation) { harness.input(tag, at: index, value: value, sourceLocation: sourceLocation) }
    public func inputIfPresent(_ tag: String = "input", at index: Int = 0, value: String) { harness.inputIfPresent(tag, at: index, value: value) }
    public func blur(_ tag: String = "input", at index: Int = 0, sourceLocation: SourceLocation = #_sourceLocation) { harness.blur(tag, at: index, sourceLocation: sourceLocation) }
    public func change(_ tag: String = "select", at index: Int = 0, value: String, sourceLocation: SourceLocation = #_sourceLocation) { harness.change(tag, at: index, value: value, sourceLocation: sourceLocation) }
    public func check(_ tag: String = "input", at index: Int = 0, checked: Bool, sourceLocation: SourceLocation = #_sourceLocation) { harness.check(tag, at: index, checked: checked, sourceLocation: sourceLocation) }
    public func fire(_ event: String, on tag: String, text: String? = nil, at index: Int = 0, sourceLocation: SourceLocation = #_sourceLocation) { harness.fire(event, on: tag, text: text, at: index, sourceLocation: sourceLocation) }
    public func press(_ tag: String = "input", key: String, at index: Int = 0, sourceLocation: SourceLocation = #_sourceLocation) { harness.press(tag, key: key, at: index, sourceLocation: sourceLocation) }
    @discardableResult
    public func debug() -> String { harness.debug() }
    public func expect(text: String, sourceLocation: SourceLocation = #_sourceLocation) { harness.expect(text: text, sourceLocation: sourceLocation) }
    public func expect(_ tag: String, text: String? = nil, sourceLocation: SourceLocation = #_sourceLocation) { harness.expect(tag, text: text, sourceLocation: sourceLocation) }
    /// Unmounts the rendered tree, firing `onDisappear` parent-first.
    /// See `TestHarness.unmount()`. Calling again is a no-op.
    public func unmount() { harness.unmount() }
}
