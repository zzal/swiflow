# Swiflow Phase 13a — SwiflowTesting Harness

## Goal

Ship a pure-Swift headless test renderer that lets components be exercised with `render()` + query + `#expect` — no WASM build, no browser, no JavaScriptKit. Covers the full reactive lifecycle: `@State` mutation, scheduler flush, child-component embedding, two-way bindings, and form validation.

---

## Section 1 — Architecture

### New files

| File | Responsibility |
|---|---|
| `Sources/SwiflowTesting/TestHarness.swift` | Public API: `render()` free function, `TestHarness` struct, `TestNode` struct |
| `Sources/SwiflowTesting/TestRenderer.swift` | Internal: `TestRenderer` class — mount tree, scheduler, rerender callback, tree-walk helpers |
| `Tests/SwiflowTestingTests/TestHarnessTests.swift` | Unit tests against Counter and SignIn components defined inline |

### New `Package.swift` targets

```swift
.target(
    name: "SwiflowTesting",
    dependencies: ["Swiflow"],
    path: "Sources/SwiflowTesting",
    swiftSettings: [.swiftLanguageMode(.v6)]
),
.testTarget(
    name: "SwiflowTestingTests",
    dependencies: ["SwiflowTesting", "Swiflow"],
    path: "Tests/SwiflowTestingTests",
    swiftSettings: [.swiftLanguageMode(.v6)]
),
```

`SwiflowTesting` depends only on `Swiflow` — no JavaScriptKit, no SwiflowWeb. Because it lives in the same `Package.swift`, it has `package`-level access to `HandlerRegistry`, `diff`, `wireState`, and related internals exactly as `SwiflowWeb` does.

### Synchronous-only

All test operations are synchronous. `SyncScheduler` (already in `Sources/Swiflow/Reactivity/Scheduler.swift`) handles batching and flushing. Async test support (for `task { }` lifecycle hooks) is deferred to a pre-1.0 follow-up.

---

## Section 2 — Entry point

```swift
/// Renders `component` into a headless virtual DOM and returns a `TestHarness`
/// for querying and interacting with the result.
///
/// `@State` wiring and the initial diff happen synchronously. The returned
/// harness reflects the fully-rendered initial state.
@MainActor
public func render<C: Component>(_ component: C) -> TestHarness {
    TestHarness(TestRenderer(component))
}
```

The root component's `body` is diffed directly — not wrapped in a `.component` anchor — so `mountTree` is the element tree returned by `body`, and the root component itself is tracked separately by identity in `TestRenderer`.

---

## Section 3 — `TestNode`

```swift
/// A snapshot of a single element node returned by `TestHarness` queries.
/// Assert against its fields with `#expect`.
public struct TestNode {
    /// HTML tag name (e.g. `"button"`, `"p"`, `"input"`).
    public let tag: String
    /// Concatenated text content of this element's subtree (depth-first,
    /// `.text` nodes only). Empty string if the element has no text descendants.
    public let text: String
    /// HTML attributes from `ElementData.attributes`.
    public let attributes: [String: String]
    /// DOM properties from `ElementData.properties`.
    public let properties: [String: PropertyValue]
}
```

---

## Section 4 — `TestHarness` public API

`TestHarness` is a struct wrapping a `TestRenderer` class reference so it can be passed by value while sharing mutable state.

### Queries

```swift
/// Returns the first element matching `tag` (and `text`, if supplied).
/// `text` matches when the element's subtree text content contains the string.
/// Returns `nil` if no match is found.
public func find(_ tag: String, text: String? = nil) -> TestNode?

/// Returns all elements matching `tag` and optional `text`, in document order.
public func findAll(_ tag: String, text: String? = nil) -> [TestNode]

/// True iff at least one element matches `tag` and optional `text`.
public func exists(_ tag: String, text: String? = nil) -> Bool

/// All text content in the rendered tree, concatenated depth-first.
/// Useful for broad "does this string appear anywhere" assertions.
public var allText: String
```

### Interactions

Each interaction fires an event on the first matching element, then calls `scheduler.flush()`, which synchronously re-renders all dirty components and updates `mountTree`. Subsequent queries read the updated tree immediately.

```swift
/// Fires a `click` event on the first element matching `tag` (and `text`).
/// No-op if no matching element has a click handler.
public func click(_ tag: String, text: String? = nil)

/// Fires an `input` event with `targetValue: value` on the element at
/// position `index` among all elements matching `tag` (default `"input"`).
/// `at: 0` is the first match, `at: 1` the second, etc.
/// No-op if no matching element has an input handler.
public func input(_ tag: String = "input", at index: Int = 0, value: String)

/// Fires a `blur` event on the element at position `index` among all
/// elements matching `tag` (default `"input"`).
/// No-op if no matching element has a blur handler.
public func blur(_ tag: String = "input", at index: Int = 0)
```

`input` and `blur` use `at:` rather than `text:` because `<input>` elements have no text content to distinguish them by.

---

## Section 5 — `TestRenderer` internals

### Initialization

```swift
final class TestRenderer {
    var mountTree: MountNode
    let handles: HandleAllocator
    let handlers: HandlerRegistry
    let scheduler: SyncScheduler
    let rootInstance: any Component
    let rootAnyComponent: AnyComponent
}
```

Steps:
1. Allocate `HandleAllocator()`, `HandlerRegistry()`.
2. Create `SyncScheduler { [weak self] component in self?.rerender(component) }`.
3. Wrap instance: `rootAnyComponent = AnyComponent(instance)`.
4. `wireState(on: rootAnyComponent, scheduler: scheduler)`.
5. `rootInstance.body` → initial VNode.
6. `diff(mounted: nil, next: vnode, handles:, handlers:, scheduler:)` → store `mountTree`.

### Rerender callback

Called by `SyncScheduler.flush()` once per dirty `AnyComponent`:

```swift
func rerender(_ component: AnyComponent) {
    if ObjectIdentifier(component.instance) == ObjectIdentifier(rootInstance) {
        // Root: re-diff from the top
        let result = diff(mounted: mountTree, next: rootInstance.body,
                          handles: handles, handlers: handlers, scheduler: scheduler)
        mountTree = result.newMountTree
    } else {
        // Nested component anchor (e.g. Toast, SignIn)
        guard let node = findComponentNode(component, in: mountTree) else { return }
        let result = diff(mounted: node.componentBody, next: component.instance.body,
                          handles: handles, handlers: handlers, scheduler: scheduler)
        node.componentBody = result.newMountTree
    }
}
```

### Tree-walk helpers (internal)

**`findComponentNode(_:in:)`** — locates the `MountNode` whose `component.instance` matches by identity. Recurses into `children` for element nodes and into `componentBody` for component anchors.

**`textContent(of:)`** — concatenates all `.text` VNode strings depth-first. For element nodes, joins children's text. For component anchors, delegates to `componentBody`.

**`findElements(tag:text:in:)`** — collects `(MountNode, ElementData)` pairs where `data.tag == tag` and (if `text != nil`) `textContent(of: node).contains(text!)`. Used by `find`, `findAll`, `exists`, and the interaction methods.

### Event dispatch sequence

For `click("button", text: "Increment")`:
1. `findElements(tag: "button", text: "Increment", in: mountTree)` → first match.
2. `node.handlerIds["click"]` → handler ID.
3. `handlers.dispatch(id: handlerID, event: EventInfo(type: "click"))`.
4. `scheduler.flush()` → rerender callback fires for each dirty component → `mountTree` updated.

For `input(at: 1, value: "secret")`:
1. `findElements(tag: "input", text: nil, in: mountTree)` → `[...]`, take index 1.
2. `node.handlerIds["input"]` → handler ID.
3. `handlers.dispatch(id: handlerID, event: EventInfo(type: "input", targetValue: "secret"))`.
4. `scheduler.flush()`.

For `blur(at: 0)`:
1. Same as `input` but event name `"blur"` and no `targetValue`.

All three are no-ops when no matching handler is found — no precondition failure, no throw.

---

## Section 6 — Testing strategy

Tests in `Tests/SwiflowTestingTests/TestHarnessTests.swift`. Components under test are defined inline; no WASM build required.

### Counter suite

```swift
// Initial state
let r = render(Counter())
#expect(r.find("p", text: "Count: 0") != nil)
#expect(r.find("h1", text: "Hello, Swiflow!") != nil)

// Click increments count
r.click("button", text: "Increment")
#expect(r.find("p", text: "Count: 1") != nil)
#expect(r.find("p", text: "Count: 0") == nil)

// Multiple clicks
r.click("button", text: "Increment")
r.click("button", text: "Increment")
#expect(r.find("p", text: "Count: 3") != nil)
```

### Conditional rendering (Toast)

```swift
let r = render(Counter())
#expect(r.exists("div", text: "Saved!") == false)
r.click("button", text: "Show toast")
#expect(r.exists("div", text: "Saved!"))
```

### Two-way input binding

```swift
let r = render(Counter())
#expect(r.find("h1", text: "Hello, Swiflow!") != nil)
r.input(value: "World")
#expect(r.find("h1", text: "Hello, World!") != nil)
```

### `allText` smoke test

```swift
let r = render(Counter())
#expect(r.allText.contains("Count: 0"))
#expect(r.allText.contains("Hello, Swiflow!"))
```

### Form validation (SignIn)

```swift
let r = render(SignIn())

// Untouched — no errors shown
#expect(r.exists("p", text: "Required") == false)

// Email field: invalid, touched
r.input(at: 0, value: "notanemail")
r.blur(at: 0)
#expect(r.find("p", text: "Invalid email address") != nil)

// Email field: valid
r.input(at: 0, value: "good@test.com")
r.blur(at: 0)
#expect(r.find("p", text: "Invalid email address") == nil)

// Password field: too short
r.input(at: 1, value: "short")
r.blur(at: 1)
#expect(r.find("p", text: "Must be at least 8 characters") != nil)

// Password valid — form becomes submittable
r.input(at: 1, value: "secret99")
r.blur(at: 1)
#expect(r.exists("p", text: "Must be at least") == false)

// Submit — touchAll fires, guard passes, state flips
r.click("button", text: "Sign In")
#expect(r.find("p", text: "Signed in as good@test.com!") != nil)

// Reset
r.click("button", text: "Sign out")
#expect(r.find("h2", text: "Sign In") != nil)
```

### `findAll` + index

```swift
let r = render(Counter())
let buttons = r.findAll("button")
#expect(buttons.count >= 2)
#expect(buttons[0].text == "Increment")
```

---

## Section 7 — Design decisions

| Question | Decision |
|---|---|
| Sync vs async | Synchronous (`SyncScheduler`). Async deferred to pre-1.0. |
| Query model | Tag + optional text filter. RTL-style: find by what the user sees. |
| Assertion model | Return `TestNode?` / `[TestNode]`; caller uses `#expect`. No built-in assertions. |
| `input`/`blur` addressing | `at: Int` index (not text, since inputs have no text content). |
| Root component in mount tree | Root is NOT a component anchor — its `body` is diffed directly. Root re-renders re-diff from `mountTree` root. |
| Nested components | ARE component anchors in the tree. Rerender finds anchor by `ObjectIdentifier(instance)`, re-diffs `componentBody`. |
| No-op on missing handler | Interactions are silent no-ops when target has no handler for the event. No throw, no precondition. |
| `package` access | `SwiflowTesting` uses `package` access to `HandlerRegistry`, `diff`, `wireState` — same pattern as `SwiflowWeb`. |
