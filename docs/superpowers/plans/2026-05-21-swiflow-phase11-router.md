# SwiflowRouter — Phase 11 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `SwiflowRouter` — a first-party hash/history router for Swiflow with `RouterRoot`, `Route`, `Link`, and `@Environment(\.router)`.

**Architecture:** New `SwiflowRouter` library target depending on `Swiflow` + `JavaScriptKit`. Pure-Swift core types (`RoutePattern`, `RouterContext`, `Router`, `RouteDefinition`, `RouteBuilder`) live in `Sources/SwiflowRouter/Core/` and are fully testable on macOS. WASM-only components (`RouterRoot`, `Link`) live in `Sources/SwiflowRouter/Web/` behind `#if canImport(JavaScriptKit)`. Users write `import SwiflowWeb; import SwiflowRouter`.

**Tech Stack:** Swift 6, Swift Testing (`@Suite`, `@Test`, `#expect`), `@resultBuilder`, `JavaScriptKit` (WASM bridge behind `#if canImport`), `Swiflow` (Component, VNode, EnvironmentValues, `embed`, `link`, `withEnvironment`, `Ref`, `ChildrenBuilder`).

**Critical codebase facts:**
- `link()` in `Sources/Swiflow/DSL/Elements.swift` already produces `<a>` tags (named `link` to avoid the short `a()` free function). Use `link(...)` to render anchor elements.
- `embed { MyComponent() }` is how you wrap a Component in a VNode.
- Tests: `@testable import SwiflowRouter`, `@MainActor @Suite("...") struct FooTests`, `@Test("...") func name()`, `#expect(...)`.
- Swift 6 strict concurrency — every new target uses `.swiftLanguageMode(.v6)`.
- Cross-module package visibility: use `package` not `internal` for types shared across `SwiflowRouter` + tests.
- `RouteDefinition.factory` type is `(RouterContext) -> VNode` (non-`@Sendable`, non-`@MainActor`) — same pattern as `ComponentDescription.factory`. The diff calls these closures on the main actor.

---

## File Map

| File | Status | Responsibility |
|---|---|---|
| `Package.swift` | Modify | Add `SwiflowRouter` library + `SwiflowRouterTests` test target |
| `Sources/SwiflowRouter/Core/RoutePattern.swift` | Create | Path-pattern parsing + full/prefix matching |
| `Sources/SwiflowRouter/Core/RouterContext.swift` | Create | `RouterContext` struct + `Router` struct |
| `Sources/SwiflowRouter/Core/RouterKey.swift` | Create | Private `RouterKey` + `EnvironmentValues.router` extension |
| `Sources/SwiflowRouter/Core/RouteDefinition.swift` | Create | `package struct RouteDefinition` |
| `Sources/SwiflowRouter/Core/RouteBuilder.swift` | Create | `@resultBuilder RouteBuilder` + `Route(...)` DSL free functions |
| `Sources/SwiflowRouter/Core/RouteMatching.swift` | Create | `matchRoutes` + query-string parsing |
| `Sources/SwiflowRouter/Web/RouterRoot.swift` | Create | `RouterRoot: Component` (WASM bridge) |
| `Sources/SwiflowRouter/Web/Link.swift` | Create | `Link: Component` (two inits, WASM bridge) |
| `Tests/SwiflowRouterTests/RoutePatternTests.swift` | Create | Pattern matching unit tests |
| `Tests/SwiflowRouterTests/RouterContextTests.swift` | Create | Context construction + query parsing tests |
| `Tests/SwiflowRouterTests/RouteMatchingTests.swift` | Create | Flat, nested, first-match, 404 tests |
| `Tests/SwiflowRouterTests/RouterTests.swift` | Create | `Router` default value + env key tests |
| `examples/MiniRouter/Package.swift` | Create | Example app Package.swift |
| `examples/MiniRouter/index.html` | Create | Example app HTML shell |
| `examples/MiniRouter/Sources/App/App.swift` | Create | `RouterRoot` + 3 routes |
| `examples/MiniRouter/Sources/App/NavBar.swift` | Create | Shared nav with `Link` |
| `examples/MiniRouter/Sources/App/Pages/HomePage.swift` | Create | Home page |
| `examples/MiniRouter/Sources/App/Pages/AboutPage.swift` | Create | About page |
| `examples/MiniRouter/Sources/App/Pages/UsersPage.swift` | Create | Users page (reads `:id` param + programmatic nav) |
| `docs/guides/router.md` | Create | User guide |
| `README.md` | Modify | Update phase status line |

---

## Task 1: Package.swift additions + SwiflowRouter module scaffold

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SwiflowRouter/Core/RoutePattern.swift` (stub)
- Create: `Sources/SwiflowRouter/Web/RouterRoot.swift` (stub, WASM-only)

- [ ] **Step 1: Add SwiflowRouter library + test target to Package.swift**

Open `Package.swift`. Add after the `SwiflowWeb` product line:

```swift
.library(name: "SwiflowRouter", targets: ["SwiflowRouter"]),
```

Add after the `SwiflowCLI` target:

```swift
.target(
    name: "SwiflowRouter",
    dependencies: [
        "Swiflow",
        .product(name: "JavaScriptKit", package: "JavaScriptKit"),
    ],
    path: "Sources/SwiflowRouter",
    swiftSettings: [.swiftLanguageMode(.v6)]
),
```

Add after the `SwiflowCLITests` test target:

```swift
.testTarget(
    name: "SwiflowRouterTests",
    dependencies: ["SwiflowRouter"],
    path: "Tests/SwiflowRouterTests",
    swiftSettings: [.swiftLanguageMode(.v6)]
),
```

- [ ] **Step 2: Create stub source files so the target compiles**

Create `Sources/SwiflowRouter/Core/RoutePattern.swift`:

```swift
// Sources/SwiflowRouter/Core/RoutePattern.swift
import Swiflow
```

Create `Sources/SwiflowRouter/Web/RouterRoot.swift`:

```swift
// Sources/SwiflowRouter/Web/RouterRoot.swift
#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow
#endif
```

Create `Tests/SwiflowRouterTests/RoutePatternTests.swift`:

```swift
// Tests/SwiflowRouterTests/RoutePatternTests.swift
import Testing
@testable import SwiflowRouter
```

- [ ] **Step 3: Verify the build succeeds**

```bash
swift build --package-path /path/to/swiflow 2>&1 | tail -5
```

Expected: `Build complete!` (or equivalent with no errors referencing SwiflowRouter).

- [ ] **Step 4: Verify the test target compiles**

```bash
swift test --package-path /path/to/swiflow --filter SwiflowRouterTests 2>&1 | tail -5
```

Expected: `Test run with 0 tests in 0 suites passed` (empty test target — no failures).

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/SwiflowRouter/ Tests/SwiflowRouterTests/
git commit -m "feat(router): scaffold SwiflowRouter target + test target"
```

---

## Task 2: RoutePattern — path parsing and matching

**Files:**
- Create: `Sources/SwiflowRouter/Core/RoutePattern.swift`
- Create: `Tests/SwiflowRouterTests/RoutePatternTests.swift`

**Context:** `RoutePattern` is an internal type that parses a path string like `"/users/:id"` into segments and matches it against a real path string. It is used by `RouteDefinition` and `matchRoutes`. It is `package` (not `public`) — callers in the same module use it; test targets use `@testable import`.

- [ ] **Step 1: Write the failing tests**

Replace `Tests/SwiflowRouterTests/RoutePatternTests.swift` with:

```swift
// Tests/SwiflowRouterTests/RoutePatternTests.swift
import Testing
@testable import SwiflowRouter

@Suite("RoutePattern")
struct RoutePatternTests {

    @Test("static segment matches exactly")
    func staticSegmentMatchesExactly() {
        let p = RoutePattern("/about")
        #expect(p.match("/about") != nil)
        #expect(p.match("/about") == [:])
    }

    @Test("static segment does not match different path")
    func staticSegmentNoMatch() {
        let p = RoutePattern("/about")
        #expect(p.match("/contact") == nil)
    }

    @Test("param segment captures value")
    func paramSegmentCaptures() {
        let p = RoutePattern("/users/:id")
        let result = p.match("/users/42")
        #expect(result == ["id": "42"])
    }

    @Test("multiple param segments captured")
    func multipleParams() {
        let p = RoutePattern("/users/:userId/posts/:postId")
        let result = p.match("/users/1/posts/99")
        #expect(result == ["userId": "1", "postId": "99"])
    }

    @Test("wildcard captures remaining path")
    func wildcardCapturesRemaining() {
        let p = RoutePattern("*")
        let result = p.match("/anything/goes/here")
        #expect(result?["*"] == "anything/goes/here")
    }

    @Test("trailing slash normalized on input")
    func trailingSlashNormalized() {
        let p = RoutePattern("/about")
        #expect(p.match("/about/") != nil)
    }

    @Test("root path matches /")
    func rootPathMatches() {
        let p = RoutePattern("/")
        #expect(p.match("/") != nil)
        #expect(p.match("") != nil)
    }

    @Test("prefixMatch returns remainder and params")
    func prefixMatchReturnsRemainder() {
        let p = RoutePattern("/users")
        let result = p.prefixMatch("/users/42")
        #expect(result?.params == [:])
        #expect(result?.remainder == "/42")
    }

    @Test("prefixMatch with param segment")
    func prefixMatchWithParam() {
        let p = RoutePattern("/orgs/:org")
        let result = p.prefixMatch("/orgs/apple/repos")
        #expect(result?.params == ["org": "apple"])
        #expect(result?.remainder == "/repos")
    }

    @Test("prefixMatch returns nil when prefix does not match")
    func prefixMatchNoMatch() {
        let p = RoutePattern("/users")
        #expect(p.prefixMatch("/posts/1") == nil)
    }

    @Test("query string stripped before matching")
    func queryStringStripped() {
        let p = RoutePattern("/search")
        #expect(p.match("/search?q=swift") != nil)
    }
}
```

- [ ] **Step 2: Run tests — expect failures**

```bash
swift test --package-path /path/to/swiflow --filter RoutePatternTests 2>&1 | grep -E "error:|FAIL|passed"
```

Expected: compiler errors or all tests fail (RoutePattern not yet implemented).

- [ ] **Step 3: Implement RoutePattern**

Replace `Sources/SwiflowRouter/Core/RoutePattern.swift` with:

```swift
// Sources/SwiflowRouter/Core/RoutePattern.swift
import Swiflow

package struct RoutePattern: Sendable {
    private enum Segment: Sendable {
        case literal(String)
        case param(String)
        case wildcard
    }

    private let segments: [Segment]

    package init(_ pattern: String) {
        let stripped = Self.stripQuery(pattern)
        let normalized = stripped.hasSuffix("/") && stripped.count > 1
            ? String(stripped.dropLast())
            : stripped
        let withoutLeadingSlash = normalized.hasPrefix("/")
            ? String(normalized.dropFirst())
            : normalized
        if withoutLeadingSlash.isEmpty {
            segments = []
        } else {
            segments = withoutLeadingSlash
                .split(separator: "/", omittingEmptySubsequences: false)
                .map { part in
                    if part == "*" { return .wildcard }
                    if part.hasPrefix(":") { return .param(String(part.dropFirst())) }
                    return .literal(String(part))
                }
        }
    }

    /// Full match: returns param dict on match, nil on no-match.
    /// Returns [:] for a static match with no params.
    package func match(_ path: String) -> [String: String]? {
        let parts = splitPath(normalize(path))
        return matchFull(segments, parts: parts)
    }

    /// Prefix match: returns (remainder, params) when this pattern matches
    /// a prefix of `path`. `remainder` is the unmatched suffix (always
    /// starts with `/`).
    package func prefixMatch(_ path: String) -> (remainder: String, params: [String: String])? {
        let parts = splitPath(normalize(path))
        guard let (params, remaining) = matchPrefix(segments, parts: parts) else { return nil }
        let remainder = remaining.isEmpty ? "/" : "/" + remaining.joined(separator: "/")
        return (remainder, params)
    }

    // MARK: - Private helpers

    private static func stripQuery(_ path: String) -> String {
        if let q = path.firstIndex(of: "?") { return String(path[path.startIndex..<q]) }
        return path
    }

    private func normalize(_ path: String) -> String {
        var s = Self.stripQuery(path)
        while s.hasSuffix("/") && s.count > 1 { s.removeLast() }
        if s.hasPrefix("/") { s = String(s.dropFirst()) }
        return s
    }

    private func splitPath(_ normalized: String) -> [String] {
        normalized.isEmpty ? [] : normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    }

    private func matchFull(_ segs: [Segment], parts: [String]) -> [String: String]? {
        var params: [String: String] = [:]
        var i = 0
        for seg in segs {
            switch seg {
            case .literal(let expected):
                guard i < parts.count, parts[i] == expected else { return nil }
                i += 1
            case .param(let name):
                guard i < parts.count else { return nil }
                params[name] = parts[i]
                i += 1
            case .wildcard:
                params["*"] = parts[i...].joined(separator: "/")
                i = parts.count
            }
        }
        guard i == parts.count else { return nil }
        return params
    }

    private func matchPrefix(_ segs: [Segment], parts: [String]) -> ([String: String], [String])? {
        var params: [String: String] = [:]
        var i = 0
        for seg in segs {
            switch seg {
            case .literal(let expected):
                guard i < parts.count, parts[i] == expected else { return nil }
                i += 1
            case .param(let name):
                guard i < parts.count else { return nil }
                params[name] = parts[i]
                i += 1
            case .wildcard:
                params["*"] = parts[i...].joined(separator: "/")
                return (params, [])
            }
        }
        return (params, Array(parts[i...]))
    }
}
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
swift test --package-path /path/to/swiflow --filter RoutePatternTests 2>&1 | tail -5
```

Expected: `Test run with 11 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowRouter/Core/RoutePattern.swift Tests/SwiflowRouterTests/RoutePatternTests.swift
git commit -m "feat(router): RoutePattern — path parsing and full/prefix matching"
```

---

## Task 3: RouterContext, Router, and RouterKey

**Files:**
- Create: `Sources/SwiflowRouter/Core/RouterContext.swift`
- Create: `Sources/SwiflowRouter/Core/RouterKey.swift`
- Create: `Tests/SwiflowRouterTests/RouterContextTests.swift`
- Create: `Tests/SwiflowRouterTests/RouterTests.swift`

**Context:** `RouterContext` is what route factory closures receive (path matched, params, query). `Router` is what `@Environment(\.router)` gives components (current path + navigation actions). `RouterKey` is the private `EnvironmentKey` conformance. `EnvironmentValues` is in `Swiflow` — we extend it here with `var router: Router`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiflowRouterTests/RouterContextTests.swift`:

```swift
// Tests/SwiflowRouterTests/RouterContextTests.swift
import Testing
@testable import SwiflowRouter

@Suite("RouterContext")
struct RouterContextTests {

    @Test("path field stored correctly")
    func pathField() {
        let ctx = RouterContext(path: "/users/42", params: ["id": "42"], query: [:])
        #expect(ctx.path == "/users/42")
    }

    @Test("params field stored correctly")
    func paramsField() {
        let ctx = RouterContext(path: "/", params: ["id": "7"], query: [:])
        #expect(ctx.params["id"] == "7")
    }

    @Test("query field stored correctly")
    func queryField() {
        let ctx = RouterContext(path: "/search", params: [:], query: ["q": "swift", "page": "2"])
        #expect(ctx.query["q"] == "swift")
        #expect(ctx.query["page"] == "2")
    }

    @Test("default init has empty params and query")
    func defaultInit() {
        let ctx = RouterContext(path: "/")
        #expect(ctx.params.isEmpty)
        #expect(ctx.query.isEmpty)
    }
}
```

Create `Tests/SwiflowRouterTests/RouterTests.swift`:

```swift
// Tests/SwiflowRouterTests/RouterTests.swift
import Testing
@testable import SwiflowRouter
import Swiflow

@Suite("Router + EnvironmentValues")
struct RouterTests {

    @Test("default Router path is /")
    func defaultRouterPath() {
        let env = EnvironmentValues()
        #expect(env.router.path == "/")
    }

    @Test("default Router navigate is a no-op")
    func defaultNavigateIsNoOp() {
        let env = EnvironmentValues()
        // Should not crash
        env.router.navigate("/test")
    }

    @Test("default Router replace is a no-op")
    func defaultReplaceIsNoOp() {
        let env = EnvironmentValues()
        env.router.replace("/test")
    }

    @Test("default Router back is a no-op")
    func defaultBackIsNoOp() {
        let env = EnvironmentValues()
        env.router.back()
    }

    @Test("EnvironmentValues router can be overridden")
    func routerCanBeOverridden() {
        var navigated = ""
        var env = EnvironmentValues()
        env.router = Router(path: "/custom", navigate: { navigated = $0 }, replace: { _ in }, back: {})
        #expect(env.router.path == "/custom")
        env.router.navigate("/new")
        #expect(navigated == "/new")
    }
}
```

- [ ] **Step 2: Run tests — expect failures**

```bash
swift test --package-path /path/to/swiflow --filter "RouterContextTests|RouterTests" 2>&1 | grep -E "error:|FAIL"
```

Expected: compiler errors (types not yet defined).

- [ ] **Step 3: Implement RouterContext and Router**

Create `Sources/SwiflowRouter/Core/RouterContext.swift`:

```swift
// Sources/SwiflowRouter/Core/RouterContext.swift
import Swiflow

/// The runtime context injected into route factory closures.
/// Carries the matched path, extracted `:param` captures, and
/// parsed `?key=value` query parameters.
public struct RouterContext: Sendable {
    public let path: String
    public let params: [String: String]
    public let query: [String: String]

    public init(
        path: String,
        params: [String: String] = [:],
        query: [String: String] = [:]
    ) {
        self.path = path
        self.params = params
        self.query = query
    }
}

/// The value injected into `@Environment(\.router)`.
/// Gives components read access to the current path and write
/// access via `navigate`, `replace`, and `back`.
public struct Router: Sendable {
    public let path: String
    public let navigate: @Sendable (String) -> Void
    public let replace: @Sendable (String) -> Void
    public let back: @Sendable () -> Void

    public init(
        path: String,
        navigate: @escaping @Sendable (String) -> Void,
        replace: @escaping @Sendable (String) -> Void,
        back: @escaping @Sendable () -> Void
    ) {
        self.path = path
        self.navigate = navigate
        self.replace = replace
        self.back = back
    }
}
```

- [ ] **Step 4: Implement RouterKey + EnvironmentValues extension**

Create `Sources/SwiflowRouter/Core/RouterKey.swift`:

```swift
// Sources/SwiflowRouter/Core/RouterKey.swift
import Swiflow

private enum RouterKey: EnvironmentKey {
    static let defaultValue = Router(
        path: "/",
        navigate: { _ in },
        replace: { _ in },
        back: {}
    )
}

public extension EnvironmentValues {
    /// The active router. Read with `@Environment(\.router) var router`.
    /// Defaults to a no-op router with `path == "/"` when no `RouterRoot`
    /// is present — useful for snapshot tests and components rendered
    /// outside a router context.
    var router: Router {
        get { self[RouterKey.self] }
        set { self[RouterKey.self] = newValue }
    }
}
```

- [ ] **Step 5: Run tests — expect all pass**

```bash
swift test --package-path /path/to/swiflow --filter "RouterContextTests|RouterTests" 2>&1 | tail -5
```

Expected: `Test run with 9 tests in 2 suites passed`.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowRouter/Core/RouterContext.swift \
        Sources/SwiflowRouter/Core/RouterKey.swift \
        Tests/SwiflowRouterTests/RouterContextTests.swift \
        Tests/SwiflowRouterTests/RouterTests.swift
git commit -m "feat(router): RouterContext, Router, RouterKey + env extension"
```

---

## Task 4: RouteDefinition + RouteBuilder + Route DSL functions

**Files:**
- Create: `Sources/SwiflowRouter/Core/RouteDefinition.swift`
- Create: `Sources/SwiflowRouter/Core/RouteBuilder.swift`

**Context:** `RouteDefinition` is the internal type produced by `Route(...)` calls. Its `factory` is a closure `(RouterContext) -> VNode` called by `matchRoutes` when a route matches. The `children` array is non-empty only for namespace routes (`Route("/prefix") { children }`). `RouteBuilder` is the `@resultBuilder` powering the trailing-closure DSL. The three `Route` free functions are the public API.

`embed { MyComponent() }` is the correct way to turn a Component into a VNode — import it from `Swiflow`. Factory closures created by `Route<C: Component>(_ path:, _ factory:)` wrap the user's component factory inside `embed { }`, so the diff can manage the Component's lifecycle.

- [ ] **Step 1: Create RouteDefinition**

Create `Sources/SwiflowRouter/Core/RouteDefinition.swift`:

```swift
// Sources/SwiflowRouter/Core/RouteDefinition.swift
import Swiflow

/// Internal unit of the route tree. Callers build these through the
/// `Route(...)` DSL free functions — never directly.
package struct RouteDefinition {
    package let pattern: RoutePattern
    /// Called by `matchRoutes` when this route's pattern matches the
    /// current path. Returns the VNode to render. Non-`@MainActor`
    /// because the closure is created from `@MainActor` context and
    /// called from `RouterRoot.body` (also `@MainActor`).
    package let factory: (RouterContext) -> VNode
    /// Non-empty for namespace routes created with `Route("/prefix") { children }`.
    package let children: [RouteDefinition]

    package init(
        pattern: RoutePattern,
        factory: @escaping (RouterContext) -> VNode,
        children: [RouteDefinition] = []
    ) {
        self.pattern = pattern
        self.factory = factory
        self.children = children
    }
}
```

- [ ] **Step 2: Create RouteBuilder + Route DSL functions**

Create `Sources/SwiflowRouter/Core/RouteBuilder.swift`:

```swift
// Sources/SwiflowRouter/Core/RouteBuilder.swift
import Swiflow

/// Accumulates `RouteDefinition` values from a trailing-closure block.
/// Mirrors `ChildrenBuilder` from `Swiflow` but produces
/// `[RouteDefinition]` instead of `[VNode]`.
@resultBuilder
public enum RouteBuilder {
    public static func buildBlock(_ components: [RouteDefinition]...) -> [RouteDefinition] {
        components.flatMap { $0 }
    }
    public static func buildExpression(_ expression: RouteDefinition) -> [RouteDefinition] {
        [expression]
    }
    public static func buildOptional(_ component: [RouteDefinition]?) -> [RouteDefinition] {
        component ?? []
    }
    public static func buildEither(first component: [RouteDefinition]) -> [RouteDefinition] {
        component
    }
    public static func buildEither(second component: [RouteDefinition]) -> [RouteDefinition] {
        component
    }
    public static func buildArray(_ components: [[RouteDefinition]]) -> [RouteDefinition] {
        components.flatMap { $0 }
    }
}

// MARK: - Route DSL

/// Leaf route whose component factory ignores the router context.
///
/// ```swift
/// Route("/about") { AboutPage() }
/// ```
public func Route<C: Component>(
    _ path: String,
    _ factory: @escaping () -> C
) -> RouteDefinition {
    RouteDefinition(pattern: RoutePattern(path)) { _ in
        embed { factory() }
    }
}

/// Leaf route whose component factory receives the router context
/// (useful for reading `:param` captures and query params).
///
/// ```swift
/// Route("/users/:id") { ctx in UserPage(id: ctx.params["id"] ?? "") }
/// ```
public func Route<C: Component>(
    _ path: String,
    _ factory: @escaping (RouterContext) -> C
) -> RouteDefinition {
    RouteDefinition(pattern: RoutePattern(path)) { ctx in
        embed { factory(ctx) }
    }
}

/// Namespace route — groups child routes under a common path prefix.
///
/// ```swift
/// Route("/users") {
///     Route("/") { UserListPage() }
///     Route("/:id") { ctx in UserDetailPage(id: ctx.params["id"] ?? "") }
/// }
/// ```
public func Route(
    _ path: String,
    @RouteBuilder _ children: () -> [RouteDefinition]
) -> RouteDefinition {
    RouteDefinition(pattern: RoutePattern(path), factory: { _ in .text("") }, children: children())
}
```

- [ ] **Step 3: Verify it compiles**

```bash
swift build --package-path /path/to/swiflow 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiflowRouter/Core/RouteDefinition.swift \
        Sources/SwiflowRouter/Core/RouteBuilder.swift
git commit -m "feat(router): RouteDefinition, RouteBuilder, Route DSL functions"
```

---

## Task 5: matchRoutes — route resolution algorithm

**Files:**
- Create: `Sources/SwiflowRouter/Core/RouteMatching.swift`
- Create: `Tests/SwiflowRouterTests/RouteMatchingTests.swift`

**Context:** `matchRoutes` is the core of the router. It walks the `[RouteDefinition]` tree depth-first, trying each route in order. For leaf routes it uses full pattern matching. For namespace routes (non-empty `children`) it uses prefix matching and recurses. It also strips the query string and parses it into `RouterContext.query`.

Tests use `RouteDefinition(pattern:factory:children:)` directly (instead of `Route(...)` DSL) so they're self-contained and don't depend on Components.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiflowRouterTests/RouteMatchingTests.swift`:

```swift
// Tests/SwiflowRouterTests/RouteMatchingTests.swift
import Testing
@testable import SwiflowRouter
import Swiflow

// Helpers — build RouteDefinition with a VNode factory (no Component needed)
private func leaf(_ path: String, result: VNode) -> RouteDefinition {
    RouteDefinition(pattern: RoutePattern(path), factory: { _ in result })
}

private func leafCapture(_ path: String, into box: UnsafeMutablePointer<RouterContext?>) -> RouteDefinition {
    RouteDefinition(pattern: RoutePattern(path), factory: { ctx in
        box.pointee = ctx
        return .text("matched")
    })
}

@MainActor
@Suite("matchRoutes")
struct RouteMatchingTests {

    @Test("flat route matches exact path")
    func flatRouteMatchesExactPath() {
        let routes = [leaf("/about", result: .text("about"))]
        #expect(matchRoutes(routes, path: "/about") == .text("about"))
    }

    @Test("flat route returns nil on no match")
    func flatRouteNoMatch() {
        let routes = [leaf("/about", result: .text("about"))]
        #expect(matchRoutes(routes, path: "/contact") == nil)
    }

    @Test("first match wins")
    func firstMatchWins() {
        let routes = [
            leaf("/page", result: .text("first")),
            leaf("/page", result: .text("second")),
        ]
        #expect(matchRoutes(routes, path: "/page") == .text("first"))
    }

    @Test("param captured in RouterContext")
    func paramCapturedInContext() {
        var captured: RouterContext? = nil
        let route = leafCapture("/users/:id", into: &captured)
        _ = matchRoutes([route], path: "/users/42")
        #expect(captured?.params["id"] == "42")
    }

    @Test("query string parsed into RouterContext.query")
    func queryStringParsed() {
        var captured: RouterContext? = nil
        let route = leafCapture("/search", into: &captured)
        _ = matchRoutes([route], path: "/search?q=swift&page=2")
        #expect(captured?.query["q"] == "swift")
        #expect(captured?.query["page"] == "2")
    }

    @Test("query string stripped before pattern matching")
    func queryStringDoesNotBreakMatch() {
        let routes = [leaf("/about", result: .text("about"))]
        #expect(matchRoutes(routes, path: "/about?utm=foo") != nil)
    }

    @Test("nested route matches child path")
    func nestedRouteMatchesChild() {
        let userList = leaf("/", result: .text("list"))
        let userDetail = leaf("/:id", result: .text("detail"))
        let usersGroup = RouteDefinition(
            pattern: RoutePattern("/users"),
            factory: { _ in .text("") },
            children: [userList, userDetail]
        )
        #expect(matchRoutes([usersGroup], path: "/users") == .text("list"))
        #expect(matchRoutes([usersGroup], path: "/users/42") == .text("detail"))
    }

    @Test("nested params merged with parent params")
    func nestedParamsMerged() {
        var captured: RouterContext? = nil
        let child = RouteDefinition(pattern: RoutePattern("/:repoId"), factory: { ctx in
            captured = ctx
            return .text("repo")
        })
        let parent = RouteDefinition(
            pattern: RoutePattern("/orgs/:org"),
            factory: { _ in .text("") },
            children: [child]
        )
        _ = matchRoutes([parent], path: "/orgs/apple/myrepo")
        #expect(captured?.params["org"] == "apple")
        #expect(captured?.params["repoId"] == "myrepo")
    }

    @Test("wildcard catch-all route matches any path")
    func wildcardCatchAll() {
        let routes = [
            leaf("/about", result: .text("about")),
            leaf("*", result: .text("404")),
        ]
        #expect(matchRoutes(routes, path: "/anything") == .text("404"))
    }

    @Test("returns nil when no route matches (no catch-all)")
    func returnsNilForUnmatchedPath() {
        let routes = [leaf("/about", result: .text("about"))]
        #expect(matchRoutes(routes, path: "/missing") == nil)
    }
}
```

- [ ] **Step 2: Run tests — expect failures**

```bash
swift test --package-path /path/to/swiflow --filter RouteMatchingTests 2>&1 | grep -E "error:|FAIL"
```

Expected: compiler errors (`matchRoutes` not yet defined).

- [ ] **Step 3: Implement matchRoutes**

Create `Sources/SwiflowRouter/Core/RouteMatching.swift`:

```swift
// Sources/SwiflowRouter/Core/RouteMatching.swift
import Swiflow

/// Walks `routes` depth-first, returns the first matching route's VNode.
/// Strips the query string before pattern matching; parsed query params
/// are available in `RouterContext.query`. Returns `nil` if no route matches.
@MainActor
package func matchRoutes(_ routes: [RouteDefinition], path: String) -> VNode? {
    let (cleanPath, query) = splitQuery(path)
    return matchList(routes, path: cleanPath, parentParams: [:], query: query)
}

// MARK: - Private helpers

@MainActor
private func matchList(
    _ routes: [RouteDefinition],
    path: String,
    parentParams: [String: String],
    query: [String: String]
) -> VNode? {
    for route in routes {
        if route.children.isEmpty {
            // Leaf: attempt full match
            if let params = route.pattern.match(path) {
                let merged = parentParams.merging(params) { _, new in new }
                let ctx = RouterContext(path: path, params: merged, query: query)
                return route.factory(ctx)
            }
        } else {
            // Namespace: attempt prefix match, recurse into children
            if let (remainder, params) = route.pattern.prefixMatch(path) {
                let merged = parentParams.merging(params) { _, new in new }
                if let result = matchList(route.children, path: remainder, parentParams: merged, query: query) {
                    return result
                }
            }
        }
    }
    return nil
}

private func splitQuery(_ path: String) -> (clean: String, query: [String: String]) {
    guard let qIdx = path.firstIndex(of: "?") else { return (path, [:]) }
    let clean = String(path[path.startIndex..<qIdx])
    let queryString = String(path[path.index(after: qIdx)...])
    var query: [String: String] = [:]
    for pair in queryString.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1)
        if parts.count == 2 {
            let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            query[key] = value
        }
    }
    return (clean, query)
}
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
swift test --package-path /path/to/swiflow --filter RouteMatchingTests 2>&1 | tail -5
```

Expected: `Test run with 10 tests in 1 suite passed`.

- [ ] **Step 5: Run the full test suite — verify no regressions**

```bash
swift test --package-path /path/to/swiflow 2>&1 | tail -5
```

Expected: all tests pass (count grows by 10 + earlier SwiflowRouter tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowRouter/Core/RouteMatching.swift \
        Tests/SwiflowRouterTests/RouteMatchingTests.swift
git commit -m "feat(router): matchRoutes — flat + nested route resolution with query parsing"
```

---

## Task 6: RouterRoot component (WASM bridge)

**Files:**
- Replace stub: `Sources/SwiflowRouter/Web/RouterRoot.swift`

**Context:** `RouterRoot` is a `Component` (reference type, `@MainActor`). It holds `@State var currentPath: String` initialised from the live browser URL. On `onAppear()` it installs a `hashchange` or `popstate` listener via `JSClosure`. Mutating `currentPath` triggers a re-render via `@State`. Its `body` calls `matchRoutes`, wraps the result in `withEnvironment(\.router, ...)`, and falls back to a 404 text node.

`@State` initial value must be set via `_currentPath = State(wrappedValue: ...)` in `init` — the standard Swift pattern for overriding a property-wrapper default in a custom initializer.

`withEnvironment` and `embed` come from `Swiflow`. `matchRoutes` is `package` in the same module.

This file is WASM-only — wrap everything in `#if canImport(JavaScriptKit)`.

- [ ] **Step 1: Implement RouterRoot**

Replace `Sources/SwiflowRouter/Web/RouterRoot.swift` with:

```swift
// Sources/SwiflowRouter/Web/RouterRoot.swift
#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// The root component of a routed Swiflow app.
///
/// Mounts inside `Swiflow.render(into:_:)` and owns the entire routing
/// lifecycle: URL reading, browser event listening, route matching, and
/// `@Environment(\.router)` injection.
///
/// ```swift
/// Swiflow.render(into: "#app") {
///     RouterRoot {
///         Route("/") { HomePage() }
///         Route("/about") { AboutPage() }
///         Route("/users/:id") { ctx in UsersPage(id: ctx.params["id"] ?? "") }
///     }
/// }
/// ```
public final class RouterRoot: Component {
    public enum Mode { case hash, history }

    @State private var currentPath: String = "/"
    private let mode: Mode
    private let routes: [RouteDefinition]
    private var listenerClosure: JSClosure?

    public init(mode: Mode = .hash, @RouteBuilder routes: () -> [RouteDefinition]) {
        self.mode = mode
        self.routes = routes()
        _currentPath = State(wrappedValue: Self.readPath(mode: mode))
    }

    public var body: VNode {
        let router = Router(
            path: currentPath,
            navigate: { [weak self] path in self?.push(path) },
            replace:  { [weak self] path in self?.replacePath(path) },
            back:     { JSObject.global.history.back!() }
        )
        let matched = matchRoutes(routes, path: currentPath)
        return withEnvironment(\.router, router) {
            matched ?? VNode.text("404 — no route matched \(currentPath)")
        }
    }

    public func onAppear() {
        let closure = JSClosure { [weak self] _ -> JSValue in
            self?.sync()
            return .undefined
        }
        let event = mode == .hash ? "hashchange" : "popstate"
        _ = JSObject.global.window.addEventListener!(event.jsValue, closure)
        listenerClosure = closure
    }

    // MARK: - Private

    private func sync() {
        currentPath = Self.readPath(mode: mode)
    }

    private static func readPath(mode: Mode) -> String {
        let loc = JSObject.global.window.location
        switch mode {
        case .hash:
            let hash = loc.hash.string ?? ""
            let path = hash.hasPrefix("#") ? String(hash.dropFirst()) : ""
            return path.isEmpty ? "/" : path
        case .history:
            return loc.pathname.string ?? "/"
        }
    }

    private func push(_ path: String) {
        switch mode {
        case .hash:
            JSObject.global.window.location.hash = path.jsValue
        case .history:
            _ = JSObject.global.history.pushState!(JSValue.null, "".jsValue, path.jsValue)
            currentPath = path
        }
    }

    private func replacePath(_ path: String) {
        switch mode {
        case .hash:
            _ = JSObject.global.history.replaceState!(JSValue.null, "".jsValue, ("#" + path).jsValue)
        case .history:
            _ = JSObject.global.history.replaceState!(JSValue.null, "".jsValue, path.jsValue)
        }
        currentPath = path
    }
}
#endif
```

- [ ] **Step 2: Verify the full build compiles (macOS + swift build)**

```bash
swift build --package-path /path/to/swiflow 2>&1 | tail -5
```

Expected: `Build complete!` (the `#if canImport(JavaScriptKit)` guard means RouterRoot's body is skipped on macOS — only the `import` lines and the `#if` wrapper compile).

- [ ] **Step 3: Run tests — no regressions**

```bash
swift test --package-path /path/to/swiflow 2>&1 | tail -5
```

Expected: all previously passing tests still pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiflowRouter/Web/RouterRoot.swift
git commit -m "feat(router): RouterRoot component — hash/history mode, @State currentPath, event listener"
```

---

## Task 7: Link component (WASM bridge)

**Files:**
- Create: `Sources/SwiflowRouter/Web/Link.swift`

**Context:** `Link` is a `Component` (not a free function) because it needs to call `event.preventDefault()` on the raw DOM click event — which is not accessible through `EventInfo`. Instead, `Link` uses `Ref<JSObject>` + `onAppear()` to install a direct `JSClosure` event listener on the rendered anchor element.

A single `Link` class exposes two initializers. Internally it stores `enum Content { case label(String); case children([VNode]) }`.

`link(...)` (lowercase, from `Swiflow/DSL/Elements.swift`) produces `<a>` tags — use it in `body`. `Ref<JSObject>` and `.ref(linkRef)` come from `Swiflow`. `AmbientEnvironment.current` is accessed at mount time (in `onAppear`) to read the `router.navigate` closure.

This file is WASM-only — wrap everything in `#if canImport(JavaScriptKit)`.

- [ ] **Step 1: Implement Link**

Create `Sources/SwiflowRouter/Web/Link.swift`:

```swift
// Sources/SwiflowRouter/Web/Link.swift
#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

/// An in-app navigation link. Renders an `<a>` element whose click handler
/// calls `router.navigate(path)` and prevents full-page reload via
/// `event.preventDefault()`.
///
/// Two call shapes:
/// ```swift
/// Link("/about", "About")            // label variant
/// Link("/about") { img(...) }        // children variant
/// ```
public final class Link: Component {
    private enum Content {
        case label(String)
        case children([VNode])
    }

    private let path: String
    private let content: Content
    private let linkRef = Ref<JSObject>()
    private var clickClosure: JSClosure?
    // Captured during body evaluation (when AmbientEnvironment.current is
    // set by the diff). Must NOT be read in onAppear/onChange — those run
    // outside a body call and see the default no-op environment.
    private var capturedNavigate: (@Sendable (String) -> Void)?

    /// Label variant — renders `<a href="{path}">{label}</a>`.
    public init(_ path: String, _ label: String) {
        self.path = path
        self.content = .label(label)
    }

    /// Children variant — renders `<a href="{path}">{ children }</a>`.
    public init(_ path: String, @ChildrenBuilder _ children: () -> [VNode]) {
        self.path = path
        self.content = .children(children())
    }

    public var body: VNode {
        // Read navigate HERE — AmbientEnvironment.current is set by the
        // diff only during body evaluation. Storing it lets onAppear use it.
        capturedNavigate = AmbientEnvironment.current[keyPath: \.router].navigate
        switch content {
        case .label(let text):
            return link(.attr("href", path), .ref(linkRef)) { VNode.text(text) }
        case .children(let nodes):
            return link(.attr("href", path), .ref(linkRef)) { nodes }
        }
    }

    public func onAppear() {
        let navigate = capturedNavigate ?? { _ in }
        let targetPath = path
        let closure = JSClosure { args -> JSValue in
            args.first?.object?.preventDefault.function?()
            navigate(targetPath)
            return .undefined
        }
        linkRef.wrappedValue?.addEventListener.function?("click", closure)
        clickClosure = closure
    }
}
#endif
```

- [ ] **Step 2: Verify the build**

```bash
swift build --package-path /path/to/swiflow 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 3: Run tests — no regressions**

```bash
swift test --package-path /path/to/swiflow 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiflowRouter/Web/Link.swift
git commit -m "feat(router): Link component — single class, label + children variants, JSClosure click handler"
```

---

## Task 8: examples/MiniRouter/ — 3-page demo app

**Files:**
- Create: `examples/MiniRouter/Package.swift`
- Create: `examples/MiniRouter/index.html`
- Create: `examples/MiniRouter/Sources/App/App.swift`
- Create: `examples/MiniRouter/Sources/App/NavBar.swift`
- Create: `examples/MiniRouter/Sources/App/Pages/HomePage.swift`
- Create: `examples/MiniRouter/Sources/App/Pages/AboutPage.swift`
- Create: `examples/MiniRouter/Sources/App/Pages/UsersPage.swift`

**Context:** Mirror the `examples/HelloWorld/` structure. The example depends on `SwiflowWeb` and `SwiflowRouter` via local path. It demonstrates `RouterRoot`, `Route`, `Link`, `@Environment(\.router)` programmatic navigation, and param extraction. The app uses hash mode (default).

- [ ] **Step 1: Create Package.swift**

Create `examples/MiniRouter/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiniRouter",
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

- [ ] **Step 2: Create index.html**

Create `examples/MiniRouter/index.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>MiniRouter — Swiflow Phase 11 Demo</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 640px; margin: 2rem auto; padding: 0 1rem; }
    nav { display: flex; gap: 1rem; margin-bottom: 2rem; border-bottom: 1px solid #ccc; padding-bottom: 1rem; }
    nav a { text-decoration: none; color: #0070f3; }
    nav a:hover { text-decoration: underline; }
    button { padding: 0.4rem 1rem; cursor: pointer; }
  </style>
</head>
<body>
  <div id="app"></div>
  <!-- Load the Swiflow driver BEFORE the WASM bootstrap so
       `window.swiflow` exists when App.main calls Swiflow.render. -->
  <script src=".build/plugins/PackageToJS/outputs/Package/platforms/browser.js" type="module">
  </script>
</body>
</html>
```

- [ ] **Step 3: Create shared NavBar component**

Create `examples/MiniRouter/Sources/App/NavBar.swift`:

```swift
import Swiflow
import SwiflowWeb
import SwiflowRouter
import JavaScriptKit

final class NavBar: Component {
    var body: VNode {
        nav {
            embed { Link("/", "Home") }
            embed { Link("/about", "About") }
            embed { Link("/users/42", "User 42") }
        }
    }
}
```

- [ ] **Step 4: Create page components**

Create `examples/MiniRouter/Sources/App/Pages/HomePage.swift`:

```swift
import Swiflow
import SwiflowWeb
import JavaScriptKit

final class HomePage: Component {
    var body: VNode {
        div {
            embed { NavBar() }
            h1("Home")
            p("Welcome to the MiniRouter demo.")
        }
    }
}
```

Create `examples/MiniRouter/Sources/App/Pages/AboutPage.swift`:

```swift
import Swiflow
import SwiflowWeb
import JavaScriptKit

final class AboutPage: Component {
    var body: VNode {
        div {
            embed { NavBar() }
            h1("About")
            p("This demo exercises RouterRoot, Route, Link, and programmatic navigation.")
        }
    }
}
```

Create `examples/MiniRouter/Sources/App/Pages/UsersPage.swift`:

```swift
import Swiflow
import SwiflowWeb
import SwiflowRouter
import JavaScriptKit

final class UsersPage: Component {
    let userId: String
    @Environment(\.router) var router

    init(userId: String) {
        self.userId = userId
    }

    var body: VNode {
        // Read router.navigate HERE — inside body, where AmbientEnvironment.current
        // is set by the diff. Accessing self.router from a click handler (outside
        // body) would return the default no-op, since the ambient is not set then.
        let navigate = router.navigate
        return div {
            embed { NavBar() }
            h1("User: \(userId)")
            p("Loaded via the :id route param.")
            button("Go Home", .on(.click) { navigate("/") })
        }
    }
}
```

- [ ] **Step 5: Create App.swift entry point**

Create `examples/MiniRouter/Sources/App/App.swift`:

```swift
import Swiflow
import SwiflowWeb
import SwiflowRouter
import JavaScriptKit

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") {
            RouterRoot {
                Route("/") { HomePage() }
                Route("/about") { AboutPage() }
                Route("/users/:id") { ctx in
                    UsersPage(userId: ctx.params["id"] ?? "unknown")
                }
            }
        }
    }
}
```

- [ ] **Step 6: Verify the example compiles on macOS (Package resolve only)**

```bash
swift package resolve --package-path /path/to/swiflow/examples/MiniRouter 2>&1 | tail -5
```

Expected: resolves without errors (note: the WASM build requires the WASM SDK — macOS `swift build` is expected to fail on WASM-only code, which is correct).

- [ ] **Step 7: Commit**

```bash
git add examples/MiniRouter/
git commit -m "feat(router): examples/MiniRouter — 3-page RouterRoot + Link + programmatic nav demo"
```

---

## Task 9: docs/guides/router.md + README status line

**Files:**
- Create: `docs/guides/router.md`
- Modify: `README.md`

- [ ] **Step 1: Create the router guide**

Create `docs/guides/router.md`:

```markdown
# SwiflowRouter

SwiflowRouter is Swiflow's first-party router. It ships as a separate library
target so non-routed apps pay zero overhead.

## Installation

Add `SwiflowRouter` to your app's `Package.swift`:

```swift
dependencies: [
    .package(path: "../.."),            // or the GitHub URL
    .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", ...),
],
targets: [
    .executableTarget(
        name: "App",
        dependencies: [
            .product(name: "SwiflowWeb", package: "Swiflow"),
            .product(name: "SwiflowRouter", package: "Swiflow"),
        ]
    ),
]
```

## Quick start

```swift
import Swiflow
import SwiflowWeb
import SwiflowRouter

@main struct App {
    @MainActor static func main() {
        Swiflow.render(into: "#app") {
            RouterRoot {
                Route("/") { HomePage() }
                Route("/about") { AboutPage() }
                Route("/users/:id") { ctx in
                    UsersPage(id: ctx.params["id"] ?? "")
                }
            }
        }
    }
}
```

## Routing modes

`RouterRoot` defaults to **hash mode** — URLs like `/#/about`. Hash mode works
on any static host (GitHub Pages, S3, CDN) without server configuration.

```swift
// Hash mode (default) — /#/users/42
RouterRoot { ... }
RouterRoot(mode: .hash) { ... }

// History mode — /users/42 (requires server to serve index.html for all paths)
RouterRoot(mode: .history) { ... }
```

## Route patterns

```swift
Route("/")                              // exact match on root
Route("/about")                         // static segment
Route("/users/:id")                     // :id captures one segment
Route("/files/*")                       // * captures everything including slashes
```

Trailing slashes are normalised — `/about` and `/about/` match the same pattern.

## Receiving route params

```swift
Route("/users/:id") { ctx in
    UserPage(id: ctx.params["id"] ?? "")
}
```

`ctx.query` carries `?key=value` pairs from the URL:

```swift
Route("/search") { ctx in
    SearchPage(query: ctx.query["q"] ?? "")
}
```

## Nested routes

```swift
RouterRoot {
    Route("/") { HomePage() }
    Route("/users") {
        Route("/") { UserListPage() }
        Route("/:id") { ctx in UserDetailPage(id: ctx.params["id"] ?? "") }
    }
}
```

Path `/users/42` matches the nested `/:id` route. Params from parent and child
are merged — a parent `:org` param is available alongside the child's `:repo`.

## Navigation with Link

```swift
// Label variant
embed { Link("/about", "About Us") }

// Children variant (icon, styled text, etc.)
embed { Link("/about") { span("About Us") } }
```

`Link` renders an `<a>` element and intercepts the click to call
`router.navigate(path)` without a full-page reload.

## Programmatic navigation

Use `@Environment(\.router)` inside any component in the router tree:

```swift
final class LogoutButton: Component {
    @Environment(\.router) var router

    var body: VNode {
        button("Log out", .on(.click) { [self] _ in
            // ... clear session ...
            self.router.navigate("/login")
        })
    }
}
```

`router.path` — current path string.
`router.navigate("/path")` — push a new history entry and re-render.
`router.replace("/path")` — replace the current history entry.
`router.back()` — equivalent to `history.back()`.

## 404 handling

If no route matches, `RouterRoot` renders a plain text "404" node. Add a
catch-all route to show a custom page:

```swift
RouterRoot {
    Route("/") { HomePage() }
    Route("*") { NotFoundPage() }   // must be last
}
```
```

- [ ] **Step 2: Update README status line**

In `README.md`, find the current phase status line (search for `Phase 10` or `Status`) and update it to reflect Phase 11:

The exact text will vary — find the line that says something like `Phase 10 (Effects & Environment)` and change it to:

```
Phase 11 (Router)
```

- [ ] **Step 3: Run the full test suite one final time**

```bash
swift test --package-path /path/to/swiflow 2>&1 | tail -5
```

Expected: all tests pass (including all SwiflowRouterTests added in Tasks 2–5).

- [ ] **Step 4: Commit**

```bash
git add docs/guides/router.md README.md
git commit -m "docs(router): user guide + README Phase 11 status"
```

---

## Exit criteria checklist

Before marking Phase 11 complete:

- [ ] `swift test` passes 100% (all SwiflowRouterTests + no regressions in SwiflowTests/SwiflowCLITests)
- [ ] `examples/MiniRouter/` resolves and `swift package js` succeeds with the WASM SDK
- [ ] `@Environment(\.router)` works without a crash when `RouterRoot` is absent (default no-op)
- [ ] `Route("/users/:id") { ctx in ... }` and `Route("/") { ... }` both compile
- [ ] `Link("/about", "About")` and `Link("/about") { ... }` both compile (single type, two inits)
- [ ] `docs/guides/router.md` is committed
- [ ] README status line updated to Phase 11
