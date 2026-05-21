# SwiflowRouter — Phase 11 Design Spec

> **Status:** Approved for implementation 2026-05-21

---

## Goal

Ship a first-party router so multi-page Swiflow apps are buildable without dropping to JavaScript. `RouterRoot`, `Route`, `Link`, and `@Environment(\.router)` give a React-Router-shaped experience while staying entirely in Swift.

---

## Scope (what's in Phase 11)

| In | Out (Phase 13) |
|---|---|
| `RouterRoot`, `Route`, `Routes`, `Link` | `LazyRoute` / real code-splitting |
| Hash mode (default) + history mode | SSR hydration |
| Nested routes with prefix stripping | Advanced guards / redirects |
| `@Environment(\.router)` — navigate, replace, back | Animation transitions between routes |
| `examples/MiniRouter/` 3-page example | |
| macOS-testable route matching tests | |

---

## Architecture

Separate `SwiflowRouter` library target. Depends on `Swiflow` (core types) and `JavaScriptKit` (browser bridge, guarded by `#if canImport(JavaScriptKit)`).

Users of a routed app write:
```swift
import SwiflowWeb      // brings Swiflow via @_exported
import SwiflowRouter   // brings RouterRoot, Route, Link, @Environment(\.router)
```

Non-routed apps add zero router overhead.

### Directory layout

```
Sources/SwiflowRouter/
  Core/
    RoutePattern.swift      — pattern parsing + matching
    RouterContext.swift     — RouterContext, RouterInterface, RouterMode
    RouteDefinition.swift   — RouteDefinition struct
    RouteBuilder.swift      — @resultBuilder + Route/Routes DSL functions
    RouterKey.swift         — EnvironmentValues.router extension
  Web/
    RouterRoot.swift        — Component; event wiring (#if canImport(JavaScriptKit))
    Link.swift              — VNode factory (#if canImport(JavaScriptKit))

Tests/SwiflowRouterTests/
  RoutePatternTests.swift
  RouterContextTests.swift
  RouteMatchingTests.swift
  RouterInterfaceTests.swift

examples/MiniRouter/
  Package.swift
  Sources/App/App.swift
  Sources/App/Pages/HomePage.swift
  Sources/App/Pages/AboutPage.swift
  Sources/App/Pages/UsersPage.swift
  index.html
```

### Package.swift additions

```swift
// Products
.library(name: "SwiflowRouter", targets: ["SwiflowRouter"]),

// Targets
.target(
    name: "SwiflowRouter",
    dependencies: [
        "Swiflow",
        .product(name: "JavaScriptKit", package: "JavaScriptKit"),
    ],
    path: "Sources/SwiflowRouter",
    swiftSettings: [.swiftLanguageMode(.v6)]
),
.testTarget(
    name: "SwiflowRouterTests",
    dependencies: ["SwiflowRouter"],
    path: "Tests/SwiflowRouterTests",
    swiftSettings: [.swiftLanguageMode(.v6)]
),
```

No new top-level `dependencies:` entries — JavaScriptKit is already declared.

---

## Core Types (macOS-testable)

### RoutePattern

Internal type. Parses a path pattern string into a regex + ordered param names.

```swift
struct RoutePattern: Sendable {
    /// Returns nil if the pattern does not match `path`.
    /// Returns [:] for a static match with no params.
    func match(_ path: String) -> [String: String]?

    /// True if `path` starts with this pattern (used for prefix matching in nested routes).
    /// Returns the remaining suffix and extracted params.
    func prefixMatch(_ path: String) -> (remainder: String, params: [String: String])?
}
```

Rules:
- `:name` captures one path segment (`[^/]+`). The capture is stored under `"name"`.
- `*` captures everything including slashes. Stored under `"*"`.
- Static segments are matched literally.
- Trailing `/` is stripped from both pattern and input before matching.

### RouterContext

```swift
public struct RouterContext: Sendable {
    public let path: String               // full matched path
    public let params: [String: String]   // :param captures
    public let query: [String: String]    // ?key=value pairs from query string
}
```

Query string is parsed from the real path at match time (stripped before pattern matching).

### RouterInterface

The value injected into `@Environment(\.router)`.

```swift
public struct RouterInterface: Sendable {
    public let currentPath: String
    public let navigate: @Sendable (String) -> Void   // pushState + re-render
    public let replace:  @Sendable (String) -> Void   // replaceState + re-render
    public let back:     @Sendable () -> Void          // history.back()
}
```

### RouterKey + EnvironmentValues extension

```swift
private enum RouterKey: EnvironmentKey {
    static let defaultValue = RouterInterface(
        currentPath: "/",
        navigate: { _ in },
        replace:  { _ in },
        back:     {}
    )
}

public extension EnvironmentValues {
    var router: RouterInterface {
        get { self[RouterKey.self] }
        set { self[RouterKey.self] = newValue }
    }
}
```

`@Environment(\.router)` works even without `RouterRoot` — the default no-op keeps components compilable in isolation (e.g., snapshot tests).

### RouteDefinition

```swift
public struct RouteDefinition {
    let pattern: RoutePattern
    let factory: (RouterContext) -> VNode
    let children: [RouteDefinition]
}
```

### RouteBuilder + DSL

```swift
@resultBuilder
public struct RouteBuilder {
    public static func buildBlock(_ components: RouteDefinition...) -> [RouteDefinition]
    public static func buildArray(_ components: [[RouteDefinition]]) -> [RouteDefinition]
    public static func buildOptional(_ component: [RouteDefinition]?) -> [RouteDefinition]
    public static func buildEither(first: [RouteDefinition]) -> [RouteDefinition]
    public static func buildEither(second: [RouteDefinition]) -> [RouteDefinition]
}

// Leaf route — no children, component factory ignoring context
public func Route<C: Component>(_ path: String, _ factory: @escaping () -> C) -> RouteDefinition

// Leaf route — factory receives RouterContext (for params, query)
public func Route<C: Component>(_ path: String, _ factory: @escaping (RouterContext) -> C) -> RouteDefinition

// Namespace route — groups children under a common prefix
public func Route(_ path: String, @RouteBuilder _ children: () -> [RouteDefinition]) -> RouteDefinition

// Convenience: no Route wrapper needed when only one level
public func Routes(@RouteBuilder _ children: () -> [RouteDefinition]) -> [RouteDefinition]
```

---

## RouterRoot (WASM bridge)

```swift
#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

public final class RouterRoot: Component {
    public enum Mode { case hash, history }

    @State private var currentPath: String
    private let mode: Mode
    private let routes: [RouteDefinition]
    private var listenerClosure: JSClosure?

    public init(mode: Mode = .hash, @RouteBuilder routes: () -> [RouteDefinition]) {
        self.mode = mode
        self.routes = routes()
        // Override the @State default with the real URL at construction time.
        // Must use the _backing-property assignment pattern because Swift
        // requires stored properties to be initialized before `self` is available.
        _currentPath = State(wrappedValue: Self.readPath(mode: mode))
    }

    public var body: VNode {
        let interface = RouterInterface(
            currentPath: currentPath,
            navigate: { [weak self] path in self?.push(path) },
            replace:  { [weak self] path in self?.replacePath(path) },
            back:     { JSObject.global.history.back!() }
        )
        let matched = matchRoutes(routes, path: currentPath)
        return withEnvironment(\.router, interface) {
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

### Route matching algorithm

`package func matchRoutes(_ routes: [RouteDefinition], path: String) -> VNode?`

1. Strip query string from `path`; save it for `RouterContext.query`.
2. For each `RouteDefinition` in order:
   - If `definition.children` is empty: attempt full `pattern.match(path)`. On match, build `RouterContext` and call `factory(ctx)`. Return the VNode.
   - If `definition.children` is non-empty: attempt `pattern.prefixMatch(path)`. On match, recurse into children with the remainder. Return first non-nil result.
3. Return `nil` (caller renders 404).

First match wins. Order in the `RouteBuilder` closure is the priority order.

---

## Link (WASM bridge)

`Link` is a `Component` (not a free function) because it needs to call `event.preventDefault()` on the raw DOM event, which is not available through the `EventInfo` value type. Using `Ref<JSObject>` + `onAppear()` lets it install a `JSClosure` directly on the element.

```swift
#if canImport(JavaScriptKit)
import JavaScriptKit
import Swiflow

// Label variant
public final class Link: Component {
    private let path: String
    private let label: String
    private let linkRef = Ref<JSObject>()
    private var clickClosure: JSClosure?

    public init(_ path: String, _ label: String) {
        self.path = path
        self.label = label
    }

    public var body: VNode {
        a(.attr("href", path), .ref(linkRef)) { VNode.text(label) }
    }

    public func onAppear() {
        let navigate = AmbientEnvironment.current[keyPath: \.router].navigate
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

// Children variant (convenience wrapper)
public final class LinkContainer: Component {
    private let path: String
    private let children: [VNode]
    private let linkRef = Ref<JSObject>()
    private var clickClosure: JSClosure?

    public init(_ path: String, @ChildrenBuilder _ content: () -> [VNode]) {
        self.path = path
        self.children = content()
    }

    public var body: VNode {
        a(.attr("href", path), .ref(linkRef)) { children }
    }

    public func onAppear() {
        let navigate = AmbientEnvironment.current[keyPath: \.router].navigate
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

Note: `onAppear()` captures `AmbientEnvironment.current[keyPath: \.router].navigate` at mount time. The `navigate` closure is a `@Sendable (String) -> Void` that calls `RouterRoot.push()` — it captures a weak reference to `RouterRoot`, so if the router is unmounted the navigation is a no-op.

---

## Nested Routes

```swift
RouterRoot {
    Route("/") { HomePage() }
    Route("/users") {
        Route("/") { UserListPage() }
        Route("/:id") { ctx in UserDetailPage(id: ctx.params["id"]!) }
    }
    Route("/about") { AboutPage() }
}
```

`Route("/users") { children }` creates a `RouteDefinition` with `children = [...]` and an empty factory. When the matching algorithm encounters a non-empty `children` list, it uses `prefixMatch` on the parent pattern and recurses with the remainder path.

Path `/users/42`:
1. `Route("/")` → no match
2. `Route("/users")` → prefix match, remainder = `/42`
   1. `Route("/")` on `/42` → no match
   2. `Route("/:id")` on `/42` → match, `params = ["id": "42"]`

Params from parent and child are merged — if the parent had a `:param`, it's available in the child's `RouterContext` alongside the child's params.

---

## MiniRouter Example App

Located at `examples/MiniRouter/`. Demonstrates all Phase 11 features.

```swift
// App.swift
@main struct App {
    @MainActor static func main() {
        Swiflow.render(into: "#app") {
            RouterRoot {
                Route("/") { HomePage() }
                Route("/about") { AboutPage() }
                Route("/users/:id") { ctx in UsersPage(userId: ctx.params["id"]!) }
            }
        }
    }
}

// Shared nav — lives in a NavBar component used by all pages
final class NavBar: Component {
    var body: VNode {
        nav {
            Link("/", "Home")
            Link("/about", "About")
            Link("/users/42", "User 42")
        }
    }
}

// UsersPage — shows programmatic navigation
final class UsersPage: Component {
    let userId: String
    @Environment(\.router) var router

    var body: VNode {
        div {
            NavBar()
            h1("User: \(userId)")
            button("Go Home", .on(.click) { self.router.navigate("/") })
        }
    }
}
```

`examples/MiniRouter/Package.swift` mirrors `examples/HelloWorld/Package.swift` — depends on `Swiflow` + `SwiflowRouter` via local path.

---

## Test Strategy

**Covered on macOS (no WASM):**

| Test file | Key cases |
|---|---|
| `RoutePatternTests.swift` | Static match, `:param` capture, `*` wildcard, no-match, trailing-slash normalization |
| `RouterContextTests.swift` | Query string parsing (`?k=v&k2=v2`), param passthrough, empty query |
| `RouteMatchingTests.swift` | Flat route match, nested route match, param merging, first-match-wins, 404 nil return |
| `RouterInterfaceTests.swift` | Default no-op interface compiles + runs without crash, env key lookup |

**Covered by existing WASM E2E (SwiflowCLITests):**

The existing `swiflow init + swiflow dev` and `swiflow build` E2E tests cover the WASM pipeline. `RouterRoot` + `Link` are smoke-tested by the `MiniRouter` example but not by a dedicated E2E test in Phase 11 (the init command doesn't scaffold a router app yet; that's Phase 13).

---

## Error Handling

- **No route matches:** `RouterRoot.body` renders `VNode.text("404 — no route matched \(currentPath)")`. Callers can override by adding a catch-all `Route("*") { NotFoundPage() }` last in their builder.
- **`RouterInterface` without `RouterRoot`:** default no-op (navigate/replace/back are no-ops, currentPath is "/"). Components compile and render; navigation simply doesn't work. Useful for snapshot tests.
- **`popstate` without history mode:** the listener is installed conditionally — hash mode uses `hashchange`, history mode uses `popstate`. No cross-contamination.

---

## Public API Surface

```swift
// Types
public struct RouterContext: Sendable { path, params, query }
public struct RouterInterface: Sendable { currentPath, navigate, replace, back }
public struct RouteDefinition                           // opaque to callers

// Env
public extension EnvironmentValues { var router: RouterInterface }

// DSL (free functions, platform-agnostic)
public func Route<C: Component>(_ path: String, _ factory: () -> C) -> RouteDefinition
public func Route<C: Component>(_ path: String, _ factory: (RouterContext) -> C) -> RouteDefinition
public func Route(_ path: String, @RouteBuilder _ children: () -> [RouteDefinition]) -> RouteDefinition
public func Routes(@RouteBuilder _ children: () -> [RouteDefinition]) -> [RouteDefinition]

// WASM-only (behind #if canImport(JavaScriptKit))
public final class RouterRoot: Component { init(mode:routes:) }
public final class Link: Component { init(_ path: String, _ label: String) }
public final class LinkContainer: Component { init(_ path: String, @ChildrenBuilder content: () -> [VNode]) }
```

`@resultBuilder struct RouteBuilder` is public (needed for `@RouteBuilder` parameter labels), but its static methods are an implementation detail.
