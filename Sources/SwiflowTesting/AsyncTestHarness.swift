// Sources/SwiflowTesting/AsyncTestHarness.swift
import Swiflow

/// A test harness for components that use `.task` async effects. `settle()`
/// drives all in-flight tasks to completion and flushes the resulting
/// re-renders to a fixed point, so assertions see settled state deterministically.
@MainActor
public struct AsyncTestHarness {
    let renderer: TestRenderer
    let harness: TestHarness

    public init<C: Component>(_ component: C) {
        let r = TestRenderer(component)
        self.renderer = r
        self.harness = TestHarness(r)
    }

    /// Await every in-flight `.task` *for this harness's render root*, flush
    /// resulting re-renders, and repeat until none remain. Throws `SettleError`
    /// if it cannot reach a fixed point within `maxRounds` (a task that reruns
    /// every render, or two tasks that retrigger each other). Scoping to this
    /// root's `TaskScope` keeps `settle()` from awaiting tasks owned by other
    /// (e.g. concurrently running) test renderers in the same process.
    public func settle(maxRounds: Int = 100) async throws {
        var rounds = 0
        while true {
            let tasks = renderer.taskScope.inFlightTasks()
            if tasks.isEmpty { break }
            rounds += 1
            if rounds > maxRounds { throw SettleError.exceededMaxRounds(maxRounds) }
            for t in tasks { await t.value }
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
