# Handler Seam & Harness Fidelity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clear the 5 highest-leverage High findings from `docs/reviews/2026-06-10-quality-audit.md` by lifting the handler-registry ambient into Swiflow core and making SwiflowTesting render through the production code path.

**Architecture:** Core gains a fourth ambient slot (`HandlerAmbient`, mirroring `RenderObserverBox`/`SwiflowTaskRuntime.currentScope`/`AmbientEnvironment`). The event/binding modifiers move from SwiflowDOM into core and register against that slot, which lets us delete SwiflowTesting's divergent duplicate API. TestRenderer is then rewritten to wrap its root in a `.component` anchor and diff from the root — exactly what `SwiflowDOM.Renderer.renderOnce()` does — which makes lifecycle hooks, state wiring, observer bracketing, and nested re-renders come from the *same* code the browser uses instead of a re-implementation. Finally the harness's synthetic events gain the fields the JS driver always sends.

**Tech Stack:** Swift 6 / SwiftPM, Swift Testing (`@Suite`, `@Test`, `#expect`). All host-side; no WASM build required to land this.

**Audit findings cleared:** Unit 2 HIGH "event-modifier API implemented twice", Unit 2 HIGH "TestRenderer skips production lifecycle", Unit 9 HIGH "targetChecked omitted", Unit 9 HIGH "blur() drops target value", Unit 9 HIGH "nested re-render diverges". Also incidentally fixes Unit 9 MEDIUM "TestRenderer discards patches" *partially* (root diff still discards them — out of scope) and unblocks a later fix for Unit 2 LOW "Link bypasses the event seam" (Router can now use `.on` from core — not done in this plan).

---

## Environment notes (read first)

- **Always run tests as `env -u SWIFLOW_SOURCE swift test`.** This shell exports
  `SWIFLOW_SOURCE=…/swiflow`, which makes one `InitCommandTests` case fail for
  unrelated reasons. The full suite is currently green (765 tests) under `env -u`.
- Work on a branch: `git checkout -b feat/handler-seam-harness-fidelity` (branch off
  `audit/swiflow-quality-audit` or `main` — the audit branch only adds docs).
- `package`-access symbols (HandlerRegistry, ComponentDescription's
  `init(typeID:key:factory:)`, `diff`, `destroy`, `firePostRenderLifecycle`,
  `collectComponentIDs`) are visible across all targets in this package once you
  `import Swiflow` — no access-level changes needed.
- After touching anything under `js-driver/` or `examples/` you'd need to re-run embed
  scripts — **this plan touches neither**, so no codegen steps.

## File structure

| File | Action | Responsibility |
|---|---|---|
| `Sources/Swiflow/Reactivity/HandlerAmbient.swift` | create | The ambient handler-registry slot (4th ambient, same pattern as RenderObserverBox) |
| `Sources/Swiflow/DSL/EventModifiers.swift` | create (git mv from SwiflowDOM) | `.on` / `.value` / `.checked` / `.selection` / `.ref` modifiers, now renderer-agnostic |
| `Sources/SwiflowDOM/AttributeModifiers.swift` | delete (via git mv) | — |
| `Sources/SwiflowDOM/Renderer.swift` | modify | Install `HandlerAmbient.current` around renders; drop `_currentRenderingRenderer` |
| `Sources/SwiflowDOM/SwiflowDOM.swift` | modify | Delete the `_currentRenderingRenderer` declaration |
| `Sources/SwiflowTesting/TestingModifiers.swift` | delete | — (core modifiers now work headlessly) |
| `Sources/SwiflowTesting/TestRenderer.swift` | rewrite render paths | Root `.component` anchor; production diff path; lifecycle; payload fidelity; `unmount()`; `check()` |
| `Sources/SwiflowTesting/TestHarness.swift` | modify | `unmount()` + `check()` passthroughs |
| `Sources/SwiflowTesting/AsyncTestHarness.swift` | modify | Same two passthroughs |
| `Tests/SwiflowTests/DSL/EventModifierAmbientTests.swift` | create | Core modifiers register via the ambient |
| `Tests/SwiflowTestingTests/BindingHarnessTests.swift` | create | Two-way bindings round-trip headlessly |
| `Tests/SwiflowTestingTests/LifecycleHarnessTests.swift` | create | onAppear/onChange/onDisappear fire under test |
| `Tests/SwiflowTestingTests/RootRerenderTests.swift` | create | Parent re-reads shared state when child mutates |
| `Tests/SwiflowTestingTests/EventPayloadFidelityTests.swift` | create | check()/blur payloads mirror the driver |
| `CHANGELOG.md` | modify | `[Unreleased]` entries |

---

### Task 1: Core `HandlerAmbient` + move the modifiers into core

This task is atomic across three modules — core gains the modifiers, SwiflowDOM loses
its copy and installs the ambient, SwiflowTesting loses its duplicate (which would
otherwise create ambiguous-overload build errors). The package will not build between
steps 3 and 6; that's expected — run tests only at the checkpoints shown.

**Files:**
- Create: `Sources/Swiflow/Reactivity/HandlerAmbient.swift`
- Create: `Sources/Swiflow/DSL/EventModifiers.swift` (git mv + edits)
- Delete: `Sources/SwiflowDOM/AttributeModifiers.swift` (the mv), `Sources/SwiflowTesting/TestingModifiers.swift`
- Modify: `Sources/SwiflowDOM/Renderer.swift:138-144`, `Sources/SwiflowDOM/SwiflowDOM.swift:25`, `Sources/SwiflowTesting/TestRenderer.swift` (ambient name swap only — 3 occurrences)
- Test: `Tests/SwiflowTests/DSL/EventModifierAmbientTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTests/DSL/EventModifierAmbientTests.swift
import Testing
@testable import Swiflow

@Suite(.serialized)
@MainActor
struct EventModifierAmbientTests {

    @Test func postfixOnRegistersThroughAmbientRegistry() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }

        var fired = false
        let node = div { VNode.text("hi") }.on(.click) { fired = true }

        guard case .element(let data) = node,
              let handler = data.handlers["click"] else {
            Issue.record("expected a click handler on the element")
            return
        }
        registry.dispatch(id: handler.id, event: EventInfo(type: "click"))
        #expect(fired)
    }

    @Test func attributeOnRegistersThroughAmbientRegistry() {
        let registry = HandlerRegistry()
        HandlerAmbient.current = registry
        defer { HandlerAmbient.current = nil }

        var received: EventInfo? = nil
        let attr = Attribute.on(.input) { info in received = info }

        guard case .handler(_, let handler) = attr else {
            Issue.record("expected .handler attribute")
            return
        }
        registry.dispatch(id: handler.id, event: EventInfo(type: "input", targetValue: "x"))
        #expect(received?.targetValue == "x")
    }
}
```

Note: if `Attribute`'s `.handler` case has different associated-value labels, match
the pattern to the case as declared in `Sources/Swiflow/DSL/Modifiers.swift`
(it is constructed as `.handler(event:value:)` — so the pattern is
`case .handler(_, let handler)` with the second value being the `EventHandler`).

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u SWIFLOW_SOURCE swift test --filter EventModifierAmbientTests`
Expected: **compile failure** — `HandlerAmbient` not found, and `VNode`/`Attribute` have no `.on` in module `Swiflow`.

- [ ] **Step 3: Create the ambient slot**

```swift
// Sources/Swiflow/Reactivity/HandlerAmbient.swift
//
// The active handler registry. Saved/restored by each render root around its
// render, exactly like `RenderObserverBox.current` and
// `SwiflowTaskRuntime.currentScope`. Core's event/binding modifiers
// (DSL/EventModifiers.swift) register handlers against this slot, so every
// renderer backend (SwiflowDOM's browser Renderer, SwiflowTesting's headless
// TestRenderer) gets the same modifier API — same registration path, same
// failure semantics — by installing its registry here.

package enum HandlerAmbient {
    @MainActor package static var current: HandlerRegistry?
}
```

- [ ] **Step 4: Move the modifiers file into core**

```bash
git mv Sources/SwiflowDOM/AttributeModifiers.swift Sources/Swiflow/DSL/EventModifiers.swift
```

Then edit `Sources/Swiflow/DSL/EventModifiers.swift`:

1. Replace the first three lines (path comment, `#if canImport(JavaScriptKit)`,
   `@_exported import Swiflow`) with the single header line:
   ```swift
   // Sources/Swiflow/DSL/EventModifiers.swift
   ```
2. Delete the trailing `#endif` (last line of the file).
3. Replace the whole `_registerAmbientHandler` function (the doc comment + body that
   reads `_currentRenderingRenderer`) with:

```swift
/// Registers `invoke` with the ambient handler registry installed by the
/// active render root (SwiflowDOM's browser Renderer or SwiflowTesting's
/// TestRenderer). Called internally by the `.on(_:perform:)` and binding
/// modifiers below. Traps if no render root is active — only possible when a
/// modifier is constructed outside a render cycle, which is a programmer error.
@MainActor
func _registerAmbientHandler(
    _ invoke: @escaping @MainActor (EventInfo) -> Void
) -> EventHandler {
    guard let registry = HandlerAmbient.current else {
        preconditionFailure(
            "Swiflow modifier .on(_:perform:) was used outside a render cycle. "
            + "Event handlers must be constructed inside a Component body while a render root "
            + "is actively building the tree — Swiflow.render(into:_:) in the browser, "
            + "SwiflowTesting.render(_:) in tests."
        )
    }
    return registry.register { event in
        MainActor.assumeIsolated { invoke(event) }
    }
}
```

Everything else in the file (all `.on`/`.value`/`.checked`/`.selection`/`.ref`
overloads) stays byte-identical — they only call `_registerAmbientHandler`, which is
exactly why the move works.

- [ ] **Step 5: Wire SwiflowDOM's Renderer to the ambient and delete the old global**

In `Sources/SwiflowDOM/Renderer.swift`, `renderOnce()` currently begins:

```swift
_currentRenderingRenderer = self
SwiflowTaskRuntime.currentScope = taskScope
RenderObserverBox.current = queryClient
defer {
    _currentRenderingRenderer = nil
    SwiflowTaskRuntime.currentScope = nil
    RenderObserverBox.current = nil
}
```

Replace both `_currentRenderingRenderer` lines:

```swift
HandlerAmbient.current = handlers
SwiflowTaskRuntime.currentScope = taskScope
RenderObserverBox.current = queryClient
defer {
    HandlerAmbient.current = nil
    SwiflowTaskRuntime.currentScope = nil
    RenderObserverBox.current = nil
}
```

In `Sources/SwiflowDOM/SwiflowDOM.swift`, delete line 25:

```swift
nonisolated(unsafe) var _currentRenderingRenderer: Renderer?
```

Verify nothing else references it: `grep -rn "_currentRenderingRenderer" Sources/` must return nothing.

- [ ] **Step 6: Swap SwiflowTesting to the core ambient and delete its duplicate API**

```bash
git rm Sources/SwiflowTesting/TestingModifiers.swift
```

In `Sources/SwiflowTesting/TestRenderer.swift`, replace all three occurrences of
`_testAmbientHandlers = self.handlers` with `HandlerAmbient.current = self.handlers`
(one in `init`, one in `rerender`) and the two `_testAmbientHandlers = nil` defer
lines with `HandlerAmbient.current = nil`. (The `var _testAmbientHandlers` declaration
died with TestingModifiers.swift.)

- [ ] **Step 7: Run the new test, then the full suite**

Run: `env -u SWIFLOW_SOURCE swift test --filter EventModifierAmbientTests`
Expected: PASS (2 tests).

Run: `env -u SWIFLOW_SOURCE swift test`
Expected: all green. **Triage note:** any test that previously constructed `.on`
*outside* a render (and silently got TestingModifiers' `.skip`) will now trap with
the precondition. That trap is the production semantic — fix such tests by moving
modifier construction inside a rendered component body, or by setting
`HandlerAmbient.current` to a fresh `HandlerRegistry` for the test's duration
(mirroring EventModifierAmbientTests above). Do not re-add silent-skip behavior.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(core): lift handler registry into a core ambient seam

Moves the event/binding modifiers from SwiflowDOM into Swiflow core,
registering against HandlerAmbient.current (4th ambient, same pattern
as RenderObserverBox). Deletes SwiflowTesting's divergent duplicate
.on API. Clears audit finding: 'event-modifier API implemented twice
with divergent semantics'."
```

---

### Task 2: Prove two-way bindings work headlessly

`.value`/`.checked`/`.selection` now exist under test for the first time. Lock that in.

**Files:**
- Test: `Tests/SwiflowTestingTests/BindingHarnessTests.swift` (create)

- [ ] **Step 1: Write the test**

```swift
// Tests/SwiflowTestingTests/BindingHarnessTests.swift
import Testing
import Swiflow
import SwiflowTesting

@Component
final class EchoInput {
    @State var text = ""
    var body: VNode {
        div {
            input(.value($text))
            p { VNode.text("echo: \(text)") }
        }
    }
}

@Suite
@MainActor
struct BindingHarnessTests {

    @Test func valueBindingRoundTripsThroughHarness() {
        let harness = render(EchoInput())
        #expect(harness.allText.contains("echo: "))

        harness.input(value: "hello")

        #expect(harness.allText.contains("echo: hello"))
    }
}
```

- [ ] **Step 2: Run it**

Run: `env -u SWIFLOW_SOURCE swift test --filter BindingHarnessTests`
Expected: PASS. (If it fails to compile because `input(...)` collides with the harness
method name in scope, qualify the DSL call as `Swiflow.input(.value($text))`.)

This test was *impossible* before Task 1 — `.value` did not exist headlessly.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiflowTestingTests/BindingHarnessTests.swift
git commit -m "test(testing): two-way value binding round-trips through the harness"
```

---

### Task 3: TestRenderer renders through the production component-anchor path

This rewires TestRenderer to do what `SwiflowDOM.Renderer.renderOnce()` does: wrap the
root instance in a `.component` description and diff from the root. The diff's
component-mount path then performs state wiring, handler scoping, environment +
observer bracketing, and body evaluation — the same code production runs. That fixes
both lifecycle (via `firePostRenderLifecycle`) and the nested-re-render divergence
(root-always re-render) in one move, and deletes the manual re-implementations.

**Files:**
- Modify: `Sources/SwiflowTesting/TestRenderer.swift` (init, rerender; delete `findComponentNode` if unused after this; add `unmount()`)
- Modify: `Sources/SwiflowTesting/TestHarness.swift` (add `unmount()`)
- Modify: `Sources/SwiflowTesting/AsyncTestHarness.swift` (add passthrough)
- Test: `Tests/SwiflowTestingTests/LifecycleHarnessTests.swift`, `Tests/SwiflowTestingTests/RootRerenderTests.swift` (create)

- [ ] **Step 1: Write the failing lifecycle test**

```swift
// Tests/SwiflowTestingTests/LifecycleHarnessTests.swift
import Testing
import Swiflow
import SwiflowTesting

@Component
final class LifecycleProbe {
    @State var n = 0
    var log: [String] = []
    var body: VNode {
        div {
            p { VNode.text("count \(n)") }
            button(.on(.click) { self.n += 1 }) { VNode.text("inc") }
        }
    }
    func onAppear() { log.append("appear") }
    func onChange() { log.append("change") }
    func onDisappear() { log.append("disappear") }
}

@Suite
@MainActor
struct LifecycleHarnessTests {

    @Test func lifecycleHooksFireUnderTest() {
        let probe = LifecycleProbe()
        let harness = render(probe)

        #expect(probe.log == ["appear"], "onAppear must fire on mount, as in the browser")

        harness.click("button")
        #expect(probe.log == ["appear", "change"], "onChange must fire on re-render")

        harness.unmount()
        #expect(probe.log == ["appear", "change", "disappear"], "onDisappear must fire on unmount")
    }
}
```

(If the `button(.on(.click) { … })` trailing-closure spelling doesn't match the DSL,
use the explicit form `button(.on(.click, perform: { self.n += 1 }))`.)

- [ ] **Step 2: Run it to verify it fails**

Run: `env -u SWIFLOW_SOURCE swift test --filter LifecycleHarnessTests`
Expected: compile failure on `harness.unmount()` (no such member) — and once stubbed,
assertion failure: `probe.log == []` because lifecycle never fires today.

- [ ] **Step 3: Rewrite TestRenderer's render paths**

In `Sources/SwiflowTesting/TestRenderer.swift`:

3a. Replace the stored properties `rootInstance`/`rootID` with a stored root
description, keeping `rootComponent`:

```swift
let rootComponent: AnyComponent
/// Root description with a same-instance factory — mirrors
/// SwiflowDOM.Renderer.renderOnce(): the factory is consumed exactly once at
/// first mount; every later diff at the same position reuses the instance.
private let rootDescription: ComponentDescription
```

3b. Replace `init` with:

```swift
init<C: Component>(_ instance: C, queryClient: QueryClient = QueryClient()) {
    let relay = RerenderRelay()
    self.handles = HandleAllocator()
    self.handlers = HandlerRegistry()
    self.queryClient = queryClient
    let anyComponent = AnyComponent(instance)
    self.rootComponent = anyComponent
    self.rootDescription = ComponentDescription(
        typeID: anyComponent.typeID,
        key: nil,
        factory: { anyComponent }
    )
    self.scheduler = SyncScheduler { [relay] component in
        MainActor.assumeIsolated { relay.owner?.rerender(component) }
    }

    HandlerAmbient.current = self.handlers
    SwiflowTaskRuntime.currentScope = taskScope
    RenderObserverBox.current = queryClient
    defer {
        HandlerAmbient.current = nil
        SwiflowTaskRuntime.currentScope = nil
        RenderObserverBox.current = nil
    }
    // The diff's component-mount path does the rest — wireStateAndRestore,
    // handler scope, environment + observer bracketing, body evaluation —
    // the same code the browser renderer runs.
    let result = diff(
        mounted: nil,
        next: .component(rootDescription),
        handles: self.handles,
        handlers: self.handlers,
        scheduler: self.scheduler
    )
    self.mountTree = result.newMountTree
    firePostRenderLifecycle(result.newMountTree, preExistingIDs: [])
    relay.owner = self
}
```

This deletes: the manual `wireState(on:scheduler:)` call, the manual
`queryClient.willEvaluate/didEvaluate` bracketing, and the direct `instance.body`
evaluation — all now provided by the diff, as in production.

3c. Replace `rerender(_:)` with:

```swift
/// Always re-renders from the root — exactly like the browser Renderer,
/// where the RAF flush calls renderOnce() regardless of which component
/// marked itself dirty. The diff decides which bodies to re-evaluate.
func rerender(_ component: AnyComponent) {
    _ = component
    HandlerAmbient.current = self.handlers
    SwiflowTaskRuntime.currentScope = taskScope
    RenderObserverBox.current = queryClient
    defer {
        HandlerAmbient.current = nil
        SwiflowTaskRuntime.currentScope = nil
        RenderObserverBox.current = nil
    }
    let preExistingIDs = collectComponentIDs(mountTree)
    let result = diff(
        mounted: mountTree,
        next: .component(rootDescription),
        handles: handles,
        handlers: handlers,
        scheduler: scheduler
    )
    mountTree = result.newMountTree
    firePostRenderLifecycle(result.newMountTree, preExistingIDs: preExistingIDs)
}
```

3d. Add `unmount()` after `rerender`:

```swift
/// Tears down the mounted tree: fires `onDisappear` (parent-first), closes
/// handler scopes, and notifies the query client of component unmounts —
/// mirroring SwiflowDOM.Renderer.teardown() minus the JS patches.
func unmount() {
    RenderObserverBox.current = queryClient
    defer { RenderObserverBox.current = nil }
    var patches: [Patch] = []
    destroy(mountTree, into: &patches, handlers: handlers)
}
```

3e. Delete `findComponentNode(_:in:)` if its only caller was the old nested-rerender
branch (`grep -n findComponentNode Sources/ Tests/` — if any test calls it, keep it).

- [ ] **Step 4: Add the harness passthroughs**

`Sources/SwiflowTesting/TestHarness.swift` — after `change(...)`:

```swift
/// Unmounts the rendered tree, firing `onDisappear` parent-first — mirrors
/// `Swiflow.unmount(into:)` in the browser. Queries after unmount read the
/// last-rendered tree and are unspecified.
public func unmount() { renderer.unmount() }
```

`Sources/SwiflowTesting/AsyncTestHarness.swift` — in the passthrough block:

```swift
public func unmount() { harness.unmount() }
```

- [ ] **Step 5: Run the lifecycle test, the root-rerender test (next step), then the full suite**

Run: `env -u SWIFLOW_SOURCE swift test --filter LifecycleHarnessTests`
Expected: PASS.

- [ ] **Step 6: Write the root-rerender test**

```swift
// Tests/SwiflowTestingTests/RootRerenderTests.swift
import Testing
import Swiflow
import SwiflowTesting

final class SharedLabel {
    var value = "before"
}

@Component
final class LabelMutatingChild {
    let model: SharedLabel
    @State var tick = 0
    init(model: SharedLabel) { self.model = model }
    var body: VNode {
        button(.on(.click) {
            self.model.value = "after"
            self.tick += 1
        }) { VNode.text("mutate") }
    }
}

@Component
final class SharedLabelParent {
    let model = SharedLabel()
    var body: VNode {
        div {
            p { VNode.text("label: \(model.value)") }
            embed { LabelMutatingChild(model: self.model) }
        }
    }
}

@Suite
@MainActor
struct RootRerenderTests {

    /// Audit finding (Unit 9 HIGH): a nested component's @State change used to
    /// diff only that subtree; production re-renders from root. The parent's
    /// body reads shared state the child mutates — it must refresh under test
    /// exactly as it does in the browser.
    @Test func parentRefreshesWhenChildMutatesSharedState() {
        let harness = render(SharedLabelParent())
        #expect(harness.allText.contains("label: before"))

        harness.click("button")

        #expect(harness.allText.contains("label: after"))
    }
}
```

Note: `embed { LabelMutatingChild(model: self.model) }` allocates a fresh child per
factory call, satisfying the factory contract — the *model* is shared, not the
component instance.

- [ ] **Step 7: Run everything**

Run: `env -u SWIFLOW_SOURCE swift test --filter RootRerenderTests`
Expected: PASS (would have failed before step 3c).

Run: `env -u SWIFLOW_SOURCE swift test`
Expected: all green. **Triage note:** existing tests now (a) fire `onAppear`/`onChange`
they previously never saw, and (b) re-render from root on any state change. Failures
here are tests encoding the old, unfaithful behavior — update the test, not the
renderer. Two patterns to expect: tests counting body evaluations (root body now
re-evaluates on child changes — that's production behavior), and tests whose
components do real work in `onAppear`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(testing): TestRenderer renders through the production component path

Root is now a .component anchor diffed from the top — the diff performs
state wiring, scoping, observer bracketing, and body evaluation exactly
as the browser renderer does. Adds firePostRenderLifecycle +
collectComponentIDs (onAppear/onChange) and unmount() (onDisappear).
Clears audit findings: 'TestRenderer skips production lifecycle' and
'nested re-render diverges from production'."
```

---

### Task 4: Driver-shaped event payloads + `check()`

The JS driver's `serializeEvent` (js-driver/swiflow-driver.js:70-80) snapshots
`target.value` and `target.checked` on **every** dispatch. Mirror that: synthesize the
snapshot from the matched node's current `properties` bag, and add the missing
checkbox-toggle API.

**Files:**
- Modify: `Sources/SwiflowTesting/TestRenderer.swift` (snapshot helper; click/input/blur/change; new `check`)
- Modify: `Sources/SwiflowTesting/TestHarness.swift`, `Sources/SwiflowTesting/AsyncTestHarness.swift` (`check` passthrough)
- Test: `Tests/SwiflowTestingTests/EventPayloadFidelityTests.swift` (create)

- [ ] **Step 1: Write the failing test**

```swift
// Tests/SwiflowTestingTests/EventPayloadFidelityTests.swift
import Testing
import Swiflow
import SwiflowTesting

@Component
final class CheckboxForm {
    @State var agreed = false
    var body: VNode {
        div {
            input(.attr("type", "checkbox"), .checked($agreed))
            p { VNode.text(agreed ? "agreed" : "not agreed") }
        }
    }
}

@Component
final class BlurValidator {
    @State var name = "ada"
    @State var lastBlurValue = "<none>"
    var body: VNode {
        div {
            input(.value($name), .on(.blur) { info in
                self.lastBlurValue = info.targetValue ?? "<nil>"
            })
            p { VNode.text("blur saw: \(lastBlurValue)") }
        }
    }
}

@Suite
@MainActor
struct EventPayloadFidelityTests {

    /// Audit finding (Unit 9 HIGH): EventInfo never carried targetChecked, so
    /// `.checked` bindings were untestable. The driver sends it on every
    /// dispatch with a checkable target.
    @Test func checkTogglesACheckedBinding() {
        let harness = render(CheckboxForm())
        #expect(harness.allText.contains("not agreed"))

        harness.check(checked: true)

        #expect(harness.allText.contains("agreed"))
    }

    /// Audit finding (Unit 9 HIGH): blur() dispatched with no targetValue,
    /// while the browser always snapshots target.value — validate-on-blur
    /// handlers worked in production and saw nil under test.
    @Test func blurCarriesTheCurrentTargetValue() {
        let harness = render(BlurValidator())

        harness.blur()

        #expect(harness.allText.contains("blur saw: ada"))
    }
}
```

(If `.on(.blur)` is not an `Event` case, check `Sources/Swiflow/DSL/Event.swift` for
the blur member's exact name; the harness's `blur()` dispatches the `"blur"` DOM
event, so the modifier must subscribe to the same name.)

- [ ] **Step 2: Run to verify failure**

Run: `env -u SWIFLOW_SOURCE swift test --filter EventPayloadFidelityTests`
Expected: compile failure (`check(checked:)` doesn't exist); after stubbing, the blur
test fails with `blur saw: <nil>`.

- [ ] **Step 3: Implement the snapshot + payload changes in TestRenderer**

Add the helper (near the interaction methods):

```swift
/// Mirrors the JS driver's serializeEvent(): snapshot the target's current
/// `value`/`checked` from the mount tree the way the browser snapshots them
/// from the live DOM (js-driver/swiflow-driver.js:70-80). Returns nils for
/// elements without those properties — same as the driver's `"value" in
/// target` / `"checked" in target` guards.
private func targetSnapshot(of node: MountNode) -> (value: String?, checked: Bool?) {
    guard case .element(let data) = node.vnode else { return (nil, nil) }
    var value: String? = nil
    var checked: Bool? = nil
    if let v = data.properties["value"] {
        switch v {
        case .string(let s): value = s
        case .int(let i): value = String(i)
        case .double(let d): value = String(d)
        case .bool(let b): value = String(b)
        }
    }
    if case .bool(let b)? = data.properties["checked"] { checked = b }
    return (value, checked)
}
```

Update the four dispatch sites to include the snapshot, and add `check`:

```swift
func click(tag: String, text: String?) {
    let matches = findElements(tag: tag, text: text, in: mountTree)
    guard let (node, _) = matches.first,
          let id = node.handlerIds["click"] else { return }
    let snap = targetSnapshot(of: node)
    handlers.dispatch(id: id, event: EventInfo(
        type: "click", targetValue: snap.value, targetChecked: snap.checked))
    scheduler.flush()
}

func input(tag: String, at index: Int, value: String) {
    let matches = findElements(tag: tag, text: nil, in: mountTree)
    guard index < matches.count else { return }
    let (node, _) = matches[index]
    guard let id = node.handlerIds["input"] else { return }
    let snap = targetSnapshot(of: node)
    handlers.dispatch(id: id, event: EventInfo(
        type: "input", targetValue: value, targetChecked: snap.checked))
    scheduler.flush()
}

func blur(tag: String, at index: Int) {
    let matches = findElements(tag: tag, text: nil, in: mountTree)
    guard index < matches.count else { return }
    let (node, _) = matches[index]
    guard let id = node.handlerIds["blur"] else { return }
    let snap = targetSnapshot(of: node)
    handlers.dispatch(id: id, event: EventInfo(
        type: "blur", targetValue: snap.value, targetChecked: snap.checked))
    scheduler.flush()
}

func change(tag: String, at index: Int, value: String) {
    let matches = findElements(tag: tag, text: nil, in: mountTree)
    guard index < matches.count else { return }
    let (node, _) = matches[index]
    guard let id = node.handlerIds["change"] else { return }
    let snap = targetSnapshot(of: node)
    handlers.dispatch(id: id, event: EventInfo(
        type: "change", targetValue: value, targetChecked: snap.checked))
    scheduler.flush()
}

/// Simulates toggling a checkbox/radio: dispatches `change` with
/// `targetChecked` — the payload shape `.checked(_:)` bindings read.
func check(tag: String, at index: Int, checked: Bool) {
    let matches = findElements(tag: tag, text: nil, in: mountTree)
    guard index < matches.count else { return }
    let (node, _) = matches[index]
    guard let id = node.handlerIds["change"] else { return }
    let snap = targetSnapshot(of: node)
    handlers.dispatch(id: id, event: EventInfo(
        type: "change", targetValue: snap.value, targetChecked: checked))
    scheduler.flush()
}
```

- [ ] **Step 4: Add the harness passthroughs**

`TestHarness.swift` (next to `change`):

```swift
/// Simulates toggling a checkbox/radio input. Dispatches a `change` event
/// whose `targetChecked` is `checked`, mirroring the browser driver's payload.
public func check(_ tag: String = "input", at index: Int = 0, checked: Bool) {
    renderer.check(tag: tag, at: index, checked: checked)
}
```

`AsyncTestHarness.swift` (passthrough block):

```swift
public func check(_ tag: String = "input", at index: Int = 0, checked: Bool) { harness.check(tag, at: index, checked: checked) }
```

- [ ] **Step 5: Run the tests, then the full suite**

Run: `env -u SWIFLOW_SOURCE swift test --filter EventPayloadFidelityTests`
Expected: PASS (2 tests).

Run: `env -u SWIFLOW_SOURCE swift test`
Expected: all green (payload additions are strictly additive — existing handlers
ignore fields they don't read).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(testing): driver-shaped event payloads + check() API

click/input/blur/change now snapshot the target's value/checked from the
mount tree, mirroring js-driver serializeEvent(); adds check() so
.checked bindings are exercisable. Clears audit findings: 'targetChecked
omitted everywhere' and 'blur() drops the target value'."
```

---

### Task 5: CHANGELOG + audit report bookkeeping

**Files:**
- Modify: `CHANGELOG.md` (top `## [Unreleased]` section — create it if a release consumed the previous one)
- Modify: `docs/reviews/2026-06-10-quality-audit.md` (mark the five findings fixed)

- [ ] **Step 1: Add CHANGELOG entries**

Under `## [Unreleased]` → `### Changed` (create the section as needed, matching the
existing entry style):

```markdown
### Changed

- **Event/binding modifiers moved into the `Swiflow` core module.**
  `.on`, `.value`, `.checked`, `.selection`, and `.ref` now register through a
  core ambient handler seam instead of living in `SwiflowDOM` — no user-facing
  API change (SwiflowDOM re-exports Swiflow), but the modifiers now work
  headlessly under `SwiflowTesting`.
- **`SwiflowTesting` is now faithful to the browser renderer.** Components
  under test render through the production diff path: `onAppear`/`onChange`/
  `onDisappear` fire, state changes re-render from the root, and synthetic
  events carry `targetValue`/`targetChecked` the way the JS driver sends them.

### Added

- `TestHarness.check(_:at:checked:)` — simulate checkbox/radio toggles.
- `TestHarness.unmount()` — tear down the tree, firing `onDisappear`.
```

- [ ] **Step 2: Annotate the audit report**

In `docs/reviews/2026-06-10-quality-audit.md`, append ` **[FIXED — see
docs/superpowers/plans/2026-06-10-handler-seam-harness-fidelity.md]**` to the five
cleared HIGH headings (Unit 2 ×2, Unit 9 ×3) and update the tally table High counts
accordingly (Cross-module 2→0, SwiflowTesting 3→0, Total 19→14).

- [ ] **Step 3: Final full-suite run and commit**

Run: `env -u SWIFLOW_SOURCE swift test`
Expected: all green.

```bash
git add CHANGELOG.md docs/reviews/2026-06-10-quality-audit.md
git commit -m "docs: changelog + audit bookkeeping for handler seam / harness fidelity"
```

---

## Verification (end-to-end)

1. `env -u SWIFLOW_SOURCE swift test` — full host suite green.
2. `grep -rn "_testAmbientHandlers\|_currentRenderingRenderer" Sources/ Tests/` — zero hits.
3. `grep -rn "func on(" Sources/ | grep -v Swiflow/DSL` — the only `.on` definitions live in `Sources/Swiflow/DSL/EventModifiers.swift`.
4. Optional (requires the wasm toolchain): `cd examples/TodoCRUD && swiflow build` — proves the moved modifiers compile for the wasm target through SwiflowDOM's re-export.

## Out of scope (deliberately)

- Routing `Link` through the new seam (Unit 2 LOW) — now unblocked, separate change.
- TestRenderer consuming `result.patches` (Unit 9 MEDIUM follow-up).
- Loud interaction misses / unified selector model (Unit 9 MEDIUMs).
- The SW update Critical and the dev-loop batch — separate plans.
