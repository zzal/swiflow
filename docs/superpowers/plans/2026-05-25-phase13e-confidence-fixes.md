# Phase 13e — Confidence Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close all 11 audit gaps (1 critical + 10 important) from the Phase 13 confidence audit, spanning public API hygiene, @Environment correctness, CLI distribution readiness, and Router test coverage.

**Architecture:** Nine independent tasks, each with its own TDD cycle and commit. Tasks 1–2 demote internal types to `package` access. Tasks 3–4 add the `.environment()` postfix modifier and fix environment equality in VNode diff. Tasks 5–6 add missing Router tests (unit + Playwright). Tasks 7–8 add URL-dep infrastructure to `swiflow init` and close the init integration test gap. Task 9 writes the SwiflowTesting guide.

**Tech Stack:** Swift 6, Swift Testing, XCTest (macro tests only), Playwright (TypeScript), Swift Package Manager `package` access level.

---

## File Structure

**Create:**
- `examples/RouterDemo/Package.swift` — minimal router example package
- `examples/RouterDemo/Sources/App/App.swift` — two-page hash-mode router app
- `examples/RouterDemo/index.html` — SPA entry point for the router demo
- `Tests/SwiflowRouterTests/RouterEnvironmentTests.swift` — R1 unit test
- `Tests/playwright/router.spec.ts` — R2 Playwright router URL test
- `docs/guides/testing.md` — SwiflowTesting user guide (A4)

**Modify:**
- `Sources/Swiflow/Patch.swift` — `public` → `package` (A1)
- `Sources/Swiflow/PatchPayload.swift` — `public` → `package` (A1)
- `Sources/Swiflow/PatchSerializer.swift` — `public` → `package` (A1)
- `Sources/Swiflow/HandleAllocator.swift` — `public` → `package` (A3)
- `Sources/Swiflow/MountTree.swift` — all `public` → `package` (A3)
- `Sources/SwiflowTesting/TestHarness.swift` — `TestNode.properties: [String: String]` (A2)
- `Sources/Swiflow/DSL/EnvironmentDSL.swift` — add `.environment()` postfix (E1)
- `Sources/Swiflow/Reactivity/Environment.swift` — `Equatable` conformance with typed-erased equality (E2)
- `Sources/Swiflow/VNode.swift` — update `VNode.==` to compare env values (E2)
- `Sources/SwiflowCLI/Templates/Templates.swift` — URL dep variant for `packageSwift` (C1+C2)
- `Sources/SwiflowCLI/Commands/InitCommand.swift` — `--swiflow-version` flag (C1+C2)
- `Package.swift` — add `SwiflowTesting` dep to `SwiflowRouterTests` target (R1)
- `Tests/playwright/playwright.config.ts` — second webServer on port 3001 (R2)
- `Tests/SwiflowCLITests/InitCommandTests.swift` — fix `@Component` check + add integration test (C3)

---

## Task 1: Demote internal types to `package` — Patch, PatchPayload, PatchSerializer, HandleAllocator, MountNode (A1 + A3)

**Files:**
- Modify: `Sources/Swiflow/Patch.swift`
- Modify: `Sources/Swiflow/PatchPayload.swift`
- Modify: `Sources/Swiflow/PatchSerializer.swift`
- Modify: `Sources/Swiflow/HandleAllocator.swift`
- Modify: `Sources/Swiflow/MountTree.swift`

This is a pure access-level refactor. No behaviour changes. Tests use `@testable import Swiflow` and are in the same package, so they continue to access `package` members.

- [ ] **Step 1: Change `Patch` from `public` to `package`**

In `Sources/Swiflow/Patch.swift`, change line 13:
```swift
// Before:
public enum Patch: Equatable, Sendable {

// After:
package enum Patch: Equatable, Sendable {
```

- [ ] **Step 2: Change `PatchPayload` and `PatchPayload.Field` from `public` to `package`**

In `Sources/Swiflow/PatchPayload.swift`:
```swift
// Before:
public struct PatchPayload: Equatable, Sendable {
    public let op: String
    public let fields: [String: Field]
    public init(op: String, fields: [String: Field]) { ... }
    public enum Field: Equatable, Sendable {
        case int(Int)
        case string(String)
        case property(PropertyValue)
        case double(Double)
    }
}

// After:
package struct PatchPayload: Equatable, Sendable {
    package let op: String
    package let fields: [String: Field]
    package init(op: String, fields: [String: Field]) { ... }
    package enum Field: Equatable, Sendable {
        case int(Int)
        case string(String)
        case property(PropertyValue)
        case double(Double)
    }
}
```

- [ ] **Step 3: Change `PatchSerializer` from `public` to `package`**

In `Sources/Swiflow/PatchSerializer.swift`, change:
```swift
// Before:
public enum PatchSerializer {
    public static func encode(_ patch: Patch) -> PatchPayload {

// After:
package enum PatchSerializer {
    package static func encode(_ patch: Patch) -> PatchPayload {
```

- [ ] **Step 4: Change `HandleAllocator` from `public` to `package`**

In `Sources/Swiflow/HandleAllocator.swift`:
```swift
// Before:
public final class HandleAllocator {
    public init(start: Int = 0) { ... }
    public func next() -> Int { ... }
}

// After:
package final class HandleAllocator {
    package init(start: Int = 0) { ... }
    package func next() -> Int { ... }
}
```

- [ ] **Step 5: Change all `public` members of `MountNode` to `package`**

In `Sources/Swiflow/MountTree.swift`, change every `public` to `package` throughout the file. Specifically:
- `public final class MountNode` → `package final class MountNode`
- All `public let`, `public var`, `public private(set) var`, `public func`, `public init` → replace `public` with `package`
- Leave any existing `package` declarations unchanged.

- [ ] **Step 6: Build and verify compilation**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete!` (or no errors). If `SwiflowWeb` or `SwiflowTesting` fail to compile, they're in the same package so they have `package` access — investigate and fix any missed access level changes.

- [ ] **Step 7: Run tests**

```bash
swift test --filter SwiflowTests 2>&1 | tail -5
```

Expected: All existing tests pass. The `PatchTests`, `PatchPayloadTests`, `PatchSerializerTests`, `HandleAllocatorTests`, `MountTreeTests` suites must still pass since they use `@testable import Swiflow`.

- [ ] **Step 8: Commit**

```bash
git add Sources/Swiflow/Patch.swift Sources/Swiflow/PatchPayload.swift Sources/Swiflow/PatchSerializer.swift Sources/Swiflow/HandleAllocator.swift Sources/Swiflow/MountTree.swift
git commit -m "refactor(api): demote Patch, PatchPayload, PatchSerializer, HandleAllocator, MountNode to package access"
```

---

## Task 2: Fix `PropertyValue` leak through `TestNode` (A2)

**Files:**
- Modify: `Sources/SwiflowTesting/TestHarness.swift`
- Test: `Tests/SwiflowTestingTests/TestHarnessTests.swift`

Currently `TestNode.properties: [String: PropertyValue]` leaks an internal DOM type into the public `SwiflowTesting` API. The fix: return `[String: String]` by flattening each `PropertyValue` to its string representation.

- [ ] **Step 1: Write a failing test**

Add to `Tests/SwiflowTestingTests/TestHarnessTests.swift`, inside an appropriate suite:

```swift
@Test("TestNode.properties keys and values are plain strings")
@MainActor
func testNodePropertiesAreStrings() {
    // MinimalCounter has an input with no explicit properties set,
    // but we need a component that sets a typed property.
    // Use the harness directly: render a component that sets .value($text).
    @Component
    final class PropHost: Component {
        @State var text = "hello"
        var body: VNode {
            input(.value($text))
        }
    }
    let h = render(PropHost())
    let node = h.find("input")
    // properties must be [String: String], not [String: PropertyValue]
    // If it compiles and the value is "hello" as a String, the type is right.
    #expect(node?.properties["value"] == "hello")
}
```

Run: `swift test --filter SwiflowTestingTests 2>&1 | tail -10`

Expected: Compilation error — `node?.properties["value"]` returns `PropertyValue?`, not `String?`. Confirms the test is exercising the right thing.

- [ ] **Step 2: Change `TestNode.properties` to `[String: String]`**

In `Sources/SwiflowTesting/TestHarness.swift`, replace `TestNode`:

```swift
public struct TestNode {
    public let tag: String
    public let text: String
    public let attributes: [String: String]
    public let properties: [String: String]
}
```

Add a private helper to flatten `PropertyValue`:

```swift
private func flattenProperty(_ value: PropertyValue) -> String {
    switch value {
    case .string(let s): return s
    case .bool(let b):   return b ? "true" : "false"
    case .int(let i):    return String(i)
    case .double(let d): return String(d)
    }
}
```

Update every `TestNode(...)` initialisation in `TestHarness.swift` (there are two — inside `find` and `findAll`) to call `flattenProperty`:

```swift
// In find:
return TestNode(
    tag: data.tag,
    text: renderer.textContent(of: node),
    attributes: data.attributes,
    properties: data.properties.mapValues { flattenProperty($0) }
)
```

Apply the same `mapValues` change in `findAll`.

- [ ] **Step 3: Build and run tests**

```bash
swift build 2>&1 | tail -5
swift test --filter SwiflowTestingTests 2>&1 | tail -10
```

Expected: Build succeeds, `testNodePropertiesAreStrings` passes. If any existing test previously compared `PropertyValue` directly, update it to compare the string representation.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiflowTesting/TestHarness.swift Tests/SwiflowTestingTests/TestHarnessTests.swift
git commit -m "fix(api): change TestNode.properties to [String: String] to stop PropertyValue leaking"
```

---

## Task 3: Add `.environment()` postfix VNode modifier (E1)

**Files:**
- Modify: `Sources/Swiflow/DSL/EnvironmentDSL.swift`
- Test: `Tests/SwiflowTests/Environment/EnvironmentDSLTests.swift`

`withEnvironment(\.locale, "fr") { child }` is the existing standalone function. This task adds `child.environment(\.locale, "fr")` as a postfix alternative, consistent with every other VNode modifier (`.on()`, `.attr()`, `.class()`, etc.).

- [ ] **Step 1: Write failing tests**

Add to `Tests/SwiflowTests/Environment/EnvironmentDSLTests.swift`:

```swift
@Test(".environment() postfix produces an environmentOverride VNode")
func postfixEnvironmentModifier() {
    let vnode = VNode.text("hello").environment(\.locale, "fr")
    guard case let .environmentOverride(env, child) = vnode else {
        Issue.record("Expected .environmentOverride, got \(vnode)")
        return
    }
    #expect(env.locale == "fr")
    if case .text(let t) = child {
        #expect(t == "hello")
    } else {
        Issue.record("Expected .text child")
    }
}

@Test(".environment() chains to produce nested overrides")
func postfixEnvironmentChain() {
    let vnode = VNode.text("x")
        .environment(\.locale, "fr")
        .environment(\.colorScheme, .dark)
    // Outer override is colorScheme (last applied)
    guard case let .environmentOverride(outerEnv, outerChild) = vnode else {
        Issue.record("Expected outer .environmentOverride"); return
    }
    #expect(outerEnv.colorScheme == .dark)
    guard case .environmentOverride(let innerEnv, _) = outerChild else {
        Issue.record("Expected inner .environmentOverride"); return
    }
    #expect(innerEnv.locale == "fr")
}
```

Run: `swift test --filter EnvironmentDSLTests 2>&1 | tail -5`

Expected: FAIL — `value of type 'VNode' has no member 'environment'`

- [ ] **Step 2: Add the postfix modifier**

Append to `Sources/Swiflow/DSL/EnvironmentDSL.swift`:

```swift
public extension VNode {
    /// Wraps this VNode in an `.environmentOverride` node, injecting a single
    /// environment value for the subtree rooted at this node.
    ///
    /// ```swift
    /// embed { Sidebar() }.environment(\.locale, "fr")
    /// ```
    func environment<Value>(
        _ keyPath: WritableKeyPath<EnvironmentValues, Value>,
        _ value: Value
    ) -> VNode {
        var overrides = EnvironmentValues()
        overrides[keyPath: keyPath] = value
        return .environmentOverride(overrides, self)
    }
}
```

- [ ] **Step 3: Run tests**

```bash
swift test --filter EnvironmentDSLTests 2>&1 | tail -5
```

Expected: All tests in `EnvironmentDSLTests` pass including the two new ones.

- [ ] **Step 4: Commit**

```bash
git add Sources/Swiflow/DSL/EnvironmentDSL.swift Tests/SwiflowTests/Environment/EnvironmentDSLTests.swift
git commit -m "feat(dsl): add .environment() postfix VNode modifier"
```

---

## Task 4: Fix `EnvironmentValues` equality in VNode diff (E2)

**Files:**
- Modify: `Sources/Swiflow/Reactivity/Environment.swift`
- Modify: `Sources/Swiflow/VNode.swift`
- Test: `Tests/SwiflowTests/VNode/VNodeTests.swift` (existing file)

**Problem:** `VNode.==` for `.environmentOverride` compares only the child VNode, not the environment values. If `\.locale` changes from `"fr"` to `"de"` but the child VNode is identical, the diff treats the nodes as equal and skips the subtree — silently suppressing the environment change.

**Fix:** Make `EnvironmentValues: Equatable` using a type-erased equality store. When `K.Value: Equatable`, equality is value-aware. For non-`Equatable` values (e.g. `Router`), equality always returns `false` (conservative: always re-merge, which is the current behavior).

- [ ] **Step 1: Write a failing test**

Add to `Tests/SwiflowTests/VNodeTests.swift`:

```swift
@Test("environmentOverride VNodes with different env values are not equal")
func environmentOverrideDifferentValuesAreNotEqual() {
    let a = withEnvironment(\.locale, "fr") { VNode.text("hello") }
    let b = withEnvironment(\.locale, "de") { VNode.text("hello") }
    // Before fix: a == b (wrong — diff skips subtree when locale changes)
    // After fix:  a != b (correct)
    #expect(a != b)
}

@Test("environmentOverride VNodes with same env values are equal")
func environmentOverrideSameValuesAreEqual() {
    let a = withEnvironment(\.locale, "fr") { VNode.text("hello") }
    let b = withEnvironment(\.locale, "fr") { VNode.text("hello") }
    #expect(a == b)
}
```

Run: `swift test --filter VNodeTests 2>&1 | tail -5`

Expected: `environmentOverrideDifferentValuesAreNotEqual` FAILS (because current `==` compares only the child).

- [ ] **Step 2: Rewrite `EnvironmentValues` with typed-erased equality**

Replace the entire content of `Sources/Swiflow/Reactivity/Environment.swift` with:

```swift
// Sources/Swiflow/Reactivity/Environment.swift

public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

public struct EnvironmentValues {
    private struct StoredValue {
        let any: Any
        let equals: (Any) -> Bool
    }

    private var storage: [ObjectIdentifier: StoredValue] = [:]

    public init() {}

    // Equatable overload — preferred when K.Value: Equatable
    public subscript<K: EnvironmentKey>(_ key: K.Type) -> K.Value where K.Value: Equatable {
        get { storage[ObjectIdentifier(K.self)]?.any as? K.Value ?? K.defaultValue }
        set {
            let v = newValue
            storage[ObjectIdentifier(K.self)] = StoredValue(any: v, equals: { ($0 as? K.Value) == v })
        }
    }

    // Fallback for non-Equatable values; equality always false (conservative)
    public subscript<K: EnvironmentKey>(_ key: K.Type) -> K.Value {
        get { storage[ObjectIdentifier(K.self)]?.any as? K.Value ?? K.defaultValue }
        set {
            storage[ObjectIdentifier(K.self)] = StoredValue(any: newValue, equals: { _ in false })
        }
    }

    func merging(_ overrides: EnvironmentValues) -> EnvironmentValues {
        var result = self
        for (id, val) in overrides.storage { result.storage[id] = val }
        return result
    }
}

extension EnvironmentValues: Equatable {
    public static func == (lhs: EnvironmentValues, rhs: EnvironmentValues) -> Bool {
        guard lhs.storage.count == rhs.storage.count else { return false }
        for (id, lhsVal) in lhs.storage {
            guard let rhsVal = rhs.storage[id] else { return false }
            if !lhsVal.equals(rhsVal.any) { return false }
        }
        return true
    }
}

public enum ColorScheme: Equatable, Sendable { case light, dark }

private enum LocaleKey: EnvironmentKey { static let defaultValue = "en" }
private enum ColorSchemeKey: EnvironmentKey { static let defaultValue = ColorScheme.light }

extension EnvironmentValues {
    public var locale: String {
        get { self[LocaleKey.self] }
        set { self[LocaleKey.self] = newValue }
    }
    public var colorScheme: ColorScheme {
        get { self[ColorSchemeKey.self] }
        set { self[ColorSchemeKey.self] = newValue }
    }
}

enum AmbientEnvironment {
    nonisolated(unsafe) static var current: EnvironmentValues = .init()
}

@propertyWrapper
public struct Environment<Value> {
    let keyPath: KeyPath<EnvironmentValues, Value>
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) { self.keyPath = keyPath }
    public var wrappedValue: Value { AmbientEnvironment.current[keyPath: keyPath] }
}
```

- [ ] **Step 3: Update `VNode.==` to compare environment values**

In `Sources/Swiflow/VNode.swift`, change the `environmentOverride` case in the `==` function:

```swift
// Before:
case (.environmentOverride(_, let a), .environmentOverride(_, let b)):
    return a == b   // compare only the child, not the env values

// After:
case (.environmentOverride(let envA, let a), .environmentOverride(let envB, let b)):
    return envA == envB && a == b
```

- [ ] **Step 4: Build and run all environment tests**

```bash
swift build 2>&1 | tail -5
swift test --filter "Environment" 2>&1 | tail -10
```

Expected: Build succeeds. `environmentOverrideDifferentValuesAreNotEqual` and `environmentOverrideSameValuesAreEqual` both pass. All existing `EnvironmentValuesTests`, `EnvironmentDSLTests`, `EnvironmentThreadingTests` still pass.

- [ ] **Step 5: Run full test suite**

```bash
swift test 2>&1 | tail -5
```

Expected: All tests pass. The `VNodeTests` suite passes.

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/Reactivity/Environment.swift Sources/Swiflow/VNode.swift Tests/SwiflowTests/VNodeTests.swift
git commit -m "fix(diff): make EnvironmentValues Equatable; VNode diff now detects environment changes"
```

---

## Task 5: Router `@Environment` propagation test across `embed {}` (R1)

**Files:**
- Modify: `Package.swift` — add `SwiflowTesting` dep to `SwiflowRouterTests`
- Create: `Tests/SwiflowRouterTests/RouterEnvironmentTests.swift`

`@Environment(\.router)` is injected at `RouterRoot`. This task verifies that a component nested inside `embed {}` reads the injected router correctly via `withEnvironment`.

- [ ] **Step 1: Add `SwiflowTesting` to `SwiflowRouterTests` in `Package.swift`**

In `Package.swift`, find the `SwiflowRouterTests` target declaration and add `"SwiflowTesting"`:

```swift
// Before:
.testTarget(
    name: "SwiflowRouterTests",
    dependencies: ["SwiflowRouter"],
    path: "Tests/SwiflowRouterTests",
    swiftSettings: [.swiftLanguageMode(.v6)]
),

// After:
.testTarget(
    name: "SwiflowRouterTests",
    dependencies: ["SwiflowRouter", "SwiflowTesting"],
    path: "Tests/SwiflowRouterTests",
    swiftSettings: [.swiftLanguageMode(.v6)]
),
```

- [ ] **Step 2: Create `RouterEnvironmentTests.swift`**

Create `Tests/SwiflowRouterTests/RouterEnvironmentTests.swift` with:

```swift
// Tests/SwiflowRouterTests/RouterEnvironmentTests.swift
import Testing
import Swiflow
import SwiflowRouter
@testable import SwiflowTesting

/// Components that read @Environment(\.router) inside embed {} subtrees.
@MainActor
private final class RouterReader: Component {
    @Environment(\.router) var router
    var body: VNode { p(router.path) }
}

@MainActor
private final class RouterHost: Component {
    let injectedRouter: Router

    init(router: Router) { self.injectedRouter = router }

    var body: VNode {
        withEnvironment(\.router, injectedRouter) {
            embed { RouterReader() }
        }
    }
}

@Suite("Router @Environment propagation across embed {}")
struct RouterEnvironmentTests {

    @Test("@Environment(\\. router) inside embed {} reads the injected router path")
    @MainActor
    func readsInjectedRouterPath() {
        let customRouter = Router(
            path: "/dashboard",
            navigate: { _ in },
            replace: { _ in },
            back: {}
        )
        let h = render(RouterHost(router: customRouter))
        let node = h.find("p")
        #expect(node?.text == "/dashboard")
    }

    @Test("@Environment(\\. router) defaults to '/' when no RouterRoot is present")
    @MainActor
    func defaultsToRootPath() {
        let h = render(RouterReader())
        let node = h.find("p")
        #expect(node?.text == "/")
    }

    @Test("Changing injected router path updates the subtree")
    @MainActor
    func updatedRouterPathPropagates() {
        let h = render(RouterHost(router: Router(
            path: "/first",
            navigate: { _ in }, replace: { _ in }, back: {}
        )))
        #expect(h.find("p")?.text == "/first")
    }
}
```

- [ ] **Step 3: Run the new tests**

```bash
swift test --filter SwiflowRouterTests 2>&1 | tail -10
```

Expected: All tests in `SwiflowRouterTests` pass, including the three new tests in `RouterEnvironmentTests`.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Tests/SwiflowRouterTests/RouterEnvironmentTests.swift
git commit -m "test(router): verify @Environment(\\\.router) propagates correctly across embed {} boundaries"
```

---

## Task 6: Playwright router URL/history test (R2)

**Files:**
- Create: `examples/RouterDemo/Package.swift`
- Create: `examples/RouterDemo/Sources/App/App.swift`
- Create: `examples/RouterDemo/index.html`
- Modify: `Tests/playwright/playwright.config.ts` — add second webServer on port 3001
- Create: `Tests/playwright/router.spec.ts`

This task verifies that `Router.navigate()` and `history.back()` actually change the URL and trigger re-renders. The `RouterDemo` example uses hash-mode routing (`RouterRoot(mode: .hash)`) — no server-side SPA configuration needed.

- [ ] **Step 1: Create `examples/RouterDemo/Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RouterDemo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "App", targets: ["App"]),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "SwiflowWeb", package: "Swiflow"),
                .product(name: "SwiflowRouter", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)
```

- [ ] **Step 2: Create `examples/RouterDemo/Sources/App/App.swift`**

```swift
// Sources/App/App.swift
import Swiflow
import SwiflowWeb
import SwiflowRouter
import JavaScriptKit

@Component
final class HomePage: Component {
    @Environment(\.router) var router

    var body: VNode {
        div {
            h1("Home")
            p("You are on the home page.")
            Link(to: "/about") { text("Go to About") }
        }
    }
}

@Component
final class AboutPage: Component {
    @Environment(\.router) var router

    var body: VNode {
        div {
            h1("About")
            p("You are on the about page.")
            button("Back", .on(.click) { self.router.back() })
        }
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") {
            RouterRoot(mode: .hash) {
                Route("/") { HomePage() }
                Route("/about") { AboutPage() }
            }
        }
    }
}
```

- [ ] **Step 3: Create `examples/RouterDemo/index.html`**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>RouterDemo</title>
  </head>
  <body>
    <div id="app"></div>
    <script src="swiflow-driver.js"></script>
    <script type="module">
      import { init } from "./.build/plugins/PackageToJS/outputs/Package/index.js";
      await init();
    </script>
  </body>
</html>
```

- [ ] **Step 4: Add second webServer to `playwright.config.ts`**

In `Tests/playwright/playwright.config.ts`, modify the export to add a second `webServer` for the RouterDemo. First add the path constant after `DEMO_PROJECT`:

```typescript
const ROUTER_DEMO_ROOT = join(REPO_ROOT, "examples", "RouterDemo");
```

Then change `webServer:` from a single object to an array:

```typescript
  webServer: [
    {
      command: `'${SWIFLOW}' dev`,
      cwd: DEMO_PROJECT,
      url: "http://127.0.0.1:3000",
      reuseExistingServer: false,
      timeout: 300_000,
    },
    {
      command: `'${SWIFLOW}' dev --port 3001`,
      cwd: ROUTER_DEMO_ROOT,
      url: "http://127.0.0.1:3001",
      reuseExistingServer: false,
      timeout: 300_000,
    },
  ],
```

- [ ] **Step 5: Write `Tests/playwright/router.spec.ts`**

```typescript
// Tests/playwright/router.spec.ts
import { test, expect, type ConsoleMessage } from "@playwright/test";

test.describe("RouterDemo — hash-mode navigation", () => {
  test.use({ baseURL: "http://127.0.0.1:3001" });

  test("Home page renders on load", async ({ page }) => {
    const errors: ConsoleMessage[] = [];
    page.on("console", (msg) => { if (msg.type() === "error") errors.push(msg); });

    await page.goto("/");
    await expect(page.getByRole("heading", { name: "Home" })).toBeVisible();
    expect(errors.map((e) => e.text()), "no console errors on load").toHaveLength(0);
  });

  test("Link navigation changes URL hash and renders About page", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByRole("heading", { name: "Home" })).toBeVisible();

    await page.getByRole("link", { name: "Go to About" }).click();

    // URL hash must change to /about
    await expect(page).toHaveURL(/#\/about$/);
    // About heading must appear
    await expect(page.getByRole("heading", { name: "About" })).toBeVisible();
    // Home heading must be gone
    await expect(page.getByRole("heading", { name: "Home" })).toHaveCount(0);
  });

  test("Back button returns to Home page and restores URL", async ({ page }) => {
    await page.goto("/#/about");
    await expect(page.getByRole("heading", { name: "About" })).toBeVisible();

    await page.getByRole("button", { name: "Back" }).click();

    await expect(page.getByRole("heading", { name: "Home" })).toBeVisible();
    // URL hash must no longer point at /about
    const url = page.url();
    expect(url).not.toMatch(/#\/about/);
  });
});
```

- [ ] **Step 6: Run Playwright tests locally to verify** (requires WASM SDK + Playwright install)

```bash
cd Tests/playwright && npx playwright test router.spec.ts
```

Expected: All three tests pass. If the RouterDemo WASM hasn't been built yet, `swiflow dev` builds it on first run (~3 min).

- [ ] **Step 7: Commit**

```bash
git add examples/RouterDemo/ Tests/playwright/playwright.config.ts Tests/playwright/router.spec.ts
git commit -m "test(playwright): add RouterDemo example and hash-mode URL navigation tests"
```

---

## Task 7: `swiflow init` URL dependency infrastructure (C1 + C2)

**Files:**
- Modify: `Sources/SwiflowCLI/Templates/Templates.swift`
- Modify: `Sources/SwiflowCLI/Commands/InitCommand.swift`
- Test: `Tests/SwiflowCLITests/TemplatesTests.swift` (verify new URL variant)
- Test: `Tests/SwiflowCLITests/InitCommandTests.swift` (argument parsing)

Currently `swiflow init` requires `--swiflow-source` (a local path). The generated `Package.swift` embeds `.package(path: ...)`. This blocks distribution: once a GitHub release exists, users can't run `swiflow init my-app` without providing the path manually.

This task adds a `--swiflow-version` flag. When provided, the generated `Package.swift` uses `.package(url: ..., exact: version)` instead of `.package(path: ...)`. The path-based flow remains unchanged.

- [ ] **Step 1: Write failing tests for the URL dep variant**

Add to `Tests/SwiflowCLITests/TemplatesTests.swift` (or create it if it doesn't exist in the right form):

```swift
@Test("packageSwift with URL dep uses .package(url:exact:) instead of .package(path:)")
func packageSwiftURLDep() {
    let pkg = Templates.packageSwift(
        name: "MyApp",
        swiflowDep: .url("https://github.com/example/Swiflow.git", version: "1.0.0")
    )
    #expect(pkg.contains(#".package(url: "https://github.com/example/Swiflow.git", exact: "1.0.0")"#))
    #expect(!pkg.contains(".package(path:"))
}

@Test("packageSwift with path dep uses .package(path:)")
func packageSwiftPathDep() {
    let pkg = Templates.packageSwift(
        name: "MyApp",
        swiflowDep: .path("/abs/path/to/swiflow")
    )
    #expect(pkg.contains(#".package(path: "/abs/path/to/swiflow")"#))
    #expect(!pkg.contains(".package(url:"))
}
```

Run: `swift test --filter TemplatesTests 2>&1 | tail -5`

Expected: FAIL — `Templates.packageSwift` doesn't have the new signature yet.

- [ ] **Step 2: Add `SwiflowDep` enum and update `Templates.packageSwift`**

In `Sources/SwiflowCLI/Templates/Templates.swift`, add before the `Templates` enum or inside it:

```swift
/// How the generated Package.swift depends on Swiflow.
enum SwiflowDep {
    /// A local path dep: `.package(path: "/path/to/swiflow")`.
    case path(String)
    /// A versioned URL dep: `.package(url: "...", exact: "x.y.z")`.
    case url(String, version: String)

    var packageFragment: String {
        switch self {
        case .path(let p):
            return #".package(path: "\#(p)")"#
        case .url(let u, let v):
            return #".package(url: "\#(u)", exact: "\#(v)")"#
        }
    }
}
```

Change `Templates.packageSwift` signature from:
```swift
static func packageSwift(name: String, swiflowSource: String) -> String
```
to:
```swift
static func packageSwift(name: String, swiflowDep: SwiflowDep) -> String
```

And update the template substitution to use `swiflowDep.packageFragment` in place of the old `{{SWIFLOW_SOURCE}}` substitution:

```swift
static func packageSwift(name: String, swiflowDep: SwiflowDep) -> String {
    return rawPackageSwift
        .replacingOccurrences(of: "{{NAME}}", with: name)
        .replacingOccurrences(of: #".package(path: "{{SWIFLOW_SOURCE}}")"#,
                              with: swiflowDep.packageFragment)
}
```

Update `ProjectWriter` (wherever it calls `Templates.packageSwift`) to pass `.path(swiflowSource)` instead:

```swift
// Before:
Templates.packageSwift(name: name, swiflowSource: swiflowSource)

// After:
Templates.packageSwift(name: name, swiflowDep: .path(swiflowSource))
```

- [ ] **Step 3: Add `--swiflow-version` flag to `InitCommand`**

In `Sources/SwiflowCLI/Commands/InitCommand.swift`, add a new option after the `swiflowSource` option:

```swift
@Option(
    name: .customLong("swiflow-version"),
    help: ArgumentHelp(
        "Version of Swiflow to depend on via URL (e.g. 1.0.0).",
        discussion: """
            When provided, the generated Package.swift uses a versioned URL dependency \
            on the official Swiflow GitHub release instead of a local path.
            Example: --swiflow-version 1.0.0
            """
    )
)
var swiflowVersion: String?
```

Update the `run()` method to resolve the dependency type:

```swift
func run() async throws {
    let dep: SwiflowDep
    if let version = swiflowVersion {
        dep = .url("https://github.com/swiflow/swiflow.git", version: version)
    } else if let source = swiflowSource ?? ProcessInfo.processInfo.environment["SWIFLOW_SOURCE"] {
        dep = .path(source)
    } else {
        throw ValidationError("""
            --swiflow-source is required. Swiflow has no public release yet.
            Pass the path to your local Swiflow clone:
              swiflow init \(name) --swiflow-source /path/to/swiflow
            Or set the SWIFLOW_SOURCE environment variable.
            Or use --swiflow-version once a release is available.
            """)
    }

    // ... rest of run() uses `dep` instead of `swiflowSource`
    try ProjectWriter.writeProject(
        name: name,
        into: parentURL,
        swiflowDep: dep,
        jsDriverSource: EmbeddedDriver.javascriptSource
    )
    // ...
}
```

Update `ProjectWriter.writeProject` signature to accept `swiflowDep: SwiflowDep` instead of `swiflowSource: String`.

- [ ] **Step 4: Update `ProjectWriter` and its tests**

In `Sources/SwiflowCLI/Project/ProjectWriter.swift`, change `swiflowSource: String` to `swiflowDep: SwiflowDep` and thread it through to `Templates.packageSwift`.

Update all callers in tests that pass `swiflowSource:` to pass `swiflowDep: .path("../..") ` instead. Search with:

```bash
grep -rn "swiflowSource:" Tests/SwiflowCLITests/ Sources/SwiflowCLI/
```

Replace each call.

- [ ] **Step 5: Build and run tests**

```bash
swift build 2>&1 | tail -5
swift test --filter SwiflowCLITests 2>&1 | tail -10
```

Expected: All tests pass. The new URL dep tests pass. Existing path dep tests still pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowCLI/ Tests/SwiflowCLITests/
git commit -m "feat(init): add --swiflow-version flag; SwiflowDep enum supports path and URL package deps"
```

---

## Task 8: `swiflow init` integration test + fix pre-existing test regression (C3)

**Files:**
- Modify: `Tests/SwiflowCLITests/InitCommandTests.swift`

Two fixes in this task:
1. Fix `appSwiftIsCounterComponent` which checks for `"final class Counter: Component"` but the template now uses `@Component`.
2. Add an end-to-end integration test that calls `InitCommand.run()` and then builds the scaffolded project.

- [ ] **Step 1: Fix the `appSwiftIsCounterComponent` test**

In `Tests/SwiflowCLITests/InitCommandTests.swift`, find the test at line ~89 and update:

```swift
// Before (at line 89):
@Test("Generated App.swift uses Counter: Component with @State (Phase 3)")
func appSwiftIsCounterComponent() throws {
    // ...
    #expect(app.contains("final class Counter: Component"))
    // ...
}

// After:
@Test("Generated App.swift uses @Component Counter with @State")
func appSwiftIsCounterComponent() throws {
    // ... (same setup) ...
    // @Component macro replaces explicit `: Component` conformance declaration.
    #expect(app.contains("@Component"))
    #expect(app.contains("final class Counter {"))
    #expect(app.contains("@State var count: Int = 0"))
    #expect(app.contains("Swiflow.render(into: \"#app\") { Counter() }"))
    let hasRerenderCall = app.contains("Swiflow.rerender()\n") || app.contains("            Swiflow.rerender()")
    #expect(!hasRerenderCall,
            "Counter shouldn't need explicit rerender — @State handles it")
}
```

- [ ] **Step 2: Verify the fix**

```bash
swift test --filter InitCommandTests 2>&1 | tail -5
```

Expected: `appSwiftIsCounterComponent` now passes.

- [ ] **Step 3: Add integration test suite**

Add to `Tests/SwiflowCLITests/InitCommandTests.swift` (after existing suites):

```swift
@Suite("InitCommand end-to-end integration (requires WASM SDK)")
struct InitCommandIntegrationTests {

    static var wasmSDKAvailable: Bool {
        let runner = SystemProcessRunner()
        let result = try? runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["swift", "sdk", "list"],
            workingDirectory: nil,
            environment: nil,
            captureOutput: true
        )
        guard let stdout = result?.standardOutput else { return false }
        return !WasmSDKProbe.parseSDKList(stdout).isEmpty
    }

    static var swiflowRepoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiflowCLITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
    }

    @Test(
        "swiflow init end-to-end: InitCommand.run() produces a project that builds successfully",
        .enabled(if: wasmSDKAvailable)
    )
    func initCommandRunThenBuild() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiflow-init-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // 1. Invoke the full InitCommand.run() — not just ProjectWriter directly.
        let cmd = try InitCommand.parse([
            "Demo",
            "--path", tmp.path,
            "--swiflow-source", Self.swiflowRepoRoot.path,
        ])
        try await cmd.run()

        // 2. Verify the project directory was created.
        let project = tmp.appendingPathComponent("Demo")
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: project.appendingPathComponent("Package.swift").path))
        #expect(fm.fileExists(atPath: project.appendingPathComponent("Sources/App/App.swift").path))

        // 3. Build the scaffolded project.
        let runner = SystemProcessRunner()
        guard let swift = try SwiftExecutableLocator.locate(using: runner) else {
            Issue.record("swift not on PATH; cannot complete end-to-end test.")
            return
        }
        let probe = WasmSDKProbe(runner: runner, swiftExecutable: swift)
        guard let sdk = try probe.list().first else {
            Issue.record("WasmSDKProbe returned empty; flaky WASM SDK detection?")
            return
        }
        let toolchainBundleID = MacToolchainProbe.swiftLatestBundleIdentifier()
        let invocation = BuildInvocation(
            swiftExecutable: swift,
            projectPath: project,
            swiftSDK: sdk,
            toolchainBundleID: toolchainBundleID
        )
        let result = try invocation.run(using: runner)
        #expect(result.exitCode == 0)

        // 4. Verify PackageToJS output exists.
        let outputDir = project.appendingPathComponent(".build/plugins/PackageToJS/outputs/Package")
        #expect(fm.fileExists(atPath: outputDir.appendingPathComponent("index.js").path))
        #expect(fm.fileExists(atPath: outputDir.appendingPathComponent("App.wasm").path))
    }
}
```

- [ ] **Step 4: Run the new integration test (skips without WASM SDK)**

```bash
swift test --filter InitCommandIntegrationTests 2>&1 | tail -5
```

Expected: If WASM SDK is present, the test passes (~170s). If not, it skips with `.enabled(if:)`.

- [ ] **Step 5: Commit**

```bash
git add Tests/SwiflowCLITests/InitCommandTests.swift
git commit -m "test(init): fix @Component template check; add InitCommand.run() integration test"
```

---

## Task 9: Write SwiflowTesting user guide (A4)

**Files:**
- Create: `docs/guides/testing.md`

Users must currently read `TestHarness.swift` inline docs to discover the API. This task writes a guide.

- [ ] **Step 1: Create `docs/guides/testing.md`**

```markdown
# SwiflowTesting

`SwiflowTesting` is a headless unit-test renderer for Swiflow components. It
runs components synchronously (no requestAnimationFrame), so tests are
deterministic and need no async/await.

## Quick start

```swift
import Testing
import Swiflow
import SwiflowTesting

@Component
final class Counter: Component {
    @State var count = 0
    var body: VNode {
        div {
            p("Count: \(count)")
            button("Increment", .on(.click) { self.count += 1 })
        }
    }
}

@Suite("Counter")
struct CounterTests {
    @Test @MainActor func incrementsOnClick() {
        let h = render(Counter())
        #expect(h.find("p")?.text == "Count: 0")
        h.click("button", text: "Increment")
        #expect(h.find("p")?.text == "Count: 1")
    }
}
```

## `render(_:)`

```swift
@MainActor func render<C: Component>(_ component: C) -> TestHarness
```

Mounts `component` into a headless virtual DOM. Returns a `TestHarness`.
All state mutations are flushed synchronously before `render` returns.

## Querying the tree

### `find(_ tag:text:) -> TestNode?`

Returns the first element matching the tag. The optional `text` parameter
filters by subtree text content (substring match).

```swift
h.find("p")              // first <p>
h.find("button", text: "Save")  // first <button> whose text contains "Save"
```

### `findAll(_ tag:text:) -> [TestNode]`

Returns all matching elements in document order.

```swift
let inputs = h.findAll("input")
```

### `exists(_ tag:text:) -> Bool`

True if at least one matching element exists.

### `allText -> String`

All text content in the tree, concatenated depth-first. Useful for broad
smoke tests.

## `TestNode` fields

| Field | Type | Description |
|-------|------|-------------|
| `tag` | `String` | HTML tag name (e.g. `"div"`) |
| `text` | `String` | Subtree text content |
| `attributes` | `[String: String]` | HTML attributes set via `.attr()` or `.class()` |
| `properties` | `[String: String]` | DOM properties set via `.value()`, `.checked()`, etc. (string-converted) |

## Interactions

### `click(_ tag:text:)`

Fires a `click` event on the first matching element and flushes state
synchronously.

```swift
h.click("button", text: "Sign in")
```

### `input(_ tag:at:value:)`

Fires an `input` event on the element at `index` (among all elements
matching `tag`) and flushes.

```swift
h.input("input", at: 0, value: "user@example.com")
```

### `blur(_ tag:at:)`

Fires a `blur` event and flushes.

```swift
h.blur("input", at: 1)
```

## Notes

- All `TestHarness` methods and the `render()` function require `@MainActor`.
- `@Environment` values are read during `body` evaluation as usual; use
  `withEnvironment(...)` or `VNode.environment(...)` in your component to
  inject test values.
- `@State` is wired the same way as in production; mutations trigger
  synchronous re-renders via `SyncScheduler`.

## Limitations

- No async/await support: `task {}` lifecycle hooks (pre-1.0 feature) are
  not exercised by `TestHarness`.
- `change` events (for `<select>`, `<textarea>`) are not yet wired. Use
  `input` as a workaround where possible.
```

- [ ] **Step 2: Commit**

```bash
git add docs/guides/testing.md
git commit -m "docs(testing): add SwiflowTesting user guide"
```

---

## Post-implementation checklist

After all tasks are committed:

- [ ] **Run full test suite**

```bash
swift test 2>&1 | tail -5
```

Expected: All tests pass. Count should be at least 530+ (previous 513 + new tests).

- [ ] **Verify audit items closed**

| ID | Task | Status |
|----|------|--------|
| A1 | Task 1 | `Patch`, `PatchPayload`, `PatchSerializer` → `package` |
| A2 | Task 2 | `TestNode.properties: [String: String]` |
| A3 | Task 1 | `HandleAllocator`, `MountNode` → `package` |
| A4 | Task 9 | `docs/guides/testing.md` written |
| E1 | Task 3 | `.environment()` postfix modifier added |
| E2 | Task 4 | `EnvironmentValues: Equatable`; VNode diff detects env changes |
| R1 | Task 5 | Router env propagation tested across `embed {}` |
| R2 | Task 6 | Playwright: navigate + hash change + back verified |
| C1 | Task 7 | `--swiflow-version` flag; URL dep infrastructure in place |
| C2 | Task 7 | URL dep → portable generated Package.swift |
| C3 | Task 8 | `InitCommand.run()` → build integration test |
