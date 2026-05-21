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
        // Capture navigate during body — accessing router outside body
        // returns the default no-op because AmbientEnvironment is not set.
        let navigate = router.navigate
        return button("Log out", .on(.click) { _ in navigate("/login") })
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
