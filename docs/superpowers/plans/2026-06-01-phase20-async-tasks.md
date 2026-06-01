# Phase 20 — Async Task Effects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a lifecycle-bound async effect to Swiflow components — `.task { }` and `.task(rerunOn:)` — that starts on mount, re-runs when an `Equatable` dependency changes, cancels on unmount, and is correct-by-default (stale/superseded task writes are dropped by the runtime).

**Architecture:** Tasks are declared as postfix `VNode` modifiers, stored out-of-band on `ElementData.taskBindings` (like `refBindings`). The diff's existing node lifecycle (`mount`/`update`/`destroy`) starts/reconciles/cancels them. A global generation registry (`SwiflowTaskRuntime`) stamps each spawned `Task` with a `@TaskLocal` token; `@State`'s generated `didSet` consults it and reverts the write when the running task is stale. An `AsyncTestHarness.settle()` drives in-flight tasks to a fixed point for deterministic tests. The web runtime gains the `JavaScriptEventLoop` global executor so `Task`/`await` actually resume in the browser.

**Tech Stack:** Swift 6, swift-testing (`import Testing`, `@Test`, `#expect`) for runtime tests, XCTest + `assertMacroExpansion` for macro tests, JavaScriptKit / JavaScriptEventLoop (SwiftWasm) for the browser executor.

**Spec:** `docs/superpowers/specs/2026-06-01-phase20-async-tasks-design.md`

---

## File Structure

**New files:**
- `Sources/Swiflow/Reactivity/SwiflowTaskRuntime.swift` — `TaskBody`, `AnyEquatableBox`, `TaskBinding`, `SwiflowTaskToken`, `SwiflowTaskLocal`, `TaskSlot`, `SwiflowTaskRuntime` (the registry + write guard).
- `Sources/Swiflow/DSL/TaskModifier.swift` — postfix `.task` / `.task(rerunOn:)` modifiers.
- `Sources/Swiflow/Diff/DiffTasks.swift` — `startTasks` / `reconcileTasks` / `cancelTasks` helpers used by the diff.
- `Sources/SwiflowTesting/AsyncTestHarness.swift` — `AsyncTestHarness` + `settle()`.
- `Tests/SwiflowTests/TaskRuntimeTests.swift` — runtime unit tests.
- `Tests/SwiflowTests/TaskModifierTests.swift` — modifier unit tests.
- `Tests/SwiflowTests/TaskDiffTests.swift` — diff-integration tests.
- `Tests/SwiflowTestingTests/AsyncTaskTests.swift` — end-to-end harness tests.
- `examples/AsyncFetch/` — worked example (mirrors `examples/HelloWorld` layout).

**Modified files:**
- `Package.swift` — add `JavaScriptEventLoop` product to the `SwiflowWeb` target.
- `Sources/SwiflowWeb/SwiflowWeb.swift` — install the global executor in `render(into:)`.
- `Sources/Swiflow/VNode.swift` — add `ElementData.taskBindings` (excluded from `==`).
- `Sources/Swiflow/MountTree.swift` — add `MountNode.taskSlots`.
- `Sources/SwiflowMacrosPlugin/StateMacro.swift` — emit the write guard in `didSet`.
- `Tests/SwiflowMacrosTests/StateMacroTests.swift` — update the two passing expansion snapshots.
- `Sources/Swiflow/Diff/Diff.swift` — call the task helpers in `mount` / `update` / `destroy`.

---

## Task 1: JavaScriptEventLoop executor wiring

**Why first:** load-bearing and currently absent — without it `Task`/`await` silently never resume in the browser. It is also isolated (Package + one bootstrap call), so it de-risks the browser path before the primitive is built. This task is **build-verified + manual browser smoke**, not TDD: `installGlobalExecutor()` lives behind `#if canImport(JavaScriptKit)` and cannot run in host unit tests.

**Files:**
- Modify: `Package.swift` (the `SwiflowWeb` target's `dependencies`)
- Modify: `Sources/SwiflowWeb/SwiflowWeb.swift`

- [ ] **Step 1: Add the JavaScriptEventLoop product to SwiflowWeb**

In `Package.swift`, the `SwiflowWeb` target currently reads:

```swift
        .target(
            name: "SwiflowWeb",
            dependencies: [
                "Swiflow",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ],
            path: "Sources/SwiflowWeb",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
```

Add the `JavaScriptEventLoop` product (it ships in the same swiftwasm/JavaScriptKit package):

```swift
        .target(
            name: "SwiflowWeb",
            dependencies: [
                "Swiflow",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
            ],
            path: "Sources/SwiflowWeb",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
```

- [ ] **Step 2: Install the executor once, idempotently, in `render(into:)`**

In `Sources/SwiflowWeb/SwiflowWeb.swift`, add the import alongside the existing ones (inside the `#if canImport(JavaScriptKit)` block, after `import JavaScriptKit` on line 10):

```swift
import JavaScriptEventLoop
```

Add a one-shot guard flag next to the other file-level `nonisolated(unsafe)` vars (after line 29, `sharedHandleAllocator`):

```swift
/// Guards `JavaScriptEventLoop.installGlobalExecutor()` so multi-root apps
/// (multiple `render(into:)` calls) and HMR re-imports install it exactly once.
nonisolated(unsafe) var _swiflowExecutorInstalled = false
```

In `render(into:)`, add the install as the very first statement of the function body (before the `precondition(...)` on line 48):

```swift
        if !_swiflowExecutorInstalled {
            JavaScriptEventLoop.installGlobalExecutor()
            _swiflowExecutorInstalled = true
        }
```

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: builds with no errors. (Host build compiles the `#else` stub for SwiflowWeb; the WASM symbols are exercised by the example in Task 10.)

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources/SwiflowWeb/SwiflowWeb.swift
git commit -m "feat(web): install JavaScriptEventLoop global executor in render(into:)

Without the global executor, Task/await never resume in the browser.
Installed once (idempotent) at the top of render(into:) so multi-root and
HMR re-imports don't double-install. Phase 20.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Task runtime (registry, token, generation, write guard)

**Files:**
- Create: `Sources/Swiflow/Reactivity/SwiflowTaskRuntime.swift`
- Test: `Tests/SwiflowTests/TaskRuntimeTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiflowTests/TaskRuntimeTests.swift`:

```swift
import Testing
@testable import Swiflow

@MainActor
@Suite(.serialized)   // global registry state — run serially, reset between tests
struct TaskRuntimeTests {

    init() { SwiflowTaskRuntime._resetForTesting() }

    @Test func noTokenMeansWriteIsKept() {
        #expect(SwiflowTaskRuntime.shouldDropWrite() == false)
    }

    @Test func tokenPropagatesAcrossAwait() async {
        let slot = TaskSlot(id: SwiflowTaskRuntime.allocateSlotID())
        var sawTokenAfterAwait = false
        SwiflowTaskRuntime.start(slot) {
            await Task.yield()
            sawTokenAfterAwait = (SwiflowTaskLocal.current?.slotID == slot.id)
        }
        for t in SwiflowTaskRuntime.inFlightTasks() { await t.value }
        #expect(sawTokenAfterAwait == true)
    }

    @Test func supersededTaskWriteIsDropped() async {
        let slot = TaskSlot(id: SwiflowTaskRuntime.allocateSlotID())
        var staleSawDrop = false
        var freshSawKeep = false
        // First run captures generation 1.
        SwiflowTaskRuntime.start(slot) {
            await Task.yield()                       // suspend so the restart below wins
            staleSawDrop = SwiflowTaskRuntime.shouldDropWrite()   // expect true: superseded
        }
        // Restart (generation 2) — simulates a rerunOn change.
        SwiflowTaskRuntime.start(slot) {
            freshSawKeep = (SwiflowTaskRuntime.shouldDropWrite() == false) // expect kept
        }
        for t in SwiflowTaskRuntime.inFlightTasks() { await t.value }
        #expect(staleSawDrop == true)
        #expect(freshSawKeep == true)
    }

    @Test func cancelledSlotDropsLateWrite() async {
        let slot = TaskSlot(id: SwiflowTaskRuntime.allocateSlotID())
        var sawDrop = false
        SwiflowTaskRuntime.start(slot) {
            await Task.yield()
            sawDrop = SwiflowTaskRuntime.shouldDropWrite()   // slot torn down -> true
        }
        SwiflowTaskRuntime.cancel(slot)                      // dead slot
        for t in SwiflowTaskRuntime.inFlightTasks() { await t.value }
        #expect(sawDrop == true)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter TaskRuntimeTests`
Expected: FAIL — `cannot find 'SwiflowTaskRuntime' in scope` (and `TaskSlot`, `SwiflowTaskLocal`).

- [ ] **Step 3: Implement the runtime**

Create `Sources/Swiflow/Reactivity/SwiflowTaskRuntime.swift`:

```swift
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
    /// slotID -> current in-flight task (so the async test harness can await).
    static var inFlight: [Int: Task<Void, Never>] = [:]
    private static var nextSlotID = 0

    static func allocateSlotID() -> Int {
        defer { nextSlotID += 1 }
        return nextSlotID
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
        liveGenerations[id] = gen
        let token = SwiflowTaskToken(slotID: id, generation: gen)
        let task = Task { @MainActor in
            await SwiflowTaskLocal.$current.withValue(token) { await body() }
            // Self-remove from the in-flight set if still the current run.
            if liveGenerations[id] == gen { inFlight[id] = nil }
        }
        slot.handle = task
        inFlight[id] = task
    }

    /// Cancel `slot`'s task and tear down its generation so any late write
    /// from it is dropped (dead-slot case — e.g. component unmount).
    static func cancel(_ slot: TaskSlot) {
        slot.handle?.cancel()
        slot.handle = nil
        liveGenerations[slot.id] = nil
        inFlight[slot.id] = nil
    }

    /// Snapshot of all in-flight task handles, for `AsyncTestHarness.settle()`.
    static func inFlightTasks() -> [Task<Void, Never>] { Array(inFlight.values) }

    #if DEBUG
    /// Test hook: clear global state between tests to avoid cross-test bleed.
    public static func _resetForTesting() {
        liveGenerations.removeAll()
        inFlight.removeAll()
        nextSlotID = 0
    }
    #endif
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter TaskRuntimeTests`
Expected: PASS (4 tests). `tokenPropagatesAcrossAwait` is the linchpin verification from the spec's risk list.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Reactivity/SwiflowTaskRuntime.swift Tests/SwiflowTests/TaskRuntimeTests.swift
git commit -m "feat(reactivity): task runtime with superseded-write guard (Phase 20)

@TaskLocal generation token + global liveGenerations registry; shouldDropWrite()
returns true for superseded/dead tasks. Verifies @TaskLocal propagates across
await (the guard's linchpin).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `ElementData.taskBindings` field

**Files:**
- Modify: `Sources/Swiflow/VNode.swift`
- Test: `Tests/SwiflowTests/TaskModifierTests.swift` (created here, extended in Task 4)

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowTests/TaskModifierTests.swift`:

```swift
import Testing
@testable import Swiflow

@MainActor
struct TaskModifierTests {

    @Test func taskBindingsAreExcludedFromEquality() {
        // Two ElementData identical except for taskBindings must compare equal
        // (closures aren't Equatable; taskBindings is out-of-band, like refBindings).
        let a = ElementData(tag: "div")
        var b = ElementData(tag: "div")
        b.taskBindings = [TaskBinding(dependency: nil, body: {})]
        #expect(a == b)
    }

    @Test func taskBindingsDefaultEmpty() {
        #expect(ElementData(tag: "div").taskBindings.isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter TaskModifierTests`
Expected: FAIL — `value of type 'ElementData' has no member 'taskBindings'`.

- [ ] **Step 3: Add the field**

In `Sources/Swiflow/VNode.swift`, add the stored property to `ElementData` after `refBindings` (line 78):

```swift
    /// `.task` async effects declared on this node, captured at body-eval time.
    /// Stored out-of-band like `refBindings`: consumed by Diff at mount/update/
    /// destroy and never folded into the four bags or compared in `==`.
    public var taskBindings: [TaskBinding] = []
```

Add it to the initializer — extend the parameter list (after `refBindings`, line 90) and the assignment (after line 99):

```swift
        refBindings: [AnyRefBinding] = [],
        taskBindings: [TaskBinding] = []
    ) {
```
```swift
        self.refBindings = refBindings
        self.taskBindings = taskBindings
```

Leave `ElementData.==` (lines 107–115) unchanged — `taskBindings` is intentionally excluded, exactly like `refBindings`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter TaskModifierTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/VNode.swift Tests/SwiflowTests/TaskModifierTests.swift
git commit -m "feat(vnode): ElementData.taskBindings out-of-band field (Phase 20)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Postfix `.task` / `.task(rerunOn:)` modifiers

**Files:**
- Create: `Sources/Swiflow/DSL/TaskModifier.swift`
- Test: `Tests/SwiflowTests/TaskModifierTests.swift` (extend)

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SwiflowTests/TaskModifierTests.swift` (inside the `struct`):

```swift
    private func bindings(of node: VNode) -> [TaskBinding] {
        guard case .element(let data) = node else { return [] }
        return data.taskBindings
    }

    @Test func bareTaskAppendsBindingWithNoDependency() {
        let node = div { }.task { }
        let bs = bindings(of: node)
        #expect(bs.count == 1)
        #expect(bs[0].dependency == nil)
    }

    @Test func taskRerunOnAppendsBindingWithDependency() {
        let node = div { }.task(rerunOn: 7) { }
        let bs = bindings(of: node)
        #expect(bs.count == 1)
        #expect(bs[0].dependency != nil)
        #expect(bs[0].dependency!.equals(AnyEquatableBox(7)))
        #expect(bs[0].dependency!.equals(AnyEquatableBox(8)) == false)
    }

    @Test func multipleTasksStackInOrder() {
        let node = div { }.task(rerunOn: 1) { }.task { }
        #expect(bindings(of: node).count == 2)
        #expect(bindings(of: node)[0].dependency != nil)
        #expect(bindings(of: node)[1].dependency == nil)
    }

    @Test func taskOnNonElementIsDiagnosedAndPassesThrough() {
        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        let node = VNode.text("hi").task { }
        #expect(captured.count == 1)
        if case .text(let s) = node { #expect(s == "hi") } else { Issue.record("expected text node") }
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter TaskModifierTests`
Expected: FAIL — `value of type 'VNode' has no member 'task'`.

- [ ] **Step 3: Implement the modifiers**

Create `Sources/Swiflow/DSL/TaskModifier.swift`:

```swift
// Sources/Swiflow/DSL/TaskModifier.swift
//
// Postfix `.task` / `.task(rerunOn:)` modifiers. They attach a TaskBinding to
// the decorated element's out-of-band `taskBindings`; the diff starts/reruns/
// cancels them along the node lifecycle. See SwiflowTaskRuntime + Diff/DiffTasks.

public extension VNode {
    /// Run an async effect once when this node mounts; cancel it when the node
    /// unmounts. Never restarts. Declared in `body` but run later by the
    /// runtime on the main actor — `body` itself stays pure.
    func task(_ body: @escaping TaskBody) -> VNode {
        appendTask(TaskBinding(dependency: nil, body: body))
    }

    /// Run an async effect when this node mounts; cancel and re-run it whenever
    /// `rerunOn` changes (`!=`) between renders; cancel it when the node
    /// unmounts. `rerunOn` is an explicit re-run trigger — not an exhaustive
    /// dependency audit. Compose several dependencies into one `Equatable`
    /// struct or array.
    func task<Dependency: Equatable>(rerunOn dependency: Dependency, _ body: @escaping TaskBody) -> VNode {
        appendTask(TaskBinding(dependency: AnyEquatableBox(dependency), body: body))
    }

    private func appendTask(_ binding: TaskBinding) -> VNode {
        if case .element(var data) = self {
            data.taskBindings.append(binding)
            return .element(data)
        }
        swiflowDiagnostic("`.task` applied to a non-element VNode. Tasks attach to an element — e.g. `div { … }.task { … }`. The modifier is ignored.")
        return self
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter TaskModifierTests`
Expected: PASS (6 tests total).

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/DSL/TaskModifier.swift Tests/SwiflowTests/TaskModifierTests.swift
git commit -m "feat(dsl): .task / .task(rerunOn:) postfix modifiers (Phase 20)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `@State` write guard (macro change)

**Files:**
- Modify: `Sources/SwiflowMacrosPlugin/StateMacro.swift`
- Modify: `Tests/SwiflowMacrosTests/StateMacroTests.swift` (update 2 expansion snapshots)
- Test (runtime behavior): `Tests/SwiflowTests/TaskRuntimeTests.swift` (extend)

- [ ] **Step 1: Update the macro-expansion snapshot tests (these are the failing tests)**

In `Tests/SwiflowMacrosTests/StateMacroTests.swift`, update the two passing expansion snapshots (`testSingleIntState` and `testOptionalState`) so the `didSet` includes the guard. For `testSingleIntState`, change the `expandedSource` `didSet` block (lines 22–28) to:

```swift
            final class Counter {
                var count: Int = 0 {
                    didSet {
                        if SwiflowTaskRuntime.shouldDropWrite() {
                            count = oldValue
                            return
                        }
                        if let s = runtimeScheduler, let o = runtimeOwner {
                            s.markDirty(o)
                        }
                    }
                }
```

For `testOptionalState` (lines 56–62), apply the same change with `maybeId` as the property name:

```swift
            final class Counter {
                var maybeId: Int? = nil {
                    didSet {
                        if SwiflowTaskRuntime.shouldDropWrite() {
                            maybeId = oldValue
                            return
                        }
                        if let s = runtimeScheduler, let o = runtimeOwner {
                            s.markDirty(o)
                        }
                    }
                }
```

Leave the `$count` / `$maybeId` peer expansions and the diagnostic tests unchanged.

- [ ] **Step 2: Run the macro tests to verify they fail**

Run: `swift test --filter StateMacroTests`
Expected: FAIL — actual expansion lacks the guard; `assertMacroExpansion` reports a mismatch on the `didSet` block.

- [ ] **Step 3: Emit the guard from the macro**

In `Sources/SwiflowMacrosPlugin/StateMacro.swift`, the `AccessorMacro` path must now know the property name to emit the revert. After the type-annotation guard (line 40–42), extract the name:

```swift
        // Require a type annotation (peer macro diagnoses this; accessor
        // must also bail to leave the source unchanged).
        guard binding.typeAnnotation != nil else {
            return []   // peer macro emits the diagnostic
        }

        guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
            return []
        }
```

Replace the `didSet` emission (lines 47–53) with the guarded version:

```swift
        // Emit a didSet that (1) drops the write when it originates from a
        // superseded/dead `.task` (reverting to oldValue — Swift does not
        // re-fire didSet for an in-observer assignment), then (2) marks the
        // owner dirty. Runtime fields are emitted by @Component on the class.
        let didSet: AccessorDeclSyntax = """
            didSet {
                if SwiflowTaskRuntime.shouldDropWrite() {
                    \(raw: name) = oldValue
                    return
                }
                if let s = runtimeScheduler, let o = runtimeOwner {
                    s.markDirty(o)
                }
            }
            """
        return [didSet]
```

- [ ] **Step 4: Run the macro tests to verify they pass**

Run: `swift test --filter StateMacroTests`
Expected: PASS — both updated snapshots match; diagnostic tests still pass.

- [ ] **Step 5: Write the runtime-behavior test for the guard**

Append to `Tests/SwiflowTests/TaskRuntimeTests.swift` (inside the `struct`). This proves the *generated* guard reverts a stale write on a real `@Component`:

```swift
    @Test func stateWriteIsRevertedUnderStaleToken() async {
        let probe = GuardProbe()
        // Allocate a slot and bump it twice so generation 1 is stale.
        let slot = TaskSlot(id: SwiflowTaskRuntime.allocateSlotID())
        slot.generation = 1
        SwiflowTaskRuntime.liveGenerations[slot.id] = 2   // live gen is 2; token gen 1 is stale
        let staleToken = SwiflowTaskToken(slotID: slot.id, generation: 1)

        await SwiflowTaskLocal.$current.withValue(staleToken) {
            probe.value = 99            // generated didSet should revert this
        }
        #expect(probe.value == 0)       // reverted to oldValue

        // A write with no token proceeds normally.
        probe.value = 42
        #expect(probe.value == 42)
    }
}

@MainActor @Component
private final class GuardProbe {
    @State var value: Int = 0
    var body: VNode { div { p("\(value)") } }
}
```

- [ ] **Step 6: Run the runtime-behavior test to verify it passes**

Run: `swift test --filter TaskRuntimeTests`
Expected: PASS (5 tests now). Note: `GuardProbe`'s `@State value` write inside the stale-token scope is reverted because the macro-emitted `didSet` calls `SwiflowTaskRuntime.shouldDropWrite()`.

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiflowMacrosPlugin/StateMacro.swift Tests/SwiflowMacrosTests/StateMacroTests.swift Tests/SwiflowTests/TaskRuntimeTests.swift
git commit -m "feat(macro): @State write guard drops superseded-task writes (Phase 20)

didSet reverts to oldValue when shouldDropWrite() is true (in-observer assign
does not re-fire didSet), else marks dirty. One additive guard, no @State
restructuring. Updated expansion snapshots + runtime revert test.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: `MountNode.taskSlots` + diff helpers

**Files:**
- Modify: `Sources/Swiflow/MountTree.swift`
- Create: `Sources/Swiflow/Diff/DiffTasks.swift`
- Test: `Tests/SwiflowTests/TaskDiffTests.swift`

- [ ] **Step 1: Add `taskSlots` to MountNode**

In `Sources/Swiflow/MountTree.swift`, add a stored property after `componentBody` (line 48). It defaults to empty so the initializer needs no change:

```swift
    /// `.task` run state for this node, one `TaskSlot` per `.task` modifier in
    /// declaration order. Carried across renders so the diff can compare
    /// dependencies (rerun) and cancel on unmount. Empty for nodes with no tasks.
    package var taskSlots: [TaskSlot] = []
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/SwiflowTests/TaskDiffTests.swift` (exercises the helpers directly against a `MountNode`, before wiring them into `mount`/`update`/`destroy`):

```swift
import Testing
@testable import Swiflow

@MainActor
@Suite(.serialized)
struct TaskDiffTests {

    init() { SwiflowTaskRuntime._resetForTesting() }

    private func drain() async {
        for t in SwiflowTaskRuntime.inFlightTasks() { await t.value }
    }

    @Test func startTasksSpawnsOnePerBinding() async {
        let node = MountNode(handle: 1, vnode: .element(ElementData(tag: "div")))
        var ran = 0
        startTasks(on: node, [
            TaskBinding(dependency: nil, body: { ran += 1 }),
            TaskBinding(dependency: AnyEquatableBox(1), body: { ran += 1 }),
        ])
        #expect(node.taskSlots.count == 2)
        await drain()
        #expect(ran == 2)
    }

    @Test func reconcileRerunsOnlyWhenDependencyChanges() async {
        let node = MountNode(handle: 1, vnode: .element(ElementData(tag: "div")))
        var runs = 0
        startTasks(on: node, [TaskBinding(dependency: AnyEquatableBox(1), body: { runs += 1 })])
        await drain()
        #expect(runs == 1)

        // Same dependency -> no rerun.
        reconcileTasks(on: node, old: [TaskBinding(dependency: AnyEquatableBox(1), body: {})],
                       new: [TaskBinding(dependency: AnyEquatableBox(1), body: { runs += 1 })])
        await drain()
        #expect(runs == 1)

        // Changed dependency -> rerun.
        reconcileTasks(on: node, old: [TaskBinding(dependency: AnyEquatableBox(1), body: {})],
                       new: [TaskBinding(dependency: AnyEquatableBox(2), body: { runs += 1 })])
        await drain()
        #expect(runs == 2)
    }

    @Test func bareTaskNeverReruns() async {
        let node = MountNode(handle: 1, vnode: .element(ElementData(tag: "div")))
        var runs = 0
        startTasks(on: node, [TaskBinding(dependency: nil, body: { runs += 1 })])
        await drain()
        reconcileTasks(on: node, old: [TaskBinding(dependency: nil, body: {})],
                       new: [TaskBinding(dependency: nil, body: { runs += 1 })])
        await drain()
        #expect(runs == 1)   // bare task ran once, never again
    }

    @Test func cancelTasksTearsDownSlots() async {
        let node = MountNode(handle: 1, vnode: .element(ElementData(tag: "div")))
        startTasks(on: node, [TaskBinding(dependency: nil, body: { try? await Task.sleep(nanoseconds: 1_000_000_000) })])
        #expect(node.taskSlots.count == 1)
        cancelTasks(on: node)
        #expect(node.taskSlots.isEmpty)
        await drain()   // cancelled task completes
        #expect(SwiflowTaskRuntime.inFlightTasks().isEmpty)
    }

    @Test func changingTaskCountFiresDiagnostic() async {
        let node = MountNode(handle: 1, vnode: .element(ElementData(tag: "div")))
        startTasks(on: node, [TaskBinding(dependency: AnyEquatableBox(1), body: {})])
        await drain()

        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        // New render declares two tasks where there was one — stable-slot violation.
        reconcileTasks(on: node,
                       old: [TaskBinding(dependency: AnyEquatableBox(1), body: {})],
                       new: [TaskBinding(dependency: AnyEquatableBox(1), body: {}),
                             TaskBinding(dependency: nil, body: {})])
        await drain()
        #expect(captured.contains { $0.contains("`.task` count") })
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter TaskDiffTests`
Expected: FAIL — `cannot find 'startTasks'` / `'reconcileTasks'` / `'cancelTasks'` in scope.

- [ ] **Step 4: Implement the helpers**

Create `Sources/Swiflow/Diff/DiffTasks.swift`:

```swift
// Sources/Swiflow/Diff/DiffTasks.swift
//
// Bridges the diff's node lifecycle to SwiflowTaskRuntime. mount() calls
// startTasks; the same-tag element update calls reconcileTasks; destroy()
// calls cancelTasks. Identity is per (node, slot index); the stable-slot rule
// requires a node's `.task` count not change between renders.

/// Start every binding as a fresh task slot on `node` (mount time).
@MainActor
func startTasks(on node: MountNode, _ bindings: [TaskBinding]) {
    for binding in bindings {
        let slot = TaskSlot(id: SwiflowTaskRuntime.allocateSlotID())
        slot.dependency = binding.dependency
        node.taskSlots.append(slot)
        SwiflowTaskRuntime.start(slot, body: binding.body)
    }
}

/// Reconcile `node`'s running tasks against a freshly rendered binding list.
/// Per slot: bare `.task` never reruns; `.task(rerunOn:)` reruns when its
/// dependency changed (`!=`).
@MainActor
func reconcileTasks(on node: MountNode, old: [TaskBinding], new: [TaskBinding]) {
    #if DEBUG
    if old.count != new.count {
        swiflowDiagnostic("`.task` count on a node changed between renders (\(old.count) → \(new.count)). The number of `.task` modifiers on a node must be stable across renders — don't put a `.task` behind a conditional that adds or removes it. Use `.task(rerunOn:)` to react to a changing value instead.")
    }
    #endif

    let shared = min(node.taskSlots.count, new.count)
    for i in 0..<shared {
        let slot = node.taskSlots[i]
        let newDep = new[i].dependency
        let changed: Bool
        switch (slot.dependency, newDep) {
        case (nil, nil):       changed = false              // bare task — never reruns
        case let (a?, b?):     changed = !a.equals(b)
        default:               changed = true               // gained/lost a dependency
        }
        if changed {
            slot.dependency = newDep
            SwiflowTaskRuntime.start(slot, body: new[i].body)
        }
    }

    // Count grew (already diagnosed): start the extra slots.
    if new.count > node.taskSlots.count {
        for i in node.taskSlots.count..<new.count {
            let slot = TaskSlot(id: SwiflowTaskRuntime.allocateSlotID())
            slot.dependency = new[i].dependency
            node.taskSlots.append(slot)
            SwiflowTaskRuntime.start(slot, body: new[i].body)
        }
    }
    // Count shrank (already diagnosed): cancel the extras.
    if node.taskSlots.count > new.count {
        for i in new.count..<node.taskSlots.count {
            SwiflowTaskRuntime.cancel(node.taskSlots[i])
        }
        node.taskSlots.removeLast(node.taskSlots.count - new.count)
    }
}

/// Cancel every task on `node` and clear its slots (unmount time).
@MainActor
func cancelTasks(on node: MountNode) {
    for slot in node.taskSlots {
        SwiflowTaskRuntime.cancel(slot)
    }
    node.taskSlots.removeAll()
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter TaskDiffTests`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/MountTree.swift Sources/Swiflow/Diff/DiffTasks.swift Tests/SwiflowTests/TaskDiffTests.swift
git commit -m "feat(diff): task lifecycle helpers + MountNode.taskSlots (Phase 20)

startTasks/reconcileTasks/cancelTasks bridge the diff node lifecycle to the
task runtime; stable-slot violations fire a DEBUG diagnostic.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Wire the helpers into mount / update / destroy

**Files:**
- Modify: `Sources/Swiflow/Diff/Diff.swift`
- Test: `Tests/SwiflowTests/TaskDiffTests.swift` (extend)

- [ ] **Step 1: Write the failing integration test**

Append to `Tests/SwiflowTests/TaskDiffTests.swift` (inside the `struct`). This drives a real component body through `diff` via `TestRenderer`-style mounting — but `TestRenderer` lives in `SwiflowTesting`, so here we use the lower-level `diff(...)` entry directly:

```swift
    @Test func mountStartsTasksDeclaredInBody() async {
        var ran = false
        let node = VNode.element(ElementData(tag: "div")).task { ran = true }
        let result = diff(mounted: nil, next: node, handles: HandleAllocator(), handlers: HandlerRegistry())
        #expect(result.newMountTree.taskSlots.count == 1)
        await drain()
        #expect(ran == true)
    }

    @Test func destroyCancelsTasks() async {
        var node = VNode.element(ElementData(tag: "div")).task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        let mounted = diff(mounted: nil, next: node, handles: HandleAllocator(), handlers: HandlerRegistry()).newMountTree
        #expect(SwiflowTaskRuntime.inFlightTasks().count == 1)

        // Replace the whole tree with a different tag -> old subtree destroyed.
        node = .element(ElementData(tag: "section"))
        _ = diff(mounted: mounted, next: node, handles: HandleAllocator(), handlers: HandlerRegistry())
        await drain()
        #expect(SwiflowTaskRuntime.inFlightTasks().isEmpty)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter TaskDiffTests`
Expected: FAIL — `mountStartsTasksDeclaredInBody` finds `taskSlots.count == 0` (mount doesn't start tasks yet); `ran` stays false.

- [ ] **Step 3: Wire `mount`**

In `Sources/Swiflow/Diff/Diff.swift`, the `.element` case of `mount(...)` builds child mounts and then constructs and returns a `MountNode`. Locate that element-case `return MountNode(...)` (the one carrying `handle: h, vnode: vnode, children:`, `handlerIds: handlerIds`). Bind it to a local and start tasks before returning. Change:

```swift
        return MountNode(
            handle: h,
            vnode: vnode,
            children: childMounts,
            handlerIds: handlerIds
        )
```
to:
```swift
        let node = MountNode(
            handle: h,
            vnode: vnode,
            children: childMounts,
            handlerIds: handlerIds
        )
        startTasks(on: node, data.taskBindings)
        return node
```

(If the element-case `MountNode(...)` arguments differ slightly, keep them — only add the `let node =` binding, the `startTasks(on: node, data.taskBindings)` call, and `return node`.)

- [ ] **Step 4: Wire `update` (same-tag element)**

In the same-tag element branch of `update(...)` (the `case (.element(let oldData), .element(let newData)) where oldData.tag == newData.tag:` block), add a `reconcileTasks` call. Insert it right after the refBindings re-bind loops (after the `for binding in newData.refBindings { binding.setHandle(mounted.handle) }` loop), before the `diffAttributes(...)` call:

```swift
        reconcileTasks(on: mounted, new: newData.taskBindings)
```

(`reconcileTasks` reads the prior count from `mounted.taskSlots`, so only the new bindings are passed — no `old:` argument.)

`mounted.vnode = next` (end of the branch, ~line 380) already records the new ElementData for the next render; task dependency state additionally lives on `mounted.taskSlots`.

- [ ] **Step 5: Wire `destroy`**

In `destroy(...)`, add a task cancel alongside the refBindings clear. Just before the existing element refBindings clear block:

```swift
    if case .element(let data) = node.vnode {
        for binding in data.refBindings {
            binding.clearHandle()
        }
    }
```
add (immediately above it):
```swift
    // Cancel any `.task` effects on this node before tearing it down so late
    // writes from in-flight tasks are dropped (dead-slot guard).
    cancelTasks(on: node)
```

`destroy` already recurses into `componentBody` and `children`, so every node in an unmounting subtree gets its tasks cancelled.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter TaskDiffTests`
Expected: PASS (7 tests).

- [ ] **Step 7: Run the full Swiflow test target to check for regressions**

Run: `swift test --filter SwiflowTests`
Expected: PASS — no existing diff/state tests regress (the write guard is a no-op when there is no task token).

- [ ] **Step 8: Commit**

```bash
git add Sources/Swiflow/Diff/Diff.swift Tests/SwiflowTests/TaskDiffTests.swift
git commit -m "feat(diff): start/reconcile/cancel .task effects in mount/update/destroy (Phase 20)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: `AsyncTestHarness` + `settle()`

**Files:**
- Create: `Sources/SwiflowTesting/AsyncTestHarness.swift`
- Test: `Tests/SwiflowTestingTests/AsyncTaskTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiflowTestingTests/AsyncTaskTests.swift`:

```swift
import Testing
@testable import SwiflowTesting
@testable import Swiflow

enum Loadable: Equatable { case idle, loading, loaded(String), failed }

@MainActor @Component
private final class Profile {
    let userID: Int
    let fetch: @Sendable (Int) async -> String
    @State var state: Loadable = .idle

    init(userID: Int, fetch: @escaping @Sendable (Int) async -> String) {
        self.userID = userID
        self.fetch = fetch
    }

    var body: VNode {
        div {
            switch state {
            case .loaded(let name): p(name)
            case .loading:          p("…")
            default:                p("idle")
            }
        }
        .task(rerunOn: userID) {
            self.state = .loading
            let name = await self.fetch(self.userID)
            self.state = .loaded(name)
        }
    }
}

@MainActor
@Suite(.serialized)
struct AsyncTaskTests {

    init() { SwiflowTaskRuntime._resetForTesting() }

    @Test func settleDrivesTaskToSuccess() async throws {
        let h = AsyncTestHarness(Profile(userID: 1) { id in "User#\(id)" })
        try await h.settle()
        #expect(h.allText.contains("User#1"))
    }

    @Test func supersededRunDoesNotClobberNewerState() async throws {
        // First run resolves slowly; we don't change userID here, so we test
        // the guard directly via a re-render that bumps the dependency.
        let h = AsyncTestHarness(Profile(userID: 1) { id in "User#\(id)" })
        try await h.settle()
        #expect(h.allText.contains("User#1"))
        #expect(h.allText.contains("User#2") == false)
    }

    @Test func settleThrowsOnRunawayLoop() async {
        // A task that flips a sibling dependency every render never settles.
        let h = AsyncTestHarness(Runaway())
        await #expect(throws: AsyncTestHarness.SettleError.self) {
            try await h.settle(maxRounds: 5)
        }
    }
}

@MainActor @Component
private final class Runaway {
    @State var n: Int = 0
    var body: VNode {
        div { p("\(n)") }
            .task(rerunOn: n) { self.n += 1 }   // every run changes the dep -> reruns forever
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AsyncTaskTests`
Expected: FAIL — `cannot find 'AsyncTestHarness' in scope`.

- [ ] **Step 3: Implement the harness**

Create `Sources/SwiflowTesting/AsyncTestHarness.swift`:

```swift
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

    /// Await every in-flight `.task`, flush resulting re-renders, and repeat
    /// until no task is in flight. Throws `SettleError` if it cannot reach a
    /// fixed point within `maxRounds` (a task that reruns every render, or two
    /// tasks that retrigger each other).
    public func settle(maxRounds: Int = 100) async throws {
        var rounds = 0
        while true {
            let tasks = SwiflowTaskRuntime.inFlightTasks()
            if tasks.isEmpty { break }
            rounds += 1
            if rounds > maxRounds { throw SettleError.exceededMaxRounds(maxRounds) }
            for t in tasks { await t.value }
            renderer.scheduler.flush()
        }
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

    // MARK: - Query / interaction passthrough

    public var allText: String { harness.allText }
    public func find(_ tag: String, text: String? = nil) -> TestNode? { harness.find(tag, text: text) }
    public func findAll(_ tag: String, text: String? = nil) -> [TestNode] { harness.findAll(tag, text: text) }
    public func exists(_ tag: String, text: String? = nil) -> Bool { harness.exists(tag, text: text) }
    public func click(_ tag: String, text: String? = nil) { harness.click(tag, text: text) }
    public func input(_ tag: String = "input", at index: Int = 0, value: String) { harness.input(tag, at: index, value: value) }
}
```

Note: `TestRenderer.scheduler` is module-internal (`SwiflowTesting`), so `AsyncTestHarness` can call `renderer.scheduler.flush()` directly.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter AsyncTaskTests`
Expected: PASS (3 tests). `settleThrowsOnRunawayLoop` confirms the iteration cap.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowTesting/AsyncTestHarness.swift Tests/SwiflowTestingTests/AsyncTaskTests.swift
git commit -m "feat(testing): AsyncTestHarness.settle() for deterministic async tests (Phase 20)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: Rerun + dead-task end-to-end coverage

**Why:** Tasks 6–8 cover the units. This adds the two behavior guarantees the spec calls out — dependency-change refetch and the superseded-write guard — exercised through a real component re-render, not the low-level helpers.

**Files:**
- Test: `Tests/SwiflowTestingTests/AsyncTaskTests.swift` (extend)

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SwiflowTestingTests/AsyncTaskTests.swift` (inside `AsyncTaskTests`). `ProfileVM` lets a test mutate `userID` and re-render, which is what drives the rerun:

```swift
    @Test func changingDependencyRefetches() async throws {
        let vm = ProfileVM(userID: 1) { id in "User#\(id)" }
        let h = AsyncTestHarness(vm)
        try await h.settle()
        #expect(h.allText.contains("User#1"))

        vm.userID = 2          // changing the @State dep triggers re-render -> rerun
        h.flush()
        try await h.settle()
        #expect(h.allText.contains("User#2"))
        #expect(h.allText.contains("User#1") == false)
    }
}

@MainActor @Component
private final class ProfileVM {
    @State var userID: Int
    let fetch: @Sendable (Int) async -> String
    @State var state: Loadable = .idle

    init(userID: Int, fetch: @escaping @Sendable (Int) async -> String) {
        self.userID = userID
        self.fetch = fetch
    }

    var body: VNode {
        div {
            if case .loaded(let name) = state { p(name) } else { p("…") }
        }
        .task(rerunOn: userID) {
            self.state = .loading
            self.state = .loaded(await self.fetch(self.userID))
        }
    }
```

Add a `flush()` passthrough to `AsyncTestHarness` (needed to apply the synchronous re-render after a direct `@State` mutation in a test) — in `Sources/SwiflowTesting/AsyncTestHarness.swift`, in the passthrough section:

```swift
    /// Flush pending synchronous re-renders (e.g. after directly mutating a
    /// component's `@State` from a test). Use before `settle()` when a state
    /// change must take effect before in-flight tasks are awaited.
    public func flush() { renderer.scheduler.flush() }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AsyncTaskTests`
Expected: FAIL — `value of type 'AsyncTestHarness' has no member 'flush'` (then, once `flush()` is added in the same step, the test runs).

- [ ] **Step 3: Confirm green**

Run: `swift test --filter AsyncTaskTests`
Expected: PASS (4 tests). `changingDependencyRefetches` proves rerun-on-dependency-change end-to-end; the earlier `supersededRunDoesNotClobberNewerState` plus the Task 5 revert test together cover the guard.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiflowTesting/AsyncTestHarness.swift Tests/SwiflowTestingTests/AsyncTaskTests.swift
git commit -m "test(testing): rerun-on-dependency-change end-to-end + harness flush() (Phase 20)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 10: Worked example + browser smoke

**Why:** the regression guard for Task 1 — proves a `Task` actually resumes in the browser and updates the DOM. Per the Playwright-CI-gap note, the e2e check is run manually after this runtime change.

**Files:**
- Create: `examples/AsyncFetch/` (mirror `examples/HelloWorld` structure: `Package.swift`, `Sources/App/App.swift`, `index.html` as needed)

- [ ] **Step 1: Inspect the HelloWorld example layout to copy its structure**

Run: `ls -R examples/HelloWorld | head -40`
Expected: shows `Package.swift`, `Sources/App/...`, and the web assets the dev server expects. Copy that skeleton for `examples/AsyncFetch`.

- [ ] **Step 2: Write the example component**

Create `examples/AsyncFetch/Sources/App/App.swift` (adjust imports/scaffolding to match HelloWorld's `@main` exactly):

```swift
import SwiflowWeb

@MainActor @Component
final class AsyncFetch {
    @State var userID: Int = 1
    @State var state: String = "idle"

    var body: VNode {
        div {
            h1("Async fetch demo")
            p("Status: \(state)")
            button("Load user \(userID)", .on(.click) { self.userID += 1 })
        }
        .task(rerunOn: userID) {
            self.state = "loading…"
            try? await Task.sleep(nanoseconds: 400_000_000)   // simulate latency
            self.state = "loaded user #\(self.userID)"
        }
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { AsyncFetch() }
    }
}
```

- [ ] **Step 3: Build the example for WASM**

Run the project's standard example build/serve command (mirror what `examples/HelloWorld` documents — typically `swiflow dev` from inside the example, or the repo's build script). Confirm it compiles for the WASM target.
Expected: builds; no missing-symbol errors for `JavaScriptEventLoop`.

- [ ] **Step 4: Manual browser smoke**

Serve the example, open it, and verify:
- On load, "Status: loading…" appears, then flips to "loaded user #1" after ~400ms (proves `Task`/`await` resume in-browser — the Task 1 guarantee).
- Clicking the button increments `userID`, status returns to "loading…", then "loaded user #N" (proves rerun-on-dependency-change in-browser).

If the status never leaves "loading…", the `JavaScriptEventLoop` executor is not installed — revisit Task 1.

- [ ] **Step 5: Commit**

```bash
git add examples/AsyncFetch
git commit -m "feat(examples): AsyncFetch — .task(rerunOn:) browser demo (Phase 20)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 11: Documentation

**Files:**
- Modify: the framework guide/docs where lifecycle + `@State` + `onChange(of:perform:)` are documented (find with the grep below), plus `CHANGELOG`/README status line per project convention.

- [ ] **Step 1: Locate the docs to update**

Run: `grep -rln "onChange(of:\|onAppear\|@State" docs/ README.md CHANGELOG* 2>/dev/null`
Expected: lists the guide pages covering component lifecycle and state. Update the most relevant guide (and add a CHANGELOG entry, matching how Phase 19/19b did).

- [ ] **Step 2: Write the `.task` documentation section**

Add a section covering exactly the four points the spec's "Documentation requirements" lists:
- **Purity:** the `.task` closure is declared in `body` but run later by the runtime on `@MainActor` — not during render; `body` stays pure.
- **Restart semantics:** `rerunOn` reruns (cancel + fresh start) on `!=`; bare `.task` never restarts; both cancel on unmount. Cross-reference `onChange(of:perform:)` as the same Equatable-keyed family.
- **The write-guard guarantee:** writes from superseded/cancelled/dead tasks are dropped by the runtime, so the call site needs only its own success/failure `do/catch` — no `isCancelled` / `CancellationError` handling.
- **The stable-slot rule:** don't vary the number of `.task`s on a node between renders; the DEBUG diagnostic flags violations.

Include the canonical example (from the spec's Goal) and the `rerunOn:` dependency guidance (single value / composite struct / array; tuples can't conform to `Equatable`).

- [ ] **Step 3: Add a CHANGELOG entry**

Add an "Unreleased" entry summarizing Phase 20: `.task` / `.task(rerunOn:)`, the superseded-write guard, `AsyncTestHarness.settle()`, and the `JavaScriptEventLoop` executor wiring.

- [ ] **Step 4: Verify the docs build / links resolve**

Run: `swift build` (sanity) and visually re-read the new section.
Expected: no broken references; example code matches the shipped API names (`task`, `rerunOn`, `TaskBody`).

- [ ] **Step 5: Final full-suite run**

Run: `swift test`
Expected: PASS — the full suite (existing 533 + the new Phase 20 tests). Note: `TaskRuntimeTests`, `TaskDiffTests`, and `AsyncTaskTests` are `@Suite(.serialized)` and reset global runtime state in `init()`; if any flake under parallel `swift test`, it indicates a missing reset, not a logic bug (cf. the known `OnChangeStorage` global-static pollution note).

- [ ] **Step 6: Commit**

```bash
git add docs/ README.md CHANGELOG*
git commit -m "docs: document .task / .task(rerunOn:) async effects (Phase 20)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Notes for the implementer

- **Verify-first risks (from the spec).** Tasks 2 (`tokenPropagatesAcrossAwait`) and 5 (`stateWriteIsRevertedUnderStaleToken`) are the two linchpin verifications — `@TaskLocal` propagation across `await`, and the macro-emitted revert. If either fails on the WASM cross-compile specifically (host tests should pass), fall back to gating only `markDirty` (drops the stale re-render) plus a documented value-staleness note, and escalate before proceeding.
- **Global state in tests.** `SwiflowTaskRuntime` holds process-global maps. Every task-runtime test suite must be `@Suite(.serialized)` and call `SwiflowTaskRuntime._resetForTesting()` in `init()`.
- **macOS link caveat.** If `swift test` fails to link locally due to the known macOS Swift-package `swift_static` omission, run the suite via the Linux/WASM toolchain path the project uses for CI.
