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

/// Owns the in-flight `.task` runs for ONE render root — a `Renderer` in
/// production, a `TestRenderer` in tests. Scoping the in-flight set per root is
/// what lets `AsyncTestHarness.settle()` await only ITS tasks, so concurrent
/// roots (including parallel test suites that share the process) never await,
/// cancel, or reset one another's tasks.
@MainActor
package final class TaskScope {
    package init() {}
    /// runID -> in-flight task. A run self-removes its entry on completion.
    var inFlight: [Int: Task<Void, Never>] = [:]
    /// Snapshot of this scope's in-flight task handles, for draining/settling.
    package func inFlightTasks() -> [Task<Void, Never>] { Array(inFlight.values) }
}

/// Global task registry + the superseded-/dead-task write guard.
@MainActor
public enum SwiflowTaskRuntime {
    /// slotID -> live generation. A write whose token generation != this is dropped.
    ///
    /// Lifecycle: an entry is written on every `start` (the slot's current
    /// generation) and removed on `cancel` (unmount or — via the diff —
    /// teardown). A task that completes *normally* does NOT remove its entry;
    /// the sentinel persists until the owning node is cancelled. That is
    /// intentional, not a leak: the live set is bounded by (live nodes ×
    /// tasks-per-node), and the entry is what lets a late, superseded write
    /// from the same slot be recognised as stale.
    ///
    /// `nonisolated(unsafe)`: all mutations happen on @MainActor; the dict is
    /// read by `shouldDropWrite()` from the @State didSet which also runs on
    /// @MainActor (via `@Component`, which injects it), but the compiler cannot prove
    /// this statically across macro expansion boundaries.
    nonisolated(unsafe) static var liveGenerations: [Int: Int] = [:]

    /// The scope that tasks spawned during the current render belong to. A
    /// renderer sets this around its diff pass via `withScope`; `start` captures
    /// it into each spawned task. The diff is SYNCHRONOUS, so this ambient is
    /// only ever read/written within a single un-suspended main-actor run —
    /// concurrent roots (and parallel test suites) interleave only at `await`
    /// points, which never occur mid-diff, so there is no cross-scope clobbering.
    ///
    /// `package`: set by `Renderer` (SwiflowDOM) and `TestRenderer`
    /// (SwiflowTesting), both separate modules in this package.
    package static var currentScope: TaskScope?

    /// Tasks spawned with no active render scope land here (defensive; a real
    /// render always sets one) so nothing is silently untracked.
    static let fallbackScope = TaskScope()

    private static var nextSlotID = 0
    private static var nextRunID = 0

    /// Run a SYNCHRONOUS render/diff pass with `scope` active, so any `.task`s it
    /// starts register in `scope`. Restores the prior scope. Must wrap only
    /// synchronous work — never `await` while a scope is installed.
    @discardableResult
    package static func withScope<T>(_ scope: TaskScope, _ body: () -> T) -> T {
        let prev = currentScope
        currentScope = scope
        defer { currentScope = prev }
        return body()
    }

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
    ///
    /// `nonisolated`: the `@State` didSet expands into a synchronous observer
    /// on a `@Component` class (always @MainActor); the compiler cannot prove @MainActor
    /// isolation across macro expansion boundaries, so the call must be
    /// `nonisolated`. Safety is preserved because `liveGenerations` is
    /// `nonisolated(unsafe)` and all mutations occur on @MainActor, while all
    /// reads occur in `@State` didSets which also run on @MainActor.
    ///
    /// CONTRACT: callers MUST run on the main actor. The `nonisolated` keyword
    /// is a workaround for the macro-expansion isolation gap — NOT a license to
    /// call this off the main actor. An off-actor caller would race the
    /// `nonisolated(unsafe)` `liveGenerations` reads against `start`/`cancel`
    /// mutations. Any future non-component caller must uphold this.
    public nonisolated static func shouldDropWrite() -> Bool {
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
        // Capture the scope active at spawn time (synchronously, mid-diff) so
        // the task registers/self-removes in the right root's set even after
        // `currentScope` has moved on to another render.
        let scope = currentScope ?? fallbackScope
        liveGenerations[id] = gen
        let token = SwiflowTaskToken(slotID: id, generation: gen)
        let task = Task { @MainActor in
            await SwiflowTaskLocal.$current.withValue(token) { await body() }
            scope.inFlight[runID] = nil
        }
        slot.handle = task
        scope.inFlight[runID] = task
    }

    /// Cancel `slot`'s task and tear down its generation so any late write
    /// from it is dropped (dead-slot case — e.g. component unmount).
    static func cancel(_ slot: TaskSlot) {
        slot.handle?.cancel()
        slot.handle = nil
        liveGenerations[slot.id] = nil
        // Note: the task handle remains in its scope's `inFlight` so a settler
        // can await its completion; it self-removes from that scope when it finishes.
    }

    #if DEBUG
    /// Test hook: clears the global generation map + the fallback scope. NOT the
    /// per-test isolation mechanism — that comes from each renderer/test owning
    /// its own `TaskScope`; tests should not need to call this (and must not call
    /// it from a concurrently-running suite, since `liveGenerations` is global).
    ///
    /// The slot/run ID counters are intentionally NOT reset: their global
    /// uniqueness is load-bearing for the per-slot write guard across parallel
    /// tests, so zeroing them could alias a live slot from another suite.
    public static func _resetForTesting() {
        liveGenerations.removeAll()
        fallbackScope.inFlight.removeAll()
        currentScope = nil
    }
    #endif
}
