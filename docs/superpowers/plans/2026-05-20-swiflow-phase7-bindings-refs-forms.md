# Swiflow Phase 7 — Bindings, Refs & Form Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `Binding<Value>` consumers (`.value`, `.checked`, `.selection`), a first-party `Ref<Element>` story, the `textarea`/`select`/`option` factories that complete the form-input surface, and prove the combination in the HelloWorld example.

**Architecture:** New `Attribute.compound([Attribute])` case lets one modifier produce multiple bag effects (needed because `.value($text)` must both set the `value` property AND register an `.input` handler). New `Attribute.refBinding(AnyRefBinding)` case lets the Diff bind/clear a `Ref<Element>` at mount/unmount without going through a JS-driver patch. `EventInfo` gains `targetChecked: Bool?` and three computed parsing accessors; the JS driver mirrors the new field bit-for-bit in both `js-driver/swiflow-driver.js` and `Sources/SwiflowCLI/EmbeddedDriver.swift`.

**Tech Stack:** Swift 6.0, Swift Testing, swift-argument-parser, JavaScriptKit 0.53. No new dependencies.

**Spec:** [`docs/superpowers/specs/2026-05-20-swiflow-phase7-bindings-refs-forms-design.md`](../specs/2026-05-20-swiflow-phase7-bindings-refs-forms-design.md)

---

## File Structure

**Edit (Swift sources):**
- `Sources/Swiflow/DSL/Elements.swift` — add `textarea`, `select`, `option` factories (Task A).
- `Sources/Swiflow/VNode.swift` — extend `EventInfo` with `targetChecked` + computed `targetIntValue` / `targetDoubleValue` (Task B); add `Attribute.compound([Attribute])` and `Attribute.refBinding(AnyRefBinding)` cases (Tasks C, E).
- `Sources/Swiflow/DSL/Modifiers.swift` — `applyAttributes` recursively folds `.compound`; binds `.refBinding` (Tasks C, E).
- `Sources/Swiflow/Reactivity/State.swift` — un-hide `Binding<Value>` and `State.projectedValue` (Task F).
- New: `Sources/Swiflow/Reactivity/Ref.swift` — `Ref<Element>` + `AnyRefBinding` (Task E).
- `Sources/Swiflow/Diff/Diff.swift` — call `refBinding.setHandle(h)` on mount; `clearHandle()` on destroy (Task E).
- `Sources/SwiflowWeb/AttributeModifiers.swift` — add `.value(_:Binding<...>)`, `.checked(_:Binding<Bool>)`, `.selection(_:Binding<String>)`, `.ref(_:)` overloads (Tasks C, D, E).
- `Sources/SwiflowWeb/DispatcherBridge.swift` — unpack `targetChecked` from JS payload (Task B).

**Edit (JS driver + mirror):**
- `js-driver/swiflow-driver.js` — extend `serializeEvent` with `targetChecked`; expose `window.swiflow.nodeForHandle(h)` for Ref lookup (Tasks B, E).
- `Sources/SwiflowCLI/EmbeddedDriver.swift` — auto-regenerates from the JS source via `scripts/embed-driver.swift`; mirror enforced by `DriverEmbedderTests`.

**Edit (templates + example):**
- `Sources/SwiflowCLI/Templates/Templates.swift` and `examples/HelloWorld/Sources/App/App.swift` — add text-input demo using `.value($greeting)` and `.ref($greetingInput)`; byte-equality test must stay green (Task G).

**New (docs):**
- `docs/guides/forms.md` — controlled-input + manual validation recipe (Task G).

**Edit (README):**
- `README.md` — status line bump to "Phase 7" (Task H).

---

## Task A: textarea / select / option element factories

**Files:**
- Modify: `Sources/Swiflow/DSL/Elements.swift`
- Add: `Tests/SwiflowTests/DSL/FormElementsTests.swift`

- [ ] **A.1: Write failing tests**

  Create `Tests/SwiflowTests/DSL/FormElementsTests.swift`:

  ```swift
  import Testing
  @testable import Swiflow

  @Suite("textarea / select / option element factories")
  struct FormElementsTests {

      @Test("textarea with text content")
      func textareaWithText() {
          let node = textarea("hello", .attr("rows", 5))
          guard case .element(let data) = node else {
              Issue.record("expected element"); return
          }
          #expect(data.tag == "textarea")
          #expect(data.attributes["rows"] == "5")
          guard case .text(let body) = data.children.first else {
              Issue.record("expected text child"); return
          }
          #expect(body == "hello")
      }

      @Test("select with option children")
      func selectWithOptions() {
          let node = select(.attr("name", "color")) {
              option("Red", .attr("value", "r"))
              option("Blue", .attr("value", "b"))
          }
          guard case .element(let data) = node else {
              Issue.record("expected element"); return
          }
          #expect(data.tag == "select")
          #expect(data.children.count == 2)
      }

      @Test("option label")
      func optionLabel() {
          let node = option("Red", .attr("value", "r"))
          guard case .element(let data) = node else {
              Issue.record("expected element"); return
          }
          #expect(data.tag == "option")
          #expect(data.attributes["value"] == "r")
          guard case .text(let body) = data.children.first else {
              Issue.record("expected text child"); return
          }
          #expect(body == "Red")
      }
  }
  ```

  Run: `swift test --filter FormElementsTests 2>&1 | tail -10`. Expected: all three FAIL (factories not yet defined).

- [ ] **A.2: Add factories**

  Edit `Sources/Swiflow/DSL/Elements.swift`. After the existing `input(...)` (around line 113), add:

  ```swift
  /// HTML `<textarea>` — text content goes between the open and close tags.
  public func textarea(_ text: String = "", _ attributes: Attribute...) -> VNode {
      let children: [VNode] = text.isEmpty ? [] : [.text(text)]
      return .element(applyAttributes(tag: "textarea", attributes, children: children))
  }

  /// HTML `<textarea>` with block-form children (rare; usually use the
  /// string overload above).
  public func textarea(_ attributes: Attribute..., @ChildrenBuilder children: () -> [VNode]) -> VNode {
      .element(applyAttributes(tag: "textarea", attributes, children: children()))
  }

  /// HTML `<select>` — children are `option(...)` nodes.
  public func select(_ attributes: Attribute..., @ChildrenBuilder children: () -> [VNode]) -> VNode {
      .element(applyAttributes(tag: "select", attributes, children: children()))
  }

  /// HTML `<option>` — text label as content; `.attr("value", ...)` sets the
  /// underlying form value.
  public func option(_ label: String, _ attributes: Attribute...) -> VNode {
      let children: [VNode] = label.isEmpty ? [] : [.text(label)]
      return .element(applyAttributes(tag: "option", attributes, children: children))
  }
  ```

  If `@ChildrenBuilder` is the correct attribute name, check the existing factories — Phase 5 may have renamed it. Adjust accordingly.

- [ ] **A.3: Confirm pass**

  `swift test --filter FormElementsTests 2>&1 | tail -10`

  Expected: all three pass.

- [ ] **A.4: Full suite**

  `swift test 2>&1 | tail -5` — Phase 6 baseline 286 + 3 = 289.

- [ ] **A.5: Commit**

  ```bash
  git add Sources/Swiflow/DSL/Elements.swift Tests/SwiflowTests/DSL/FormElementsTests.swift
  git commit -m "$(cat <<'EOF'
  feat(dsl): textarea / select / option element factories

  Phase 7 form-input surface needs more than `input`. Add textarea (with
  text-content shorthand + block-form children), select (block-form
  children for the option list), and option (text-label shorthand).

  Tests cover node-structure: tag name, attribute roundtrip, child shape.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task B: EventInfo typed accessors + JS driver mirror

**Files:**
- Modify: `Sources/Swiflow/VNode.swift:116-127` (EventInfo)
- Modify: `Sources/SwiflowWeb/DispatcherBridge.swift:32-41`
- Modify: `js-driver/swiflow-driver.js:55-60`
- Modify: `Sources/SwiflowCLI/EmbeddedDriver.swift` (via regen)
- Add: `Tests/SwiflowTests/VNode/EventInfoAccessorsTests.swift`

- [ ] **B.1: Extend EventInfo struct**

  Replace `Sources/Swiflow/VNode.swift:116-127` with:

  ```swift
  /// Runtime DOM event payload surfaced into Swift handlers.
  ///
  /// The two-argument `.on(_:perform:)` modifier passes one of these to the
  /// user closure. `EventInfo` is the runtime payload (type + value/checked
  /// snapshots); the `Event` enum selects which event to listen for.
  public struct EventInfo: Equatable, Sendable {
      /// DOM event name (e.g. `"click"`, `"input"`).
      public let type: String

      /// Snapshot of `event.target.value` for form inputs; `nil` for events
      /// without a value-bearing target.
      public let targetValue: String?

      /// Snapshot of `event.target.checked` for checkbox/radio inputs;
      /// `nil` for events without a `checked` property on the target.
      public let targetChecked: Bool?

      public init(type: String, targetValue: String? = nil, targetChecked: Bool? = nil) {
          self.type = type
          self.targetValue = targetValue
          self.targetChecked = targetChecked
      }

      /// `targetValue` parsed as an `Int`; `nil` if absent or unparseable.
      public var targetIntValue: Int? { targetValue.flatMap(Int.init) }

      /// `targetValue` parsed as a `Double`; `nil` if absent or unparseable.
      public var targetDoubleValue: Double? { targetValue.flatMap(Double.init) }
  }
  ```

- [ ] **B.2: Failing tests for new accessors**

  Create `Tests/SwiflowTests/VNode/EventInfoAccessorsTests.swift`:

  ```swift
  import Testing
  @testable import Swiflow

  @Suite("EventInfo typed accessors")
  struct EventInfoAccessorsTests {

      @Test("targetChecked initializes to nil by default")
      func defaultChecked() {
          let e = EventInfo(type: "click")
          #expect(e.targetChecked == nil)
      }

      @Test("targetChecked roundtrips")
      func checkedRoundtrip() {
          let e = EventInfo(type: "change", targetChecked: true)
          #expect(e.targetChecked == true)
      }

      @Test("targetIntValue parses a numeric string")
      func intParses() {
          let e = EventInfo(type: "input", targetValue: "42")
          #expect(e.targetIntValue == 42)
      }

      @Test("targetIntValue returns nil for non-numeric")
      func intNilOnAlpha() {
          let e = EventInfo(type: "input", targetValue: "abc")
          #expect(e.targetIntValue == nil)
      }

      @Test("targetDoubleValue parses a decimal")
      func doubleParses() {
          let e = EventInfo(type: "input", targetValue: "3.14")
          #expect(e.targetDoubleValue == 3.14)
      }

      @Test("targetDoubleValue returns nil for non-numeric")
      func doubleNilOnAlpha() {
          let e = EventInfo(type: "input", targetValue: "xx")
          #expect(e.targetDoubleValue == nil)
      }
  }
  ```

  Run: `swift test --filter EventInfoAccessorsTests` — expected: all pass (we already extended the struct in B.1).

- [ ] **B.3: Wire DispatcherBridge**

  Edit `Sources/SwiflowWeb/DispatcherBridge.swift`. In the JSClosure body (around lines 34-41), replace:

  ```swift
  let type = payload.type.string ?? ""
  let targetValue = payload.targetValue.string

  registry.dispatch(
      id: handlerId,
      event: EventInfo(type: type, targetValue: targetValue)
  )
  ```

  with:

  ```swift
  let type = payload.type.string ?? ""
  let targetValue = payload.targetValue.string
  let targetChecked = payload.targetChecked.boolean

  registry.dispatch(
      id: handlerId,
      event: EventInfo(
          type: type,
          targetValue: targetValue,
          targetChecked: targetChecked
      )
  )
  ```

  Note: `JSValue.boolean` returns `Bool?` — `nil` when the JS value is `null`/`undefined`/not a boolean. That matches our desired semantics (no `checked` on the target → nil).

- [ ] **B.4: Update JS driver — both source AND embedded mirror**

  Edit `js-driver/swiflow-driver.js:55-60`. Replace `serializeEvent` body with:

  ```js
    function serializeEvent(event) {
      const target = event.target;
      const targetValue =
        target && "value" in target ? String(target.value) : null;
      const targetChecked =
        target && "checked" in target ? Boolean(target.checked) : null;
      return {
        type: event.type,
        targetValue: targetValue,
        targetChecked: targetChecked,
      };
    }
  ```

  Then regenerate the embedded mirror:

  ```bash
  swift scripts/embed-driver.swift
  ```

  This rewrites `Sources/SwiflowCLI/EmbeddedDriver.swift` from the JS source. The `DriverEmbedderTests` will fail until both files agree.

- [ ] **B.5: Confirm pass**

  ```bash
  swift test 2>&1 | tail -10
  ```

  Expected: 289 (Task A) + 6 (new EventInfo tests) = 295. Plus the JS-driver bit-for-bit test still green.

- [ ] **B.6: Commit**

  ```bash
  git add Sources/Swiflow/VNode.swift \
          Sources/SwiflowWeb/DispatcherBridge.swift \
          js-driver/swiflow-driver.js \
          Sources/SwiflowCLI/EmbeddedDriver.swift \
          Tests/SwiflowTests/VNode/EventInfoAccessorsTests.swift
  git commit -m "$(cat <<'EOF'
  feat(events): EventInfo.targetChecked + typed Int/Double accessors

  Phase 7's Binding consumers need checkbox state (event.target.checked)
  and parsed numeric values. Extend EventInfo with:

  - targetChecked: Bool? — populated from event.target.checked when the
    DOM target has a `checked` property; nil otherwise.
  - targetIntValue / targetDoubleValue — computed accessors that parse
    targetValue lazily; nil on absence or parse failure.

  JS driver serializeEvent emits targetChecked alongside targetValue.
  DispatcherBridge unpacks both. Embedded driver regenerated; bit-for-bit
  test stays green.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task C: `.value(_:Binding<...>)` consumers

**Files:**
- Modify: `Sources/Swiflow/DSL/Modifiers.swift` — add `Attribute.compound([Attribute])` case; teach `applyAttributes` to recursively fold it.
- Modify: `Sources/SwiflowWeb/AttributeModifiers.swift` — add `.value(_:Binding<String|Int|Double>)` overloads, prefix and postfix.
- Add: `Tests/SwiflowTests/Binding/ValueBindingTests.swift` (lives in `Sources/Swiflow` package or wherever the test renderer is).

- [ ] **C.1: Add `Attribute.compound([Attribute])`**

  Edit `Sources/Swiflow/DSL/Modifiers.swift`. After `case skip` (added in Phase 6), add:

  ```swift
  /// Composite of multiple attribute effects produced by a single modifier
  /// (e.g. `.value($text)` writes both a `value` property AND an `.input`
  /// handler). `applyAttributes` recursively flattens these during the fold;
  /// composites never reach `ElementData`.
  case compound([Attribute])
  ```

  In `applyAttributes(...)`'s `switch attribute` block, add a case (place it AFTER `.skip` to keep related cases together):

  ```swift
  case .compound(let inner):
      // Recursively process the composite's inner attributes inline.
      // Order matters: later writes win, so a composite that issues
      // both a .property and a .handler appends to the bags in
      // declaration order — same as if the user had passed them
      // individually.
      for attr in inner {
          // Re-enter the switch via a recursive call. Since
          // `applyAttributes` is a top-level free function with
          // `var attrs`/`var handlers` captures, we hand-roll the
          // inner switch instead to avoid re-allocating bags.
          switch attr {
          case .attribute(let name, let value):
              if URLSanitizer.urlAttributeNames.contains(name.lowercased()) {
                  if let sanitized = URLSanitizer.sanitize(value) {
                      attrs[name] = sanitized
                  }
                  // (URL sanitizer rejection diagnostic already lives in
                  // the outer .attribute arm; the composite path doesn't
                  // re-emit it — composites are framework-issued and
                  // pre-validated.)
              } else {
                  attrs[name] = value
              }
          case .property(let name, let value): props[name] = value
          case .style(let name, let value): styles[name] = value
          case .handler(let event, let value): handlers[event] = value
          case .key(let value): key = value
          case .skip: continue
          case .compound(let nested):
              // Composites of composites are legal but degenerate.
              // Flatten one more level inline; deeper nesting falls
              // back to the outer `for` resuming with the nested list.
              for n in nested { /* same inner switch — implementer may DRY */ }
          case .refBinding: continue  // handled separately (Task E)
          }
      }
  ```

  **Implementer note:** the duplicated inner switch is verbose; an alternative is to refactor `applyAttributes` to extract a `process(_ attr: Attribute)` inner function with captured `inout` bags. Either shape is fine; pick the one your taste prefers and that the existing code style supports.

- [ ] **C.2: Failing tests for binding round-trip**

  Create `Tests/SwiflowTests/Binding/ValueBindingTests.swift`:

  ```swift
  import Testing
  @testable import Swiflow

  @Suite("@State + .value(_:Binding<String>) round-trip")
  @MainActor
  struct ValueBindingTests {

      @Test("input(.value($text)) writes text into the value property")
      func writesValueProperty() async throws {
          // Build a state cell; verify that the rendered VNode carries
          // `value` as a property with the binding's current value.
          let state = State<String>(wrappedValue: "hello")
          // .value is in SwiflowWeb; we need a way to test without WASM.
          // The implementer must arrange for a Swiflow-side test that
          // doesn't require JavaScriptKit — either by testing through
          // the renderer's package-level entry point with a stub
          // dispatcher, or by structuring `.value` so its property-set
          // portion lives in Swiflow (not SwiflowWeb) and only the
          // handler-registration lives platform-side.
          //
          // Most natural shape: keep `.value` as a platform-bridged
          // modifier in SwiflowWeb, and gate this test #if canImport(JavaScriptKit).
          Issue.record("Implementer: complete using the existing SwiflowWeb test rig (see Phase 5 test patterns) or split the modifier so the property-set portion is testable in pure Swiflow.")
      }

      // ... additional tests for Int / Double parsing once the impl shape
      //     is settled.
  }
  ```

  This task is the most architectural in Phase 7. The implementer subagent will resolve the test-harness shape; treat the test stub as a TDD nudge, not a finished test.

- [ ] **C.3: Implement `.value(_:Binding<String>)`**

  Edit `Sources/SwiflowWeb/AttributeModifiers.swift`. Append (inside the existing `#if canImport(JavaScriptKit)` block):

  ```swift
  public extension Attribute {
      /// Two-way binding for a text input/textarea. The current value of
      /// `binding.get()` is written to the element's `value` property on
      /// every render; an `.input` event handler is registered that calls
      /// `binding.set(eventInfo.targetValue ?? "")` so the binding
      /// reflects user edits.
      @MainActor
      static func value(_ binding: Binding<String>) -> Attribute {
          let handler = _registerAmbientHandler { info in
              binding.set(info.targetValue ?? "")
          }
          return .compound([
              .property(name: "value", value: .string(binding.get())),
              .handler(event: "input", value: handler),
          ])
      }

      @MainActor
      static func value(_ binding: Binding<Int>) -> Attribute {
          let handler = _registerAmbientHandler { info in
              if let parsed = info.targetIntValue {
                  binding.set(parsed)
              }
              // Silent on parse failure; binding stays at last good Int.
          }
          return .compound([
              .property(name: "value", value: .string(String(binding.get()))),
              .handler(event: "input", value: handler),
          ])
      }

      @MainActor
      static func value(_ binding: Binding<Double>) -> Attribute {
          let handler = _registerAmbientHandler { info in
              if let parsed = info.targetDoubleValue {
                  binding.set(parsed)
              }
          }
          return .compound([
              .property(name: "value", value: .string(String(binding.get()))),
              .handler(event: "input", value: handler),
          ])
      }
  }

  public extension VNode {
      @MainActor
      func value(_ binding: Binding<String>) -> VNode {
          if case .element(var data) = self {
              data.properties["value"] = .string(binding.get())
              let handler = _registerAmbientHandler { info in
                  binding.set(info.targetValue ?? "")
              }
              data.handlers["input"] = handler
              return .element(data)
          }
          swiflowDiagnostic("Postfix .value applied to a non-element VNode — silently ignored.")
          return self
      }

      @MainActor
      func value(_ binding: Binding<Int>) -> VNode {
          if case .element(var data) = self {
              data.properties["value"] = .string(String(binding.get()))
              let handler = _registerAmbientHandler { info in
                  if let parsed = info.targetIntValue { binding.set(parsed) }
              }
              data.handlers["input"] = handler
              return .element(data)
          }
          swiflowDiagnostic("Postfix .value applied to a non-element VNode — silently ignored.")
          return self
      }

      @MainActor
      func value(_ binding: Binding<Double>) -> VNode {
          if case .element(var data) = self {
              data.properties["value"] = .string(String(binding.get()))
              let handler = _registerAmbientHandler { info in
                  if let parsed = info.targetDoubleValue { binding.set(parsed) }
              }
              data.handlers["input"] = handler
              return .element(data)
          }
          swiflowDiagnostic("Postfix .value applied to a non-element VNode — silently ignored.")
          return self
      }
  }
  ```

  Check `PropertyValue.string(...)` is the correct API for setting a property to a string value (it might be `.string(_)` or a different shape — verify with `grep PropertyValue Sources/Swiflow/`).

- [ ] **C.4: Resolve and run the binding tests**

  The implementer settles the test-harness question from C.2 and writes concrete tests:
  - Render-time property set: `input(.value($s)).element.properties["value"]` reflects `s.wrappedValue`.
  - Round-trip via dispatched `EventInfo`: register the handler, dispatch a synthetic input event, assert `s.wrappedValue` updated.

- [ ] **C.5: Full suite**

  `swift test 2>&1 | tail -5` — target: previous count + N (where N is the actual test count added).

- [ ] **C.6: Commit**

  ```bash
  git add Sources/Swiflow/DSL/Modifiers.swift \
          Sources/SwiflowWeb/AttributeModifiers.swift \
          Tests/SwiflowTests/Binding/ValueBindingTests.swift
  git commit -m "$(cat <<'EOF'
  feat(binding): .value(_:Binding<String|Int|Double>) consumers

  Phase 3 shipped Binding<Value> without a DSL consumer; Phase 6 hid it
  from autocomplete. Phase 7 ships the consumers — `.value($text)`
  round-trips through .input events on input and textarea, both prefix
  (Attribute static func) and postfix (VNode method).

  - String binding: targetValue ?? "" -> binding.set.
  - Int / Double bindings: parse via targetIntValue / targetDoubleValue;
    leave binding unchanged on parse failure (input stays in the DOM
    until the user fixes it).
  - New Attribute.compound([Attribute]) case lets a single modifier
    produce both the value-property set AND the handler registration.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task D: `.checked(_:Binding<Bool>)` + `.selection(_:Binding<String>)`

**Files:**
- Modify: `Sources/SwiflowWeb/AttributeModifiers.swift`
- Add: `Tests/SwiflowTests/Binding/CheckedSelectionBindingTests.swift`

- [ ] **D.1: Add .checked overloads (Attribute + VNode)**

  Same pattern as `.value`. Uses `.change` event, reads `info.targetChecked`. The "current value" write goes to the `checked` property (boolean PropertyValue).

  ```swift
  public extension Attribute {
      @MainActor
      static func checked(_ binding: Binding<Bool>) -> Attribute {
          let handler = _registerAmbientHandler { info in
              if let c = info.targetChecked { binding.set(c) }
          }
          return .compound([
              .property(name: "checked", value: .bool(binding.get())),
              .handler(event: "change", value: handler),
          ])
      }
  }

  public extension VNode {
      @MainActor
      func checked(_ binding: Binding<Bool>) -> VNode {
          if case .element(var data) = self {
              data.properties["checked"] = .bool(binding.get())
              let handler = _registerAmbientHandler { info in
                  if let c = info.targetChecked { binding.set(c) }
              }
              data.handlers["change"] = handler
              return .element(data)
          }
          swiflowDiagnostic("Postfix .checked applied to a non-element VNode — silently ignored.")
          return self
      }
  }
  ```

- [ ] **D.2: Add .selection overloads**

  Same shape; uses `.change` event, reads `info.targetValue` (the selected `<option>`'s `value` attribute).

  ```swift
  public extension Attribute {
      @MainActor
      static func selection(_ binding: Binding<String>) -> Attribute {
          let handler = _registerAmbientHandler { info in
              binding.set(info.targetValue ?? "")
          }
          return .compound([
              .property(name: "value", value: .string(binding.get())),
              .handler(event: "change", value: handler),
          ])
      }
  }

  public extension VNode {
      @MainActor
      func selection(_ binding: Binding<String>) -> VNode {
          if case .element(var data) = self {
              data.properties["value"] = .string(binding.get())
              let handler = _registerAmbientHandler { info in
                  binding.set(info.targetValue ?? "")
              }
              data.handlers["change"] = handler
              return .element(data)
          }
          swiflowDiagnostic("Postfix .selection applied to a non-element VNode — silently ignored.")
          return self
      }
  }
  ```

- [ ] **D.3: Tests + commit**

  Tests mirror Task C's shape. Commit alongside.

---

## Task E: `Ref<Element>` + `.ref(_:)`

**Files:**
- Add: `Sources/Swiflow/Reactivity/Ref.swift`
- Modify: `Sources/Swiflow/DSL/Modifiers.swift` — add `Attribute.refBinding(AnyRefBinding)` case.
- Modify: `Sources/Swiflow/Diff/Diff.swift` — bind/clear on mount/destroy.
- Modify: `Sources/SwiflowWeb/AttributeModifiers.swift` — `.ref(_:)` modifier + JSObject getter.
- Modify: `js-driver/swiflow-driver.js` — expose `window.swiflow.nodeForHandle(h)`.
- Modify: `Sources/SwiflowCLI/EmbeddedDriver.swift` — regenerated.

- [ ] **E.1: Investigate handle types**

  Grep to find the canonical handle type:

  ```bash
  grep -n "typealias NodeHandle\|struct NodeHandle\|typealias Handle\b" Sources/Swiflow/ | head
  ```

  If a public `NodeHandle` exists, use it for `Ref<Element>.handle`. If handles are bare `Int`, surface a `package` typealias or use the existing concrete type.

- [ ] **E.2: Write `Ref.swift`**

  ```swift
  // Sources/Swiflow/Reactivity/Ref.swift

  /// A first-party DOM reference, populated by the framework at element
  /// mount time. Use to focus an input, scroll an element into view, or
  /// invoke any other imperative DOM API.
  ///
  /// ```swift
  /// final class Form: Component {
  ///     @State var name = ""
  ///     let nameInput = Ref<JSObject>()
  ///
  ///     var body: VNode {
  ///         div {
  ///             input(.value($name), .ref(nameInput))
  ///         }
  ///     }
  ///
  ///     func onAppear() {
  ///         _ = nameInput.wrappedValue?.focus.function?()
  ///     }
  /// }
  /// ```
  ///
  /// `wrappedValue` returns `nil` outside the mount window (before
  /// `onAppear` fires; after `onDisappear` returns).
  @MainActor
  @propertyWrapper
  public final class Ref<Element> {
      /// Framework-set; opaque to user code.
      package var handle: NodeHandle?

      public init() {}

      /// Looks the bound DOM node up in the JS-side handle table via
      /// `window.swiflow.nodeForHandle(handle)`. Returns `nil` if the
      /// ref isn't currently bound or the lookup fails (the JS driver
      /// must be loaded for this to succeed).
      public var wrappedValue: Element? {
          // The lookup itself lives in SwiflowWeb (it depends on
          // JavaScriptKit). Phase 7 ships the override-point as
          // `package`-level closure; SwiflowWeb installs it once at
          // render() time.
          guard let handle = handle else { return nil }
          return Ref._resolver?(handle) as? Element
      }

      /// `$ref` projected value — what the `.ref(_:)` modifier accepts.
      public var projectedValue: Ref<Element> { self }

      /// Package-internal hook installed by SwiflowWeb at render() time.
      /// SwiftPM-package-internal, not part of the public API.
      package static var _resolver: ((NodeHandle) -> Any?)?
  }

  /// Type-erased wrapper for binding a `Ref<E>` into an `Attribute`.
  /// Stores the box and the setter methods so the Diff can call them
  /// without knowing the generic type.
  package struct AnyRefBinding {
      let setHandle: (NodeHandle) -> Void
      let clearHandle: () -> Void

      package init<E>(_ ref: Ref<E>) {
          self.setHandle = { ref.handle = $0 }
          self.clearHandle = { ref.handle = nil }
      }
  }
  ```

- [ ] **E.3: Wire `.refBinding(AnyRefBinding)` into `Attribute`**

  Edit `Sources/Swiflow/DSL/Modifiers.swift`. Add the case to `Attribute`:

  ```swift
  /// Binds the host element's DOM-side handle into a `Ref<Element>` at
  /// mount time. Cleared on destroy. Handled by Diff; never appears in
  /// `ElementData`'s bags.
  case refBinding(AnyRefBinding)
  ```

  Teach `applyAttributes(...)` to drop `.refBinding` (it's handled out-of-band by Diff). Add a case:

  ```swift
  case .refBinding:
      continue
  ```

  But the Diff also needs to see the original `.refBinding(...)` attribute on the element. **Design choice:** `applyAttributes` is the *fold step* — it returns `ElementData` for the runtime. The Ref bindings are runtime metadata, not bag entries. Options:

  - **A:** Extend `ElementData` with a new `refBindings: [AnyRefBinding]` field; the fold extracts these alongside the bags. Most consistent with the existing design.
  - **B:** Stash the bindings in a side-channel keyed by the element's eventual handle. Fragile.

  **Recommended: Option A.** Add `refBindings: [AnyRefBinding]` to `ElementData` (it lives near `attributes`, `properties`, `style`, `handlers`); have `applyAttributes` populate it from `.refBinding(...)` cases; have Diff consume it on mount/destroy.

- [ ] **E.4: Diff mount/destroy integration**

  In `Sources/Swiflow/Diff/Diff.swift`, `case .element(let data)` arm of `mount(...)` (around line 93), after the handle is allocated:

  ```swift
  for binding in data.refBindings {
      binding.setHandle(h)
  }
  ```

  In `destroy(...)` (around line 432), for the element case, before tearing down children:

  ```swift
  if case .element(let data) = node.vnode {
      for binding in data.refBindings {
          binding.clearHandle()
      }
  }
  ```

- [ ] **E.5: SwiflowWeb side — resolver + modifier**

  In `Sources/SwiflowWeb/AttributeModifiers.swift`, append:

  ```swift
  public extension Attribute {
      static func ref<E>(_ ref: Ref<E>) -> Attribute {
          .refBinding(AnyRefBinding(ref))
      }
  }

  public extension VNode {
      func ref<E>(_ ref: Ref<E>) -> VNode {
          if case .element(var data) = self {
              data.refBindings.append(AnyRefBinding(ref))
              return .element(data)
          }
          swiflowDiagnostic("Postfix .ref applied to a non-element VNode — silently ignored.")
          return self
      }
  }
  ```

  And install the resolver at `Swiflow.render(into:)` entry point — somewhere in `Sources/SwiflowWeb/SwiflowWeb.swift`:

  ```swift
  Ref<Any>._resolver = { handle in
      JSObject.global.swiflow.object?.nodeForHandle.function?(.number(Double(handle.value))).object
  }
  ```

  (Adjust to the actual `NodeHandle` shape — if it's a struct with `.value`, use that; if it's a typealias for `Int`, use `Double(handle)`.)

- [ ] **E.6: JS driver — expose nodeForHandle**

  Edit `js-driver/swiflow-driver.js`. In the existing `window.swiflow` install (near the bottom of the file), add:

  ```js
  window.swiflow.nodeForHandle = function (h) {
    return nodes.get(h) || null;
  };
  ```

  Regenerate the embedded driver: `swift scripts/embed-driver.swift`.

- [ ] **E.7: Tests**

  - Pure-Swift test: `Ref<Int>.handle` is nil on construction; assigning `setHandle(5)` makes it `5`; `clearHandle()` returns it to nil.
  - Diff-level test: mount an `input(.ref(myRef))` Component; assert `myRef.handle != nil` after mount; destroy; assert `myRef.handle == nil`.
  - The full JS lookup is integration-test territory — covered by the HelloWorld smoke test in Task G + the Playwright e2e suite from Phase 4.

- [ ] **E.8: Commit**

  ```bash
  git add Sources/Swiflow/Reactivity/Ref.swift \
          Sources/Swiflow/DSL/Modifiers.swift \
          Sources/Swiflow/VNode.swift \
          Sources/Swiflow/Diff/Diff.swift \
          Sources/SwiflowWeb/AttributeModifiers.swift \
          Sources/SwiflowWeb/SwiflowWeb.swift \
          js-driver/swiflow-driver.js \
          Sources/SwiflowCLI/EmbeddedDriver.swift \
          Tests/SwiflowTests/Reactivity/RefTests.swift
  git commit -m "$(cat <<'EOF'
  feat(reactivity): Ref<Element> + .ref(_:) modifier for first-party DOM access

  Frontend day-one tasks like "focus this input on mount" required dropping
  into JavaScriptKit before now. Ship Ref<Element> with a `.ref(_:)`
  modifier (prefix + postfix); the Diff binds the element handle on mount
  and clears on destroy. `wrappedValue` looks up the live DOM node via a
  new `window.swiflow.nodeForHandle(h)` helper in the JS driver.

  Ref<JSObject> is the canonical Phase 7 shape; typed element wrappers
  (Ref<HTMLInputElement>) come post-1.0.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task F: Un-hide `Binding<Value>` from autocomplete

**Files:**
- Modify: `Sources/Swiflow/Reactivity/State.swift`

- [ ] **F.1: Remove `@_documentation(visibility: internal)`**

  Drop the annotation from both `Binding<Value>` and `State.projectedValue`. Replace the Phase 6 doc-comments with normal docs that describe the now-shipping consumers (`.value`, `.checked`, `.selection`).

  Reference the spec for the recommended wording (§6 in the spec doc).

- [ ] **F.2: Build + test**

  `swift build && swift test 2>&1 | tail -5`

- [ ] **F.3: Commit**

  ```bash
  git add Sources/Swiflow/Reactivity/State.swift
  git commit -m "$(cat <<'EOF'
  docs(state): un-hide Binding<Value> now that consumers ship

  Phase 6 hid Binding<Value> and State.projectedValue from autocomplete
  via @_documentation(visibility: internal) because no DSL modifier
  consumed them. Phase 7 ships .value, .checked, and .selection
  consumers, so $sigil access becomes a real first-class API. Drop the
  visibility annotation; rewrite doc-comments to describe the consumers.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task G: HelloWorld text-input demo + forms recipe doc

**Files:**
- Modify: `examples/HelloWorld/Sources/App/App.swift`
- Modify: `Sources/SwiflowCLI/Templates/Templates.swift`
- New: `docs/guides/forms.md`

- [ ] **G.1: Decide HelloWorld extension shape**

  Add `@State var greeting: String = "Swiflow"` and `let greetingInput = Ref<JSObject>()`. The body now wires `.value($greeting)` and `.ref(greetingInput)` onto an `input`, with a `label` next to it. `onAppear` calls `greetingInput.wrappedValue?.focus.function?()`.

  Keep the existing Counter logic; this is additive.

- [ ] **G.2: Update both files in lockstep**

  Edit `examples/HelloWorld/Sources/App/App.swift` and the `rawAppSwift` literal in `Sources/SwiflowCLI/Templates/Templates.swift`. Maintain byte-equality for `TemplatesTests.appSwiftMatchesExample`.

  The exact code shape — including how `Ref` is declared (a stored `let` vs. a property wrapper) — follows from Task E's decisions. Match the canonical example to whatever Task E ended up with.

- [ ] **G.3: Run `TemplatesTests`**

  `swift test --filter TemplatesTests 2>&1 | tail`

- [ ] **G.4: Write `docs/guides/forms.md`**

  Cover:
  - Controlled-input pattern with `.value($text)`.
  - Validation-on-blur using `.on(.blur)` and a side `@State var error`.
  - Composing multiple fields (name + email, no validator framework yet).
  - Pointer to `Ref<Element>` for autofocus / scroll-into-view.
  - Heavy validation framework → Phase 12.

  Target length: ≤ 200 lines. Code blocks copy-pastable.

- [ ] **G.5: Smoke-test in the browser**

  ```bash
  ./.build/debug/swiflow dev --project examples/HelloWorld &
  sleep 5  # wait for the WASM build (the CLI does its own)
  open http://localhost:3000
  ```

  Verify in browser: typing in the greeting input updates the `<h1>`. (Don't kill the dev server until you've confirmed.)

- [ ] **G.6: Commit**

  ```bash
  git add examples/HelloWorld/Sources/App/App.swift \
          Sources/SwiflowCLI/Templates/Templates.swift \
          docs/guides/forms.md
  git commit -m "$(cat <<'EOF'
  feat(example): HelloWorld text-input demo + docs/guides/forms.md

  Extend the Counter scaffold with a text input bound via .value($text)
  and a Ref<JSObject> that onAppear() focuses on first mount. Mirror in
  the swiflow init template; byte-equality test stays green.

  docs/guides/forms.md ships a tight controlled-input + manual validation
  recipe. Form validation framework (Field, Form, validators) arrives in
  Phase 12.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task H: Final test pass + Phase 7 ship

**Files:**
- Modify: `README.md` (status line)

- [ ] **H.1: Full test suite**

  `swift test 2>&1 | tail -5` — target: 286 (Phase 6) + ~15 (Phase 7 added tests) ≈ 301.

- [ ] **H.2: Build smoke**

  `swift build 2>&1 | tail -5` — clean.

- [ ] **H.3: Bump README status**

  Update the Status line to "Phase 7 (Bindings, Refs & Form Foundations) complete" — wording in the parent master plan.

- [ ] **H.4: Commit status bump**

  ```bash
  git add README.md
  git commit -m "$(cat <<'EOF'
  docs(readme): bump status to Phase 7 (Bindings, Refs & Form Foundations) complete

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

- [ ] **H.5: Push**

  `git push origin main`

- [ ] **H.6: Update memory if new conventions surfaced**

  Candidates:
  - `Attribute.compound([Attribute])` pattern for one-modifier-multiple-effects.
  - `Ref<Element>._resolver` package-level closure for cross-module JS bridging.

  Skip if nothing new.

---

## Verification

After all tasks land:

```bash
swift test 2>&1 | tail -5
# Expected: ~301 tests passing.

./.build/debug/swiflow init phase7-smoketest --swiflow-source "$(pwd)" --output /tmp
cd /tmp/phase7-smoketest && swift build && cd -
# Expected: clean Swift build (host-only sanity).
```

Browser:

```bash
./.build/debug/swiflow dev --project examples/HelloWorld
# Expected: typing in the greeting input updates <h1> in real time.
```

---

## Out of Scope

Deferred to later phases per the master plan:

- HMR (instant save→pixels) → Phase 8.
- Multi-select `<select multiple>` binding → Phase 12.
- Form validation framework (`Field`, `Form`, validators) → Phase 12.
- Typed element wrappers (`Ref<HTMLInputElement>`, etc.) → post-1.0.
- `useEffect`-style deps on `onChange` → Phase 10.
- `@Environment` / context DI → Phase 10.

---

## Self-Review

- **Spec coverage:** Task A covers §1 (form factories). Task B covers §2 (EventInfo). Task C covers §3 (.value). Task D covers §4 (.checked + .selection). Task E covers §5 (Ref<Element>). Task F covers §6 (un-hide Binding). Task G covers §7 (HelloWorld demo + forms recipe). Task H ships.
- **Placeholder scan:** Task C.1's inner switch is intentionally permissive on style ("DRY at implementer's discretion"); Task E.5's `JSObject.global.swiflow.object?.nodeForHandle.function?...` invocation depends on the actual handle type and JavaScriptKit version — implementer adjusts.
- **Type consistency:** `Attribute.compound([Attribute])`, `Attribute.refBinding(AnyRefBinding)`, `Attribute.skip` (Phase 6) all play together in `applyAttributes` — the implementer must verify exhaustiveness when adding new cases. `AnyRefBinding`, `Ref<Element>`, `ElementData.refBindings` are referenced consistently across Diff, Modifiers, and AttributeModifiers.
