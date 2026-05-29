// Sources/App/App.swift
import Swiflow
import SwiflowWeb
import JavaScriptKit

/// Counter — the HelloWorld showcase root.
///
/// Wires the framework primitives + a curated set of modern HTML/CSS
/// surfaces. See the design spec for the full picture; in summary:
/// - `host { }` + Task-1 dual-selector class rules so scoped CSS hits the root.
/// - Native `<dialog>` for Sign In: focus trap, Escape-to-close, ::backdrop.
/// - `view-transition-name` on `.signin-dialog` + `document.startViewTransition`
///   wrapping `openSignIn` / `closeSignIn` for a morphing open/close in
///   supporting browsers. (Increment was tried but throttled rapid clicks.)
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
                    li("Sign in… — opens a native <dialog>, morphing via the View Transitions API.")
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

    func openSignIn() {
        withViewTransition {
            self.showSignIn = true
            if let el = self.signInDialog.wrappedValue { _ = el.showModal?() }
        }
    }

    func closeSignIn() {
        withViewTransition {
            if let el = self.signInDialog.wrappedValue { _ = el.close?() }
            self.showSignIn = false
        }
    }

    /// Run `mutate` inside `document.startViewTransition` when the browser
    /// supports it; otherwise apply the mutation directly. The dialog's
    /// `view-transition-name` ties the morph to the .signin-dialog element.
    ///
    /// `vtClosure` retains the callback so JS can invoke it before ARC frees
    /// it. Reassigning drops the prior reference; JavaScriptKit's current
    /// JSClosure no longer needs explicit release() — ARC reclaim is
    /// sufficient. Same pattern as SwiflowWeb/HMRBridge.swift's snapshotClosure
    /// slot. openSignIn and closeSignIn are never concurrent, so they can
    /// share the same slot.
    func withViewTransition(_ mutate: @escaping @MainActor () -> Void) {
        guard let document = JSObject.global.document.object,
              document.startViewTransition != .undefined else {
            mutate()
            return
        }
        let cb = JSClosure { _ in
            MainActor.assumeIsolated { mutate() }
            return .undefined
        }
        vtClosure = cb
        _ = document.startViewTransition!(cb)
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { Counter() }
    }
}
