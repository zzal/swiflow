// Sources/Swiflow/Reactivity/SwiflowTaskRuntime.swift
//
// Runtime support for `.task` / `.task(rerunOn:)` async effects (Phase 20).
// A spawned task is stamped with a @TaskLocal token carrying its (slotID,
// generation). `@State`'s generated didSet consults `shouldDropWrite()` and
// reverts the write when the running task has been superseded (its slot moved
// to a newer generation) or torn down (component unmounted). This makes the
// primitive correct-by-default: stale data can neither re-render nor clobber.

/// The body of a `.task` effect. Non-throwing; runs on the main actor.
public typealias TaskBody = @MainActor @Sendable () async -> Void

/// Type-erased `Equatable` dependency for `.task(rerunOn:)`. Captures a
/// value-aware equality closure at construction time (mirrors the pattern in
/// `EnvironmentValues.StoredValue`).
public struct AnyEquatableBox {
    let value: Any
    let isEqual: (Any) -> Bool

    public init<T: Equatable>(_ value: T) {
        self.value = value
        self.isEqual = { ($0 as? T) == value }
    }

    func equals(_ other: AnyEquatableBox) -> Bool { isEqual(other.value) }
}

/// One async effect declared by `.task` on a node, captured at body-eval time.
public struct TaskBinding {
    /// `nil` for a bare `.task { }` (runs once, never reruns).
    public let dependency: AnyEquatableBox?
    public let body: TaskBody

    public init(dependency: AnyEquatableBox?, body: @escaping TaskBody) {
        self.dependency = dependency
        self.body = body
    }
}

/// Stamped onto a spawned task; lets a `@State` write detect staleness.
struct SwiflowTaskToken: Sendable {
    let slotID: Int
    let generation: Int
}

/// Non-isolated task-local so it propagates across the task's `await`s and is
/// readable from any context (the `@State` didSet reads it on the main actor).
enum SwiflowTaskLocal {
    @TaskLocal static var current: SwiflowTaskToken?
}

/// Per-node, per-slot run state. Stored on `MountNode.taskSlots`; carried
/// across renders so the diff can compare dependencies and cancel/restart.
package final class TaskSlot {
    package let id: Int
    package var generation: Int = 0
    package var dependency: AnyEquatableBox?
    package var handle: Task<Void, Never>?
    package init(id: Int) { self.id = id }
}

/// Global task registry + the superseded-/dead-task write guard.
@MainActor
public enum SwiflowTaskRuntime {
    /// slotID -> live generation. A write whose token generation != this is dropped.
    static var liveGenerations: [Int: Int] = [:]
    /// All in-flight tasks keyed by a unique task-run ID (not slotID), so
    /// superseded and cancelled tasks remain awaitable until they complete.
    static var inFlight: [Int: Task<Void, Never>] = [:]
    private static var nextSlotID = 0
    private static var nextRunID = 0

    static func allocateSlotID() -> Int {
        defer { nextSlotID += 1 }
        return nextSlotID
    }

    private static func allocateRunID() -> Int {
        defer { nextRunID += 1 }
        return nextRunID
    }

    /// Consulted by `@State`'s generated `didSet`. True when the current
    /// execution is inside a task that has been superseded (generation bumped
    /// by a rerun) or whose slot was torn down (component unmounted).
    public static func shouldDropWrite() -> Bool {
        guard let token = SwiflowTaskLocal.current else { return false }
        guard let live = liveGenerations[token.slotID] else { return true }
        return token.generation != live
    }

    /// Start (or restart) `slot`'s task, bumping its generation so a still-
    /// running prior task's writes are dropped (latest-wins).
    static func start(_ slot: TaskSlot, body: @escaping TaskBody) {
        slot.handle?.cancel()
        slot.generation += 1
        let id = slot.id
        let gen = slot.generation
        let runID = allocateRunID()
        liveGenerations[id] = gen
        let token = SwiflowTaskToken(slotID: id, generation: gen)
        let task = Task { @MainActor in
            await SwiflowTaskLocal.$current.withValue(token) { await body() }
            inFlight[runID] = nil
        }
        slot.handle = task
        inFlight[runID] = task
    }

    /// Cancel `slot`'s task and tear down its generation so any late write
    /// from it is dropped (dead-slot case — e.g. component unmount).
    static func cancel(_ slot: TaskSlot) {
        slot.handle?.cancel()
        slot.handle = nil
        liveGenerations[slot.id] = nil
        // Note: the task handle remains in inFlight so the test harness can
        // await its completion; it will self-remove when it finishes.
    }

    /// Snapshot of all in-flight task handles, for `AsyncTestHarness.settle()`.
    static func inFlightTasks() -> [Task<Void, Never>] { Array(inFlight.values) }

    #if DEBUG
    /// Test hook: clear global state between tests to avoid cross-test bleed.
    public static func _resetForTesting() {
        liveGenerations.removeAll()
        inFlight.removeAll()
        nextSlotID = 0
        nextRunID = 0
    }
    #endif
}
