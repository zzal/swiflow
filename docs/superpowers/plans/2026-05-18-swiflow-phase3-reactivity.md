# Swiflow Phase 3 — Reactivity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the manual `Swiflow.rerender()` model with `@State`-driven Components that re-render automatically, batched per `requestAnimationFrame`, with `onMount`/`onUpdate(prev:)`/`onUnmount` lifecycle hooks and React-style position-based identity.

**Architecture:** A `Component` protocol with `var body: VNode` lives in `Sources/Swiflow/` and is embeddable in any VNode tree via a new `VNode.component(ComponentDescription)` case. Mount-tree nodes gain an optional `component` slot that holds the live instance across renders. `@State` is a property wrapper that, via Mirror introspection at instance-construction time, gets a callback into a per-renderer `Scheduler` that marks the owning component dirty. The Scheduler batches dirty components per rAF tick, walks them in mount order, calls `body` on each, runs the existing diff against the previous body output, and ships one consolidated patch batch.

**Tech Stack:**
- Swift 6 (strict concurrency, `@MainActor` for the renderer/scheduler)
- Existing Swiflow diff + patch + handler infrastructure (no replacements)
- `Sources/Swiflow/Reactivity/` subdirectory for the new reactive primitives
- JavaScriptKit's `JSObject.global.requestAnimationFrame` for the rAF binding (WASM-only)
- Swift Testing for unit coverage; existing `DevCommandIntegrationTests` for e2e

---

## Out-of-scope for Phase 3

To keep this phase finishable:
- **Fine-grained reactivity** (`@Observable` / signal-style). Coarse `@State`-triggers-owner only.
- **Suspense / async components.** Body must produce a VNode synchronously.
- **Context / dependency injection.** Components only see what's wired via init or `@State`.
- **Multiple render roots.** Single `Swiflow.render(Component, into:)` per app; the existing precondition holds.
- **Server-side rendering / static export.**
- **Component DevTools / time-travel.**

---

## Design decisions (locked from spec §6, plus implementation specifics)

The spec sketches Phase 3 but leaves implementation details open. These are pinned now:

1. **Component is a class-bound protocol.** Reference semantics: state mutations should be visible to the framework without explicit copy/return. `protocol Component: AnyObject`.

2. **`var body: VNode` is synchronous.** Async bodies (suspense, data fetching) are post-Phase 4.

3. **Lifecycle hooks:** `onMount()`, `onUpdate(prev: Self)`, `onUnmount()`. Defaulted to no-op via protocol extension. `prev` is the same instance — Components don't get "snapshotted"; the hook receives `self` for symmetry with React's `prevProps`-style signature, but in practice the component will compare `@State` values it already owns. (This is a minor concession to ergonomics; we may revisit if it confuses users.)

4. **Position-based identity, type+key matched.** At the same child index, if `oldVNode.component.typeID == newVNode.component.typeID` and `oldVNode.component.key == newVNode.component.key`, the instance is reused. Otherwise the old is destroyed and a new instance is created.

5. **`@State` is a class-instance property wrapper** with a heap-allocated storage box. The wrapper has a private `_owner: AnyComponent?` and `_scheduler: Scheduler?` set by the framework at component-construction time via Mirror walk. Setter calls `scheduler.markDirty(owner)`.

6. **The Scheduler is `@MainActor`-isolated and per-renderer.** WASM runs on a single thread; the actor model reflects reality and silences strict-concurrency warnings. Tests use the in-process `flush()` API; production uses rAF.

7. **Mount tree extension:** `MountNode` gains optional `component: AnyComponent?` and `componentBody: MountNode?`. A component-anchor node is a MountNode whose `vnode` is `.component(...)` and whose `componentBody` is the mounted body subtree. The component-anchor has a handle (assigned via HandleAllocator) but does NOT correspond to a DOM node — it's purely structural. The diff threads through it: child operations on the parent's children list see the component-anchor's `componentBody.handle` as the DOM-level child handle.

8. **VNode equality with components is by reference identity.** `case component(let desc)` ≡ `case component(let other)` iff `desc.typeID == other.typeID && desc.key == other.key`. The factory closure isn't compared (closures aren't equatable). This means two `Counter()` invocations at the same position produce equal VNodes — the diff doesn't see them as "different."

9. **DSL embedding:** A free function `component(_ factory: @escaping () -> some Component, key: String? = nil) -> VNode` produces the `.component(...)` case. The Hello World template embeds the root via `Swiflow.render(Counter(), into: "#app")` (a separate overload — see Task 8).

10. **No automatic state batching across event handlers.** A single click handler that mutates three `@State` properties produces three `markDirty` calls but only one rAF callback (set semantics). State mutations during the body() pass are an error — flagged via runtime check.

---

## File structure

### New files
- `Sources/Swiflow/Reactivity/Component.swift` — protocol, AnyComponent type erasure, ComponentDescription
- `Sources/Swiflow/Reactivity/State.swift` — `@State` property wrapper with Box storage
- `Sources/Swiflow/Reactivity/Scheduler.swift` — protocol + InProcessScheduler (testable)
- `Sources/Swiflow/Reactivity/Lifecycle.swift` — hook protocol extension defaults
- `Sources/Swiflow/DSL/ComponentDSL.swift` — `component(_:key:)` factory
- `Sources/SwiflowWeb/RAFScheduler.swift` — rAF-backed Scheduler conformance
- `Tests/SwiflowTests/Reactivity/ComponentTests.swift`
- `Tests/SwiflowTests/Reactivity/StateTests.swift`
- `Tests/SwiflowTests/Reactivity/SchedulerTests.swift`
- `Tests/SwiflowTests/Reactivity/ComponentDiffTests.swift`

### Modified files
- `Sources/Swiflow/VNode.swift` — add `case component(ComponentDescription)` + Equatable update
- `Sources/Swiflow/MountTree.swift` — add `component` and `componentBody` optional slots
- `Sources/Swiflow/Diff/Diff.swift` — mount/update/destroy paths for `.component`
- `Sources/SwiflowWeb/SwiflowWeb.swift` — add `render(_:into:)` overload for Component, expose Scheduler binding
- `Sources/SwiflowWeb/Renderer.swift` — accept Component root, integrate Scheduler, fire lifecycle hooks
- `Sources/SwiflowCLI/Templates/Templates.swift` — Hello World becomes `Counter: Component` with `@State`

---

## Test-coverage plan

Per task, write tests first. Aggregate coverage at end of phase:
- **Unit:** Component, @State, Scheduler, .component case in diff
- **Integration:** Renderer drives Component through mount/update/unmount with hooks
- **End-to-end:** Existing `DevCommandIntegrationTests` exercises the rebuilt Counter template; no new e2e test needed if the existing one stays green after the template flip.

Total expected new tests: ~30. Total new + modified LOC: ~1,200.

---

## Task ordering (with natural pause point after Task 5)

Tasks 1–5 build the foundation and minimum viable integration. After Task 5 the pieces compose, but `@State` isn't wired (Tasks 6–7) and the Renderer doesn't accept a Component root yet (Task 8). Pause point at end of Task 5 = "the new types exist and the diff handles them; the next slice wires the user-facing reactivity."

---

### Task 1: Component protocol + AnyComponent type erasure + ComponentDescription

**Files:**
- Create: `Sources/Swiflow/Reactivity/Component.swift`
- Create: `Tests/SwiflowTests/Reactivity/ComponentTests.swift`

**Notes for the implementer:**
- `Component` is `AnyObject`-bound (class-only). This gives reference semantics — `@State` mutations are visible without copy/return.
- `AnyComponent` is a `final class` wrapper that erases the Component conformance and exposes `typeID: ObjectIdentifier` and an `instance: Component` projection. It's needed so MountNode can hold a heterogeneous component reference without conditional conformance gymnastics.
- `ComponentDescription` is a `Sendable`-safe value: type identity + optional key + a `factory` closure (non-Sendable in Phase 3 — components themselves aren't Sendable yet).
- Lifecycle hooks default to no-op via protocol extension. Implementations are expected to override only what they need.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/Reactivity/ComponentTests.swift
import Testing
@testable import Swiflow

@Suite("Component")
struct ComponentTests {

    final class Counter: Component {
        var clickCount = 0
        var body: VNode { .text("count=\(clickCount)") }
    }

    final class Greeter: Component {
        var body: VNode { .text("hi") }
    }

    @Test("AnyComponent erases concrete type but preserves identity")
    func anyComponentIdentity() {
        let counter = Counter()
        let erased = AnyComponent(counter)
        #expect(erased.typeID == ObjectIdentifier(Counter.self))
        #expect(erased.instance === counter)
    }

    @Test("Default lifecycle hooks are no-ops (Counter doesn't override)")
    func defaultLifecycleNoops() {
        let counter = Counter()
        counter.onMount()
        counter.onUpdate(prev: counter)
        counter.onUnmount()
        // No assertion needed — just verifying these compile and don't crash.
        #expect(counter.clickCount == 0)
    }

    @Test("ComponentDescription captures typeID and key for diff identity")
    func descriptionIdentity() {
        let d1 = ComponentDescription(typeID: ObjectIdentifier(Counter.self), key: nil, factory: { Counter() })
        let d2 = ComponentDescription(typeID: ObjectIdentifier(Counter.self), key: nil, factory: { Counter() })
        let d3 = ComponentDescription(typeID: ObjectIdentifier(Greeter.self), key: nil, factory: { Greeter() })
        let d4 = ComponentDescription(typeID: ObjectIdentifier(Counter.self), key: "a", factory: { Counter() })
        #expect(d1 == d2)
        #expect(d1 != d3)
        #expect(d1 != d4)
    }

    @Test("ComponentDescription.instantiate() invokes the factory and returns AnyComponent")
    func instantiateProducesAnyComponent() {
        let desc = ComponentDescription(typeID: ObjectIdentifier(Counter.self), key: nil, factory: { Counter() })
        let any1 = desc.instantiate()
        let any2 = desc.instantiate()
        #expect(any1.typeID == ObjectIdentifier(Counter.self))
        #expect(any1.instance !== any2.instance, "Each instantiate() must produce a fresh instance")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "Component"` (from repo root)
Expected: compile error — `Component`, `AnyComponent`, `ComponentDescription` don't exist.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/Swiflow/Reactivity/Component.swift

/// A reactive UI building block.
///
/// Components are reference-typed (class-bound) so that property mutations
/// — typically driven by `@State` — are visible to the framework without
/// the caller having to return a new value. Instances live across renders
/// when the parent's diff finds a same-position, same-type, same-key match;
/// the diff calls `body` again on the reused instance and reconciles the
/// result against the previously-mounted body subtree.
///
/// Conforming types should:
/// 1. Implement `var body: VNode` — pure, synchronous, runs every render.
/// 2. Optionally override `onMount`, `onUpdate(prev:)`, `onUnmount`.
/// 3. Declare reactive state with `@State` (Task 2) — direct stored
///    properties work but don't trigger re-renders.
public protocol Component: AnyObject {
    /// The view this component renders. Called by the diff on every render.
    /// Must be pure (no side effects) — the renderer doesn't memoize.
    var body: VNode { get }

    /// Called once after the component's body has been mounted to the DOM.
    /// Defaulted to no-op.
    func onMount()

    /// Called after every re-render's patches have been applied.
    /// `prev` is the same instance (reference equality holds); the parameter
    /// exists for symmetry with React's `prevProps` signature. Defaulted
    /// to no-op.
    func onUpdate(prev: Self)

    /// Called immediately before the component's subtree is destroyed.
    /// Defaulted to no-op.
    func onUnmount()
}

public extension Component {
    func onMount() {}
    func onUpdate(prev: Self) {}
    func onUnmount() {}
}

/// Type-erased reference to a `Component`. Stored on `MountNode` so the
/// mount tree can hold heterogeneous component instances without
/// conditional-conformance gymnastics. `typeID` is the identity used by the
/// diff to decide instance reuse.
public final class AnyComponent {
    public let typeID: ObjectIdentifier
    public let instance: any Component

    public init<C: Component>(_ instance: C) {
        self.typeID = ObjectIdentifier(C.self)
        self.instance = instance
    }
}

/// A value-typed factory description, used as the payload of
/// `VNode.component`. The diff compares descriptions by `typeID` + `key`;
/// two descriptions of the same component type at the same position are
/// considered the same and the existing instance is reused.
///
/// The `factory` closure isn't part of equality — closures aren't
/// equatable, and the factory is only consumed at first mount. Subsequent
/// renders with the same typeID + key reuse the existing AnyComponent.
public struct ComponentDescription: Equatable {
    public let typeID: ObjectIdentifier
    public let key: String?
    public let factory: () -> AnyComponent

    public init(typeID: ObjectIdentifier, key: String?, factory: @escaping () -> AnyComponent) {
        self.typeID = typeID
        self.key = key
        self.factory = factory
    }

    /// Convenience init for the common case: a concrete Component factory.
    public init<C: Component>(_ type: C.Type, key: String? = nil, factory: @escaping () -> C) {
        self.typeID = ObjectIdentifier(type)
        self.key = key
        self.factory = { AnyComponent(factory()) }
    }

    public func instantiate() -> AnyComponent {
        factory()
    }

    public static func == (lhs: ComponentDescription, rhs: ComponentDescription) -> Bool {
        lhs.typeID == rhs.typeID && lhs.key == rhs.key
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "Component"`
Expected: PASS — 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Reactivity/Component.swift Tests/SwiflowTests/Reactivity/ComponentTests.swift
git commit -m "feat(reactivity): Component protocol, AnyComponent, ComponentDescription"
```

---

### Task 2: @State property wrapper

**Files:**
- Create: `Sources/Swiflow/Reactivity/State.swift`
- Create: `Tests/SwiflowTests/Reactivity/StateTests.swift`

**Notes for the implementer:**
- `@State` is a class-instance property wrapper. The underlying storage is a heap-allocated `Box<Value>` so the wrapper itself is small and mutations are visible across reads.
- The wrapper has `_owner: AnyComponent?` and `_scheduler: WeakScheduler?` slots set later by the framework (Task 7). Until those are set, `wrappedValue` setter just stores — no scheduling. This lets tests construct `@State` values directly without a full Renderer.
- Class-instance property wrappers in Swift require `static subscript(_enclosingInstance:wrapped:storage:)` to access the enclosing instance — but that's complex and not needed for Phase 3. Instead, the framework will set `_owner`/`_scheduler` explicitly via Mirror walk on component construction (Task 7). This is simpler and avoids the subscript boilerplate.
- The Box is internal-but-`@_spi`-visible so Task 7's owner-injection can find and rewrite it. Or: expose `_setOwner(_:scheduler:)` as a `public` method on the wrapper. Going with the explicit method — simpler to grep, no SPI needed.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/Reactivity/StateTests.swift
import Testing
@testable import Swiflow

@Suite("@State")
struct StateTests {

    @Test("Initial value is preserved")
    func initialValue() {
        let state = State(wrappedValue: 42)
        #expect(state.wrappedValue == 42)
    }

    @Test("Mutation updates the underlying storage")
    func mutationUpdates() {
        let state = State(wrappedValue: 0)
        state.wrappedValue = 17
        #expect(state.wrappedValue == 17)
    }

    @Test("projectedValue returns a Binding-shaped pair (read/write)")
    func projectedValueReadWrite() {
        let state = State(wrappedValue: "a")
        let binding = state.projectedValue
        #expect(binding.get() == "a")
        binding.set("b")
        #expect(state.wrappedValue == "b")
    }

    @Test("Without an owner+scheduler, mutation is silent (no crash)")
    func noOwnerSilent() {
        let state = State(wrappedValue: 0)
        state.wrappedValue = 99
        // No scheduler attached — must not crash, must not try to schedule.
        #expect(state.wrappedValue == 99)
    }

    @Test("With owner+scheduler, mutation calls scheduler.markDirty exactly once per assignment")
    func mutationSchedules() {
        final class StubComponent: Component { var body: VNode { .text("") } }
        final class CountingScheduler: Scheduler {
            var markCount = 0
            var lastMarked: AnyComponent?
            func markDirty(_ component: AnyComponent) {
                markCount += 1
                lastMarked = component
            }
            func flush() {}
        }

        let owner = AnyComponent(StubComponent())
        let scheduler = CountingScheduler()
        let state = State(wrappedValue: 0)
        state._setOwner(owner, scheduler: scheduler)

        state.wrappedValue = 1
        state.wrappedValue = 2
        #expect(scheduler.markCount == 2)
        #expect(scheduler.lastMarked?.instance === owner.instance)
    }
}
```

> The `Scheduler` protocol referenced here is defined in Task 6. Reorder if tests need to compile before Task 6 lands; the simplest fix is to land Task 6 before Task 2's `mutationSchedules` test. **Task ordering note:** swap Tasks 2 and 6, or write Task 2 with a minimal local `Scheduler` protocol stub that Task 6 then formalizes. Going with the local-stub approach — Task 6 will replace it with the real definition. See the "Task 2/6 ordering" note in the implementer prompt.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "@State"`
Expected: compile error — `State` doesn't exist; `Scheduler` doesn't exist (yet).

- [ ] **Step 3: Write the implementation (with a minimal local Scheduler stub)**

```swift
// Sources/Swiflow/Reactivity/State.swift

/// Reactive state for a Component. Mutating `wrappedValue` flags the
/// owning component as dirty with the active Scheduler, which batches
/// re-renders per `requestAnimationFrame`.
///
/// Without an owner wired in, mutations are silent — useful for tests
/// constructing `@State` values outside a Renderer. The framework wires
/// the owner via `_setOwner(_:scheduler:)` at component-construction time
/// (Task 7's Mirror walk).
///
/// Usage:
/// ```swift
/// final class Counter: Component {
///     @State var count = 0
///     var body: VNode { p("\(count)") }
/// }
/// ```
@propertyWrapper
public final class State<Value> {
    private let storage: Box<Value>
    // Weak/optional so the framework can attach the owner post-construction
    // without circularity headaches. Set exactly once per @State per
    // component instance.
    private var _owner: AnyComponent?
    private weak var _scheduler: AnyObject?  // erased; cast back to Scheduler

    public init(wrappedValue: Value) {
        self.storage = Box(value: wrappedValue)
    }

    public var wrappedValue: Value {
        get { storage.value }
        set {
            storage.value = newValue
            if let owner = _owner, let scheduler = _scheduler as? Scheduler {
                scheduler.markDirty(owner)
            }
        }
    }

    public var projectedValue: Binding<Value> {
        Binding(
            get: { self.storage.value },
            set: { self.wrappedValue = $0 }
        )
    }

    /// Called by the framework at component-construction time (Task 7).
    /// Idempotent; redundant calls overwrite the previous owner.
    public func _setOwner(_ owner: AnyComponent, scheduler: Scheduler) {
        self._owner = owner
        self._scheduler = scheduler as AnyObject
    }
}

/// Two-way binding shaped like SwiftUI's. Internal use only in Phase 3 —
/// the public surface is just `$state` returning this.
public struct Binding<Value> {
    public let get: () -> Value
    public let set: (Value) -> Void

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        self.get = get
        self.set = set
    }
}

/// Heap-allocated value cell. Used by `@State` so the wrapper struct stays
/// small and mutations through the property wrapper are visible across
/// reads (no copy-on-mutation surprises).
final class Box<Value> {
    var value: Value
    init(value: Value) { self.value = value }
}

// Minimal local Scheduler protocol stub. Task 6 replaces this with the
// canonical definition in Sources/Swiflow/Reactivity/Scheduler.swift.
// IMPORTANT FOR THE TASK-6 IMPLEMENTER: delete the body of this protocol
// declaration when you create the canonical one. Leave a re-export comment
// so this file's import requirements stay clear.
#if !SWIFLOW_SCHEDULER_DEFINED_ELSEWHERE
public protocol Scheduler: AnyObject {
    func markDirty(_ component: AnyComponent)
    func flush()
}
#endif
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "@State"`
Expected: PASS — 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Reactivity/State.swift Tests/SwiflowTests/Reactivity/StateTests.swift
git commit -m "feat(reactivity): @State property wrapper with Box storage + Binding"
```

---

### Task 3: VNode.component case + ComponentDescription wiring + DSL embedding

**Files:**
- Modify: `Sources/Swiflow/VNode.swift` (add case + Equatable)
- Create: `Sources/Swiflow/DSL/ComponentDSL.swift` (free function `component(_:key:)`)
- Modify: `Sources/Swiflow/DSL/ResultBuilder.swift` (accept VNode.component in children)
- Create: `Tests/SwiflowTests/Reactivity/ComponentVNodeTests.swift`

**Notes for the implementer:**
- The existing `VNode` enum is `indirect enum VNode: Equatable { case element(ElementData) case text(String) case rawHTML(String) }`. Add `case component(ComponentDescription)` and update the synthesized Equatable to consider it. Swift's auto-synthesis handles this because `ComponentDescription` is `Equatable`.
- ResultBuilder's `buildBlock` returns `[VNode]` so accepting a `VNode.component` is automatic — no changes to the builder body needed. But verify by exercising it in a test.
- The DSL free function is named `component(_:key:)`. Signature: `public func component<C: Component>(_ factory: @escaping () -> C, key: String? = nil) -> VNode`. Avoid name collision with the proposed `Component` protocol by relying on Swift's lowercase-function / uppercase-type disambiguation.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/Reactivity/ComponentVNodeTests.swift
import Testing
@testable import Swiflow

@Suite("VNode.component")
struct ComponentVNodeTests {

    final class Counter: Component {
        var body: VNode { .text("0") }
    }

    final class Greeter: Component {
        var body: VNode { .text("hi") }
    }

    @Test("VNode.component is constructable and Equatable by typeID + key")
    func componentCaseEquatable() {
        let a = VNode.component(.init(Counter.self) { Counter() })
        let b = VNode.component(.init(Counter.self) { Counter() })
        let c = VNode.component(.init(Greeter.self) { Greeter() })
        let d = VNode.component(.init(Counter.self, key: "list-row") { Counter() })

        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
    }

    @Test("DSL `component(_:key:)` produces a VNode.component case")
    func dslComponentFreeFunction() {
        let v = component({ Counter() })
        guard case .component(let desc) = v else {
            Issue.record("Expected .component case, got \(v)")
            return
        }
        #expect(desc.typeID == ObjectIdentifier(Counter.self))
        #expect(desc.key == nil)
    }

    @Test("DSL accepts key argument")
    func dslComponentWithKey() {
        let v = component({ Counter() }, key: "row-7")
        guard case .component(let desc) = v else {
            Issue.record("Expected .component case")
            return
        }
        #expect(desc.key == "row-7")
    }

    @Test("ResultBuilder accepts component children alongside element children")
    func builderMixesElementsAndComponents() {
        let parent = div {
            h1("Heading")
            component({ Counter() })
            p("Footer")
        }
        guard case .element(let data) = parent else {
            Issue.record("Expected .element"); return
        }
        #expect(data.children.count == 3)
        if case .component = data.children[1] {
            // ok
        } else {
            Issue.record("Expected children[1] to be .component, got \(data.children[1])")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "VNode.component"`
Expected: compile error — `VNode.component` case doesn't exist; `component` free function doesn't exist.

- [ ] **Step 3: Add `.component` case to VNode**

In `Sources/Swiflow/VNode.swift`, modify the enum and the doc comment:

```swift
public indirect enum VNode: Equatable {
    case element(ElementData)
    case text(String)
    case rawHTML(String)
    /// A component anchor. Carries identity (`typeID` + `key`) and a factory
    /// closure consumed at first mount. Subsequent renders with an equal
    /// description at the same child position reuse the existing instance.
    /// Phase 3+.
    case component(ComponentDescription)
}
```

The synthesized Equatable picks up the new case automatically because `ComponentDescription` is `Equatable`. Verify with the test in Step 1.

- [ ] **Step 4: Add the DSL free function**

Create `Sources/Swiflow/DSL/ComponentDSL.swift`:

```swift
// Sources/Swiflow/DSL/ComponentDSL.swift

/// Embeds a Component in a VNode tree.
///
/// Usage in a parent component's body:
/// ```swift
/// div {
///     h1("Header")
///     component({ Counter() })           // unkeyed
///     component({ Counter() }, key: "a") // keyed; survives reorder
/// }
/// ```
///
/// The `factory` closure is invoked at first mount only. Subsequent renders
/// that produce an equal `ComponentDescription` at the same child position
/// reuse the existing instance (so `@State` survives re-renders).
public func component<C: Component>(
    _ factory: @escaping () -> C,
    key: String? = nil
) -> VNode {
    .component(ComponentDescription(C.self, key: key, factory: factory))
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter "VNode.component"`
Expected: PASS — 4 tests pass.

- [ ] **Step 6: Verify no other test broke**

Run: `swift test --skip "DevCommand end-to-end" --skip "BuildCommand end-to-end"`
Expected: all unit tests still pass. The integration suites are skipped to save ~3 min — they don't touch VNode internals.

- [ ] **Step 7: Commit**

```bash
git add Sources/Swiflow/VNode.swift Sources/Swiflow/DSL/ComponentDSL.swift Tests/SwiflowTests/Reactivity/ComponentVNodeTests.swift
git commit -m "feat(vnode): add .component case + component(_:key:) DSL"
```

---

### Task 4: Mount path for VNode.component

**Files:**
- Modify: `Sources/Swiflow/MountTree.swift` (add `component` + `componentBody` slots)
- Modify: `Sources/Swiflow/Diff/Diff.swift` (handle `.component` in `mount()`)
- Create: `Tests/SwiflowTests/Reactivity/ComponentMountTests.swift`

**Notes for the implementer:**
- A component-anchor MountNode has its own handle (consumes one from HandleAllocator) but the handle does NOT correspond to a DOM element. The DOM-facing handle is `componentBody.handle`. This matters for the parent's `appendChild` patch — the parent must reference `componentBody.handle`, not the anchor's handle.
- Implementation choice: in `mount()`, when we hit `.component`:
  1. Instantiate the AnyComponent via `desc.instantiate()`.
  2. Call `instance.body` to get the body VNode.
  3. Recursively mount the body. This gives us a `componentBody: MountNode` with a real DOM handle.
  4. Allocate an anchor handle for the component-anchor MountNode (used as identity in the mount tree; the JS driver never sees it).
  5. Return a `MountNode` with the anchor handle, `vnode: .component(...)`, `component: instance`, `componentBody: bodyMount`.
- The caller in `mount()` for `.element` children currently does `patches.append(.appendChild(parent: h, child: childMount.handle))`. After this task, when `childMount` is a component anchor, the call site must use `childMount.componentBody?.handle ?? childMount.handle` — but the cleanest abstraction is a helper `MountNode.domHandle: Int` that returns `componentBody?.domHandle ?? handle`. Add this helper.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/Reactivity/ComponentMountTests.swift
import Testing
@testable import Swiflow

@Suite("Component mount path")
struct ComponentMountTests {

    final class Hello: Component {
        var body: VNode { h1("Hello") }
    }

    @Test("Mounting a bare component produces createElement + appendChild patches for its body")
    func mountBareComponent() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v = VNode.component(.init(Hello.self) { Hello() })

        let result = diff(mounted: nil, next: v, handles: handles, handlers: handlers)

        // We expect at minimum a createElement("h1") patch from the body.
        let createsH1 = result.patches.contains {
            if case .createElement(_, let tag) = $0, tag == "h1" { return true }
            return false
        }
        #expect(createsH1)

        // The returned mount tree's root is the component anchor; its
        // componentBody is the h1 mount node.
        let root = result.newMountTree
        if case .component = root.vnode {
            // ok
        } else {
            Issue.record("Root mount node should wrap .component, got \(root.vnode)")
        }
        #expect(root.component != nil, "Anchor should hold the AnyComponent instance")
        #expect(root.componentBody != nil, "Anchor should hold its mounted body")
        if case .element(let data) = root.componentBody?.vnode {
            #expect(data.tag == "h1")
        } else {
            Issue.record("componentBody should be an h1 element")
        }
    }

    @Test("Mounting a component as a child appends the body's DOM handle (not the anchor handle) to parent")
    func childComponentBodyHandleAppendedToParent() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let parent = div {
            component({ Hello() })
        }
        let result = diff(mounted: nil, next: parent, handles: handles, handlers: handlers)

        // Find the parent div's handle from its createElement patch.
        guard
            let createDiv = result.patches.first(where: { if case .createElement(_, let t) = $0, t == "div" { return true }; return false }),
            case .createElement(let parentHandle, _) = createDiv,
            let createH1 = result.patches.first(where: { if case .createElement(_, let t) = $0, t == "h1" { return true }; return false }),
            case .createElement(let h1Handle, _) = createH1
        else {
            Issue.record("Expected createElement patches for div and h1"); return
        }

        let appendsH1ToDiv = result.patches.contains {
            if case .appendChild(let p, let c) = $0, p == parentHandle, c == h1Handle { return true }
            return false
        }
        #expect(appendsH1ToDiv, "Parent div should appendChild the body's h1 handle, not the anchor handle")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "Component mount path"`
Expected: fail — `component` slot doesn't exist on MountNode; mount() doesn't handle .component.

- [ ] **Step 3: Extend `MountNode` with component slots**

In `Sources/Swiflow/MountTree.swift`, add:

```swift
    /// For a component-anchor mount node, the live instance. `nil` for
    /// every other node kind. Phase 3+.
    public var component: AnyComponent?

    /// For a component-anchor mount node, the mount-tree root of the
    /// instance's `body`. `nil` for every other node kind. Phase 3+.
    public var componentBody: MountNode?

    /// The JS-driver-visible handle for this node. For ordinary nodes
    /// it's `handle`; for a component anchor it's the body's `domHandle`.
    /// Use this whenever building a patch that references the DOM-side
    /// node (appendChild, insertBefore, removeChild).
    public var domHandle: Int {
        componentBody?.domHandle ?? handle
    }
```

Update the init signature to accept the new optional slots:

```swift
public init(
    handle: Int,
    vnode: VNode,
    children: [MountNode] = [],
    handlerIds: [String: Int] = [:],
    component: AnyComponent? = nil,
    componentBody: MountNode? = nil
) {
    self.handle = handle
    self.vnode = vnode
    self.children = children
    self.handlerIds = handlerIds
    self.component = component
    self.componentBody = componentBody
    for child in children {
        child.parent = self
    }
}
```

- [ ] **Step 4: Handle `.component` in `mount()`**

In `Sources/Swiflow/Diff/Diff.swift`, add a case to the switch in `mount()`:

```swift
    case .component(let desc):
        let instance = desc.instantiate()
        let bodyVNode = instance.instance.body
        let bodyMount = mount(bodyVNode, into: &patches, handles: handles, handlers: handlers)
        let anchorHandle = handles.next()
        return MountNode(
            handle: anchorHandle,
            vnode: vnode,
            component: instance,
            componentBody: bodyMount
        )
```

Then update every existing `appendChild` patch emission in `mount()` to use `childMount.domHandle` instead of `childMount.handle`. Currently the only such site is in the `.element` branch:

```swift
        for childVNode in data.children {
            let childMount = mount(
                childVNode,
                into: &patches,
                handles: handles,
                handlers: handlers
            )
            patches.append(.appendChild(parent: h, child: childMount.domHandle))  // <-- changed
            mountNode.addChild(childMount)
        }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter "Component mount path"`
Expected: PASS — 2 tests pass.

- [ ] **Step 6: Run the full diff/mount test suite to check for regressions**

Run: `swift test --filter "Diff" --skip "end-to-end"`
Expected: all existing diff/mount tests still pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/Swiflow/MountTree.swift Sources/Swiflow/Diff/Diff.swift Tests/SwiflowTests/Reactivity/ComponentMountTests.swift
git commit -m "feat(diff): mount path for VNode.component (anchor + body)"
```

---

### Task 5: Update path for VNode.component (with instance reuse on type+key match)

**Files:**
- Modify: `Sources/Swiflow/Diff/Diff.swift` (handle `(.component, .component)` and component branches in `update()` and `destroy()`)
- Create: `Tests/SwiflowTests/Reactivity/ComponentUpdateTests.swift`

**Notes for the implementer:**
- `update()` currently switches on `(mounted.vnode, next)`. Add three new cases:
  1. `(.component(let oldDesc), .component(let newDesc)) where oldDesc == newDesc` — reuse instance. Call `body` again on `mounted.component!.instance`, recursively `update()` the body subtree, store the new bodyMount back into `mounted.componentBody`. Return `mounted`.
  2. `(.component, .component)` (descriptions differ — typeID or key changed): fall through to the default "replace" path. The default already calls `destroy(mounted)` + `mount(next)`; verify it correctly walks the anchor (see destroy update below).
  3. The default "destroy + mount fresh" path's `destroy()` must recurse into `componentBody` (it currently only walks `node.children`).
- `destroy()` update: in addition to the existing children walk + handler-removal, recurse into `componentBody`. The anchor itself doesn't produce a `destroyNode` patch (no DOM node to destroy at the anchor's handle).

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/Reactivity/ComponentUpdateTests.swift
import Testing
@testable import Swiflow

@Suite("Component update path")
struct ComponentUpdateTests {

    final class Counter: Component {
        var n: Int = 0
        var body: VNode { p("count=\(n)") }
    }

    final class Greeter: Component {
        var body: VNode { p("hi") }
    }

    @Test("Same description at same position reuses the instance; body is re-rendered")
    func reuseOnTypeAndKeyMatch() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v1 = VNode.component(.init(Counter.self) { Counter() })

        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)
        let originalInstance = first.newMountTree.component?.instance as? Counter
        #expect(originalInstance != nil)
        originalInstance?.n = 42

        // Build a new VNode tree with the same description. Mutate the
        // instance's state to verify the diff re-renders the body (rather
        // than producing the "0" body from a fresh factory).
        let v2 = VNode.component(.init(Counter.self) { Counter() })
        let second = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        // Reused instance? Same reference.
        #expect(second.newMountTree.component?.instance === originalInstance)

        // The body's text node should have been updated to "count=42"
        // (a setText patch).
        let setTextTo42 = second.patches.contains {
            if case .setText(_, let text) = $0, text == "count=42" { return true }
            return false
        }
        #expect(setTextTo42, "Expected setText patch to 'count=42', got patches: \(second.patches)")
    }

    @Test("Different component type at same position destroys old and mounts new")
    func replaceOnTypeMismatch() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v1 = VNode.component(.init(Counter.self) { Counter() })
        let v2 = VNode.component(.init(Greeter.self) { Greeter() })

        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)
        let oldDomHandle = first.newMountTree.domHandle

        let second = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        let destroyed = second.patches.contains {
            if case .destroyNode(let h) = $0, h == oldDomHandle { return true }
            return false
        }
        #expect(destroyed, "Expected destroyNode for the old component's body")

        // New mount should have a different instance reference.
        let newInstance = second.newMountTree.component?.instance
        let oldInstance = first.newMountTree.component?.instance
        #expect(newInstance !== oldInstance)
    }

    @Test("Different key at same position destroys old and mounts new")
    func replaceOnKeyMismatch() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v1 = VNode.component(.init(Counter.self, key: "a") { Counter() })
        let v2 = VNode.component(.init(Counter.self, key: "b") { Counter() })

        let first = diff(mounted: nil, next: v1, handles: handles, handlers: handlers)
        let oldDomHandle = first.newMountTree.domHandle
        let second = diff(mounted: first.newMountTree, next: v2, handles: handles, handlers: handlers)

        let destroyed = second.patches.contains {
            if case .destroyNode(let h) = $0, h == oldDomHandle { return true }
            return false
        }
        #expect(destroyed)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "Component update path"`
Expected: fail — `update()` doesn't handle component cases.

- [ ] **Step 3: Implement update + destroy for components**

In `Sources/Swiflow/Diff/Diff.swift`, add cases to `update()`:

```swift
    // Component → component, same description: reuse instance.
    case (.component(let oldDesc), .component(let newDesc)) where oldDesc == newDesc:
        guard let instance = mounted.component, let oldBody = mounted.componentBody else {
            // Shouldn't happen — a component-anchor must have these — but
            // fall through to replace if the invariant is somehow broken.
            destroy(mounted, into: &patches, handlers: handlers)
            return mount(next, into: &patches, handles: handles, handlers: handlers)
        }
        let newBodyVNode = instance.instance.body
        let newBodyMount = update(
            mounted: oldBody,
            next: newBodyVNode,
            into: &patches,
            handles: handles,
            handlers: handlers
        )
        mounted.componentBody = newBodyMount
        mounted.vnode = next
        return mounted
```

The default "destroy + mount fresh" case already handles `(.component, .component)` with different descriptions because the `where` guard fails and we drop through.

Update `destroy()` to recurse into `componentBody`:

```swift
func destroy(
    _ node: MountNode,
    into patches: inout [Patch],
    handlers: HandlerRegistry
) {
    // Recurse: ordinary children first, then the component body (if any).
    for child in node.children {
        destroy(child, into: &patches, handlers: handlers)
    }
    if let body = node.componentBody {
        destroy(body, into: &patches, handlers: handlers)
    }
    // Handler removal only matters for nodes that registered handlers
    // (element nodes). Component anchors have an empty handlerIds map.
    for (_, handlerID) in node.handlerIds {
        handlers.remove(id: handlerID)
    }
    // Component anchors don't produce a destroyNode patch — they don't
    // correspond to a DOM node. Only emit if this is an actual DOM node.
    if case .component = node.vnode {
        // anchor: no DOM destroy needed; body destroy above handles it
    } else {
        patches.append(.destroyNode(handle: node.handle))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "Component update path"`
Expected: PASS — 3 tests pass.

- [ ] **Step 5: Run the broader diff/mount suites**

Run: `swift test --filter "Diff" --skip "end-to-end"` and `swift test --filter "Mount" --skip "end-to-end"`
Expected: all existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/Diff/Diff.swift Tests/SwiflowTests/Reactivity/ComponentUpdateTests.swift
git commit -m "feat(diff): update + destroy paths for VNode.component (instance reuse on match)"
```

---

## 🛑 PAUSE POINT — End of Task 5

At this point: Components exist as types, can be embedded in VNode trees, and the diff handles their lifecycle (mount, update with instance reuse, destroy). `@State` exists but isn't wired into a Scheduler. The Renderer doesn't yet accept a Component as root. Hello World template is unchanged.

The user may review the implementation before proceeding to Tasks 6–9, which connect `@State` mutations to actual re-renders.

---

### Task 6: Scheduler protocol + InProcessScheduler (testable, sync flush)

**Files:**
- Create: `Sources/Swiflow/Reactivity/Scheduler.swift`
- Modify: `Sources/Swiflow/Reactivity/State.swift` (delete the local Scheduler stub; depend on this file)
- Create: `Tests/SwiflowTests/Reactivity/SchedulerTests.swift`

**Notes for the implementer:**
- `Scheduler` is the protocol; `InProcessScheduler` is a synchronous implementation for tests and headless contexts. The WASM `RAFScheduler` (Task 7) is a separate conformance.
- `markDirty` adds to a `Set<ObjectIdentifier>` to deduplicate same-component multiple marks within one batch. The actual `AnyComponent` references are kept in a parallel `[ObjectIdentifier: AnyComponent]` so flush can iterate.
- `flush()` invokes a `rerenderCallback: (AnyComponent) -> Void` once per dirty component, in insertion order. The callback is injected at scheduler construction time (so the Scheduler doesn't know about the Renderer's internals).
- After flush, the dirty set is cleared. If a callback re-marks a component (mid-flush), that mark goes into the NEXT batch (the spec is silent; React batches this way and the result is sane).

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/Reactivity/SchedulerTests.swift
import Testing
@testable import Swiflow

@Suite("Scheduler")
struct SchedulerTests {

    final class StubComponent: Component {
        var body: VNode { .text("") }
    }

    @Test("markDirty + flush calls rerender callback once per component")
    func basicFlush() {
        var called: [ObjectIdentifier] = []
        let scheduler = InProcessScheduler { any in
            called.append(ObjectIdentifier(any.instance))
        }
        let a = AnyComponent(StubComponent())
        let b = AnyComponent(StubComponent())
        scheduler.markDirty(a)
        scheduler.markDirty(b)
        #expect(called.isEmpty, "flush hasn't been called yet")
        scheduler.flush()
        #expect(called.count == 2)
        #expect(called.contains(ObjectIdentifier(a.instance)))
        #expect(called.contains(ObjectIdentifier(b.instance)))
    }

    @Test("Duplicate markDirty calls deduplicate within a single batch")
    func deduplication() {
        var callCount = 0
        let scheduler = InProcessScheduler { _ in callCount += 1 }
        let a = AnyComponent(StubComponent())
        scheduler.markDirty(a)
        scheduler.markDirty(a)
        scheduler.markDirty(a)
        scheduler.flush()
        #expect(callCount == 1, "Three markDirty calls for the same component → one flush invocation")
    }

    @Test("Flush clears the dirty set; subsequent markDirty starts a fresh batch")
    func flushClears() {
        var callCount = 0
        let scheduler = InProcessScheduler { _ in callCount += 1 }
        let a = AnyComponent(StubComponent())
        scheduler.markDirty(a)
        scheduler.flush()
        scheduler.flush() // no-op second flush
        #expect(callCount == 1)

        scheduler.markDirty(a)
        scheduler.flush()
        #expect(callCount == 2)
    }

    @Test("Marks scheduled during a flush are deferred to the next batch")
    func reentrantMarkDefers() {
        var callsThisBatch: [ObjectIdentifier] = []
        let a = AnyComponent(StubComponent())
        let b = AnyComponent(StubComponent())
        var scheduler: InProcessScheduler!
        scheduler = InProcessScheduler { any in
            callsThisBatch.append(ObjectIdentifier(any.instance))
            // Re-mark b while flushing a.
            if any.instance === a.instance && callsThisBatch.count == 1 {
                scheduler.markDirty(b)
            }
        }
        scheduler.markDirty(a)
        scheduler.flush()
        #expect(callsThisBatch.count == 1, "b should NOT have been flushed in this batch")
        scheduler.flush()
        #expect(callsThisBatch.count == 2, "b is flushed on the next batch")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "Scheduler"`
Expected: fail — `InProcessScheduler` doesn't exist.

- [ ] **Step 3: Implement Scheduler + InProcessScheduler**

Create `Sources/Swiflow/Reactivity/Scheduler.swift`:

```swift
// Sources/Swiflow/Reactivity/Scheduler.swift

/// Coordinates component re-renders. `@State` mutations call `markDirty`
/// on the active Scheduler; the Scheduler batches and eventually invokes
/// the per-component rerender callback (in production, on `requestAnimationFrame`;
/// in tests, on `flush()`).
public protocol Scheduler: AnyObject {
    /// Marks `component` as needing re-render. Idempotent within a batch.
    func markDirty(_ component: AnyComponent)

    /// Synchronously rerender every dirty component, then clear the dirty
    /// set. Tests call this directly; the WASM scheduler invokes it from
    /// a `requestAnimationFrame` callback.
    func flush()
}

/// Synchronous, no-rAF implementation. Used by tests and any headless
/// context. The `rerenderCallback` is invoked once per dirty component
/// at flush time, in the order components were first marked.
///
/// Reentrancy: marks made WHILE a callback runs are deferred to the next
/// flush. The "current batch" snapshot is taken at the start of `flush()`
/// and is consumed monolithically; any markDirty during callback execution
/// populates a fresh dirty set for the next batch.
public final class InProcessScheduler: Scheduler {
    private var dirty: [ObjectIdentifier: AnyComponent] = [:]
    private var insertionOrder: [ObjectIdentifier] = []
    private let rerenderCallback: (AnyComponent) -> Void
    private var isFlushing = false

    public init(rerenderCallback: @escaping (AnyComponent) -> Void) {
        self.rerenderCallback = rerenderCallback
    }

    public func markDirty(_ component: AnyComponent) {
        let id = ObjectIdentifier(component.instance)
        if dirty[id] == nil {
            insertionOrder.append(id)
        }
        dirty[id] = component
    }

    public func flush() {
        guard !isFlushing else { return }
        let batchIDs = insertionOrder
        let batch = batchIDs.compactMap { dirty[$0] }
        dirty.removeAll(keepingCapacity: true)
        insertionOrder.removeAll(keepingCapacity: true)

        isFlushing = true
        defer { isFlushing = false }
        for component in batch {
            rerenderCallback(component)
        }
    }
}
```

Then remove the temporary stub in `Sources/Swiflow/Reactivity/State.swift`. Delete this block:

```swift
#if !SWIFLOW_SCHEDULER_DEFINED_ELSEWHERE
public protocol Scheduler: AnyObject {
    func markDirty(_ component: AnyComponent)
    func flush()
}
#endif
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "Scheduler"` and `swift test --filter "@State"`
Expected: PASS — 4 Scheduler tests + 5 State tests still pass (the State tests use the local stub which is now removed; they need to import the canonical Scheduler from Reactivity/Scheduler.swift, which is automatic since both are in the same module).

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/Reactivity/Scheduler.swift Sources/Swiflow/Reactivity/State.swift Tests/SwiflowTests/Reactivity/SchedulerTests.swift
git commit -m "feat(reactivity): Scheduler protocol + InProcessScheduler (sync flush for tests)"
```

---

### Task 7: Mirror-based @State owner injection on Component construction

**Files:**
- Modify: `Sources/Swiflow/Reactivity/Component.swift` (add `wireState(on:scheduler:)` helper)
- Modify: `Sources/Swiflow/Diff/Diff.swift` (call `wireState` after instantiation in mount path)
- Create: `Tests/SwiflowTests/Reactivity/StateWiringTests.swift`

**Notes for the implementer:**
- After `desc.instantiate()` in the mount path, iterate over the AnyComponent's instance properties via `Mirror(reflecting:)`. For each child whose value is `State<T>` for some T, call `_setOwner(_:scheduler:)` on that State, passing the AnyComponent + scheduler.
- The Mirror-walk uses `mirror.children` which yields `(label, value)`. Filter on `value` being any `State<T>` instance. Swift's runtime won't let us spell this as `value is State<Any>`, so use a protocol witness: define an internal `StateWireable` protocol with `_setOwner(_:scheduler:)` and have `State<T>` conform. The Mirror walk then casts `child.value as? StateWireable`.
- The diff currently doesn't have access to a scheduler. Plumb a `scheduler: Scheduler?` parameter through `diff()`, `mount()`, `update()`. Default `nil` for backward compatibility — when `nil`, @State mutations stay silent (matching Task 2's "no-owner" behavior).

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SwiflowTests/Reactivity/StateWiringTests.swift
import Testing
@testable import Swiflow

@Suite("@State owner wiring via Mirror")
struct StateWiringTests {

    final class Counter: Component {
        @State var n: Int = 0
        @State var label: String = "hi"
        var body: VNode { .text("\(label)=\(n)") }
    }

    final class CountingScheduler: Scheduler {
        var markCount = 0
        var lastMarked: AnyComponent?
        func markDirty(_ component: AnyComponent) {
            markCount += 1
            lastMarked = component
        }
        func flush() {}
    }

    @Test("After mount with a Scheduler, @State mutations call scheduler.markDirty")
    func mountWiresState() {
        let scheduler = CountingScheduler()
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        let v = VNode.component(.init(Counter.self) { Counter() })
        let result = diff(
            mounted: nil,
            next: v,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler
        )

        let counter = result.newMountTree.component?.instance as? Counter
        #expect(counter != nil)
        #expect(scheduler.markCount == 0, "Mount itself should not mark anything")

        counter?.n = 5
        #expect(scheduler.markCount == 1, "Mutating @State should call markDirty once")
        #expect(scheduler.lastMarked?.instance === counter)

        counter?.label = "bye"
        #expect(scheduler.markCount == 2, "Mutating a different @State should also mark")
    }

    @Test("Without a Scheduler (nil arg), @State mutations are silent")
    func noSchedulerSilent() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let v = VNode.component(.init(Counter.self) { Counter() })
        let result = diff(
            mounted: nil,
            next: v,
            handles: handles,
            handlers: handlers,
            scheduler: nil
        )
        let counter = result.newMountTree.component?.instance as? Counter
        counter?.n = 99  // must not crash
        #expect(counter?.n == 99)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "@State owner wiring"`
Expected: fail — `diff` doesn't accept `scheduler:`; State isn't wired.

- [ ] **Step 3: Add the StateWireable witness**

In `Sources/Swiflow/Reactivity/State.swift`, add:

```swift
/// Internal protocol witness for Mirror-based @State discovery. Lets the
/// framework cast `Mirror.children`'s `Any` values to a known shape with
/// the wire-owner method. Conformance is added on `State` below.
protocol StateWireable: AnyObject {
    func _setOwner(_ owner: AnyComponent, scheduler: Scheduler)
}

extension State: StateWireable {}
```

- [ ] **Step 4: Add the `wireState(on:scheduler:)` helper**

In `Sources/Swiflow/Reactivity/Component.swift`, add a free function (kept package-internal — implementation detail):

```swift
/// Iterates the instance's stored properties via Mirror and wires every
/// `@State` wrapper to `(owner, scheduler)` so its mutations call
/// `scheduler.markDirty(owner)`.
///
/// Called by the diff at first mount of each component anchor. No-op when
/// `scheduler` is nil (used by tests and headless diffing).
func wireState(on owner: AnyComponent, scheduler: Scheduler?) {
    guard let scheduler else { return }
    let mirror = Mirror(reflecting: owner.instance)
    for child in mirror.children {
        // Property-wrapper-backed properties surface as `_propertyName`
        // children whose values are the wrapper itself.
        if let wireable = child.value as? StateWireable {
            wireable._setOwner(owner, scheduler: scheduler)
        }
    }
}
```

- [ ] **Step 5: Plumb `scheduler:` through diff**

In `Sources/Swiflow/Diff/Diff.swift`:

Update the public `diff()` signature:

```swift
public func diff(
    mounted: MountNode?,
    next: VNode,
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    scheduler: Scheduler? = nil
) -> DiffResult {
    var patches: [Patch] = []
    let root: MountNode
    if let mounted = mounted {
        root = update(
            mounted: mounted,
            next: next,
            into: &patches,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler
        )
    } else {
        root = mount(next, into: &patches, handles: handles, handlers: handlers, scheduler: scheduler)
    }
    return DiffResult(patches: patches, newMountTree: root)
}
```

Update `mount()` and `update()` to accept `scheduler: Scheduler?` and thread it through every recursive call. In `mount()`, after `desc.instantiate()`:

```swift
    case .component(let desc):
        let instance = desc.instantiate()
        wireState(on: instance, scheduler: scheduler)
        let bodyVNode = instance.instance.body
        let bodyMount = mount(bodyVNode, into: &patches, handles: handles, handlers: handlers, scheduler: scheduler)
        let anchorHandle = handles.next()
        return MountNode(
            handle: anchorHandle,
            vnode: vnode,
            component: instance,
            componentBody: bodyMount
        )
```

(No wireState call in the update path's reuse branch — the instance is the same one we wired at mount.)

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter "@State owner wiring"`
Expected: PASS — 2 tests pass.

- [ ] **Step 7: Verify no other test broke**

Run: `swift test --skip "end-to-end"`
Expected: all unit tests still pass (the `scheduler:` parameter is defaulted, so existing call sites compile unchanged).

- [ ] **Step 8: Commit**

```bash
git add Sources/Swiflow/Reactivity/Component.swift Sources/Swiflow/Reactivity/State.swift Sources/Swiflow/Diff/Diff.swift Tests/SwiflowTests/Reactivity/StateWiringTests.swift
git commit -m "feat(reactivity): Mirror-based @State owner wiring on Component mount"
```

---

### Task 8: Renderer accepts Component root + lifecycle hooks at correct times

**Files:**
- Modify: `Sources/SwiflowWeb/SwiflowWeb.swift` (add `render(_:into:)` for Component)
- Modify: `Sources/SwiflowWeb/Renderer.swift` (Component root path; lifecycle hook calls)
- Create: `Sources/SwiflowWeb/RAFScheduler.swift` (rAF-backed Scheduler conformance)
- Create: `Tests/SwiflowTests/Reactivity/RendererComponentTests.swift` (gated `#if canImport(JavaScriptKit)`)

**Notes for the implementer:**
- New `Swiflow.render` overload accepts `() -> some Component` (or `AnyComponent` directly). It wraps the component in a `VNode.component(...)` whose factory returns that very instance once (so the diff finds it on first mount) — then subsequent rerenders reuse it via the existing instance-reuse path.
- Wait — there's a subtle issue: the factory closure is called by `mount()` to produce the AnyComponent. But the user constructs the component eagerly (`Counter()`) and passes it in. So the factory closure needs to capture the user-built instance and return an `AnyComponent` wrapping it. That's fine; just `factory: { AnyComponent(theInstance) }`.
- After the first render, call `rootComponent.onMount()`. After every subsequent render, call `rootComponent.onUpdate(prev: rootComponent)`. On destruction (never in v1 since there's no programmatic unmount), call `onUnmount()`.
- The Scheduler is constructed inside Renderer and bound to a `rerenderCallback` that calls `self.renderComponent(_:)` for the dirty component. On a rAF tick, the Scheduler flushes, which calls renderComponent for each dirty component.
- For Phase 3 v1, the only "render" we know how to do is whole-tree from root. Per-component partial rendering is a Phase 4 optimization. So the rerender callback just calls `renderOnce()` (full root re-render) — but only ONCE per flush, even if many components were marked. Wrap it in a "did-render-this-batch" flag.

- [ ] **Step 1: Write the failing tests**

These tests must be gated on JavaScriptKit because they exercise SwiflowWeb (WASM-only). On macOS/Linux without WASM SDK, they compile to nothing.

```swift
// Tests/SwiflowTests/Reactivity/RendererComponentTests.swift
#if canImport(JavaScriptKit)
import Testing
@testable import Swiflow
@testable import SwiflowWeb

@Suite("Renderer with Component root")
struct RendererComponentTests {
    // These tests live in the WASM-target test bundle. Without a browser
    // runtime they can only verify pure-Swift assertions (component
    // instance creation, scheduler binding). Full DOM-side assertions
    // live in DevCommandIntegrationTests (e2e in a real browser is
    // deferred to Phase 5 per the spec).

    final class Counter: Component {
        @State var n: Int = 0
        var body: VNode { .text("count=\(n)") }
    }

    @Test("render(_:into:) for a Component constructs a Renderer and wires it")
    func renderComponentConstructs() {
        // We can't actually call Swiflow.render in unit tests (it talks to
        // window.swiflow). Instead, construct a Renderer-with-component
        // directly and verify it wires the component + a scheduler.
        let counter = Counter()
        let renderer = Renderer(rootComponent: AnyComponent(counter), selector: "#app")
        #expect(renderer.rootComponent?.instance === counter)
        #expect(renderer.scheduler != nil, "A scheduler must be created for component-rooted renderers")
    }
}
#endif
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "Renderer with Component root"`
Expected: fail or skip — depending on whether the WASM target compiles. If no WASM SDK is installed, the test file may not produce a runnable target at all, in which case the filter matches no tests and the run reports "0 tests selected". Locally with WASM SDK: compile error because `Renderer.init(rootComponent:selector:)` doesn't exist.

- [ ] **Step 3: Extend Renderer with a Component-root path**

In `Sources/SwiflowWeb/Renderer.swift`, add an alternative init and rendering path:

```swift
final class Renderer {
    let viewProducer: (() -> VNode)?  // viewProducer-mode (Phase 2a)
    let rootComponent: AnyComponent?  // component-root mode (Phase 3)
    let selector: String
    let handles: HandleAllocator
    let handlers: HandlerRegistry
    var mountTree: MountNode?
    var scheduler: Scheduler?

    /// Phase 2a init: a viewProducer closure rerun via `Swiflow.rerender()`.
    init(viewProducer: @escaping () -> VNode, selector: String) {
        self.viewProducer = viewProducer
        self.rootComponent = nil
        self.selector = selector
        self.handles = HandleAllocator()
        self.handlers = HandlerRegistry()
        self.mountTree = nil
        self.scheduler = nil
    }

    /// Phase 3 init: a root Component. Mutations to `@State` properties on
    /// this component (or any descendant component) schedule a re-render
    /// via the bound Scheduler.
    init(rootComponent: AnyComponent, selector: String) {
        self.viewProducer = nil
        self.rootComponent = rootComponent
        self.selector = selector
        self.handles = HandleAllocator()
        self.handlers = HandlerRegistry()
        self.mountTree = nil

        // Bind the scheduler with a rerenderCallback that re-runs the root.
        // The closure captures `self` weakly to avoid a retain cycle.
        var capturedSelf: Renderer? = nil
        let scheduler = InProcessScheduler { [weak self] _ in
            // Phase 3 v1: any dirty component → full-tree re-render from root.
            // Per-component partial rerender is a Phase 4 optimization.
            self?.renderOnce()
        }
        self.scheduler = scheduler
        capturedSelf = self
        _ = capturedSelf  // silence unused-variable warning
    }

    func renderOnce() {
        let nextVNode: VNode
        if let viewProducer {
            nextVNode = viewProducer()
        } else if let rootComponent {
            // Wrap the root component in a VNode.component whose factory
            // returns the existing instance. This lets the existing
            // mount/update paths handle the component the same way they
            // handle any other.
            let desc = ComponentDescription(
                typeID: rootComponent.typeID,
                key: nil,
                factory: { rootComponent }
            )
            nextVNode = .component(desc)
        } else {
            preconditionFailure("Renderer has neither viewProducer nor rootComponent")
        }

        let result = diff(
            mounted: mountTree,
            next: nextVNode,
            handles: handles,
            handlers: handlers,
            scheduler: scheduler
        )

        // Encode + ship patches (unchanged from Phase 2a).
        let jsArray = JSObject.global.Array.function!.new()
        for (index, patch) in result.patches.enumerated() {
            let payload = PatchSerializer.encode(patch)
            jsArray[index] = JSAdapter.toJSValue(payload)
        }
        let swiflowGlobal = JSObject.global.swiflow.object!
        _ = swiflowGlobal.applyPatches!(jsArray)

        let isFirstMount = (mountTree == nil)
        mountTree = result.newMountTree

        if isFirstMount {
            // The component anchor doesn't have a DOM handle; use the body's.
            let mountHandle = result.newMountTree.domHandle
            _ = swiflowGlobal.mount!(
                JSValue.number(Double(mountHandle)),
                JSValue.string(selector)
            )
            // Lifecycle: onMount on the root component, if any.
            if let root = rootComponent {
                root.instance.onMount()
            }
        } else {
            // Lifecycle: onUpdate on the root component, if any. `prev` is
            // the same instance — see design decision §3.
            if let root = rootComponent {
                callOnUpdate(root.instance)
            }
        }
    }

    /// Type-erased onUpdate call: `Component.onUpdate(prev: Self)` needs
    /// the concrete `Self`. We don't have a concrete type at this site, so
    /// pass `self` via a generic intermediate.
    private func callOnUpdate<C: Component>(_ c: C) {
        c.onUpdate(prev: c)
    }
}
```

In `Sources/SwiflowWeb/SwiflowWeb.swift`, add the new render overload:

```swift
public extension Swiflow {
    /// Phase 3 entry point: mount a `Component` root. `@State` mutations
    /// inside any component below `root` schedule re-renders automatically.
    static func render<C: Component>(_ root: C, into selector: String) {
        precondition(
            ambientRenderer == nil,
            "Swiflow.render was already called. Single-root only in Phase 3."
        )
        let renderer = Renderer(rootComponent: AnyComponent(root), selector: selector)
        ambientRenderer = renderer
        DispatcherBridge.installIfNeeded(registry: renderer.handlers)
        renderer.renderOnce()
    }
}
```

Create `Sources/SwiflowWeb/RAFScheduler.swift`:

```swift
// Sources/SwiflowWeb/RAFScheduler.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// Wraps `InProcessScheduler` with a `requestAnimationFrame` trigger.
/// Marking a component dirty enqueues a rAF callback (deduplicating across
/// multiple marks within the same frame); the rAF callback calls `flush()`.
///
/// Phase 3 v1 doesn't use this directly — the Renderer holds an
/// `InProcessScheduler` and the spec-mandated rAF batching is hand-wired in
/// Task 8's renderer. This file is reserved for the Phase 4 refactor that
/// pulls the rAF logic out into its own Scheduler conformance.
///
/// **NOTE:** Skeleton-only in Phase 3. A Phase 4 task will populate this
/// with the actual rAF binding. Leaving the file in place to mark the seam.
public final class RAFScheduler {
    // Phase 4: implement requestAnimationFrame batching.
}

#endif
```

Wait — re-reading the spec §6: "**Scheduler** — collects dirty components per `requestAnimationFrame`; re-renders each, runs the diff, ships one consolidated `[Patch]` batch per frame across the bridge." So rAF IS Phase 3.

OK let me actually implement the rAF binding. Revise the RAFScheduler file:

```swift
// Sources/SwiflowWeb/RAFScheduler.swift

#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// A `Scheduler` that batches dirty components per `requestAnimationFrame`.
/// `markDirty` schedules a rAF callback (idempotent across multiple marks
/// in the same frame); the rAF callback calls the inner `InProcessScheduler`'s
/// `flush()`, which invokes the rerender callback once per dirty component
/// in insertion order.
public final class RAFScheduler: Scheduler {
    private let inner: InProcessScheduler
    private var rafScheduled = false
    private var rafClosure: JSClosure?

    public init(rerenderCallback: @escaping (AnyComponent) -> Void) {
        self.inner = InProcessScheduler(rerenderCallback: rerenderCallback)
    }

    public func markDirty(_ component: AnyComponent) {
        inner.markDirty(component)
        scheduleRAFIfNeeded()
    }

    public func flush() {
        inner.flush()
    }

    private func scheduleRAFIfNeeded() {
        guard !rafScheduled else { return }
        rafScheduled = true

        let closure = JSClosure { [weak self] _ in
            self?.rafFired()
            return .undefined
        }
        rafClosure = closure
        _ = JSObject.global.requestAnimationFrame!(.object(closure))
    }

    private func rafFired() {
        rafScheduled = false
        rafClosure = nil
        flush()
    }
}

#endif
```

Then in `Renderer.swift`'s Phase 3 init, use `RAFScheduler` instead of `InProcessScheduler`:

```swift
init(rootComponent: AnyComponent, selector: String) {
    self.viewProducer = nil
    self.rootComponent = rootComponent
    self.selector = selector
    self.handles = HandleAllocator()
    self.handlers = HandlerRegistry()
    self.mountTree = nil

    let scheduler = RAFScheduler { [weak self] _ in
        self?.renderOnce()
    }
    self.scheduler = scheduler
}
```

- [ ] **Step 4: Run tests to verify they pass (locally, if WASM SDK installed)**

Run: `swift test --filter "Renderer with Component root"`
Expected: PASS — at least the construction test.

- [ ] **Step 5: Run the BuildCommandIntegrationTests + DevCommandIntegrationTests**

Run: `swift test --filter "end-to-end"`
Expected: both pass — the template still uses Phase 2a viewProducer flow, which is preserved.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowWeb/SwiflowWeb.swift Sources/SwiflowWeb/Renderer.swift Sources/SwiflowWeb/RAFScheduler.swift Tests/SwiflowTests/Reactivity/RendererComponentTests.swift
git commit -m "feat(renderer): Component root + RAFScheduler with lifecycle hooks"
```

---

### Task 9: Migrate Hello World template + verify e2e

**Files:**
- Modify: `Sources/SwiflowCLI/Templates/Templates.swift` (Counter: Component template)
- Modify: `Tests/SwiflowCLITests/InitCommandTests.swift` (assert new template body)
- (The existing `DevCommandIntegrationTests` end-to-end test exercises the new template via a real WASM build.)

**Notes for the implementer:**
- The new template replaces the global `var count = 0` + free `view()` + `Swiflow.rerender()` pattern with a single `Counter: Component` class using `@State`.
- The `.on("click", ...)` handler now mutates `count` (a `@State` property) directly. The Scheduler handles re-rendering automatically — no explicit `Swiflow.rerender()` call.
- The handler registration model is unchanged: `Swiflow.handlers.register { _ in ... }` returns an EventHandler, attached via `.on("click", handler)`. The closure runs synchronously on the main thread, mutates `count`, the @State setter calls `scheduler.markDirty`, the rAF tick flushes, the diff produces a setText patch.

- [ ] **Step 1: Update the template**

In `Sources/SwiflowCLI/Templates/Templates.swift`, replace `rawAppSwift` with:

```swift
    private static let rawAppSwift: String = #"""
        // Sources/App/App.swift
        import Swiflow
        import SwiflowWeb

        /// Phase 3 Hello World — a Component with @State.
        ///
        /// Compared to Phase 2a:
        /// - State lives on the Component (was a global `var`).
        /// - No explicit Swiflow.rerender() call — mutating `@State count`
        ///   schedules a re-render automatically via the Scheduler.
        @MainActor
        final class Counter: Component {
            @State var count: Int = 0

            var body: VNode {
                div(.class("container")) {
                    h1("Hello, Swiflow!")
                    p("Count: \(count)")
                    button(
                        "Increment",
                        .on("click", Swiflow.handlers.register { [weak self] _ in
                            MainActor.assumeIsolated {
                                self?.count += 1
                            }
                        })
                    )
                }
            }
        }

        @main
        struct App {
            @MainActor
            static func main() {
                Swiflow.render(Counter(), into: "#app")
            }
        }

        """#
```

- [ ] **Step 2: Update the InitCommandTests to assert the new template**

In `Tests/SwiflowCLITests/InitCommandTests.swift`, update the `threadsSwiflowSource` test (or add a new test) to also assert `App.swift` contains `final class Counter: Component` and `@State var count`:

```swift
    @Test("Generated App.swift contains a Counter: Component with @State")
    func appSwiftIsCounterComponent() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try ProjectWriter.writeProject(
            name: "Demo",
            into: tmp,
            swiflowSource: "../..",
            jsDriverSource: "// driver\n"
        )

        let app = try String(
            contentsOf: tmp.appendingPathComponent("Demo/Sources/App/App.swift"),
            encoding: .utf8
        )
        #expect(app.contains("final class Counter: Component"))
        #expect(app.contains("@State var count: Int = 0"))
        #expect(app.contains("Swiflow.render(Counter()"))
        #expect(!app.contains("Swiflow.rerender()"), "Counter should not need explicit rerender")
    }
```

- [ ] **Step 3: Run InitCommandTests**

Run: `swift test --filter "InitCommand"`
Expected: PASS — including the new template-body test.

- [ ] **Step 4: Run the e2e integration test (requires WASM SDK)**

Run: `swift test --filter "end-to-end"`
Expected: PASS — `swift package js` builds the new template successfully and the dev server serves a working page. This is the empirical proof that Phase 3 hangs together end-to-end.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowCLI/Templates/Templates.swift Tests/SwiflowCLITests/InitCommandTests.swift
git commit -m "feat(template): Hello World migrates to Counter: Component with @State"
```

---

## Self-review (controller checklist before dispatching subagents)

1. **Spec coverage.** Spec §6 lists: @State property wrapper ✓ (Task 2/7), Component protocol ✓ (Task 1), Scheduler with rAF ✓ (Task 6/8), lifecycle hooks ✓ (Task 8), position-based identity ✓ (Task 5), Hello World migration ✓ (Task 9). All covered.

2. **Placeholder scan.** Every Step has either concrete code, a precise file edit, or an exact shell command. No "TODO", no "add appropriate error handling", no "fill in details". RAFScheduler initial draft had a "skeleton only" placeholder which I then replaced with a full implementation in the same task.

3. **Type consistency.** `AnyComponent` (Task 1) is used by `wireState` (Task 7), `MountNode.component` (Task 4), `Scheduler.markDirty` (Task 6), `Renderer.rootComponent` (Task 8). `ComponentDescription` (Task 1) is referenced by `VNode.component` (Task 3), `mount()` (Task 4), `update()` (Task 5). `Scheduler.markDirty(_ component: AnyComponent)` consistent across all sites. `State<Value>._setOwner(_:scheduler:)` defined in Task 2 and called in Task 7.

4. **Task 2/6 ordering.** Task 2's tests reference `Scheduler`, which Task 6 defines. Mitigation in plan: Task 2 inlines a stub Scheduler protocol that Task 6 deletes. This means Task 2 and Task 6 cannot be parallelized but can stay sequential.

5. **Pause point clarity.** Task 5 leaves the codebase in a working state: tests pass, the existing Phase 2a viewProducer flow is untouched, Components exist but aren't wired to a Scheduler yet. The user can pause, review, and resume to Task 6 without intermediate breakage.

6. **Spec §6 nonobvious detail: "Component identity strategy — position-based...".** Captured in Task 5's three tests (reuseOnTypeAndKeyMatch, replaceOnTypeMismatch, replaceOnKeyMismatch). The diff dispatches on `mounted.vnode` vs `next` in a single switch — same-position identity is implicit in the call site.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-18-swiflow-phase3-reactivity.md`. Two execution options:

**1. Subagent-Driven (recommended)** — controller dispatches a fresh subagent per task, reviews between tasks, fast iteration. The pause point after Task 5 lets the user review the foundational integration before the user-facing reactivity wires up.

**2. Inline Execution** — execute tasks in this session using executing-plans; batched with checkpoints.

Which approach?
