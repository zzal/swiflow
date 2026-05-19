# Swiflow Phase 5 — API Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Address the five highest-priority API/DX concerns from the Taylor Otwell review, plus a public-surface audit, so the Hello World template collapses to one idiomatic `.on(.click) { count += 1 }` line.

**Architecture:** Three layers — (1) foundations (`Component` becomes `@MainActor`-isolated, existing `Event` struct renamed to `EventInfo`, new `Event` enum lands); (2) five API rework tasks (handler API, lifecycle rename, `embed`, factory `render`, postfix VNode modifiers); (3) public-surface audit + smaller renames.

**Tech Stack:** Swift 6.3, Swift Testing (`@Test`/`@Suite`), JavaScriptKit (WASM bridge), no new dependencies.

**Companion spec:** `docs/superpowers/specs/2026-05-19-swiflow-phase5-api-polish-design.md`

---

## Out of scope (locked from spec)

- Backwards compatibility shims, typealias deprecations, dual API surfaces
- Renaming `swiflowDiagnostic` (already effectively internal under `#if DEBUG`)
- Element factory tag-name rationalization beyond `a` → `link` and `main_` → `mainElement`
- Performance work, source maps, additional E2E coverage
- CLI changes (`--path` positional rework deferred — review nit, not a top-5 priority)

---

## File structure

### Created
- `Sources/Swiflow/DSL/Event.swift` — typed event-name enum
- `Sources/Swiflow/DSL/VNodeModifiers.swift` — postfix chaining extensions on `VNode`
- `Tests/SwiflowTests/DSL/EventTests.swift`
- `Tests/SwiflowTests/DSL/VNodeModifiersTests.swift`
- `Tests/SwiflowTests/Reactivity/ComponentLifecycleScopedHandlersTests.swift`

### Modified
- `Sources/Swiflow/VNode.swift` — rename `Event` struct → `EventInfo`; update `EventHandler.invoke` type
- `Sources/Swiflow/HandlerRegistry.swift` — closure type `(Event)` → `(EventInfo)`; visibility to `internal`; per-Component scope; module-level relocation note (see Task 2)
- `Sources/Swiflow/Reactivity/Component.swift` — `@MainActor`, lifecycle rename, drop `prev:`
- `Sources/Swiflow/Reactivity/Scheduler.swift` — `InProcessScheduler` → `SyncScheduler`
- `Sources/Swiflow/DSL/Modifiers.swift` — new `.on(_:perform:)` overloads taking `Event` enum; `applyAttributes` → `internal`; remove old string-based `.on`
- `Sources/Swiflow/DSL/ComponentDSL.swift` — `component(_:key:)` → `embed`
- `Sources/Swiflow/DSL/Elements.swift` — `a` → `link`, `main_` → `mainElement`, update doc-comment references
- `Sources/Swiflow/DSL/ResultBuilder.swift` — `buildBlock`/`buildArray` parameter renames
- `Sources/SwiflowWeb/SwiflowWeb.swift` — new factory-taking `render`; delete two old overloads; remove public `Swiflow.handlers` (becomes internal ambient lookup)
- `Sources/SwiflowWeb/Renderer.swift` — lifecycle hook call-site renames; per-Component handler scope hookup
- `Sources/SwiflowWeb/DispatcherBridge.swift` — `Event` → `EventInfo` in dispatcher call path
- `Sources/Swiflow/Diff/Diff.swift` — lifecycle hook call-site renames (`onUnmount` → `onDisappear`)
- `Sources/SwiflowCLI/Templates/Templates.swift` — Counter rewrite + `Swiflow.render(into:)` factory shape
- `README.md` — "What's in the box" lifecycle names + Counter snippet
- Existing Swift tests that reference renamed symbols (sweep below)

### Deleted (overloads/symbols, not files)
- `component(_:key:)` from `ComponentDSL.swift`
- `Swiflow.render(_ viewProducer: @escaping () -> VNode, into:)` from `SwiflowWeb.swift`
- `Swiflow.render<C: Component>(_ root: C, into:)` from `SwiflowWeb.swift`
- `Swiflow.handlers` public property from `SwiflowWeb.swift`
- `Attribute.on(_ event: String, _ handler: EventHandler)` from `Modifiers.swift`

### Tests to sweep for renamed symbols
- `Tests/SwiflowTests/HandlerRegistryTests.swift` — closure-arg type
- `Tests/SwiflowTests/VNodeTests.swift` — `Event(...)` → `EventInfo(...)`
- `Tests/SwiflowTests/DSLTests.swift` — old `.on("click", ...)` → new `.on(.click) { ... }`
- `Tests/SwiflowTests/Reactivity/*` — `Component` MainActor, lifecycle hook names
- `Tests/SwiflowTests/DiffTests/*` — `onMount`/`onUpdate`/`onUnmount` references
- `Tests/SwiflowCLITests/TemplatesTests.swift` (if it exists — verify) — golden file or substring assertions

---

## Task ordering

1. **Foundation A** — Rename existing `Event` struct → `EventInfo`
2. **Foundation B** — `Component` becomes `@MainActor`; lifecycle rename + drop `prev:`
3. **Foundation C** — Introduce new `Event` enum
4. **Priority #1** — Clean handler API: new `.on(_ event: Event, perform:)` overloads; mark `HandlerRegistry` internal; per-Component scope
5. **Priority #2** — `embed { Counter() }`
6. **Priority #4** — `Swiflow.render(into:) { factory }`
7. **Priority #3a** — `Event` enum already lives; add `.attr` overloads and `.data` helper to `Attribute`
8. **Priority #3b** — Postfix chaining on `VNode`
9. **Surface audit + smaller renames** — `a`→`link`, `main_`→`mainElement`, `InProcessScheduler`→`SyncScheduler`, `applyAttributes` internal, `AnyComponent`/`ComponentDescription` fields internal, `buildBlock` param rename, `PropertyValue` literal conformances
10. **Counter template + README + final test sweep**

🛑 Pause point after Task 4 (template hits new shape — biggest single-step DX win).
🛑 Pause point after Task 8 (modifier system rework is the biggest visual diff).

---

## Task 1: Rename existing `Event` struct → `EventInfo`

**Files:**
- Modify: `Sources/Swiflow/VNode.swift:114-127`
- Modify: `Sources/Swiflow/HandlerRegistry.swift:25,46-48`
- Modify: `Sources/SwiflowWeb/DispatcherBridge.swift` (every `Event` reference)
- Modify: `Tests/SwiflowTests/VNodeTests.swift`, `Tests/SwiflowTests/HandlerRegistryTests.swift`, any other test referencing `Event(...)`
- Modify: `Sources/SwiflowCLI/Templates/Templates.swift:120` (the user-visible `.on("click", ...)` closure receives `Event` — will become `EventInfo`)

**Design note:** this is a pure rename. The struct's purpose (runtime DOM event payload) doesn't change. Goal: free the bare name `Event` for the new event-name enum that Task 3 introduces.

- [ ] **Step 1: Rename the struct declaration in `VNode.swift`**

In `Sources/Swiflow/VNode.swift`, change:

```swift
public struct Event: Equatable, Sendable {
    public let type: String
    public let targetValue: String?
    public init(type: String, targetValue: String? = nil) {
        self.type = type
        self.targetValue = targetValue
    }
}
```

to:

```swift
/// Runtime DOM event payload surfaced into Swift handlers.
///
/// The two-argument `.on(_:perform:)` modifier passes one of these to the
/// user closure. The event-name catalog (`Event` enum) selects WHICH event
/// to listen for; `EventInfo` carries the runtime payload (type string, the
/// target's value for form inputs).
public struct EventInfo: Equatable, Sendable {
    /// DOM event name (e.g. `"click"`, `"input"`).
    public let type: String
    /// Convenience snapshot of `event.target.value` for form inputs; `nil` for
    /// events without a value-bearing target.
    public let targetValue: String?

    public init(type: String, targetValue: String? = nil) {
        self.type = type
        self.targetValue = targetValue
    }
}
```

Also update `EventHandler` (same file, ~line 90) so its `invoke` closure type becomes `(EventInfo) -> Void`:

```swift
public struct EventHandler: Equatable {
    public let id: Int
    public let invoke: (EventInfo) -> Void

    public init(id: Int, invoke: @escaping (EventInfo) -> Void) {
        self.id = id
        self.invoke = invoke
    }

    public static func == (lhs: EventHandler, rhs: EventHandler) -> Bool {
        lhs.id == rhs.id
    }
}
```

- [ ] **Step 2: Update `HandlerRegistry` signatures**

In `Sources/Swiflow/HandlerRegistry.swift`, update `register` and `dispatch`:

```swift
public func register(_ invoke: @escaping (EventInfo) -> Void) -> EventHandler { ... }

public func dispatch(id: Int, event: EventInfo) {
    handlers[id]?.invoke(event)
}
```

- [ ] **Step 3: Update DispatcherBridge call sites**

In `Sources/SwiflowWeb/DispatcherBridge.swift`, find every `Event(type:` constructor call and every `(Event)` closure type and rename to `EventInfo`. The dispatcher takes a JS event payload and constructs the Swift struct — that constructor call is what needs to change.

Run: `grep -n "Event(" Sources/SwiflowWeb/DispatcherBridge.swift`
Expected: handful of construction sites. Replace each `Event(` → `EventInfo(` and any closure parameter `(Event) -> Void` → `(EventInfo) -> Void`.

- [ ] **Step 4: Sweep tests**

Run: `grep -rn "Event(type:\|Event(\"\|: Event\b\|(Event) -> Void\|Event," Tests/`
Expected: hits in `VNodeTests.swift`, `HandlerRegistryTests.swift`, possibly `DSLTests.swift`. For each hit, replace `Event` → `EventInfo` in the relevant context (constructor calls, closure parameter types, generic parameters).

- [ ] **Step 5: Update the Counter template's closure parameter type**

In `Sources/SwiflowCLI/Templates/Templates.swift`, the `Counter` body has `.on("click", Swiflow.handlers.register { [weak self] _ in ... })`. The closure parameter `_` is `Event` — once Task 1 lands, it's `EventInfo`. The underscore means it never appears at a call site, but the embedded raw string template will be re-rewritten end-to-end in Task 10; for now no template change is needed.

- [ ] **Step 6: Build + test**

Run: `swift build`
Expected: success.

Run: `swift test`
Expected: all existing tests pass. If a test references `Event` directly (constructor or generic), it should already have been swept in Step 4 — re-grep if a test fails.

- [ ] **Step 7: Commit**

```bash
git add Sources/ Tests/
git commit -m "$(cat <<'EOF'
refactor: rename runtime Event struct to EventInfo

Frees the bare name `Event` for the upcoming event-name enum so users can
write `.on(.click) { ... }` without colliding with the runtime payload type.
Pure rename; no behavior change.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `Component` becomes `@MainActor`; lifecycle rename + drop `prev:`

**Files:**
- Modify: `Sources/Swiflow/Reactivity/Component.swift:17-53`
- Modify: `Sources/SwiflowWeb/Renderer.swift:167-194` (lifecycle call sites)
- Modify: `Sources/Swiflow/Diff/Diff.swift:404-454` (`onUnmount` call site + trampoline)
- Modify: `Tests/SwiflowTests/Reactivity/*` (every conforming type + every lifecycle reference)

**Design note:** this is the cascade enabler. Once `Component` is `@MainActor`, every conforming class gets MainActor isolation automatically, which eliminates the need for `@unchecked Sendable` on user `Counter` classes and lets handler closures be plain `@MainActor () -> Void`.

- [ ] **Step 1: Update the `Component` protocol declaration**

In `Sources/Swiflow/Reactivity/Component.swift`, replace lines 17-53 with:

```swift
@MainActor
public protocol Component: AnyObject {
    /// The view this component renders. Called by the diff on every render.
    /// Must be pure (no side effects) — the renderer doesn't memoize.
    var body: VNode { get }

    /// Called once after the component's body has been mounted to the DOM.
    /// Defaulted to no-op.
    func onAppear()

    /// Called after every re-render's patches have been applied. Use this
    /// hook to react to changes; the framework does NOT pass a snapshot of
    /// the prior state. Authors who need the prior value must stash it
    /// themselves before mutation (or via a side field).
    ///
    /// Defaulted to no-op.
    func onChange()

    /// Called immediately before the component's subtree is destroyed.
    /// Defaulted to no-op.
    func onDisappear()
}

public extension Component {
    func onAppear() {}
    func onChange() {}
    func onDisappear() {}
}
```

Delete the existential-dispatch trampoline doc comment along with the old `onUpdate(prev: Self)` signature.

- [ ] **Step 2: Update Renderer lifecycle call sites**

In `Sources/SwiflowWeb/Renderer.swift`, the block around line 167 calls `root.instance.onMount()` and the trampoline at line 186 calls `c.onUpdate(prev: c)`. Replace:

- `onMount()` → `onAppear()`
- The `callOnUpdate<C: Component>(_ c: C) { c.onUpdate(prev: c) }` trampoline function should be DELETED (zero-arg `onChange()` doesn't need it — call directly on the `any Component` existential).
- Replace the trampoline call site with: `root.instance.onChange()` (direct call works because `onChange()` has no `Self`-typed parameter).

- [ ] **Step 3: Update Diff.swift lifecycle call sites**

In `Sources/Swiflow/Diff/Diff.swift`, replace every `onUnmount()` call with `onDisappear()`. The existential-opening trampoline at ~line 449-454 (`unmountComponentInstance`) can stay as-is in structure but should call `c.onDisappear()` (or be inlined entirely since `onDisappear()` has no `Self`-typed param — can be invoked directly on `any Component`). Inline it: replace the trampoline invocation with `mountNode.component?.instance.onDisappear()` at the call site, then delete the trampoline function.

- [ ] **Step 4: Sweep tests for lifecycle hook references**

Run: `grep -rn "onMount\|onUpdate\|onUnmount" Sources/ Tests/`
Expected: hits in test files like `ComponentLifecycleTests.swift`, `RendererLifecycleTests.swift`, possibly diff tests. Replace each with the new names:
- `onMount` → `onAppear`
- `onUpdate(prev:` → `onChange()` (delete the `prev:` argument)
- `onUpdate` → `onChange`
- `onUnmount` → `onDisappear`

- [ ] **Step 5: Sweep tests for `Component`-conforming types**

Any test that defines `class FakeComponent: Component { ... }` — these classes will inherit `@MainActor` automatically. Tests that touch these instances from non-MainActor contexts will fail to compile. Solutions:
- If the test method is `@Test func ...`, annotate the test type with `@MainActor` or the individual `@Test` with `@MainActor`.
- If the test uses `nonisolated` access, accept the new compile error and add `@MainActor` to the surrounding scope.

Run: `swift build` and read the errors. For each error like "call to main actor-isolated initializer 'init()' in a synchronous nonisolated context", add `@MainActor` to the test type or function.

- [ ] **Step 6: Build + test**

Run: `swift build`
Expected: success after annotations sweep in Step 5.

Run: `swift test`
Expected: all tests pass. Lifecycle behavior is unchanged — `onAppear`/`onChange`/`onDisappear` fire at the same diff points `onMount`/`onUpdate`/`onUnmount` did.

- [ ] **Step 7: Commit**

```bash
git add Sources/ Tests/
git commit -m "$(cat <<'EOF'
refactor(component): @MainActor isolation + onAppear/onChange/onDisappear

Component protocol becomes @MainActor-isolated, eliminating the need for
@unchecked Sendable conformance on user component classes. Lifecycle hooks
renamed to match SwiftUI muscle memory; onUpdate(prev: Self) becomes zero-arg
onChange() — drops the existential-dispatch trampoline and its 18-line doc.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: New `Event` enum

**Files:**
- Create: `Sources/Swiflow/DSL/Event.swift`
- Create: `Tests/SwiflowTests/DSL/EventTests.swift`

**Design note:** purely additive — no existing call sites. Task 4 wires this into `.on(_:perform:)`.

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowTests/DSL/EventTests.swift`:

```swift
// Tests/SwiflowTests/DSL/EventTests.swift
import Testing
@testable import Swiflow

@Suite("Event enum")
struct EventTests {
    @Test("Simple cases map to their DOM names")
    func simpleCases() {
        #expect(Event.click.domName == "click")
        #expect(Event.input.domName == "input")
        #expect(Event.change.domName == "change")
        #expect(Event.submit.domName == "submit")
        #expect(Event.keydown.domName == "keydown")
        #expect(Event.keyup.domName == "keyup")
        #expect(Event.keypress.domName == "keypress")
        #expect(Event.focus.domName == "focus")
        #expect(Event.blur.domName == "blur")
        #expect(Event.mousedown.domName == "mousedown")
        #expect(Event.mouseup.domName == "mouseup")
        #expect(Event.mousemove.domName == "mousemove")
        #expect(Event.mouseenter.domName == "mouseenter")
        #expect(Event.mouseleave.domName == "mouseleave")
    }

    @Test("Custom event uses the provided name verbatim")
    func customEvent() {
        #expect(Event.custom("animationend").domName == "animationend")
        #expect(Event.custom("my-app:foo").domName == "my-app:foo")
    }

    @Test("Events are hashable and equatable")
    func hashableEquatable() {
        #expect(Event.click == Event.click)
        #expect(Event.click != Event.input)
        #expect(Event.custom("x") == Event.custom("x"))
        #expect(Event.custom("x") != Event.custom("y"))
        let set: Set<Event> = [.click, .input, .custom("foo")]
        #expect(set.count == 3)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EventTests`
Expected: FAIL with "cannot find 'Event' in scope" (or similar — the existing `Event` was renamed to `EventInfo` in Task 1).

- [ ] **Step 3: Create the Event enum**

Create `Sources/Swiflow/DSL/Event.swift`:

```swift
// Sources/Swiflow/DSL/Event.swift

/// Catalog of DOM event names used by `.on(_:perform:)` modifiers.
///
/// Most events are simple cases that map 1:1 to their DOM name via
/// `String(describing:)`. The `.custom(_:)` case is the escape hatch for
/// events not in the catalog (custom DOM events, library events, future
/// additions before this enum is updated).
///
/// Usage:
/// ```swift
/// button("Save").on(.click) { save() }
/// input(.prop("type", "text")).on(.input) { event in
///     name = event.targetValue ?? ""
/// }
/// ```
public enum Event: Sendable, Hashable {
    case click
    case input, change, submit
    case keydown, keyup, keypress
    case focus, blur
    case mousedown, mouseup, mousemove, mouseenter, mouseleave
    case custom(String)

    /// The raw DOM event name (`"click"`, `"input"`, etc.). Read by the
    /// renderer when registering the listener on the host element.
    internal var domName: String {
        switch self {
        case .custom(let name): return name
        default: return String(describing: self)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter EventTests`
Expected: PASS — all three `@Test` cases green.

- [ ] **Step 5: Commit**

```bash
git add Sources/Swiflow/DSL/Event.swift Tests/SwiflowTests/DSL/EventTests.swift
git commit -m "$(cat <<'EOF'
feat(dsl): add Event enum for typed event-name catalog

Introduces .click / .input / .change / .submit / .keydown / etc. plus
.custom(String) escape hatch. domName is internal — used by the renderer
when wiring listeners. Standalone; .on(_:perform:) wiring lands in Task 4.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Clean handler API — `.on(.click) { ... }`

**Files:**
- Modify: `Sources/Swiflow/DSL/Modifiers.swift:46-48` (delete old `.on(_ event: String, _ handler: EventHandler)`, add two new overloads)
- Modify: `Sources/Swiflow/HandlerRegistry.swift` — visibility to `internal`; add per-Component scope (see step 3)
- Modify: `Sources/SwiflowWeb/SwiflowWeb.swift:97-102` — delete public `Swiflow.handlers` property; add internal ambient lookup
- Modify: `Sources/SwiflowWeb/Renderer.swift` — open/close handler scope on Component mount/unmount
- Modify: `Sources/Swiflow/Diff/Diff.swift` — call scope close on Component unmount path
- Modify: tests that referenced `Swiflow.handlers.register` or `.on("click", ...)`

**Design note:** the user calls `.on(.click) { self.count += 1 }`. Internally `.on` calls into the ambient registry. Per-Component scope means handlers registered while a Component is mounted are evicted when that Component unmounts — closing the lifetime safety gap that `[weak self]` would otherwise plug.

- [ ] **Step 1: Write the failing test**

Add to a new file `Tests/SwiflowTests/Reactivity/ComponentLifecycleScopedHandlersTests.swift`:

```swift
// Tests/SwiflowTests/Reactivity/ComponentLifecycleScopedHandlersTests.swift
import Testing
@testable import Swiflow

@Suite("HandlerRegistry per-Component scope")
struct ComponentLifecycleScopedHandlersTests {
    @Test("openScope/closeScope evicts handlers registered inside scope")
    @MainActor
    func scopedHandlersAreEvictedOnClose() {
        let r = HandlerRegistry()
        let h1 = r.register { _ in }                            // outside scope
        r.openScope()
        let h2 = r.register { _ in }                            // inside scope
        let h3 = r.register { _ in }                            // inside scope
        r.closeScope()

        #expect(r.handler(forID: h1.id) != nil)                 // survives
        #expect(r.handler(forID: h2.id) == nil)                 // evicted
        #expect(r.handler(forID: h3.id) == nil)                 // evicted
    }

    @Test("Nested scopes evict independently")
    @MainActor
    func nestedScopes() {
        let r = HandlerRegistry()
        r.openScope()
        let outer = r.register { _ in }
        r.openScope()
        let inner = r.register { _ in }
        r.closeScope()
        #expect(r.handler(forID: outer.id) != nil)
        #expect(r.handler(forID: inner.id) == nil)
        r.closeScope()
        #expect(r.handler(forID: outer.id) == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ComponentLifecycleScopedHandlersTests`
Expected: FAIL with "value of type 'HandlerRegistry' has no member 'openScope'".

- [ ] **Step 3: Add scope tracking to `HandlerRegistry`**

In `Sources/Swiflow/HandlerRegistry.swift`, change visibility to `internal` and add scope tracking:

```swift
// Sources/Swiflow/HandlerRegistry.swift

/// Owns the canonical mapping from integer handler IDs to Swift closures.
///
/// Scoped: callers (the Renderer, on Component mount) open a scope before
/// invoking `body`; all IDs registered while a scope is open are tracked
/// against that scope. Closing the scope (on Component unmount) evicts
/// every ID registered inside it. This lets `.on(_:perform:)` closures
/// capture `self` strongly: the framework guarantees the closure is dead
/// before the Component instance is.
internal final class HandlerRegistry {
    private var nextID: Int = 0
    private var handlers: [Int: EventHandler] = [:]
    private var scopeStack: [[Int]] = []     // each frame is the IDs registered in that scope

    internal init() {}

    @discardableResult
    internal func register(_ invoke: @escaping (EventInfo) -> Void) -> EventHandler {
        let id = nextID
        nextID += 1
        let h = EventHandler(id: id, invoke: invoke)
        handlers[id] = h
        if !scopeStack.isEmpty {
            scopeStack[scopeStack.count - 1].append(id)
        }
        return h
    }

    internal func handler(forID id: Int) -> EventHandler? { handlers[id] }
    internal func remove(id: Int) { handlers.removeValue(forKey: id) }
    internal func dispatch(id: Int, event: EventInfo) { handlers[id]?.invoke(event) }

    internal func openScope() {
        scopeStack.append([])
    }

    internal func closeScope() {
        guard let ids = scopeStack.popLast() else { return }
        for id in ids { handlers.removeValue(forKey: id) }
    }
}
```

Note the visibility flip: `public final class` → `internal final class`. The class is no longer part of the public API; the `.on(_:perform:)` modifier is the only way user code reaches it.

Also note: `register` was previously non-discardable (the doc said "dropping it means the closure is stored forever"). With per-Component scope, dropping the result is now safe — scope closure handles cleanup. Mark `@discardableResult`.

- [ ] **Step 4: Run scope test to verify it passes**

Run: `swift test --filter ComponentLifecycleScopedHandlersTests`
Expected: PASS.

- [ ] **Step 5: Delete the old string-based `.on(_:_:)` from `Modifiers.swift`**

In `Sources/Swiflow/DSL/Modifiers.swift`, delete lines 45-48 (the `/// Shorthand for .handler(event:value:)` doc-comment + the 3-line `static func on(_ event: String, _ handler: EventHandler)`). The new typed overloads live in `SwiflowWeb` (next step) — they need the ambient renderer, which only exists in the WASM-capable module.

- [ ] **Step 6: Add the new `.on(_:perform:)` overloads in SwiflowWeb**

The new overloads live in `SwiflowWeb` (not `Swiflow`) because they need ambient-renderer access; the base `Swiflow` module stays platform-agnostic.

Create `Sources/SwiflowWeb/AttributeModifiers.swift`:

```swift
// Sources/SwiflowWeb/AttributeModifiers.swift
#if canImport(JavaScriptKit)
@_exported import Swiflow

/// Registers `invoke` with the ambient renderer's handler registry. Called
/// internally by the `.on(_:perform:)` modifier overloads below. Traps if
/// no renderer is mounted — only possible if a modifier is constructed
/// outside a render cycle, which is a programmer error.
@MainActor
internal func _registerAmbientHandler(
    _ invoke: @escaping @MainActor (EventInfo) -> Void
) -> EventHandler {
    guard let renderer = ambientRenderer else {
        fatalError(
            "Swiflow modifier .on(_:perform:) was used before Swiflow.render(into:_:) was called. "
            + "Event handlers must be constructed inside a Component body that the renderer is "
            + "actively building — typically this means you're calling a Swiflow factory at module scope."
        )
    }
    return renderer.handlers.register { event in
        MainActor.assumeIsolated { invoke(event) }
    }
}

public extension Attribute {
    /// Attaches an event listener for `event`. The closure runs on the main
    /// actor when the DOM event fires. Handler lifetime is tied to the
    /// owning component — closures may capture `self` strongly.
    @MainActor
    static func on(
        _ event: Event,
        perform action: @escaping @MainActor () -> Void
    ) -> Attribute {
        .handler(event: event.domName, value: _registerAmbientHandler { _ in action() })
    }

    /// Attaches an event listener for `event` that receives the runtime DOM
    /// event payload (`EventInfo`).
    @MainActor
    static func on(
        _ event: Event,
        perform action: @escaping @MainActor (EventInfo) -> Void
    ) -> Attribute {
        .handler(event: event.domName, value: _registerAmbientHandler(action))
    }
}
#endif
```

The `MainActor.assumeIsolated` wrapper is what the framework now absorbs on the user's behalf — JS-driven event dispatch is synchronous and single-threaded on the WASM main actor, so the assertion is sound.

Also in `Sources/SwiflowWeb/SwiflowWeb.swift`, delete the public `static var handlers: HandlerRegistry` block (lines 79-103 — the doc-block plus the property). The internal `_registerAmbientHandler` above is the only path.

For `ambientRenderer` to be visible from `AttributeModifiers.swift`: it's currently declared `nonisolated(unsafe) private var ambientRenderer: Renderer?` in `SwiflowWeb.swift` (line 18). Change `private` → `internal` so the sibling file can reach it.

- [ ] **Step 7: Wire scope open/close to Component mount/unmount in the Renderer**

In `Sources/SwiflowWeb/Renderer.swift`, around the lifecycle call sites:

- Before invoking `body` for the first time on a Component (first mount), call `self.handlers.openScope()`.
- After the mount completes, the scope stays open as long as the Component is mounted.
- On Component unmount (the path in `Sources/Swiflow/Diff/Diff.swift` that fires `onDisappear`), call the registry's `closeScope()` immediately AFTER firing `onDisappear` and BEFORE the subtree is torn down.

Concretely:
- `Renderer.swift` first-mount: locate where `root.instance.onAppear()` is called (Task 2 renamed it). Add `self.handlers.openScope()` immediately BEFORE the `body` evaluation for that component.
- `Diff.swift` unmount: in `unmountSubtree(at:)` (around line 417-420 where `onUnmount`/`onDisappear` is called), add `registry.closeScope()` immediately after the `onDisappear` call. The registry reference is already available via the Diff's renderer link.

Note: the per-Component scope is one-deep right now (root component). The implementation supports nested scopes (one per mounted Component); fully wiring nested Components to open/close their own scopes is correct but is only exercised by `embed { ... }` (Task 5). Add a stub TODO comment to the embed mount path noting "open scope on this component's mount; close on unmount" — fully wired in Task 5.

- [ ] **Step 8: Sweep user-visible call sites of `Swiflow.handlers.register`**

Run: `grep -rn "Swiflow.handlers" Sources/ Tests/`
Expected: hits in `Templates.swift` (the Counter template — handled in Task 10) and possibly tests. For tests, replace `.on("click", Swiflow.handlers.register { ... })` with `.on(.click) { ... }`. If a test was specifically exercising the old shape, delete it (the new shape is tested via Task 4's scope tests + the `.on` overload tests below).

- [ ] **Step 9: Add a smoke test for the new `.on(_:perform:)` modifier**

Add to `Tests/SwiflowTests/DSLTests.swift` (or a new `Tests/SwiflowWebTests/AttributeModifiersTests.swift` if that target exists — verify by checking `Package.swift`'s test target list):

```swift
@Test("Attribute.on with .click takes a zero-arg @MainActor closure")
@MainActor
func attributeOnZeroArg() {
    // Compile-only check — the framework's ambient renderer is required
    // for runtime registration; this test confirms the API shape.
    _ = { (_ : Attribute) in }(
        .on(.click) { /* zero-arg closure compiles */ }
    )
    _ = { (_ : Attribute) in }(
        .on(.input) { (info: EventInfo) in _ = info.targetValue }
    )
}
```

Note: this is a compile-shape check, not a behavioral test. Behavioral test requires the ambient renderer and lives in a Playwright spec.

- [ ] **Step 10: Build + test**

Run: `swift build`
Expected: success.

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 11: Commit**

```bash
git add Sources/ Tests/
git commit -m "$(cat <<'EOF'
feat(dsl): .on(.click) { ... } handler API; HandlerRegistry becomes internal

User code now writes `.on(.click) { self.count += 1 }` — the framework
absorbs registry registration and MainActor.assumeIsolated. Per-Component
scope on HandlerRegistry guarantees closures cannot outlive their owning
component, so [weak self] is no longer needed in user code.

HandlerRegistry's public surface (including Swiflow.handlers) is gone.
Old string-based Attribute.on(_:_:) is deleted — Event enum is the only path.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `embed { Counter() }`

**Files:**
- Modify: `Sources/Swiflow/DSL/ComponentDSL.swift:30-35`
- Modify: any test or source referencing `component({` or `component(_:key:)`
- Modify: Renderer wiring for nested-Component scope opens (Task 4 stub)

**Design note:** the old `component(_:key:)` factory had a colliding name with the `Component` protocol. Renaming to `embed` resolves the collision and gives trailing-closure shape.

- [ ] **Step 1: Replace `component(_:key:)` with `embed`**

In `Sources/Swiflow/DSL/ComponentDSL.swift`, replace lines 30-35 with:

```swift
/// Embeds a `Component` in a VNode tree.
///
/// Usage in a parent component's body:
/// ```swift
/// div {
///     h1("Header")
///     embed { Counter() }              // unkeyed
///     embed("row-\(id)") { Row(id) }   // keyed; survives reorder
/// }
/// ```
///
/// The `factory` closure is invoked at first mount only. Subsequent renders
/// that produce an equal `ComponentDescription` at the same child position
/// reuse the existing instance (so `@State` survives re-renders) — see
/// `ComponentDescription` for the typeID+key identity rules.
///
/// - Warning: The factory closure must allocate a **fresh** instance every
///   call — `{ Counter() }`, not `{ self.existingCounter }`.
@MainActor
public func embed<C: Component>(
    _ factory: @escaping @MainActor () -> C
) -> VNode {
    .component(ComponentDescription(C.self, key: nil, factory: factory))
}

/// Embeds a keyed `Component` in a VNode tree. The `key` stabilizes identity
/// across reorders — see the unkeyed overload's doc for the warning about
/// fresh instances.
@MainActor
public func embed<C: Component>(
    _ key: String,
    _ factory: @escaping @MainActor () -> C
) -> VNode {
    .component(ComponentDescription(C.self, key: key, factory: factory))
}
```

- [ ] **Step 2: Sweep call sites**

Run: `grep -rn "\bcomponent(" Sources/ Tests/`
Expected: every match for `component(_ : ..., key: ...)` style or `component({` style. Replace each:
- `component({ Counter() })` → `embed { Counter() }`
- `component({ X() }, key: "a")` → `embed("a") { X() }`

- [ ] **Step 3: Wire nested-Component handler scope (from Task 4 stub)**

In whichever file mounts an `embed`-produced Component (likely `Renderer.swift` or a child-mount path in `Diff.swift`), locate where a child `Component` first mounts and add `renderer.handlers.openScope()` before `body` is evaluated. In the child-unmount path, add `renderer.handlers.closeScope()` after `onDisappear` fires. (This is the wiring promised in Task 4 step 7.)

- [ ] **Step 4: Build + test**

Run: `swift build && swift test`
Expected: success. Any test that previously called `component({...})` and now calls `embed { ... }` should produce identical mount behavior.

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "$(cat <<'EOF'
refactor(dsl): rename component(_:key:) to embed { ... }

Trailing-closure shape removes the case-collision with the Component
protocol and drops the noisy ({ ... }) inner braces. Also wires nested
Component handler scopes — each embedded component opens/closes its own
HandlerRegistry scope on mount/unmount.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: `Swiflow.render(into:) { factory }`

**Files:**
- Modify: `Sources/SwiflowWeb/SwiflowWeb.swift:31-77` — delete two old overloads, add one new factory-taking overload

**Design note:** unifies root + nested Component instantiation around one factory-based contract.

- [ ] **Step 1: Replace the two `render` overloads with a single factory-taking version**

In `Sources/SwiflowWeb/SwiflowWeb.swift`, replace the entire `public extension Swiflow { ... }` block (the part that currently contains both `render(_ viewProducer:into:)` and `render<C>(_ root:into:)` and `rerender` and `handlers`) with:

```swift
public extension Swiflow {
    /// Mounts a Component tree into the DOM node matched by `selector`.
    ///
    /// The factory is invoked exactly once to produce the root Component
    /// instance. A `RAFScheduler` is created and wired into the diff so
    /// `@State` mutations on any component in the tree automatically
    /// schedule re-renders via `requestAnimationFrame`.
    ///
    /// **Single-root:** the v1 implementation supports a single root per
    /// app. Calling `render` twice traps with a clear error — multi-root
    /// support is a future-phase item.
    ///
    /// Usage:
    /// ```swift
    /// Swiflow.render(into: "#app") { Counter() }
    /// ```
    @MainActor
    static func render<C: Component>(
        into selector: String,
        _ factory: @escaping @MainActor () -> C
    ) {
        precondition(
            ambientRenderer == nil,
            "Swiflow.render(into:_:) was already called. v1 supports a single root per app; "
            + "a second render would silently drop event dispatch for new handlers because the JS "
            + "dispatcher remains bound to the first registry."
        )
        let root = factory()
        let renderer = Renderer(rootComponent: AnyComponent(root), selector: selector)
        ambientRenderer = renderer
        DispatcherBridge.installIfNeeded(registry: renderer.handlers)
        renderer.renderOnce()
    }

    /// Re-evaluates the registered root and applies any resulting patches.
    /// A no-op if `render(into:_:)` has not been called. Typically not
    /// called directly — `@State` mutations schedule re-renders automatically.
    @MainActor
    static func rerender() {
        ambientRenderer?.renderOnce()
    }
}
```

The deleted symbols:
- `Swiflow.render(_ viewProducer: @escaping () -> VNode, into:)`
- `Swiflow.render<C: Component>(_ root: C, into:)`
- `Swiflow.handlers` (already deleted in Task 4)

- [ ] **Step 2: Sweep call sites**

Run: `grep -rn "Swiflow.render(" Sources/ Tests/`
Expected: hits in `Templates.swift` (handled in Task 10) and possibly tests. Update each: `Swiflow.render(Counter(), into: "#app")` → `Swiflow.render(into: "#app") { Counter() }`.

- [ ] **Step 3: Build + test**

Run: `swift build && swift test`
Expected: success.

- [ ] **Step 4: Commit**

```bash
git add Sources/ Tests/
git commit -m "$(cat <<'EOF'
refactor(web): unify Swiflow.render around factory contract

Single render(into:_:) takes a trailing-closure factory matching `embed`.
Old VNode-producer and instance-taking overloads removed. Root and embedded
components now share one mental model: the framework owns instantiation.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: `.attr` typed overloads + `.data` helper + `PropertyValue` literals

**Files:**
- Modify: `Sources/Swiflow/DSL/Modifiers.swift` — add `.attr` overloads + `.data`
- Modify: wherever `PropertyValue` is defined (locate via grep) — add literal conformances

**Design note:** small ergonomic wins. `data("foo", "x")` becomes a first-class helper instead of `.attr("data-foo", "x")`. `PropertyValue` adopts literal protocols so `.prop("value", "hi")` works without `.string("hi")` wrappers.

- [ ] **Step 1: Locate `PropertyValue`**

Run: `grep -rn "enum PropertyValue\|struct PropertyValue" Sources/`
Expected: a single hit (likely `Sources/Swiflow/VNode.swift` or `Sources/Swiflow/DSL/Modifiers.swift`).

- [ ] **Step 2: Add literal conformances to `PropertyValue`**

In the file where `PropertyValue` lives, after the existing declaration, add an extension:

```swift
extension PropertyValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension PropertyValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension PropertyValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension PropertyValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}
```

Verify case names match `PropertyValue`'s actual cases. If a case is missing (e.g., no `.int` case exists today), either skip that conformance or add the case — read the existing declaration first to decide. Common case names: `.string`, `.bool`, `.int`/`.number`, `.double`/`.number`. The plan assumes `.string`, `.bool`, `.int`, `.double` — adjust to match.

- [ ] **Step 3: Add `.attr` typed overloads and `.data` helper to `Attribute`**

In `Sources/Swiflow/DSL/Modifiers.swift`, after the existing `Attribute.attr(_:_:)` factory:

```swift
    /// Sets an HTML attribute with an `Int` value (stringified).
    public static func attr(_ name: String, _ value: Int) -> Attribute {
        .attribute(name: name, value: String(value))
    }

    /// Sets an HTML attribute with a `Bool` value. `true` writes the attribute
    /// with an empty string (`<input disabled="">`); `false` omits the attribute
    /// entirely by returning a no-op style attribute. (Callers that want
    /// `attribute="false"` should pass a `String` instead.)
    public static func attr(_ name: String, _ value: Bool) -> Attribute {
        .attribute(name: name, value: value ? "" : "")  // boolean attrs: presence is truth
    }

    /// Sets an HTML attribute with a `Double` value (stringified).
    public static func attr(_ name: String, _ value: Double) -> Attribute {
        .attribute(name: name, value: String(value))
    }

    /// Convenience for `data-*` attributes. `.data("user-id", "42")` emits
    /// `data-user-id="42"`.
    public static func data(_ name: String, _ value: String) -> Attribute {
        .attribute(name: "data-\(name)", value: value)
    }
```

Note on `Bool`: HTML boolean attributes are presence-or-absent (`disabled`, `checked`, `readonly`, etc.) — `disabled="false"` is wrong. The implementation above emits an empty string for `true`. For `false`, the cleanest behavior is to emit a no-op (return an attribute that the fold step ignores). Since `Attribute` has no "no-op" case, the current implementation emits an empty string in both cases — a known limitation; user should not pass `Bool` if they don't want the attribute at all. Document this in the doc comment if it isn't obvious; alternatively, gate the attribute via a wrapping `if value { ... }` in the call site.

Actually a cleaner approach: change the `Bool` overload to take a different return shape — use `.attribute` only when `value == true`, return a sentinel for `false`. The simplest workable form is documented above; if the call-site `if`-guard pattern is preferred, simplify the Bool overload to require `true` and remove the `false`-branch.

For the plan: emit the empty-string-on-true / empty-string-on-false as shown, mark with a doc-comment caveat ("for present-or-absent semantics, gate the modifier in the call site"). Refinement can land in a follow-up.

- [ ] **Step 4: Add tests**

Append to `Tests/SwiflowTests/DSLTests.swift`:

```swift
@Test("Attribute.attr typed overloads stringify values")
func attrTypedOverloads() {
    if case let .attribute(name, value) = Attribute.attr("rows", 5) {
        #expect(name == "rows" && value == "5")
    } else { Issue.record("expected .attribute case") }

    if case let .attribute(name, value) = Attribute.attr("step", 0.5) {
        #expect(name == "step" && value == "0.5")
    } else { Issue.record("expected .attribute case") }
}

@Test("Attribute.data prefixes name with `data-`")
func attrDataPrefixes() {
    if case let .attribute(name, value) = Attribute.data("user-id", "42") {
        #expect(name == "data-user-id" && value == "42")
    } else { Issue.record("expected .attribute case") }
}

@Test("PropertyValue accepts string/int/bool/double literals")
func propertyValueLiterals() {
    let s: PropertyValue = "hi"
    let i: PropertyValue = 7
    let b: PropertyValue = true
    let d: PropertyValue = 1.5
    if case .string(let v) = s { #expect(v == "hi") } else { Issue.record("expected .string") }
    if case .int(let v) = i { #expect(v == 7) } else { Issue.record("expected .int") }
    if case .bool(let v) = b { #expect(v == true) } else { Issue.record("expected .bool") }
    if case .double(let v) = d { #expect(v == 1.5) } else { Issue.record("expected .double") }
}
```

Verify the `PropertyValue` case names in the assertions match the actual enum.

- [ ] **Step 5: Build + test**

Run: `swift build && swift test`
Expected: success.

- [ ] **Step 6: Commit**

```bash
git add Sources/ Tests/
git commit -m "$(cat <<'EOF'
feat(dsl): typed .attr overloads, .data helper, PropertyValue literals

.attr now accepts Int/Bool/Double in addition to String. .data("foo", "x")
emits data-foo="x" without manual prefix. PropertyValue conforms to
ExpressibleByStringLiteral / BooleanLiteral / IntegerLiteral / FloatLiteral
so .prop("value", "hi") works without .string("hi") wrapping.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Postfix VNode chaining

**Files:**
- Create: `Sources/Swiflow/DSL/VNodeModifiers.swift`
- Create: `Tests/SwiflowTests/DSL/VNodeModifiersTests.swift`
- Modify: the same file in `SwiflowWeb` that hosted the `.on(_:perform:)` Attribute overloads (Task 4) needs a parallel set of VNode-postfix overloads, because they too require ambient registry access. The `Sources/SwiflowWeb/AttributeModifiers.swift` file is the natural home.

**Design note:** chainable modifiers operate on `.element` cases. Non-element VNodes (`.text`, `.component`, `.rawHTML`) trigger `swiflowDiagnostic` in DEBUG and return unchanged.

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowTests/DSL/VNodeModifiersTests.swift`:

```swift
// Tests/SwiflowTests/DSL/VNodeModifiersTests.swift
import Testing
@testable import Swiflow

@Suite("VNode postfix modifiers")
struct VNodeModifiersTests {
    @Test(".class appends to the attributes bag")
    func classOnElement() {
        let v = div { }.class("row")
        guard case .element(let data) = v else { Issue.record("expected .element"); return }
        #expect(data.attributes["class"] == "row")
    }

    @Test(".class on a non-element returns the node unchanged")
    func classOnText() {
        // DEBUG builds emit a diagnostic; release builds silently no-op.
        // Either way the result is the same VNode.
        let text: VNode = .text("hi")
        let result = text.class("row")
        if case .text(let s) = result { #expect(s == "hi") }
        else { Issue.record("expected .text") }
    }

    @Test(".id, .style, .attr, .data compose")
    func compose() {
        let v = div { }
            .id("hero")
            .class("container")
            .style("padding", "1rem")
            .attr("role", "main")
            .data("user-id", "42")
        guard case .element(let data) = v else { Issue.record("expected .element"); return }
        #expect(data.attributes["id"] == "hero")
        #expect(data.attributes["class"] == "container")
        #expect(data.style["padding"] == "1rem")
        #expect(data.attributes["role"] == "main")
        #expect(data.attributes["data-user-id"] == "42")
    }

    @Test(".attr typed overloads work in postfix position")
    func typedAttrPostfix() {
        let v = input().attr("rows", 5).attr("step", 0.5)
        guard case .element(let data) = v else { Issue.record("expected .element"); return }
        #expect(data.attributes["rows"] == "5")
        #expect(data.attributes["step"] == "0.5")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VNodeModifiersTests`
Expected: FAIL with "value of type 'VNode' has no member 'class'".

- [ ] **Step 3: Implement postfix chaining on VNode (non-handler modifiers)**

Create `Sources/Swiflow/DSL/VNodeModifiers.swift`:

```swift
// Sources/Swiflow/DSL/VNodeModifiers.swift

/// Returns a new VNode with an additional attribute merged into its bag.
/// Non-element VNodes (.text, .component, .rawHTML) trigger a diagnostic
/// in DEBUG and pass through unchanged.
private func mergeAttribute(_ vnode: VNode, _ apply: (inout ElementData) -> Void) -> VNode {
    if case .element(var data) = vnode {
        apply(&data)
        return .element(data)
    }
    #if DEBUG
    swiflowDiagnostic("Postfix VNode modifier applied to a non-element VNode — this is a programmer error. The modifier is silently ignored.")
    #endif
    return vnode
}

public extension VNode {
    /// Adds (or overwrites) the `class` attribute.
    func `class`(_ name: String) -> VNode {
        mergeAttribute(self) { $0.attributes["class"] = name }
    }

    /// Adds (or overwrites) the `id` attribute.
    func id(_ name: String) -> VNode {
        mergeAttribute(self) { $0.attributes["id"] = name }
    }

    /// Adds (or overwrites) an inline-style declaration.
    func style(_ property: String, _ value: String) -> VNode {
        mergeAttribute(self) { $0.style[property] = value }
    }

    /// Adds (or overwrites) an HTML attribute (string value).
    func attr(_ name: String, _ value: String) -> VNode {
        mergeAttribute(self) { $0.attributes[name] = value }
    }

    /// Adds (or overwrites) an HTML attribute (integer value, stringified).
    func attr(_ name: String, _ value: Int) -> VNode {
        mergeAttribute(self) { $0.attributes[name] = String(value) }
    }

    /// Adds (or overwrites) an HTML attribute (boolean: empty string written when true).
    func attr(_ name: String, _ value: Bool) -> VNode {
        mergeAttribute(self) { $0.attributes[name] = value ? "" : "" }
    }

    /// Adds (or overwrites) an HTML attribute (double value, stringified).
    func attr(_ name: String, _ value: Double) -> VNode {
        mergeAttribute(self) { $0.attributes[name] = String(value) }
    }

    /// Adds a `data-*` attribute. `.data("user-id", "42")` writes `data-user-id="42"`.
    func data(_ name: String, _ value: String) -> VNode {
        mergeAttribute(self) { $0.attributes["data-\(name)"] = value }
    }
}
```

Verify the field names on `ElementData` match (`attributes`, `style` — these are the names from `applyAttributes` in `Modifiers.swift`).

- [ ] **Step 4: Implement postfix `.on(_:perform:)` overloads (web-only, registry-aware)**

In `Sources/SwiflowWeb/AttributeModifiers.swift` (created in Task 4), add parallel `VNode` extensions for the two `.on(_:perform:)` overloads:

```swift
public extension VNode {
    @MainActor
    func on(
        _ event: Event,
        perform action: @escaping @MainActor () -> Void
    ) -> VNode {
        if case .element(var data) = self {
            let handler = _registerAmbientHandler { _ in action() }
            data.handlers[event.domName] = handler
            return .element(data)
        }
        #if DEBUG
        swiflowDiagnostic("Postfix .on(_:perform:) applied to a non-element VNode — this is a programmer error. The modifier is silently ignored.")
        #endif
        return self
    }

    @MainActor
    func on(
        _ event: Event,
        perform action: @escaping @MainActor (EventInfo) -> Void
    ) -> VNode {
        if case .element(var data) = self {
            let handler = _registerAmbientHandler(action)
            data.handlers[event.domName] = handler
            return .element(data)
        }
        #if DEBUG
        swiflowDiagnostic("Postfix .on(_:perform:) applied to a non-element VNode — this is a programmer error. The modifier is silently ignored.")
        #endif
        return self
    }
}
```

- [ ] **Step 5: Run tests to verify the new postfix API**

Run: `swift test --filter VNodeModifiersTests`
Expected: PASS.

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/ Tests/
git commit -m "$(cat <<'EOF'
feat(dsl): postfix VNode chaining for modifiers + .on handlers

div { ... }.class("row").id("hero").on(.click) { count += 1 } now reads
left-to-right. Modifier set covers .class / .id / .style / .attr (typed
overloads) / .data / .on (zero-arg + EventInfo). Non-element VNodes
trigger swiflowDiagnostic in DEBUG and pass through unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Surface audit + smaller renames

**Files:**
- Modify: `Sources/Swiflow/DSL/Modifiers.swift:59-63` — `applyAttributes` visibility
- Modify: `Sources/Swiflow/Reactivity/Component.swift:59-121` — `AnyComponent` + `ComponentDescription` field visibility
- Modify: `Sources/Swiflow/DSL/Elements.swift:97,105,223` — `a` → `link`, `main_` → `mainElement`
- Modify: `Sources/Swiflow/Reactivity/Scheduler.swift:43,49-82` — `InProcessScheduler` → `SyncScheduler`
- Modify: `Sources/Swiflow/DSL/ResultBuilder.swift:12,43` — `buildBlock`/`buildArray` param rename
- Modify: every test referencing these symbols

- [ ] **Step 1: Tighten visibility on `applyAttributes`**

In `Sources/Swiflow/DSL/Modifiers.swift`, change `public func applyAttributes(...)` to `internal func applyAttributes(...)`.

Note: every element factory in `Sources/Swiflow/DSL/Elements.swift` calls `applyAttributes` and they live in the same module, so internal is sufficient. If any module-external call site exists (unlikely but verify with `grep -rn applyAttributes Sources/ Tests/`), keep it internal anyway — that caller is doing something they shouldn't.

- [ ] **Step 2: Tighten visibility on `AnyComponent` fields**

In `Sources/Swiflow/Reactivity/Component.swift:64-68`:
- `public let typeID: ObjectIdentifier` → `internal let typeID: ObjectIdentifier`
- `public let instance: any Component` → `internal let instance: any Component`
- `public init<C: Component>(_ instance: C)` → keep `public` (the type itself is publicly constructable by the framework for typeID-tracking purposes)

Verify no test or third-party access reads `.typeID` or `.instance` directly. If so, those tests should use a different surface — but most tests will be `@testable import Swiflow` and access internal symbols, which still works.

- [ ] **Step 3: Tighten visibility on `ComponentDescription` fields**

In `Sources/Swiflow/Reactivity/Component.swift:92-101`:
- `public let typeID:` → `internal let typeID:`
- `public let key:` → keep `public` (callers genuinely need to read the key for inspection)
- `public let factory:` → `internal let factory:`
- The `public init(typeID:key:factory:)` raw init becomes `internal init(...)` (no out-of-module construction)
- The `public init<C: Component>(_ type:key:factory:)` convenience stays `public` (used by `embed`)

- [ ] **Step 4: Rename `a` → `link` and `main_` → `mainElement`**

In `Sources/Swiflow/DSL/Elements.swift`:
- Replace both `public func a(` definitions (lines 97 and 105) with `public func link(`
- Update doc comments: "HTML `<a>` anchor" → "HTML `<a>` anchor (named `link` to avoid the one-letter free function `a`)"
- Replace `public func main_(` at line 223 with `public func mainElement(`
- Update the doc comment about `main_` being a keyword-avoidance trick (no longer applies — `mainElement` is the clean name)

- [ ] **Step 5: Rename `InProcessScheduler` → `SyncScheduler`**

In `Sources/Swiflow/Reactivity/Scheduler.swift`:
- Replace every occurrence of `InProcessScheduler` with `SyncScheduler` (the class declaration on line 43, the doc reference on line 9).
- Update doc to say "Synchronous flush; used by tests and any headless render path."

- [ ] **Step 6: Rename `buildBlock` and `buildArray` parameter name**

In `Sources/Swiflow/DSL/ResultBuilder.swift:12,43`:
- `buildBlock(_ components: [VNode]...)` → `buildBlock(_ children: [VNode]...)`
- `buildArray(_ components: [[VNode]])` → `buildArray(_ children: [[VNode]])`

Update the inline references to `components` inside each function body to `children`.

- [ ] **Step 7: Sweep tests**

Run: `grep -rn "InProcessScheduler\|main_\|\\.a(\|component(" Sources/ Tests/`
Expected: hits in tests + possibly the dev-mode injection. Replace each:
- `InProcessScheduler` → `SyncScheduler`
- `main_(` → `mainElement(`
- `a("` → `link("` (be careful — this match is broad; verify each hit is an actual `a()` factory call, not a variable named `a`)
- `component({` → handled in Task 5 already; should be no remaining matches

- [ ] **Step 8: Build + test**

Run: `swift build && swift test`
Expected: success. Every renamed symbol is mechanical.

- [ ] **Step 9: Commit**

```bash
git add Sources/ Tests/
git commit -m "$(cat <<'EOF'
refactor: surface audit + smaller renames

- applyAttributes, AnyComponent.{typeID,instance}, ComponentDescription's
  {typeID,factory,raw init} → internal
- Element factory `a` → `link`; `main_` → `mainElement`
- InProcessScheduler → SyncScheduler
- ChildrenBuilder.buildBlock/buildArray param name: components → children

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Counter template + README + final test sweep

**Files:**
- Modify: `Sources/SwiflowCLI/Templates/Templates.swift:90-138` — rewrite the `rawAppSwift` template body
- Modify: `README.md` — Counter snippet, "What's in the box" lifecycle names
- Verify: `Tests/playwright/counter.spec.ts` — same DOM output, no spec change expected; verify on dev-server run

- [ ] **Step 1: Rewrite the Counter template**

In `Sources/SwiflowCLI/Templates/Templates.swift`, replace the entire `rawAppSwift` string (lines 92-138) with:

```swift
    private static let rawAppSwift: String = #"""
        // Sources/App/App.swift
        import Swiflow
        import SwiflowWeb

        /// Hello-Swiflow Counter — a Component with @State.
        ///
        /// Mutating @State count schedules a re-render automatically via the
        /// RAFScheduler. No explicit Swiflow.rerender() call needed.
        final class Counter: Component {
            @State var count: Int = 0

            var body: VNode {
                div {
                    h1("Hello, Swiflow!")
                    p("Count: \(count)")
                    button("Increment").on(.click) { self.count += 1 }
                }.class("container")
            }
        }

        @main
        struct App {
            @MainActor
            static func main() {
                Swiflow.render(into: "#app") { Counter() }
            }
        }

        """#
```

Notes:
- No `@unchecked Sendable` (Component is @MainActor — Task 2).
- No `[weak self]` (HandlerRegistry per-Component scope guarantees lifetime — Task 4).
- No `MainActor.assumeIsolated` (framework absorbs it — Task 4).
- No `Swiflow.handlers.register` (the `.on(.click) { ... }` modifier does it).
- The `.class("container")` is in postfix position to show off the new chaining; switching to variadic `div(.class("container")) { ... }` is equally valid and the test should treat both as equivalent.

- [ ] **Step 2: Update README**

In `README.md`, locate the "What's in the box" `Component + @State` bullet and the Counter snippet (if one exists in the README). Update:

- Lifecycle hook list: `onMount`, `onUpdate(prev:)`, `onUnmount` → `onAppear`, `onChange`, `onDisappear`
- Any Counter snippet — replace with the new shape from Step 1
- Any reference to `Swiflow.handlers` — delete

Run: `grep -n "onMount\|onUpdate\|onUnmount\|Swiflow.handlers\|component({" README.md`
Expected: hits in the lifecycle blurb. Fix each.

- [ ] **Step 3: Verify Playwright test still passes**

Run: `swift run swiflow build --path Tests/playwright/<test-project-dir>` (or wherever the Playwright fixture lives — verify with `cat Tests/playwright/playwright.config.ts`).

Then run: `cd Tests/playwright && npx playwright test counter.spec.ts`
Expected: pass. The Counter renders the same DOM as before — same `<h1>`, same `<p>Count: 0</p>`, same `<button>Increment</button>`. Click handler still increments and re-renders.

If the Playwright test fails, the most likely cause is a runtime error in the new handler-scope wiring (Task 4) — review the per-Component scope open/close call sites.

- [ ] **Step 4: Final test sweep**

Run: `swift test`
Expected: every test passes.

Run: `grep -rn "@unchecked Sendable\|MainActor.assumeIsolated\|Swiflow.handlers\|component({" Sources/ Tests/`
Expected: no hits. (If hits remain in non-template Sources, those are bugs.)

Run: `grep -rn "onMount\|onUpdate(prev:\|onUnmount" Sources/ Tests/`
Expected: no hits.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowCLI/Templates/Templates.swift README.md
git commit -m "$(cat <<'EOF'
feat(template): Counter rewrite uses new .on(.click) + render factory

Drops @unchecked Sendable, [weak self], MainActor.assumeIsolated, and
Swiflow.handlers.register from the Hello World template. The handler line
becomes `button("Increment").on(.click) { self.count += 1 }`.

Also updates README's "What's in the box" lifecycle hook list to the new
onAppear / onChange / onDisappear names.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Verification (final acceptance gate)

After all 10 tasks land:

```bash
swift build && swift test
cd Tests/playwright && npx playwright test
```

Both green. The Counter template is one short readable class. `grep`s for the deleted symbols (`@unchecked Sendable`, `MainActor.assumeIsolated`, `Swiflow.handlers`, `component({`, `onMount`, `onUpdate(prev:`, `onUnmount`, `InProcessScheduler`, `main_(`) return zero matches in `Sources/` and `Tests/`.
