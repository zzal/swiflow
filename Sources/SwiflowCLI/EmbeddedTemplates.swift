// GENERATED FILE — do not edit.
//
// Regenerate by running, from the repo root:
//     swift scripts/embed-templates.swift
//
// Source: examples/*/

enum EmbeddedTemplates {
    struct Template {
        let name: String
        let files: [String: String]
    }

    static let all: [Template] = [
        Template(
            name: "HelloWorld",
            files: [
                ".gitignore": ##"""
# macOS
.DS_Store

# Swift build outputs
.build/
.swiftpm/
Package.resolved

# Editor / IDE
*.swp
*~
.idea/
.vscode/
xcuserdata/

# Swiflow dev artifacts (regenerated on `swiflow dev`)
swiflow-driver.js

# Swiflow build artifacts (emitted by `swiflow build` at project root)
swiflow-manifest.json

"""##,
                "Package.swift": ##"""
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "{{NAME}}",
    // Required because this app links SwiflowWeb, which transitively pulls
    // Hummingbird 2.x (macOS 14+). Without this floor, `swift build` fails
    // with "executable 'App' requires macos 10.13, but depends on the
    // product 'SwiflowWeb' which requires macos 14.0".
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "App", targets: ["App"]),
    ],
    dependencies: [
        // Local path back to the parent Swiflow package.
        {{SWIFLOW_DEP}},
        // JavaScriptKit is declared as a direct dependency so SwiftPM
        // exposes the `swift package js` (PackageToJS) plugin to this
        // package. Without it, the plugin only surfaces on the parent
        // package and can't target this example's executable.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.53.0")),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "SwiflowWeb", package: "Swiflow"),
            ],
            path: "Sources/App"
        ),
    ]
)

"""##,
                "README.md": ##"""
# {{NAME}}

A Swiflow project — Swift-to-WebAssembly with a Vite-inspired dev loop.

## Build

```bash
swiflow build
```

This wraps `swift package js --use-cdn --product App -c release` after
probing for an installed WASM SDK. The output lands at
`.build/plugins/PackageToJS/outputs/Package/`.

## Serve

Phase 2b doesn't ship a dev server yet (Phase 2c will). Any static HTTP
server works:

```bash
python3 -m http.server 3000
```

Then open <http://localhost:3000>.

## What you should see

- A heading: **Hello, Swiflow!**
- A paragraph: **Count: 0**
- A button: **Increment** that increments the count on each click.

"""##,
                "Sources/App/App.swift": ##"""
// Sources/App/App.swift
import Swiflow
import SwiflowWeb
import JavaScriptKit

/// Counter — the Phase 12a styling/animation demo component.
///
/// Showcases:
/// - `static var scopedStyles: CSSSheet?` with `css { }` builder
/// - `keyframes` enter animation scoped to the component
/// - `Toast` child component with `exitAnimation` / `exitDuration`
/// - `if showToast { embed { Toast(...) } }` conditional embedding
///
/// Phase 7 features (two-way bindings, Ref) are preserved from prior work.
@MainActor @Component
final class Counter {
    @State var count: Int = 0
    @State var greeting: String = "Swiflow"
    @State var celebrate: Bool = false
    @State var showToast: Bool = false
    @State var showSignIn: Bool = false
    let greetingInput = Ref<JSObject>()

    static var scopedStyles: CSSSheet? = css {
        keyframes("counter-in") {
            from { opacity("0"); transform("translateY(-6px)") }
            to   { opacity("1"); transform("translateY(0)") }
        }
        rule(".container") {
            maxWidth("480px")
            margin("2rem auto")
            padding("2rem")
            fontFamily("-apple-system, BlinkMacSystemFont, sans-serif")
            animation("counter-in 0.3s ease forwards")
        }
        rule(".count") {
            fontSize("1.5rem")
            fontWeight("600")
            color("#1a202c")
        }
        rule(".greeting-row") {
            display("flex")
            gap("0.5rem")
            alignItems("center")
            marginTop("1rem")
        }
        rule(".checkbox-row") {
            display("flex")
            gap("0.5rem")
            alignItems("center")
            marginTop("0.75rem")
            cursor("pointer")
        }
    }

    var body: VNode {
        div(.class("container")) {
            h1("Hello, \(greeting)!\(celebrate ? " \u{1F389}" : "")")
            p("Count: \(count)", .class("count"))
            button("Increment", .on(.click) { self.count += 1 })
            button("Show toast", .on(.click) { self.showToast = true })

            div(.class("greeting-row")) {
                label("Greeting:", .attr("for", "g"))
                input(.id("g"), .value($greeting), .ref(greetingInput))
            }

            label(.class("checkbox-row")) {
                input(.attr("type", "checkbox"), .checked($celebrate))
                text(" Celebrate")
            }

            if showToast {
                embed { Toast(message: "Saved!", onDone: { self.showToast = false }) }
            }

            div(.style(name: "margin-top", value: "2rem"),
                .style(name: "border-top", value: "1px solid #eee"),
                .style(name: "padding-top", value: "1.5rem")) {
                button(showSignIn ? "Hide Sign In" : "Show Sign In demo",
                       .on(.click) { self.showSignIn.toggle() })
                if showSignIn {
                    embed { SignIn() }
                }
            }
        }
    }

    func onAppear() {
        if let el = greetingInput.wrappedValue { _ = el.focus!() }
    }
}

/// Toast — demonstrates `exitAnimation` and `exitDuration`.
///
/// When the user clicks the toast (or the parent sets `showToast = false`),
/// the framework plays the `toast-out` keyframe for `exitDuration` seconds
/// before removing the DOM node — a smooth exit with zero JS glue.
@MainActor @Component
final class Toast {
    let message: String
    let onDone: () -> Void

    init(message: String, onDone: @escaping () -> Void) {
        self.message = message
        self.onDone = onDone
    }

    static var scopedStyles: CSSSheet? = css {
        keyframes("toast-in") {
            from { opacity("0"); transform("translateY(8px)") }
            to   { opacity("1"); transform("translateY(0)") }
        }
        keyframes("toast-out") {
            to { opacity("0"); transform("translateY(8px)") }
        }
        rule(".root") {
            backgroundColor("#323232")
            color("#fff")
            padding("0.75rem 1.25rem")
            borderRadius("8px")
            marginTop("1rem")
            animation("toast-in 0.2s ease forwards")
            cursor("pointer")
        }
    }

    static var exitAnimation: String? = "toast-out 0.25s ease forwards"
    static var exitDuration: Double?  = 0.25

    var body: VNode {
        div(.class("root"), .on(.click) { self.onDone() }) {
            text(message)
        }
    }
}

/// SignIn — Phase 12b form validation demo.
///
/// Showcases:
/// - `FormController` + `Field` + `Form` coordinator
/// - Two-field form (email + password) with blur-triggered error messages
/// - Submit disabled until `form.isValid`; `touchAll()` reveals all errors on early click
/// - Reset button restores initial values
@MainActor @Component
final class SignIn {
    @State var email: String    = ""
    @State var password: String = ""
    @State var ctrl: FormController = FormController()
    @State var submitted: Bool  = false

    var body: VNode {
        let em = Field("email",    $email,    $ctrl, .required(), .email)
        let pw = Field("password", $password, $ctrl, .required(), .minLength(8),
                       .custom("Must contain a number") { $0.contains { $0.isNumber } })
        let form = Form($ctrl) { em; pw }

        return div(.style(name: "max-width", value: "320px"),
            .style(name: "margin", value: "1rem 0"),
            .style(name: "font-family", value: "system-ui, sans-serif")) {

            if submitted {
                p("Signed in as \(email)!")
                button("Sign out", .on(.click) {
                    self.submitted = false
                    self.email = ""
                    self.password = ""
                    self.ctrl = FormController()
                })
            } else {
                h2("Sign In")

                div(.style(name: "margin-bottom", value: "1rem")) {
                    label("Email")
                    input(.value($email),
                          .style(name: "display", value: "block"),
                          .style(name: "width", value: "100%"),
                          .style(name: "margin-top", value: "4px"),
                          .on(.blur) { em.markTouched() })
                    if em.touched, let err = em.error {
                        p(err,
                          .style(name: "color", value: "red"),
                          .style(name: "font-size", value: "0.85rem"))
                    }
                }

                div(.style(name: "margin-bottom", value: "1rem")) {
                    label("Password")
                    input(.value($password),
                          .style(name: "display", value: "block"),
                          .style(name: "width", value: "100%"),
                          .style(name: "margin-top", value: "4px"),
                          .on(.blur) { pw.markTouched() })
                    if pw.touched, let err = pw.error {
                        p(err,
                          .style(name: "color", value: "red"),
                          .style(name: "font-size", value: "0.85rem"))
                    }
                }

                button("Sign In",
                       .style(name: "margin-right", value: "0.5rem"),
                       .attr("disabled", !form.isValid),
                       .on(.click) {
                           form.touchAll()
                           guard form.isValid else { return }
                           self.submitted = true
                       })
                button("Reset", .on(.click) { form.reset() })
            }
        }
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { Counter() }
    }
}

"""##,
                "index.html": ##"""
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>{{NAME}}</title>
    <style>
      body { font-family: -apple-system, system-ui, sans-serif; padding: 2rem; }
      .container { max-width: 480px; }
      button { padding: 0.4rem 0.9rem; font-size: 1rem; cursor: pointer; }
      .greeting-row { display: flex; gap: 0.5rem; align-items: center; margin-top: 1rem; }
      .greeting-row input { flex: 1; padding: 0.3rem 0.5rem; }
      .checkbox-row { display: flex; gap: 0.5rem; align-items: center; margin-top: 0.5rem; }

      /* Swiflow loading indicator. The driver writes
         documentElement.dataset.swiflowProgress = "0".."100"
         during WASM fetch. Customize freely. */
      html[data-swiflow-progress]:not([data-swiflow-progress="100"])::before {
        content: "Loading " attr(data-swiflow-progress) "%";
        position: fixed;
        inset: 0;
        display: flex;
        align-items: center;
        justify-content: center;
        background: #f8f8f8;
        color: #333;
        font: 16px/1.4 system-ui, sans-serif;
        z-index: 9999;
      }
    </style>
  </head>
  <body>
    <div id="app"></div>

    <!-- The Swiflow driver script owns WASM initialisation.
         It dynamically imports the PackageToJS module and calls init()
         so no <script type="module"> block is needed here. -->
    <script src="swiflow-driver.js"></script>
  </body>
</html>

"""##,
            ]
        ),
        Template(
            name: "MiniRouter",
            files: [
                "Package.swift": ##"""
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "{{NAME}}",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "App", targets: ["App"]),
    ],
    dependencies: [
        {{SWIFLOW_DEP}},
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

"""##,
                "Sources/App/App.swift": ##"""
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

"""##,
                "Sources/App/NavBar.swift": ##"""
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

"""##,
                "Sources/App/Pages/AboutPage.swift": ##"""
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

"""##,
                "Sources/App/Pages/HomePage.swift": ##"""
import Swiflow
import SwiflowWeb
import JavaScriptKit

final class HomePage: Component {
    var body: VNode {
        div {
            embed { NavBar() }
            h1("Home")
            p("Welcome to the {{NAME}} demo.")
        }
    }
}

"""##,
                "Sources/App/Pages/UsersPage.swift": ##"""
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
        // Read router.navigate HERE inside body, where AmbientEnvironment.current
        // is set by the diff. Accessing self.router from a click handler (outside
        // body) would see the default no-op.
        let navigate = router.navigate
        return div {
            embed { NavBar() }
            h1("User: \(userId)")
            p("Loaded via the :id route param.")
            button("Go Home", .on(.click) { _ in navigate("/") })
        }
    }
}

"""##,
                "index.html": ##"""
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>{{NAME}}</title>
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

    <!-- The Swiflow driver script owns WASM initialisation.
         It dynamically imports the PackageToJS module and calls init()
         so no <script type="module"> block is needed here. -->
    <script src="swiflow-driver.js"></script>
  </body>
</html>

"""##,
            ]
        ),
        Template(
            name: "RouterDemo",
            files: [
                ".gitignore": ##"""
.DS_Store
.build/
.swiftpm/

"""##,
                "Package.swift": ##"""
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "{{NAME}}",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "App", targets: ["App"]),
    ],
    dependencies: [
        {{SWIFLOW_DEP}},
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

"""##,
                "Sources/App/App.swift": ##"""
// Sources/App/App.swift
import Swiflow
import SwiflowWeb
import SwiflowRouter
import JavaScriptKit

final class HomePage: Component {
    var body: VNode {
        div {
            h1("Home")
            p("You are on the home page.")
            embed { Link("/about", "Go to About") }
        }
    }
}

final class AboutPage: Component {
    @Environment(\.router) var router

    var body: VNode {
        // Capture router.back inside body where AmbientEnvironment.current is set.
        let back = router.back
        return div {
            h1("About")
            p("You are on the about page.")
            button("Back", .on(.click) { _ in back() })
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

"""##,
                "index.html": ##"""
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>{{NAME}}</title>
  </head>
  <body>
    <div id="app"></div>

    <!-- The Swiflow driver script owns WASM initialisation.
         It dynamically imports the PackageToJS module and calls init()
         so no <script type="module"> block is needed here. -->
    <script src="swiflow-driver.js"></script>
  </body>
</html>

"""##,
            ]
        ),
    ]

    static func lookup(_ name: String) -> Template? {
        return all.first(where: { $0.name == name })
    }

    static var availableNames: [String] {
        return all.map(\.name)
    }
}
