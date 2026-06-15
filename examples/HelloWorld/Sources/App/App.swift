// Sources/App/App.swift
import Swiflow
import SwiflowDOM
import SwiflowUI
import JavaScriptKit

/// Counter — the HelloWorld showcase root, now dogfooding SwiflowUI.
///
/// The card's chrome and the modern-CSS surfaces are still hand-authored (that's
/// what HelloWorld showcases), but every reusable control is a SwiflowUI component:
/// - `Button` for the actions (token-skinned).
/// - `TextField` / `Checkbox` for the greeting + Celebrate inputs.
/// - `ToastStack` (an app-owned `[ToastItem]` queue) replaces the hand-rolled toast.
/// - `SignIn` (in the native `<dialog>`) is built from `TextField`/`Button`.
///
/// Still hand-rolled (no SwiflowUI equivalent in 1.0): the native `<dialog>` chrome,
/// the `ⓘ` Popover-API trigger + `AboutPopover`, the `<details>` inspector.
///
/// The `ToastStack` is a sibling of `.card`, not a child: `.card` is a
/// `container-type` query container, which establishes a containing block — a
/// `position: fixed` toast nested inside would anchor to the card, not the viewport.
@MainActor @Component
final class Counter {
    @State var count: Int = 0
    @State var greeting: String = "Swiflow"
    @State var celebrate: Bool = false
    @State var showSignIn: Bool = false
    @State var toasts: [ToastItem] = []
    let signInDialog = Ref<JSObject>()

    var body: VNode {
        div {
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
                    Button("Increment") { self.count += 1 }
                    Button("Show toast", variant: .secondary) {
                        self.toasts.append(ToastItem("Saved!", variant: .success))
                    }
                    Button("Sign in…", variant: .secondary) { self.openSignIn() }
                }

                TextField("Greeting", text: $greeting)
                Checkbox("Celebrate", isOn: $celebrate)

                details(.class("inspector")) {
                    summary("What's running here?")
                    ul(.class("inspector-list")) {
                        li("Sign in… — opens a native <dialog> with a CSS open/close animation, built from SwiflowUI TextField + Button.")
                        li("ⓘ — opens an `auto` popover anchored via CSS Anchor Positioning.")
                        li("Show toast — pushes a SwiflowUI ToastStack notification (auto-dismiss, pause on hover/focus).")
                    }
                }

                embed { AboutPopover() }

                // Dismissal: Escape (native <dialog>), or Cancel / Sign out / Close
                // inside SignIn. Backdrop-click-to-close is omitted (EventInfo doesn't
                // expose event.target identity).
                dialog(.ref(signInDialog), .class("signin-dialog")) {
                    if showSignIn {
                        embed { SignIn(onClose: { self.closeSignIn() }) }
                    }
                }
            }

            // Sibling of .card (see the type doc): the fixed ToastStack anchors to the
            // viewport, not the query-container card.
            ToastStack(toasts: $toasts)
        }
    }

    // Open/close are synchronous and tied to the click gesture — the dialog appears
    // the same frame, and the fade/slide is CSS (Counter+Styles.swift). showModal()
    // must run before the @State change schedules its render so [open] transitions in.
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
