# Swiflow Phase 7 — Bindings, Refs & Form Foundations (Design)

**Date:** 2026-05-20
**Status:** Approved, ready for implementation.
**Parent roadmap:** [`docs/superpowers/plans/2026-05-20-swiflow-dx-uplift-master-plan.md`](../plans/2026-05-20-swiflow-dx-uplift-master-plan.md)
**Motto:** *Save → pixels feel instant.* (Phase 7 finishes the form-input surface so Phase 8's HMR demo can include controlled inputs.)

---

## Goal

Finish what Phase 3 declared. Ship the consumers for `Binding<Value>`, add a first-party `Ref<Element>` story, and prove the combination works by exercising both in the HelloWorld example.

A React/Vue/Svelte engineer evaluating Swiflow on day one tries to type in a text box, focus it on mount, and read its current value in an event handler. After Phase 7, all three work without dropping to JavaScriptKit.

## Scope (seven surfaces)

### 1. New element factories: `textarea`, `select`, `option`

**Current state** (verified): `Sources/Swiflow/DSL/Elements.swift` ships `input(...)` (void element, line 113) but no `textarea`, `select`, or `option`. Without these, only `input` can bind text values — useless for multi-line inputs and selectors.

**New behavior:**

```swift
/// HTML `<textarea>` — text content goes between the open and close tags.
public func textarea(_ text: String = "", _ attributes: Attribute...) -> VNode
public func textarea(_ attributes: Attribute..., @ChildrenBuilder children: () -> [VNode]) -> VNode

/// HTML `<select>` — children are `option(...)` (or `optgroup` if anyone needs it).
public func select(_ attributes: Attribute..., @ChildrenBuilder children: () -> [VNode]) -> VNode

/// HTML `<option>` — text label + optional value attribute on the parent select.
public func option(_ label: String, _ attributes: Attribute...) -> VNode
```

Symmetry with the existing `input(...)`, `div(...)`, `button(...)` shapes. The string-shortcut for `textarea` mirrors how `p("hello")` works elsewhere.

**Tests:** node-structure tests (does `textarea("Hi")` produce the expected ElementData?). Two-way binding is tested in §3 and §4 below.

---

### 2. Extend `EventInfo` with typed accessors + JS driver mirror

**Current state** (verified): `Sources/Swiflow/VNode.swift:116-127`:

```swift
public struct EventInfo: Equatable, Sendable {
    public let type: String
    public let targetValue: String?
    public init(type: String, targetValue: String? = nil) { ... }
}
```

The JS driver (`js-driver/swiflow-driver.js:55-60`) builds:

```js
function serializeEvent(event) {
    const target = event.target;
    const targetValue =
      target && "value" in target ? String(target.value) : null;
    return { type: event.type, targetValue: targetValue };
}
```

This is missing `event.target.checked` (needed for checkbox bindings) and exposes nothing typed for Int/Double inputs.

**New behavior:**

Extend `EventInfo` with one new stored property (`targetChecked: Bool?`) and three computed accessors:

```swift
public struct EventInfo: Equatable, Sendable {
    public let type: String
    public let targetValue: String?
    /// Snapshot of `event.target.checked` for checkbox/radio inputs;
    /// `nil` for events without a `checked` property on the target.
    public let targetChecked: Bool?

    public init(type: String, targetValue: String? = nil, targetChecked: Bool? = nil) { ... }

    /// `targetValue` parsed as an `Int`; `nil` if absent or unparseable.
    public var targetIntValue: Int? { targetValue.flatMap(Int.init) }

    /// `targetValue` parsed as a `Double`; `nil` if absent or unparseable.
    public var targetDoubleValue: Double? { targetValue.flatMap(Double.init) }
}
```

**JS driver:** extend `serializeEvent` to also emit `targetChecked`:

```js
function serializeEvent(event) {
    const target = event.target;
    const targetValue =
      target && "value" in target ? String(target.value) : null;
    const targetChecked =
      target && "checked" in target ? Boolean(target.checked) : null;
    return { type: event.type, targetValue: targetValue, targetChecked: targetChecked };
}
```

**Mirror constraint:** per `project-js-driver-embedded-sync` memory, `Sources/SwiflowCLI/EmbeddedDriver.swift` is byte-for-byte mirror of `js-driver/swiflow-driver.js`. Phase 7 must update both, and `DriverEmbedderTests` will catch any drift.

**Bridge update:** `Sources/SwiflowWeb/DispatcherBridge.swift:38-41` currently unpacks only `targetValue`. Add `targetChecked` unpacking and pass to `EventInfo.init`.

**Tests:** unit tests on `EventInfo`'s computed accessors (no JS needed). JS driver tests (Node + jsdom path, see `Tests/JSDriverTests/`) cover the `targetChecked` serialization.

---

### 3. `Binding<Value>` consumers — `.value(_:)` for input + textarea

**Current state** (verified): `Sources/Swiflow/Reactivity/State.swift:108-116` declares `Binding<Value>` with `.get` and `.set` closures. Phase 6 hid it from autocomplete via `@_documentation(visibility: internal)` because no consumer exists.

**New behavior:** add `.value(_:Binding<...>)` overloads in `Sources/SwiflowWeb/AttributeModifiers.swift` (the same module where `.on(_:perform:)` already routes through `_registerAmbientHandler`).

```swift
public extension Attribute {
    /// Two-way binding for a text input/textarea. Sets the element's
    /// `value` property to `binding.get()` on every render and registers
    /// an `.input` event handler that calls `binding.set(eventInfo.targetValue ?? "")`.
    @MainActor
    static func value(_ binding: Binding<String>) -> Attribute
    @MainActor
    static func value(_ binding: Binding<Int>) -> Attribute    // parse with Int.init; leave unchanged on failure
    @MainActor
    static func value(_ binding: Binding<Double>) -> Attribute // parse with Double.init
}

public extension VNode {
    @MainActor func value(_ binding: Binding<String>) -> VNode
    @MainActor func value(_ binding: Binding<Int>) -> VNode
    @MainActor func value(_ binding: Binding<Double>) -> VNode
}
```

**Implementation shape:**

- For the **String** binding: register an `.input` handler via `_registerAmbientHandler { event in binding.set(event.targetValue ?? "") }`. Also write the current `binding.get()` into the element's `value` property (using the existing `.property("value", ...)` mechanism) so the input reflects state on every render. The two writes (property + handler) compose into a single `Attribute`-list contribution.

- For **Int / Double**: same pattern, but the handler attempts `Int(event.targetValue ?? "")` (or `Double.init`); on parse failure, the binding is **not updated** (DOM input keeps the bad value visible; user fixes it; the binding stays at its last-good Int). DEBUG-only `swiflowDiagnostic` optional.

- Composition: a single `Attribute.value(_:)` must produce both the property-set AND the handler-registration. Either return a synthetic `Attribute.compound([Attribute])` (new case) or design the API as two attributes packed inside one shape. **Recommended:** add a `Attribute.compound([Attribute])` case (mirrors `.skip` from Phase 6), with `applyAttributes(...)` recursively folding the inner list. Three lines of code; reusable for any future "one modifier, multiple attribute effects" need.

**Tests:**
- Round-trip via a test renderer: mount a `Component` whose body is `input(.value($state.text))`, simulate an `.input` event with `EventInfo(type: "input", targetValue: "hello")`, assert `state.text == "hello"`.
- Re-render: change `state.text` from outside, assert the rendered VNode's `value` property reflects the new value.
- Parse failure path for Int: send `"abc"`, assert binding unchanged.

---

### 4. `Binding<Bool>` for checkboxes + `Binding<String>` for single-select

**Current state:** no consumer.

**New behavior:**

```swift
public extension Attribute {
    /// Two-way binding for an `<input type="checkbox">`. Reads
    /// `eventInfo.targetChecked`; writes the element's `checked`
    /// property to `binding.get()` on every render.
    @MainActor
    static func checked(_ binding: Binding<Bool>) -> Attribute

    /// Two-way binding for a `<select>` element. Reads
    /// `eventInfo.targetValue` (the selected option's `value`);
    /// writes the element's `value` property to `binding.get()` on
    /// every render so React-style "selected" re-evaluates correctly.
    @MainActor
    static func selection(_ binding: Binding<String>) -> Attribute
}

public extension VNode {
    @MainActor func checked(_ binding: Binding<Bool>) -> VNode
    @MainActor func selection(_ binding: Binding<String>) -> VNode
}
```

`.checked` uses the **`.change`** DOM event (not `.input`) because checkbox state updates fire `change`. `.selection` also uses `.change` for the same reason on `<select>`. Both pull from the new `targetChecked` / `targetValue` fields.

**Tests:** round-trip via test renderer for both. Multi-select (`<select multiple>`) is **out of scope** for Phase 7 — comes back in Phase 12 with form validation work.

---

### 5. `Ref<Element>` — first-party DOM access

**Current state** (verified): no `Ref<...>` type exists. The only way to reach a live DOM node is to drop into JavaScriptKit and walk `JSObject.global.document.querySelector(...)`, which is the kind of escape a frontend dev shouldn't have to think about for "focus this input on mount."

**New behavior:** a `@propertyWrapper` `Ref<Element>` lives in `Sources/Swiflow/Reactivity/Ref.swift`. Shape:

```swift
@MainActor
@propertyWrapper
public final class Ref<Element> {
    /// The currently bound DOM-side handle, or `nil` if not yet
    /// mounted (or already unmounted).
    package var handle: NodeHandle?

    public init() {}

    /// The live DOM node, looked up via the JS driver's handle table.
    /// `nil` outside the mount window. `Element` is typically `JSObject`
    /// (the JavaScriptKit type), so callers can `.focus()`, `.scrollTo()`,
    /// etc.
    public var wrappedValue: Element? {
        get { /* bridge call into JS driver — Phase 7 wires it */ }
    }

    /// `$ref` projected value used by the `.ref(_:)` modifier.
    public var projectedValue: Ref<Element> { self }
}
```

**Modifier:**

```swift
public extension Attribute {
    /// Binds the host element's DOM node to `ref`. On mount, `ref.handle`
    /// is set to the freshly-allocated handle. On unmount, cleared.
    static func ref<E>(_ ref: Ref<E>) -> Attribute

    static func ref<E>(_ ref: Ref<E>, key: String) -> Attribute  // optional, can defer
}

public extension VNode {
    func ref<E>(_ ref: Ref<E>) -> VNode
}
```

**Implementation:**

1. `Ref.swift` exposes `package var handle: NodeHandle?`.
2. Diff's `mount(...)` (in `Sources/Swiflow/Diff/Diff.swift`, `case .element(let data)` arm) reads any `.refBinding(ref)` attribute and writes `ref.handle = h` after the element handle is allocated.
3. Diff's `destroy(...)` clears `ref.handle = nil`.
4. **`Ref<Element>.wrappedValue` getter** does the JS lookup. The JS driver maintains `const nodes = new Map()` (verified at `js-driver/swiflow-driver.js:21-22`). Expose a new JS helper `window.swiflow.nodeForHandle(h)` that returns `nodes.get(h)`. From Swift, `JSObject.global.swiflow.object?.nodeForHandle.function?(.number(Double(handle)))` does the round-trip. The result is a `JSValue`; cast `.object` to get a `JSObject`. If `Element` is `JSObject`, we can return it directly; if `Element` is something more specific (e.g. `HTMLInputElement`), Phase 7 ships only the `JSObject` shape — typed element wrappers are post-1.0.

**Where the `Element` generic comes from:** in Phase 7 we keep it minimal — `Ref<JSObject>` is the canonical form. The generic parameter exists for future typed-element wrappers; today callers write `@Ref var inputRef: JSObject?` (or `@Ref var inputRef = Ref<JSObject>()` per the wrapper init).

**Mount/unmount integration:** the new attribute case is `case refBinding(AnyRefBinding)` where `AnyRefBinding` is a small type-erased wrapper around `Ref<Element>` exposing only the `setHandle(_:)` and `clearHandle()` operations. The Diff cases on this and calls those methods at the right phases.

**Tests:**
- Mount a Component with `input(.ref($inputRef))`; in `onAppear` assert `inputRef.wrappedValue` is non-nil.
- Unmount; assert `inputRef.wrappedValue` is nil afterward.
- The JS lookup itself is best tested in the `Tests/JSDriverTests/` Node/jsdom path because Swift-side unit tests can't construct a live JavaScriptKit `JSObject`.

---

### 6. Un-hide `Binding<Value>` from autocomplete

**Current state** (Phase 6, just shipped): `@_documentation(visibility: internal)` on `Binding<Value>` and `State.projectedValue` in `Sources/Swiflow/Reactivity/State.swift`.

**New behavior:** remove the annotation; rewrite doc-comments to describe the new consumers.

`Binding<Value>` doc:

```swift
/// Two-way binding shaped like SwiftUI's. The projected value of `@State`,
/// accessed via the `$`-prefix sigil:
///
/// ```swift
/// @State var text = ""
/// // ...
/// input(.value($text))   // round-trips through .input events
/// input(.checked($flag)) // for type="checkbox" with .change events
/// select(.selection($choice)) { option("A"); option("B") }
/// ```
///
/// Consumers ship in `SwiflowWeb.AttributeModifiers` (`.value`, `.checked`,
/// `.selection`).
public struct Binding<Value> { ... }
```

`State.projectedValue` doc loses the "reserved for Phase 7" language and becomes a normal doc.

---

### 7. HelloWorld text-input demo + `docs/guides/forms.md`

**Current state:** the HelloWorld Counter uses only `@State var count: Int` and a single button. Nothing exercises `.value`, `.checked`, `.ref`.

**New behavior:**

Extend the Counter template (and the synced HelloWorld example) to add a small text-input demo *alongside* the counter:

```swift
final class Counter: Component {
    @State var count: Int = 0
    @State var greeting: String = "Swiflow"
    @Ref var greetingInput: Ref<JSObject>?  // syntax TBD per Ref<Element> design

    var body: VNode {
        div(.class("container")) {
            h1("Hello, \(greeting)!")
            p("Count: \(count)")
            button("Increment", .on(.click) { self.count += 1 })

            div(.class("greeting-row")) {
                label("Greeting", .attr("for", "g"))
                input(
                    .id("g"),
                    .value($greeting),
                    .ref($greetingInput)
                )
            }
        }
    }

    func onAppear() {
        // Focus the input on first mount — the canonical "Ref" demo.
        _ = greetingInput.wrappedValue?.focus.function?()
    }
}
```

The exact syntax depends on whether `@Ref` is a property wrapper or just a `let greetingInput = Ref<JSObject>()` declaration. The spec doesn't lock that choice; the plan resolves it after the Phase 7 Task E investigation step.

**Forms recipe doc** at `docs/guides/forms.md`:

- Controlled-input pattern with `.value($text)`.
- Validation-on-blur pattern using `.on(.blur)` and a separate `@State var error`.
- Multi-field form composition (a small "name + email" form). No validation framework yet — Phase 12 ships that.
- Reference to `Ref<Element>` for autofocus, scroll-into-view, and other imperative needs.

The recipe doc is short (≤ 200 lines); the goal is to give a frontend dev a copy-pastable starting point.

---

## Non-Goals (deferred to later phases)

- **HMR / module hot-swap** → Phase 8.
- **Multi-select `<select multiple>` binding** → Phase 12 (with the rest of validation).
- **Form validation framework** (`Field`, `Form`, validators) → Phase 12.
- **Typed element wrappers** (`Ref<HTMLInputElement>`, etc.) → post-1.0.
- **`useEffect`-style deps array on `onChange`** → Phase 10.
- **`@Environment` / context DI** → Phase 10.
- **File-input bindings** (`<input type="file">`) → post-1.0 (requires async file-reading bridge).

## Cross-cutting constraints

- **`js-driver/swiflow-driver.js` and `Sources/SwiflowCLI/EmbeddedDriver.swift` must stay bit-for-bit identical** — per `project-js-driver-embedded-sync` memory. Task B touches both.
- **Cross-module visibility uses `package`, not `internal`** — per `project-two-module-package-access`. New types crossing Swiflow → SwiflowWeb need `package` access (e.g. `NodeHandle`, `AnyRefBinding`).
- **SourceKit IDE diagnostics lag disk** — verify with `swift build` before reacting to phantom errors.
- **HelloWorld template ↔ example byte-equality** is asserted by `TemplatesTests.appSwiftMatchesExample`. Task G has to keep them in lockstep.

## Verification

Phase 7 ships when:

1. All seven scope items are implemented and tested.
2. `swift test` passes the full suite. Phase 6 baseline: 286/61. Phase 7 target: +10 to +15 tests (binding round-trips, EventInfo accessors, Ref mount/unmount, JS driver serializeEvent updates), no regressions.
3. `swiflow dev` renders the new HelloWorld correctly — typing in the input updates the heading; refocus via `onAppear` works.
4. `Binding<Value>` shows up in Xcode autocomplete on `State` (i.e. Phase 6's hide is reversed).
5. `docs/guides/forms.md` exists.
6. README Status line names "Phase 7 (Bindings, Refs & Form Foundations)" — bumped in Task H.

## Execution plan

Bite-sized task plan at `docs/superpowers/plans/2026-05-20-swiflow-phase7-bindings-refs-forms.md`. Execution via `superpowers:subagent-driven-development`, same flow as Phase 6.
