# Phase 13a — SwiflowTesting Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a pure-Swift headless `SwiflowTesting` module that lets components be exercised with `render()` + query + `#expect` — no WASM build, no browser, no JavaScriptKit.

**Architecture:** A new `SwiflowTesting` library target (depends only on `Swiflow`) with three files: `TestingModifiers.swift` (ambient handler registry + `.on()` extensions), `TestRenderer.swift` (headless diff engine), and `TestHarness.swift` (public `render()` + query/interaction API). The module uses `package` access to `HandlerRegistry`, `diff`, and `wireState`. Because SwiflowWeb's `.on()` modifier is gated on `#if canImport(JavaScriptKit)`, `SwiflowTesting` provides its own `.on()` overloads backed by a `@MainActor` module-level `_testAmbientHandlers` registry that `TestRenderer` sets before every diff and clears after.

**Tech Stack:** Swift 6, Swift Testing (`@Suite`, `@Test`, `#expect`), `SyncScheduler` (already in `Sources/Swiflow/Reactivity/Scheduler.swift`).

---

## File map

| File | Change |
|---|---|
| `Package.swift` | Add `SwiflowTesting` library product; add `SwiflowTesting` and `SwiflowTestingTests` targets |
| `Sources/Swiflow/Reactivity/Component.swift:136` | `func wireState` → `package func wireState` (one word) |
| `Sources/SwiflowTesting/TestingModifiers.swift` | New: `_testAmbientHandlers` + `.on()` extensions on `VNode` and `Attribute` |
| `Sources/SwiflowTesting/TestRenderer.swift` | New: `RerenderRelay`, `TestRenderer` class, `textContent`, `findElements`, `findComponentNode`, interaction helpers |
| `Sources/SwiflowTesting/TestHarness.swift` | New: `render<C>(_:)` free function, `TestNode` struct, `TestHarness` public API |
| `Tests/SwiflowTestingTests/TestHarnessTests.swift` | New: all test suites + inline `Counter` and `SignIn` components |

---

### Task 1: Package.swift + module scaffold + `wireState` access

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/Swiflow/Reactivity/Component.swift:136`
- Create: `Sources/SwiflowTesting/TestingModifiers.swift`
- Create: `Sources/SwiflowTesting/TestRenderer.swift`
- Create: `Sources/SwiflowTesting/TestHarness.swift`
- Create: `Tests/SwiflowTestingTests/TestHarnessTests.swift`

- [ ] **Step 1: Add `SwiflowTesting` product to `Package.swift`**

  In the `products:` array, after the `SwiflowRouter` product, add:

  ```swift
  .library(name: "SwiflowTesting", targets: ["SwiflowTesting"]),
  ```

- [ ] **Step 2: Add `SwiflowTesting` and `SwiflowTestingTests` targets to `Package.swift`**

  In the `targets:` array, before the first `.testTarget`, add:

  ```swift
  .target(
      name: "SwiflowTesting",
      dependencies: ["Swiflow"],
      path: "Sources/SwiflowTesting",
      swiftSettings: [.swiftLanguageMode(.v6)]
  ),
  ```

  After all existing test targets, add:

  ```swift
  .testTarget(
      name: "SwiflowTestingTests",
      dependencies: ["SwiflowTesting", "Swiflow"],
      path: "Tests/SwiflowTestingTests",
      swiftSettings: [.swiftLanguageMode(.v6)]
  ),
  ```

- [ ] **Step 3: Make `wireState` package-accessible**

  In `Sources/Swiflow/Reactivity/Component.swift`, line 136, change:

  ```swift
  func wireState(on owner: AnyComponent, scheduler: Scheduler?) {
  ```

  to:

  ```swift
  package func wireState(on owner: AnyComponent, scheduler: Scheduler?) {
  ```

  `SwiflowTesting` is in the same `Package.swift`, so `package` access is sufficient. Only this one line changes — `wireStateAndRestore` stays `internal` (it is only called by `wireState` and `diff`, both within `Swiflow`).

- [ ] **Step 4: Create `Sources/SwiflowTesting/TestingModifiers.swift`**

  `SwiflowWeb`'s `.on()` is gated on `#if canImport(JavaScriptKit)`. Test components need their own `.on()` overloads backed by an ambient handler registry that `TestRenderer` controls.

  ```swift
  // Sources/SwiflowTesting/TestingModifiers.swift
  import Swiflow

  /// Set by `TestRenderer` before every `diff` call; cleared after.
  /// Provides `.on()` extensions with the same signature as SwiflowWeb,
  /// so test components can register handlers without importing JavaScriptKit.
  @MainActor
  var _testAmbientHandlers: HandlerRegistry? = nil

  public extension Attribute {
      @MainActor
      static func on(
          _ event: Event,
          perform action: @escaping @MainActor () -> Void
      ) -> Attribute {
          guard let registry = _testAmbientHandlers else { return .skip }
          let h = registry.register { _ in MainActor.assumeIsolated { action() } }
          return .handler(event: event.domName, value: h)
      }

      @MainActor
      static func on(
          _ event: Event,
          perform action: @escaping @MainActor (EventInfo) -> Void
      ) -> Attribute {
          guard let registry = _testAmbientHandlers else { return .skip }
          let h = registry.register { info in MainActor.assumeIsolated { action(info) } }
          return .handler(event: event.domName, value: h)
      }
  }

  public extension VNode {
      @MainActor
      func on(
          _ event: Event,
          perform action: @escaping @MainActor () -> Void
      ) -> VNode {
          guard case .element(var data) = self,
                let registry = _testAmbientHandlers else { return self }
          data.handlers[event.domName] = registry.register { _ in
              MainActor.assumeIsolated { action() }
          }
          return .element(data)
      }

      @MainActor
      func on(
          _ event: Event,
          perform action: @escaping @MainActor (EventInfo) -> Void
      ) -> VNode {
          guard case .element(var data) = self,
                let registry = _testAmbientHandlers else { return self }
          data.handlers[event.domName] = registry.register { info in
              MainActor.assumeIsolated { action(info) }
          }
          return .element(data)
      }
  }
  ```

- [ ] **Step 5: Create stub `Sources/SwiflowTesting/TestRenderer.swift`**

  ```swift
  // Sources/SwiflowTesting/TestRenderer.swift
  import Swiflow

  private final class RerenderRelay: @unchecked Sendable {
      weak var owner: TestRenderer?
  }

  @MainActor
  final class TestRenderer {
      var mountTree: MountNode
      let handles: HandleAllocator
      let handlers: HandlerRegistry
      let scheduler: SyncScheduler
      let rootInstance: any Component
      let rootID: ObjectIdentifier

      init<C: Component>(_ instance: C) {
          fatalError("implemented in Task 2")
      }
  }
  ```

- [ ] **Step 6: Create stub `Sources/SwiflowTesting/TestHarness.swift`**

  ```swift
  // Sources/SwiflowTesting/TestHarness.swift
  import Swiflow

  /// A snapshot of a single element node. Assert against its fields with `#expect`.
  public struct TestNode {
      public let tag: String
      public let text: String
      public let attributes: [String: String]
      public let properties: [String: PropertyValue]
  }

  /// Renders `component` into a headless virtual DOM and returns a `TestHarness`.
  @MainActor
  public func render<C: Component>(_ component: C) -> TestHarness {
      TestHarness(TestRenderer(component))
  }

  /// Wraps a `TestRenderer` and exposes the public query + interaction API.
  @MainActor
  public struct TestHarness {
      let renderer: TestRenderer

      init(_ renderer: TestRenderer) {
          self.renderer = renderer
      }
  }
  ```

- [ ] **Step 7: Create minimal `Tests/SwiflowTestingTests/TestHarnessTests.swift`**

  ```swift
  // Tests/SwiflowTestingTests/TestHarnessTests.swift
  import Testing
  @testable import SwiflowTesting
  import Swiflow

  // Minimal inline component used by Task 2 tests.
  // Expanded to full Counter + SignIn in Task 5.
  @MainActor
  private final class MinimalCounter: Component {
      @State var count: Int = 0
      var body: VNode { p("Count: \(count)") }
  }
  ```

- [ ] **Step 8: Confirm the module compiles**

  ```bash
  swift build --target SwiflowTesting
  ```

  Expected: BUILD SUCCEEDED (the `TestRenderer.init` fatalError is fine at this stage).

  ```bash
  swift build --target SwiflowTestingTests 2>&1 | head -20
  ```

  Expected: BUILD SUCCEEDED (no tests run yet, just compilation).

- [ ] **Step 9: Commit**

  ```bash
  git add Package.swift \
      Sources/Swiflow/Reactivity/Component.swift \
      Sources/SwiflowTesting/ \
      Tests/SwiflowTestingTests/
  git commit -m "feat(testing): scaffold SwiflowTesting module + wireState package access"
  ```

---

### Task 2: `TestRenderer` init + rerender + `TestHarness.allText` (TDD)

**Files:**
- Modify: `Sources/SwiflowTesting/TestRenderer.swift`
- Modify: `Sources/SwiflowTesting/TestHarness.swift`
- Modify: `Tests/SwiflowTestingTests/TestHarnessTests.swift`

- [ ] **Step 1: Write the failing test**

  Add to `Tests/SwiflowTestingTests/TestHarnessTests.swift`:

  ```swift
  @Suite("TestHarness — allText")
  @MainActor
  struct AllTextTests {
      @Test("allText includes initial state")
      func allTextInitial() {
          let r = render(MinimalCounter())
          #expect(r.allText.contains("Count: 0"))
      }
  }
  ```

- [ ] **Step 2: Run and confirm failure**

  ```bash
  swift test --filter "allText includes initial state" 2>&1 | tail -20
  ```

  Expected: FAIL — `fatalError("implemented in Task 2")` crashes.

- [ ] **Step 3: Implement `TestRenderer.init` and supporting internals**

  Replace the entire `Sources/SwiflowTesting/TestRenderer.swift` with:

  ```swift
  // Sources/SwiflowTesting/TestRenderer.swift
  import Swiflow

  private final class RerenderRelay: @unchecked Sendable {
      weak var owner: TestRenderer?
  }

  @MainActor
  final class TestRenderer {
      var mountTree: MountNode
      let handles: HandleAllocator
      let handlers: HandlerRegistry
      let scheduler: SyncScheduler
      let rootInstance: any Component
      let rootID: ObjectIdentifier

      init<C: Component>(_ instance: C) {
          let relay = RerenderRelay()
          self.handles = HandleAllocator()
          self.handlers = HandlerRegistry()
          self.rootInstance = instance
          self.rootID = ObjectIdentifier(instance)
          self.scheduler = SyncScheduler { [relay] component in
              MainActor.assumeIsolated { relay.owner?.rerender(component) }
          }
          let any = AnyComponent(instance)
          wireState(on: any, scheduler: self.scheduler)
          _testAmbientHandlers = self.handlers
          let result = diff(
              mounted: nil,
              next: instance.body,
              handles: self.handles,
              handlers: self.handlers,
              scheduler: self.scheduler
          )
          _testAmbientHandlers = nil
          self.mountTree = result.newMountTree
          relay.owner = self
      }

      func rerender(_ component: AnyComponent) {
          _testAmbientHandlers = self.handlers
          if ObjectIdentifier(component.instance) == rootID {
              let result = diff(
                  mounted: mountTree,
                  next: rootInstance.body,
                  handles: handles,
                  handlers: handlers,
                  scheduler: scheduler
              )
              mountTree = result.newMountTree
          } else if let node = findComponentNode(component, in: mountTree) {
              let result = diff(
                  mounted: node.componentBody,
                  next: component.instance.body,
                  handles: handles,
                  handlers: handlers,
                  scheduler: scheduler
              )
              node.componentBody = result.newMountTree
          }
          _testAmbientHandlers = nil
      }

      func textContent(of node: MountNode) -> String {
          switch node.vnode {
          case .text(let s):
              return s
          case .element:
              return node.children.map { textContent(of: $0) }.joined()
          case .component:
              return node.componentBody.map { textContent(of: $0) } ?? ""
          default:
              return ""
          }
      }

      var allText: String { textContent(of: mountTree) }

      func findElements(
          tag: String,
          text: String?,
          in node: MountNode
      ) -> [(MountNode, ElementData)] {
          fatalError("implemented in Task 3")
      }

      func findComponentNode(
          _ component: AnyComponent,
          in node: MountNode
      ) -> MountNode? {
          fatalError("implemented in Task 4")
      }
  }
  ```

  Note: `ObjectIdentifier(instance)` works because `Component: AnyObject`. No `as AnyObject` cast needed.

  Note: `diff` has `environment: EnvironmentValues = .init()` as a defaulted parameter — omit it here; the default is correct for headless rendering.

- [ ] **Step 4: Add `allText` to `TestHarness`**

  Add to `TestHarness` in `Sources/SwiflowTesting/TestHarness.swift`:

  ```swift
  /// All text content in the rendered tree, concatenated depth-first.
  public var allText: String { renderer.allText }
  ```

- [ ] **Step 5: Run the test and confirm it passes**

  ```bash
  swift test --filter "allText includes initial state"
  ```

  Expected: PASS.

- [ ] **Step 6: Run the full test suite to check for regressions**

  ```bash
  swift test --skip DevCommandTests --skip BuildCommandTests
  ```

  Expected: all existing tests pass, plus the new `allTextInitial` test. If any other test fails, fix it before proceeding.

- [ ] **Step 7: Commit**

  ```bash
  git add Sources/SwiflowTesting/ Tests/SwiflowTestingTests/
  git commit -m "feat(testing): TestRenderer init + rerender + allText"
  ```

---

### Task 3: `TestNode` + `find` / `findAll` / `exists` queries (TDD)

**Files:**
- Modify: `Sources/SwiflowTesting/TestRenderer.swift`
- Modify: `Sources/SwiflowTesting/TestHarness.swift`
- Modify: `Tests/SwiflowTestingTests/TestHarnessTests.swift`

- [ ] **Step 1: Write the failing tests**

  Add to `Tests/SwiflowTestingTests/TestHarnessTests.swift`:

  ```swift
  @Suite("TestHarness — queries")
  @MainActor
  struct QueryTests {
      @Test("find returns the first matching element with correct fields")
      func findReturnsFirstMatch() {
          let r = render(MinimalCounter())
          let node = r.find("p", text: "Count: 0")
          #expect(node != nil)
          #expect(node?.tag == "p")
          #expect(node?.text == "Count: 0")
      }

      @Test("find returns nil when no match")
      func findReturnsNil() {
          let r = render(MinimalCounter())
          #expect(r.find("p", text: "Count: 99") == nil)
          #expect(r.find("h1") == nil)
      }

      @Test("find without text matches first element with that tag")
      func findByTagOnly() {
          let r = render(MinimalCounter())
          let node = r.find("p")
          #expect(node != nil)
          #expect(node?.tag == "p")
      }

      @Test("findAll returns all matching elements")
      func findAllReturnsAll() {
          // MinimalCounter has one <p>; after expanding, Counter has buttons too.
          let r = render(MinimalCounter())
          let ps = r.findAll("p")
          #expect(ps.count == 1)
          #expect(ps[0].text == "Count: 0")
      }

      @Test("exists returns true iff at least one match")
      func existsReturnsTrueAndFalse() {
          let r = render(MinimalCounter())
          #expect(r.exists("p", text: "Count: 0") == true)
          #expect(r.exists("p", text: "Count: 99") == false)
          #expect(r.exists("button") == false)
      }
  }
  ```

- [ ] **Step 2: Run and confirm failures**

  ```bash
  swift test --filter "TestHarness — queries" 2>&1 | tail -30
  ```

  Expected: FAIL — `find`, `findAll`, `exists` are not yet implemented on `TestHarness`; `findElements` fatalErrors in `TestRenderer`.

- [ ] **Step 3: Implement `findElements` in `TestRenderer`**

  Replace the `findElements` stub in `TestRenderer.swift`:

  ```swift
  func findElements(
      tag: String,
      text: String?,
      in node: MountNode
  ) -> [(MountNode, ElementData)] {
      var results: [(MountNode, ElementData)] = []
      switch node.vnode {
      case .element(let data):
          if data.tag == tag {
              let t = textContent(of: node)
              if text == nil || t.contains(text!) {
                  results.append((node, data))
              }
          }
          for child in node.children {
              results += findElements(tag: tag, text: text, in: child)
          }
      case .component:
          if let body = node.componentBody {
              results += findElements(tag: tag, text: text, in: body)
          }
      default:
          break
      }
      return results
  }
  ```

- [ ] **Step 4: Add `find`, `findAll`, `exists` to `TestHarness`**

  Add to `TestHarness` in `Sources/SwiflowTesting/TestHarness.swift`:

  ```swift
  /// Returns the first element matching `tag` (and `text`, if supplied).
  /// `text` matches when the element's subtree text content contains the string.
  public func find(_ tag: String, text: String? = nil) -> TestNode? {
      guard let (node, data) = renderer.findElements(tag: tag, text: text,
                                                     in: renderer.mountTree).first
      else { return nil }
      return TestNode(
          tag: data.tag,
          text: renderer.textContent(of: node),
          attributes: data.attributes,
          properties: data.properties
      )
  }

  /// Returns all elements matching `tag` and optional `text`, in document order.
  public func findAll(_ tag: String, text: String? = nil) -> [TestNode] {
      renderer.findElements(tag: tag, text: text, in: renderer.mountTree).map { (node, data) in
          TestNode(
              tag: data.tag,
              text: renderer.textContent(of: node),
              attributes: data.attributes,
              properties: data.properties
          )
      }
  }

  /// True iff at least one element matches `tag` and optional `text`.
  public func exists(_ tag: String, text: String? = nil) -> Bool {
      !renderer.findElements(tag: tag, text: text, in: renderer.mountTree).isEmpty
  }
  ```

- [ ] **Step 5: Run the tests and confirm they pass**

  ```bash
  swift test --filter "TestHarness — queries"
  ```

  Expected: all 5 query tests PASS.

- [ ] **Step 6: Run full suite for regressions**

  ```bash
  swift test --skip DevCommandTests --skip BuildCommandTests
  ```

  Expected: all pass.

- [ ] **Step 7: Commit**

  ```bash
  git add Sources/SwiflowTesting/ Tests/SwiflowTestingTests/
  git commit -m "feat(testing): TestNode + find/findAll/exists queries"
  ```

---

### Task 4: `click` / `input` / `blur` interactions (TDD)

**Files:**
- Modify: `Sources/SwiflowTesting/TestRenderer.swift`
- Modify: `Sources/SwiflowTesting/TestHarness.swift`
- Modify: `Tests/SwiflowTestingTests/TestHarnessTests.swift`

The inline `MinimalCounter` lacks buttons and input handlers. Expand it for this task.

- [ ] **Step 1: Expand the inline `MinimalCounter` in the test file**

  Replace `MinimalCounter` in `TestHarnessTests.swift` with:

  ```swift
  @MainActor
  private final class MinimalCounter: Component {
      @State var count: Int = 0
      @State var label: String = "Swiflow"

      var body: VNode {
          div {
              p("Count: \(count)")
              button("Increment", .on(.click) { self.count += 1 })
              input(.attr("type", "text"),
                    .on(.input) { info in self.label = info.targetValue ?? self.label })
              p("Hello, \(label)!")
          }
      }
  }
  ```

- [ ] **Step 2: Write the failing interaction tests**

  Add to `Tests/SwiflowTestingTests/TestHarnessTests.swift`:

  ```swift
  @Suite("TestHarness — interactions")
  @MainActor
  struct InteractionTests {
      @Test("click fires the handler and state updates")
      func clickIncrementsCount() {
          let r = render(MinimalCounter())
          #expect(r.find("p", text: "Count: 0") != nil)
          r.click("button", text: "Increment")
          #expect(r.find("p", text: "Count: 1") != nil)
          #expect(r.find("p", text: "Count: 0") == nil)
      }

      @Test("multiple clicks accumulate")
      func multipleClicks() {
          let r = render(MinimalCounter())
          r.click("button", text: "Increment")
          r.click("button", text: "Increment")
          r.click("button", text: "Increment")
          #expect(r.find("p", text: "Count: 3") != nil)
      }

      @Test("input fires the input handler and state updates")
      func inputUpdatesLabel() {
          let r = render(MinimalCounter())
          #expect(r.find("p", text: "Hello, Swiflow!") != nil)
          r.input(value: "World")
          #expect(r.find("p", text: "Hello, World!") != nil)
          #expect(r.find("p", text: "Hello, Swiflow!") == nil)
      }

      @Test("click is a no-op when no handler is registered")
      func clickNoHandlerIsNoOp() {
          let r = render(MinimalCounter())
          r.click("p")     // <p> has no click handler — must not crash
          #expect(r.find("p", text: "Count: 0") != nil)
      }

      @Test("input at out-of-bounds index is a no-op")
      func inputOutOfBoundsIsNoOp() {
          let r = render(MinimalCounter())
          r.input(at: 99, value: "boom")   // no crash
          #expect(r.find("p", text: "Hello, Swiflow!") != nil)
      }
  }
  ```

- [ ] **Step 3: Run and confirm failures**

  ```bash
  swift test --filter "TestHarness — interactions" 2>&1 | tail -30
  ```

  Expected: FAIL — `click`, `input`, `blur` are not implemented and `findComponentNode` fatalErrors.

- [ ] **Step 4: Implement `findComponentNode` in `TestRenderer`**

  Replace the `findComponentNode` stub:

  ```swift
  func findComponentNode(
      _ component: AnyComponent,
      in node: MountNode
  ) -> MountNode? {
      if let c = node.component,
         ObjectIdentifier(c.instance) == ObjectIdentifier(component.instance) {
          return node
      }
      for child in node.children {
          if let found = findComponentNode(component, in: child) { return found }
      }
      if let body = node.componentBody {
          return findComponentNode(component, in: body)
      }
      return nil
  }
  ```

- [ ] **Step 5: Implement interaction helpers in `TestRenderer`**

  Add to `TestRenderer`:

  ```swift
  func click(tag: String, text: String?) {
      let matches = findElements(tag: tag, text: text, in: mountTree)
      guard let (node, _) = matches.first,
            let id = node.handlerIds["click"] else { return }
      handlers.dispatch(id: id, event: EventInfo(type: "click"))
      scheduler.flush()
  }

  func input(tag: String, at index: Int, value: String) {
      let matches = findElements(tag: tag, text: nil, in: mountTree)
      guard index < matches.count else { return }
      let (node, _) = matches[index]
      guard let id = node.handlerIds["input"] else { return }
      handlers.dispatch(id: id, event: EventInfo(type: "input", targetValue: value))
      scheduler.flush()
  }

  func blur(tag: String, at index: Int) {
      let matches = findElements(tag: tag, text: nil, in: mountTree)
      guard index < matches.count else { return }
      let (node, _) = matches[index]
      guard let id = node.handlerIds["blur"] else { return }
      handlers.dispatch(id: id, event: EventInfo(type: "blur"))
      scheduler.flush()
  }
  ```

- [ ] **Step 6: Add `click`, `input`, `blur` to `TestHarness`**

  Add to `TestHarness` in `Sources/SwiflowTesting/TestHarness.swift`:

  ```swift
  /// Fires a `click` event on the first element matching `tag` (and `text`).
  /// No-op if no matching element has a click handler.
  public func click(_ tag: String, text: String? = nil) {
      renderer.click(tag: tag, text: text)
  }

  /// Fires an `input` event on the element at position `index` among all
  /// elements matching `tag` (default `"input"`). No-op if out-of-bounds
  /// or if the element has no `input` handler.
  public func input(_ tag: String = "input", at index: Int = 0, value: String) {
      renderer.input(tag: tag, at: index, value: value)
  }

  /// Fires a `blur` event on the element at position `index` among all
  /// elements matching `tag` (default `"input"`). No-op if out-of-bounds
  /// or if the element has no `blur` handler.
  public func blur(_ tag: String = "input", at index: Int = 0) {
      renderer.blur(tag: tag, at: index)
  }
  ```

- [ ] **Step 7: Run the interaction tests**

  ```bash
  swift test --filter "TestHarness — interactions"
  ```

  Expected: all 5 interaction tests PASS.

- [ ] **Step 8: Run full suite for regressions**

  ```bash
  swift test --skip DevCommandTests --skip BuildCommandTests
  ```

  Expected: all pass.

- [ ] **Step 9: Commit**

  ```bash
  git add Sources/SwiflowTesting/ Tests/SwiflowTestingTests/
  git commit -m "feat(testing): click/input/blur interactions + findComponentNode"
  ```

---

### Task 5: Full inline Counter + SignIn test suite

**Files:**
- Modify: `Tests/SwiflowTestingTests/TestHarnessTests.swift`

This task writes all the spec test cases from the design document. The inline `Counter` replaces `MinimalCounter`. `SignIn` is added. Both components use only `Swiflow` APIs — `.on()` from `SwiflowTesting`'s `TestingModifiers.swift`, no `SwiflowWeb`.

- [ ] **Step 1: Replace `MinimalCounter` with the full inline `Counter`**

  Replace the `MinimalCounter` definition at the top of `TestHarnessTests.swift` with the full `Counter` that covers all spec test cases:

  ```swift
  @MainActor
  private final class Counter: Component {
      @State var count: Int = 0
      @State var name: String = "Swiflow"
      @State var showToast: Bool = false

      var body: VNode {
          div {
              h1("Hello, \(name)!")
              p("Count: \(count)")
              button("Increment", .on(.click) { self.count += 1 })
              button("Show toast", .on(.click) { self.showToast = true })
              if showToast { div { text("Saved!") } }
              input(.attr("type", "text"),
                    .on(.input) { info in self.name = info.targetValue ?? self.name })
          }
      }
  }
  ```

  Also add the inline `SignIn`:

  ```swift
  @MainActor
  private final class SignIn: Component {
      @State var email: String = ""
      @State var password: String = ""
      @State var emailTouched: Bool = false
      @State var passwordTouched: Bool = false
      @State var isSignedIn: Bool = false

      var emailError: String? {
          guard emailTouched, !email.isEmpty else { return nil }
          return email.contains("@") ? nil : "Invalid email address"
      }

      var passwordError: String? {
          guard passwordTouched, !password.isEmpty else { return nil }
          return password.count >= 8 ? nil : "Must be at least 8 characters"
      }

      var body: VNode {
          div {
              if isSignedIn {
                  p("Signed in as \(email)!")
                  button("Sign out", .on(.click) {
                      self.isSignedIn = false
                      self.email = ""
                      self.password = ""
                      self.emailTouched = false
                      self.passwordTouched = false
                  })
              } else {
                  h2("Sign In")
                  input(.attr("type", "email"),
                        .on(.input) { info in self.email = info.targetValue ?? self.email },
                        .on(.blur) { self.emailTouched = true })
                  if let err = emailError { p(err) }
                  input(.attr("type", "password"),
                        .on(.input) { info in self.password = info.targetValue ?? self.password },
                        .on(.blur) { self.passwordTouched = true })
                  if let err = passwordError { p(err) }
                  button("Sign In", .on(.click) {
                      self.emailTouched = true
                      self.passwordTouched = true
                      guard self.emailError == nil, self.passwordError == nil,
                            !self.email.isEmpty, !self.password.isEmpty else { return }
                      self.isSignedIn = true
                  })
              }
          }
      }
  }
  ```

- [ ] **Step 2: Update the existing `QueryTests` and `InteractionTests` to use `Counter`**

  In `QueryTests` and `InteractionTests`, replace `MinimalCounter()` with `Counter()` where appropriate. The `Counter` has `p`, `h1`, `button`, and `input` elements, so the existing assertions still hold (add text qualifiers where needed now that there are two `<p>` elements):

  - `r.find("p", text: "Count: 0")` — still works (finds the count paragraph)
  - `r.find("p", text: "Count: 99") == nil` — still works
  - `r.find("p")` — still works (finds first `<p>`)
  - `r.findAll("p")` — now returns 2 (count + Hello); update `#expect(ps.count == 2)` and add:
    ```swift
    #expect(ps[0].text == "Count: 0")
    #expect(ps[1].text == "Hello, Swiflow!")
    ```
  - `r.exists("p", text: "Count: 0")` — still works
  - `r.exists("button")` → now true (Counter has buttons); update to `#expect(r.exists("button") == true)`
  - Interaction tests: `r.click("button", text: "Increment")` — correct (text disambiguates)
  - `r.input(value: "World")` — correct (first input in Counter)

- [ ] **Step 3: Write the Counter spec test suite**

  Add to `Tests/SwiflowTestingTests/TestHarnessTests.swift`:

  ```swift
  @Suite("Counter — spec test cases")
  @MainActor
  struct CounterSpecTests {
      @Test("initial state")
      func initialState() {
          let r = render(Counter())
          #expect(r.find("p", text: "Count: 0") != nil)
          #expect(r.find("h1", text: "Hello, Swiflow!") != nil)
      }

      @Test("click increments count")
      func clickIncrements() {
          let r = render(Counter())
          r.click("button", text: "Increment")
          #expect(r.find("p", text: "Count: 1") != nil)
          #expect(r.find("p", text: "Count: 0") == nil)
      }

      @Test("three clicks reach count 3")
      func threeClicks() {
          let r = render(Counter())
          r.click("button", text: "Increment")
          r.click("button", text: "Increment")
          r.click("button", text: "Increment")
          #expect(r.find("p", text: "Count: 3") != nil)
      }

      @Test("conditional toast rendering")
      func toastConditional() {
          let r = render(Counter())
          #expect(r.exists("div", text: "Saved!") == false)
          r.click("button", text: "Show toast")
          #expect(r.exists("div", text: "Saved!"))
      }

      @Test("two-way input binding updates greeting")
      func inputBinding() {
          let r = render(Counter())
          #expect(r.find("h1", text: "Hello, Swiflow!") != nil)
          r.input(value: "World")
          #expect(r.find("h1", text: "Hello, World!") != nil)
      }

      @Test("allText contains all visible text")
      func allTextSmoke() {
          let r = render(Counter())
          #expect(r.allText.contains("Count: 0"))
          #expect(r.allText.contains("Hello, Swiflow!"))
      }

      @Test("findAll returns buttons in document order")
      func findAllButtons() {
          let r = render(Counter())
          let buttons = r.findAll("button")
          #expect(buttons.count >= 2)
          #expect(buttons[0].text == "Increment")
          #expect(buttons[1].text == "Show toast")
      }
  }
  ```

- [ ] **Step 4: Write the SignIn spec test suite**

  Add to `Tests/SwiflowTestingTests/TestHarnessTests.swift`:

  ```swift
  @Suite("SignIn — form validation spec cases")
  @MainActor
  struct SignInSpecTests {
      @Test("untouched form shows no errors")
      func untouchedNoErrors() {
          let r = render(SignIn())
          #expect(r.exists("p", text: "Required") == false)
          #expect(r.exists("p", text: "Invalid email") == false)
          #expect(r.exists("p", text: "Must be at least") == false)
      }

      @Test("invalid email after touch shows error")
      func invalidEmailShowsError() {
          let r = render(SignIn())
          r.input(at: 0, value: "notanemail")
          r.blur(at: 0)
          #expect(r.find("p", text: "Invalid email address") != nil)
      }

      @Test("valid email clears email error")
      func validEmailClearsError() {
          let r = render(SignIn())
          r.input(at: 0, value: "notanemail")
          r.blur(at: 0)
          r.input(at: 0, value: "good@test.com")
          r.blur(at: 0)
          #expect(r.find("p", text: "Invalid email address") == nil)
      }

      @Test("short password after touch shows error")
      func shortPasswordShowsError() {
          let r = render(SignIn())
          r.input(at: 1, value: "short")
          r.blur(at: 1)
          #expect(r.find("p", text: "Must be at least 8 characters") != nil)
      }

      @Test("valid password clears password error")
      func validPasswordClearsError() {
          let r = render(SignIn())
          r.input(at: 1, value: "short")
          r.blur(at: 1)
          r.input(at: 1, value: "secret99")
          r.blur(at: 1)
          #expect(r.exists("p", text: "Must be at least") == false)
      }

      @Test("submit with valid credentials signs in")
      func submitSignsIn() {
          let r = render(SignIn())
          r.input(at: 0, value: "good@test.com")
          r.blur(at: 0)
          r.input(at: 1, value: "secret99")
          r.blur(at: 1)
          r.click("button", text: "Sign In")
          #expect(r.find("p", text: "Signed in as good@test.com!") != nil)
      }

      @Test("sign out returns to sign-in form")
      func signOutReturnsToForm() {
          let r = render(SignIn())
          r.input(at: 0, value: "good@test.com")
          r.blur(at: 0)
          r.input(at: 1, value: "secret99")
          r.blur(at: 1)
          r.click("button", text: "Sign In")
          r.click("button", text: "Sign out")
          #expect(r.find("h2", text: "Sign In") != nil)
      }

      @Test("submit with invalid inputs does not sign in")
      func submitInvalidDoesNothing() {
          let r = render(SignIn())
          r.click("button", text: "Sign In")   // both fields empty
          #expect(r.find("h2", text: "Sign In") != nil)
          #expect(r.find("p", text: "Signed in as") == nil)
      }
  }
  ```

- [ ] **Step 5: Run only the new spec suites**

  ```bash
  swift test --filter "Counter — spec"
  ```

  Expected: all 7 Counter spec tests PASS.

  ```bash
  swift test --filter "SignIn — form"
  ```

  Expected: all 8 SignIn spec tests PASS. If any fail, debug before proceeding.

  Common failure mode: the `SignIn.emailError` check `email.contains("@")` is too simple — `"notanemail"` has no `@`, so error IS shown. `"good@test.com"` has `@`, so error is nil. This should be correct. If `blur(at: 1)` is dispatching to the wrong index, add a `print` statement or inspect `findElements` output.

- [ ] **Step 6: Run the complete test suite**

  ```bash
  swift test --skip DevCommandTests --skip BuildCommandTests
  ```

  Expected: all tests pass (previous count + 15+ new tests). Check that no regressions appeared in `SwiflowTests`, `SwiflowCLITests`, or `SwiflowRouterTests`.

- [ ] **Step 7: Commit**

  ```bash
  git add Tests/SwiflowTestingTests/
  git commit -m "test(testing): full Counter + SignIn spec suite"
  ```

---

## Implementation notes for subagents

1. **`package` access**: `SwiflowTesting` is in the same `Package.swift` as `Swiflow`, so `package` functions in `Swiflow` (`diff`, `HandlerRegistry.dispatch`, `HandlerRegistry.register`, `Event.domName`) are accessible without imports beyond `import Swiflow`.

2. **`wireState` is now `package`**: after Task 1's one-word change, `TestRenderer.init` calls `wireState(on: AnyComponent(instance), scheduler: self.scheduler)` directly. It is called ONCE for the root; `diff` calls it internally for nested component anchors when they first mount.

3. **`_testAmbientHandlers` lifecycle**: set immediately before every call to `diff(...)` in `TestRenderer`, cleared immediately after. `diff` transitively calls nested component `body` methods; all `.on()` calls that happen during those body computations find the registry through `_testAmbientHandlers`. Never clear it mid-diff.

4. **Patches are discarded**: `diff` returns `DiffResult(patches:newMountTree:)`. `TestRenderer` only uses `result.newMountTree` — patches are silently dropped (no DOM to update).

5. **`ObjectIdentifier(instance)`**: works directly because `Component: AnyObject`. No `as AnyObject` cast needed.

6. **`diff` signature**: `diff(mounted:next:handles:handlers:scheduler:environment:)` — `environment` defaults to `.init()`, so omit it.

7. **Two `.on()` modifiers on the same element**: `input(.on(.input) { ... }, .on(.blur) { ... })` — these have different event names so they land in `data.handlers["input"]` and `data.handlers["blur"]` without conflict.

8. **`SyncScheduler.flush()` and `_testAmbientHandlers`**: `flush()` calls `rerender()` synchronously. `rerender()` sets `_testAmbientHandlers` before calling `diff` and clears after. The flush is triggered by `scheduler.flush()` called in `click`/`input`/`blur` after dispatching the event. The `@State` mutation inside the event handler calls `scheduler.markDirty(self)` before the flush.
