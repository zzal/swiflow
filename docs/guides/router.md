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
            .product(name: "SwiflowDOM", package: "Swiflow"),
            .product(name: "SwiflowRouter", package: "Swiflow"),
        ]
    ),
]
```

## Quick start

```swift
import Swiflow
import SwiflowDOM
import SwiflowRouter

@main struct App {
    @MainActor static func main() {
        Swiflow.render(into: "#app") {
            RouterRoot {
                Route("/") { HomePage() }
                Route("/about") { AboutPage() }
                Route("/users/:id") { ctx in
                    UsersPage(id: ctx.param("id"))
                }
            } notFound: { ctx in
                NotFoundPage(path: ctx.path)
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

A matched route guarantees its declared `:param` captures are present, so
`ctx.param(_:)` is non-optional — no `?? fallback` ritual:

```swift
Route("/users/:id") { ctx in
    UserPage(id: ctx.param("id"))
}
```

For non-string params, `param(_:as:)` parses through
`LosslessStringConvertible` (`Int`, `Double`, `Bool`, or your own types).
It returns an Optional because the *value* is user input — someone can
type `/users/abc` into the URL bar:

```swift
Route("/posts/:num") { ctx in
    PostPage(number: ctx.param("num", as: Int.self))   // Int? — nil on "/posts/abc"
}
```

The two failure modes are deliberately different: an unparseable **value**
is a silent `nil` (render your fallback), while a typo'd **name** — asking
for a param the pattern never declared — logs a DEBUG warning naming the
path and the declared params, then degrades (`""` / `nil`). The raw
`ctx.params: [String: String]` dictionary remains available.

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
        Route("/:id") { ctx in UserDetailPage(id: ctx.param("id")) }
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
embed { Link("/about") { span { text("About Us") } } }
```

`Link` renders an `<a>` element and intercepts the click to call
`router.navigate(path)` without a full-page reload.

### Active state

When a `Link`'s destination matches the current path, it emits
`aria-current="page"` (the standard current-page marker for assistive tech)
and adds the `sw-link-active` class for styling:

```swift
// .exact (default): active only on the destination itself
Link("/about", "About")

// .prefix: also active on segment children — section links in a nav bar
Link("/users", "Users", active: .prefix)   // lights up on /users/42 too
```

`.prefix` is segment-aware (`/users` does not match `/users2`), and on the
root path it degrades to exact — a Home link never lights up on every page.
Style it with either hook:

```css
a[aria-current="page"] { font-weight: 600; }
.sw-link-active { text-decoration: underline; }
```

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

### Why capture during `body`?

`@Environment(\.router)` reads `AmbientEnvironment.current`, which is only set
while the diff is evaluating a component's `body`. Lifecycle hooks like
`onAppear`, `onChange(of:)`, and `onDisappear` run outside that context — if
you read `router` there directly, you'll get the framework's default no-op
router (path `"/"`, no-op `navigate`). In DEBUG builds, calling `navigate`,
`replace`, or `back` on that default logs a warning naming the attempted
path and this fix — so a dead click is findable instead of silent.

The fix is to capture the values you need during `body` and use them later:

```swift
final class DelayedRedirect: Component {
    @Environment(\.router) var router
    private var navigate: (@Sendable (String) -> Void)?

    var body: VNode {
        navigate = router.navigate   // capture while body is running
        return p("Redirecting…")
    }

    func onAppear() {
        // Uses the captured closure, not @Environment directly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [navigate] in
            navigate?("/home")
        }
    }
}
```

`Link` follows this same pattern internally.

## 404 handling

Pass a `notFound:` closure — it renders whenever no route matches, receives
a `RouterContext` whose `path` is the unmatched path (params/query are
empty), and renders inside the router environment, so a `Link` home works:

```swift
RouterRoot {
    Route("/") { HomePage() }
    Route("/about") { AboutPage() }
} notFound: { ctx in
    NotFoundPage(path: ctx.path)
}
```

Without `notFound:`, an unmatched path renders a plain diagnostic text node
("404 — no route matched …") — fine in dev, not what you want to ship.

A catch-all `Route("*")` also works (it must be last — first match wins) and
is the right tool when the 404 page should participate in route matching,
e.g. under a nested prefix.
