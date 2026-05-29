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
    // Inherited from the parent Swiflow package, which sets this floor
    // because its SwiflowCLI executable depends on Hummingbird 2.x.
    // SwiflowWeb itself only links Swiflow + JavaScriptKit and doesn't
    // need macOS 14; SwiftPM just propagates the package-level platform
    // floor to every consumer, regardless of which product they import.
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
                "Sources/App/AboutPopover+Styles.swift": ##"""
// Sources/App/AboutPopover+Styles.swift
import Swiflow

extension AboutPopover {
    static var scopedStyles: CSSSheet? = css {
        rule(".info-card") {
            positionAnchor("--info-anchor")
            positionArea("bottom span-right")
            // Popover top-layer reset.
            margin("0.5rem 0 0 0")
            padding("0.75rem 1rem")
            background("color-mix(in oklab, Canvas 92%, CanvasText)")
            color("CanvasText")
            border("1px solid color-mix(in oklab, CanvasText 12%, transparent)")
            borderRadius("12px")
            boxShadow("0 12px 32px -12px rgb(0 0 0 / .35)")
            maxWidth("280px")
            fontSize("0.9375rem")
        }
        rule("h3") {
            margin("0 0 0.25rem 0")
            fontSize("0.95rem")
            fontWeight("600")
        }
        rule(".body") {
            margin("0 0 0.5rem 0")
            color("color-mix(in oklab, CanvasText 80%, Canvas)")
        }
        rule("a") {
            color("color-mix(in oklab, CanvasText 70%, blue)")
            textDecoration("none")
        }
        rule("a:hover") { textDecoration("underline") }
    }
}

"""##,
                "Sources/App/AboutPopover.swift": ##"""
// Sources/App/AboutPopover.swift
import Swiflow

/// AboutPopover — declarative popover using the Popover API.
///
/// The trigger lives in Counter and uses `popovertarget="about-popover"`
/// — no Swift event handler needed. CSS Anchor Positioning floats this
/// card next to the trigger (which sets `anchor-name: --info-anchor`).
@MainActor @Component
final class AboutPopover {
    var body: VNode {
        div(.id("about-popover"),
            .attr("popover", "auto"),
            .class("info-card")) {
            h3("About Swiflow")
            p("Swift, compiled to WASM, with a reactive component model.",
              .class("body"))
            link("View on GitHub",
                 .attr("href", "https://github.com/aduchesneau/swiflow"),
                 .attr("target", "_blank"),
                 .attr("rel", "noopener"))
        }
    }
}

"""##,
                "Sources/App/App.swift": ##"""
// Sources/App/App.swift
import Swiflow
import SwiflowWeb
import JavaScriptKit

/// Counter — the {{NAME}} showcase root.
///
/// Wires the framework primitives + a curated set of modern HTML/CSS
/// surfaces. See the design spec for the full picture; in summary:
/// - `host { }` + Task-1 dual-selector class rules so scoped CSS hits the root.
/// - `view-transition-name` on `.count` + `document.startViewTransition` for
///   a morphing increment in supporting browsers.
/// - Native `<dialog>` for Sign In: focus trap, Escape-to-close, ::backdrop.
/// - Popover API + anchor positioning for About (declarative — no Swift handler).
/// - `<details>` disclosure with animated open/close via `interpolate-size`.
/// - `color-mix` + `light-dark` system colors — auto-themes from OS.
/// - `@container` query on the card via the `raw(...)` escape hatch.
/// - `@property --accent` registered custom property, animated on increment.
@MainActor @Component
final class Counter {
    @State var count: Int = 0
    @State var greeting: String = "Swiflow"
    @State var celebrate: Bool = false
    @State var showToast: Bool = false
    @State var showSignIn: Bool = false
    let greetingInput = Ref<JSObject>()
    let signInDialog = Ref<JSObject>()
    // Retain View Transitions closure so JS can still call it.
    private var vtClosure: JSClosure?

    var body: VNode {
        div(.class("card")) {
            header(.class("header")) {
                h1("Hello, \(greeting)!\(celebrate ? " \u{1F389}" : "")",
                   .class("greeting-heading"))
                button("ⓘ",
                       .class("info-trigger"),
                       .attr("popovertarget", "about-popover"),
                       .attr("aria-label", "About Swiflow"))
            }

            p("Count: \(count)",
              .class("count"),
              .attr("aria-live", "polite"))

            div(.class("actions")) {
                button("Increment", .on(.click) { self.increment() })
                button("Show toast", .class("secondary"),
                       .on(.click) { self.showToast = true })
                button("Sign in…", .class("secondary"),
                       .on(.click) { self.openSignIn() })
            }

            div(.class("greeting-row")) {
                label("Greeting:", .attr("for", "g"))
                input(.id("g"), .value($greeting), .ref(greetingInput))
            }

            label(.class("checkbox-row")) {
                input(.attr("type", "checkbox"), .checked($celebrate))
                text(" Celebrate")
            }

            details(.class("inspector")) {
                summary("What's running here?")
                ul(.class("inspector-list")) {
                    li(".count text — animates via the View Transitions API on increment.")
                    li("Sign in… — opens a native <dialog>.")
                    li("ⓘ — opens an `auto` popover anchored via CSS Anchor Positioning.")
                    li("Show toast — mounts a `manual` popover with a 2.5s auto-dismiss.")
                }
            }

            if showToast {
                embed { Toast(message: "Saved!", onDone: { self.showToast = false }) }
            }

            embed { AboutPopover() }

            // Dismissal paths: Escape (native <dialog> behavior), Cancel /
            // Sign out / Close buttons inside SignIn. Backdrop-click-to-close
            // is omitted because EventInfo doesn't expose `event.target`
            // identity, and a generic .on(.click) on the dialog catches
            // every click that bubbles up from the form content.
            dialog(.ref(signInDialog), .class("signin-dialog")) {
                if showSignIn {
                    embed { SignIn(onClose: { self.closeSignIn() }) }
                }
            }
        }
    }

    func onAppear() {
        if let el = greetingInput.wrappedValue { _ = el.focus?() }
    }

    func increment() {
        guard let document = JSObject.global.document.object else {
            count += 1
            return
        }
        let startVT = document.startViewTransition
        if startVT == .undefined {
            count += 1
            return
        }
        // Retain on self so JS can invoke it before ARC frees it. Reassigning
        // drops the prior reference; JavaScriptKit's current JSClosure no
        // longer needs an explicit release() (it's deprecated as of recent
        // versions — ARC reclaim is sufficient). Same pattern as
        // SwiflowWeb/HMRBridge.swift's snapshotClosure slot.
        let cb = JSClosure { _ in
            MainActor.assumeIsolated { self.count += 1 }
            return .undefined
        }
        vtClosure = cb
        _ = document.startViewTransition!(cb)
    }

    func openSignIn() {
        showSignIn = true
        if let el = signInDialog.wrappedValue { _ = el.showModal?() }
    }

    func closeSignIn() {
        if let el = signInDialog.wrappedValue { _ = el.close?() }
        showSignIn = false
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
                "Sources/App/Counter+Styles.swift": ##"""
// Sources/App/Counter+Styles.swift
import Swiflow

extension Counter {
    static var scopedStyles: CSSSheet? = tokens + layout + theme + animations + responsive

    // ---- tokens ----
    static let tokens = css {
        raw("""
            @property --accent {
              syntax: "<color>";
              inherits: true;
              initial-value: oklch(.65 .14 250);
            }
            """)
        rule(":root") {
            cssVar("--accent", "light-dark(oklch(.55 .18 250), oklch(.75 .14 250))")
            cssVar("--surface", "light-dark(oklch(.99 0 0), oklch(.18 .005 250))")
            cssVar("--surface-elev", "light-dark(oklch(.97 0 0), oklch(.22 .005 250))")
            cssVar("--text", "CanvasText")
            cssVar("--text-dim", "color-mix(in oklab, CanvasText 65%, Canvas)")
            cssVar("--border", "color-mix(in oklab, CanvasText 12%, transparent)")
        }
    }

    // ---- layout ----
    static let layout = css {
        host {
            display("block")
            maxWidth("520px")
            margin("2.5rem auto")
            padding("2rem")
            containerType("inline-size")
        }
        rule(".card") {
            display("flex")
            flexDirection("column")
            gap("1rem")
            padding("1.75rem")
            borderRadius("16px")
            background("var(--surface)")
            border("1px solid var(--border)")
            boxShadow("0 1px 0 var(--border), 0 24px 48px -32px rgb(0 0 0 / .25)")
        }
        rule(".header") {
            display("flex")
            alignItems("center")
            justifyContent("space-between")
            gap("0.5rem")
            margin("0")
            padding("0")
            border("0")
        }
        rule(".greeting-heading") {
            margin("0")
            fontSize("1.4rem")
            fontWeight("600")
        }
        rule(".info-trigger") {
            anchorName("--info-anchor")
            display("grid")
            placeItems("center")
            width("1.75rem")
            height("1.75rem")
            borderRadius("50%")
            border("1px solid var(--border)")
            background("transparent")
            color("var(--text-dim)")
            cursor("pointer")
            fontSize("0.9rem")
        }
        rule(".actions") {
            display("flex")
            flexWrap("wrap")
            gap("0.5rem")
        }
        rule(".greeting-row") {
            display("flex")
            gap("0.5rem")
            alignItems("center")
        }
        rule(".greeting-row input") {
            flex("1")
            padding("0.4rem 0.6rem")
            border("1px solid var(--border)")
            borderRadius("6px")
            background("Canvas")
            color("CanvasText")
        }
        rule(".checkbox-row") {
            display("flex")
            gap("0.5rem")
            alignItems("center")
            cursor("pointer")
        }
        rule(".inspector") {
            border("1px solid var(--border)")
            borderRadius("10px")
            padding("0.5rem 0.75rem")
            interpolateSize("allow-keywords")
        }
        rule(".inspector summary") {
            cursor("pointer")
            listStyle("none")
            fontSize("0.95rem")
            color("var(--text-dim)")
        }
        rule(".inspector summary::-webkit-details-marker") {
            display("none")
        }
        rule(".inspector summary::before") {
            property("content", "\"▸ \"")
            display("inline-block")
            transition("transform .15s ease")
        }
        rule(".inspector[open] summary::before") {
            transform("rotate(90deg)")
        }
        rule(".inspector-list") {
            margin("0.5rem 0 0 0")
            padding("0 0 0 1.25rem")
            color("var(--text-dim)")
            fontSize("0.9rem")
        }
    }

    // ---- theme ----
    static let theme = css {
        rule(".count") {
            margin("0")
            fontSize("1.6rem")
            fontWeight("600")
            color("var(--accent)")
            viewTransitionName("count-value")
            transition("--accent .25s ease")
        }
        rule("button") {
            padding("0.4rem 0.9rem")
            border("1px solid var(--border)")
            borderRadius("6px")
            background("var(--accent)")
            color("Canvas")
            cursor("pointer")
            fontSize("0.95rem")
        }
        rule(".secondary") {
            background("transparent")
            color("var(--text)")
        }
        rule("button:focus-visible") {
            property("outline", "2px solid var(--accent)")
            property("outline-offset", "2px")
        }
        rule("input:focus-visible") {
            property("outline", "2px solid var(--accent)")
            property("outline-offset", "2px")
        }
        rule(".checkbox-row:focus-visible") {
            property("outline", "2px solid var(--accent)")
            property("outline-offset", "2px")
        }

        // <dialog> + ::backdrop styling.
        rule(".signin-dialog") {
            border("0")
            borderRadius("16px")
            padding("0")
            background("var(--surface-elev)")
            color("var(--text)")
            boxShadow("0 24px 48px -16px rgb(0 0 0 / .45)")
            maxWidth("min(90vw, 420px)")
        }
        rule(".signin-dialog .signin") {
            padding("1.5rem")
        }
        rule(".signin-dialog::backdrop") {
            background("color-mix(in oklab, Canvas 30%, transparent)")
            backdropFilter("blur(6px)")
        }
    }

    // ---- animations ----
    static let animations = css {
        keyframes("counter-in") {
            from { opacity("0"); transform("translateY(-6px)") }
            to   { opacity("1"); transform("translateY(0)") }
        }
        host {
            animation("counter-in 0.3s ease forwards")
        }
    }

    // ---- responsive (container query via raw escape hatch) ----
    static let responsive = css {
        raw("""
            @container (max-width: 380px) {
              .swiflow-Counter .actions { flex-direction: column; align-items: stretch; }
              .swiflow-Counter .card { padding: 1.25rem; gap: 0.75rem; }
            }
            """)
    }
}

"""##,
                "Sources/App/SignIn+Styles.swift": ##"""
// Sources/App/SignIn+Styles.swift
import Swiflow

extension SignIn {
    static var scopedStyles: CSSSheet? = css {
        rule(".signin") {
            display("flex")
            flexDirection("column")
            gap("1rem")
            maxWidth("320px")
            fontFamily("system-ui, sans-serif")
        }
        rule(".title") {
            margin("0")
            fontSize("1.25rem")
        }
        rule(".field") {
            display("flex")
            flexDirection("column")
            gap("0.25rem")
        }
        rule("input") {
            padding("0.4rem 0.6rem")
            border("1px solid color-mix(in oklab, CanvasText 18%, transparent)")
            borderRadius("6px")
            background("Canvas")
            color("CanvasText")
            fontSize("0.9375rem")
            accentColor("CanvasText")
        }
        rule("input:focus-visible") {
            property("outline", "2px solid color-mix(in oklab, CanvasText 50%, blue)")
            property("outline-offset", "2px")
        }
        rule(".error") {
            margin("0.125rem 0 0 0")
            color("oklch(.55 .2 25)")
            fontSize("0.85rem")
        }
        rule(".welcome") {
            margin("0")
            fontSize("1rem")
        }
        rule(".actions") {
            display("flex")
            gap("0.5rem")
        }
        rule("button") {
            padding("0.4rem 0.9rem")
            border("1px solid color-mix(in oklab, CanvasText 18%, transparent)")
            borderRadius("6px")
            background("color-mix(in oklab, Canvas 90%, CanvasText)")
            color("CanvasText")
            cursor("pointer")
            fontSize("0.9375rem")
        }
        rule("button:focus-visible") {
            property("outline", "2px solid color-mix(in oklab, CanvasText 50%, blue)")
            property("outline-offset", "2px")
        }
        rule(".secondary") {
            background("transparent")
        }
        rule("button[disabled]") {
            opacity("0.5")
            cursor("not-allowed")
        }
    }
}

"""##,
                "Sources/App/SignIn.swift": ##"""
// Sources/App/SignIn.swift
import Swiflow

/// SignIn — Phase 12b form validation demo, now hosted inside Counter's
/// <dialog>. All inline .style(...) calls migrated to SignIn+Styles.swift.
@MainActor @Component
final class SignIn {
    @State var email: String    = ""
    @State var password: String = ""
    @State var ctrl: FormController = FormController()
    @State var submitted: Bool  = false
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    var body: VNode {
        let em = Field("email",    $email,    $ctrl, .required(), .email)
        let pw = Field("password", $password, $ctrl, .required(), .minLength(8),
                       .custom("Must contain a number") { $0.contains { $0.isNumber } })
        let form = Form($ctrl) { em; pw }

        return div(.class("signin")) {
            if submitted {
                p("Signed in as \(email)!", .class("welcome"))
                div(.class("actions")) {
                    button("Sign out", .class("secondary"), .on(.click) {
                        self.submitted = false
                        self.email = ""
                        self.password = ""
                        self.ctrl = FormController()
                    })
                    button("Close", .on(.click) { self.onClose() })
                }
            } else {
                h2("Sign In", .class("title"))

                div(.class("field")) {
                    label("Email", .attr("for", "signin-email"))
                    input(.id("signin-email"),
                          .attr("type", "email"),
                          .value($email),
                          .on(.blur) { em.markTouched() })
                    if em.touched, let err = em.error {
                        p(err, .class("error"))
                    }
                }

                div(.class("field")) {
                    label("Password", .attr("for", "signin-password"))
                    input(.id("signin-password"),
                          .attr("type", "password"),
                          .value($password),
                          .on(.blur) { pw.markTouched() })
                    if pw.touched, let err = pw.error {
                        p(err, .class("error"))
                    }
                }

                div(.class("actions")) {
                    button("Sign In",
                           .attr("disabled", !form.isValid),
                           .on(.click) {
                               form.touchAll()
                               guard form.isValid else { return }
                               self.submitted = true
                           })
                    button("Reset", .class("secondary"), .on(.click) { form.reset() })
                    button("Cancel", .class("secondary"), .on(.click) { self.onClose() })
                }
            }
        }
    }
}

"""##,
                "Sources/App/Toast+Styles.swift": ##"""
// Sources/App/Toast+Styles.swift
import Swiflow

extension Toast {
    static var scopedStyles: CSSSheet? = layout + theme + animations

    static let layout = css {
        host {
            position("fixed")
            insetBlockEnd("1.5rem")
            insetInline("0")
            marginInline("auto")
            width("max-content")
            maxWidth("min(90vw, 360px)")
            display("flex")
            alignItems("center")
            gap("0.625rem")
            padding("0.75rem 1rem")
            // Popover top-layer rendering resets these — set them explicitly.
            margin("auto auto 1.5rem auto")
            inset("auto 0 0 0")
            border("0")
        }
        rule(".icon") {
            display("grid")
            placeItems("center")
            width("1.25rem")
            height("1.25rem")
            borderRadius("50%")
            fontSize("0.8rem")
        }
    }

    static let theme = css {
        host {
            background("color-mix(in oklab, Canvas 88%, CanvasText)")
            color("CanvasText")
            borderRadius("999px")
            border("1px solid color-mix(in oklab, CanvasText 12%, transparent)")
            boxShadow("0 12px 32px -12px rgb(0 0 0 / .35), 0 2px 6px -2px rgb(0 0 0 / .15)")
            fontSize("0.9375rem")
        }
        rule(".icon") {
            background("color-mix(in oklab, currentColor 18%, transparent)")
        }
    }

    static let animations = css {
        keyframes("toast-in") {
            from { opacity("0"); transform("translateY(12px) scale(.96)") }
            to   { opacity("1"); transform("translateY(0) scale(1)") }
        }
        keyframes("toast-out") {
            to { opacity("0"); transform("translateY(12px) scale(.98)") }
        }
        host {
            animation("toast-in .22s cubic-bezier(.2,.7,.2,1) forwards")
        }
    }
}

"""##,
                "Sources/App/Toast.swift": ##"""
// Sources/App/Toast.swift
import Swiflow
import SwiflowWeb
import JavaScriptKit

/// Toast — top-layer notification using the Popover API.
///
/// - `popover="manual"` keeps the toast on the top layer without
///   light-dismiss (other clicks aren't hijacked).
/// - Auto-dismisses after 2.5s via `after(_:do:)`; the timer is cancelled
///   in `onDisappear` so an early parent unmount doesn't fire `onDone`.
/// - `exitAnimation` / `exitDuration` still drive the exit animation when
///   the parent toggles `showToast = false`.
@MainActor @Component
final class Toast {
    let message: String
    let onDone: () -> Void
    let root = Ref<JSObject>()
    var dismissTimer: TimerHandle?

    init(message: String, onDone: @escaping () -> Void) {
        self.message = message
        self.onDone = onDone
    }

    static var exitAnimation: String? = "toast-out 0.2s ease forwards"
    static var exitDuration: Double?  = 0.2

    var body: VNode {
        div(.attr("popover", "manual"),
            .attr("role", "status"),
            .attr("aria-live", "polite"),
            .ref(root),
            .on(.click) { self.onDone() }) {
            span(.class("icon"), .attr("aria-hidden", "true")) { text("\u{2713}") }
            text(message)
        }
    }

    func onAppear() {
        if let el = root.wrappedValue {
            _ = el.showPopover?()
        }
        dismissTimer = after(2.5) { [weak self] in self?.onDone() }
    }

    func onDisappear() {
        dismissTimer?.cancel()
        dismissTimer = nil
    }
}

"""##,
                "index.html": ##"""
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{{NAME}}</title>
    <style>
      /* Swiflow loading indicator. The driver writes
         documentElement.dataset.swiflowProgress = "0".."100"
         during WASM fetch. Everything else (theme, layout, components) is
         owned by per-component scopedStyles in Swift. */
      html { color-scheme: light dark; }
      html[data-swiflow-progress]:not([data-swiflow-progress="100"])::before {
        content: "Loading " attr(data-swiflow-progress) "%";
        position: fixed;
        inset: 0;
        display: grid;
        place-items: center;
        background: Canvas;
        color: CanvasText;
        font: 16px/1.4 system-ui, sans-serif;
        z-index: 9999;
      }
      body { margin: 0; min-height: 100dvh; background: Canvas; color: CanvasText;
             font: 16px/1.5 -apple-system, system-ui, sans-serif; }
    </style>
  </head>
  <body>
    <div id="app"></div>
    <script src="swiflow-driver.js"></script>
  </body>
</html>

"""##,
            ]
        ),
        Template(
            name: "MiniRouter",
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
                "README.md": ##"""
# {{NAME}}

A Swiflow project demonstrating client-side routing with `SwiflowRouter`.

## Build

```bash
swiflow build
```

This wraps `swift package js --use-cdn --product App -c release` after
probing for an installed WASM SDK. The output lands at
`.build/plugins/PackageToJS/outputs/Package/`.

## Serve

Any static HTTP server works:

```bash
python3 -m http.server 3000
```

Then open <http://localhost:3000>.

## What you should see

- A navbar with **Home**, **About**, and **Users** links.
- Clicking a link swaps the page content without a full reload — the
  router renders the matching `Route` from `Sources/App/App.swift`.
- `/users/:id` shows a dynamic `:id` segment via `ctx.params["id"]`.

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
import SwiflowRouter
import JavaScriptKit

final class AboutPage: Component {
    @Environment(\.router) var router

    var body: VNode {
        // Capture router.back inside body where AmbientEnvironment.current is set.
        // Accessing self.router from a click handler (outside body) would see the
        // default no-op.
        let back = router.back
        return div {
            embed { NavBar() }
            h1("About")
            p("This demo exercises RouterRoot, Route, Link, and programmatic navigation.")
            button("Back", .on(.click) { _ in back() })
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
    ]

    static func lookup(_ name: String) -> Template? {
        return all.first(where: { $0.name == name })
    }

    static var availableNames: [String] {
        return all.map(\.name)
    }
}
