// Sources/App/App.swift
import Swiflow
import SwiflowWeb
import JavaScriptKit

/// Counter — the HelloWorld showcase root.
///
/// Wires the framework primitives + a curated set of modern HTML/CSS
/// surfaces. See the design spec for the full picture; in summary:
/// - `host { }` + Task-1 dual-selector class rules so scoped CSS hits the root.
/// - Native `<dialog>` for Sign In: focus trap, Escape-to-close, ::backdrop,
///   with a CSS-only open/close animation (`@starting-style` +
///   `transition-behavior: allow-discrete`). No JS, no View Transition —
///   gesture-immediate and robust across browsers.
/// - Popover API + anchor positioning for About (declarative — no Swift handler).
/// - `<details>` disclosure with animated open/close via `interpolate-size`.
/// - `color-mix` + `light-dark` system colors — auto-themes from OS.
/// - `@container` query on the card via the scoped `container(...)` primitive.
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
                button("Increment", .on(.click) { self.count += 1 })
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
                    li("Sign in… — opens a native <dialog> with a CSS open/close animation.")
                    li("ⓘ — opens an `auto` popover anchored via CSS Anchor Positioning.")
                    li("Show toast — mounts a `manual` popover with a 2.5s auto-dismiss.")
                }
            }

            // The toast sits mid-list, *before* the dialog, on purpose — to
            // demonstrate that a conditional child can live anywhere now. Each
            // builder `if`/`for` is one stable `.fragment` slot, so toggling the
            // toast off (its 2.5s auto-dismiss) empties its slot without shifting
            // the dialog's slot — the dialog is never recreated. (This is what
            // the "Toast auto-dismiss does not close an open dialog" e2e proves.)
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

    // Open/close are synchronous and tied directly to the click gesture — the
    // dialog appears the same frame, and the fade/slide is handled entirely in
    // CSS (see Counter+Styles.swift). showModal() must run before the @State
    // change schedules its render so the [open] transition fires immediately.
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
