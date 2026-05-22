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
final class Counter: Component {
    @State var count: Int = 0
    @State var greeting: String = "Swiflow"
    @State var celebrate: Bool = false
    @State var showToast: Bool = false
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
                VNode.text(" Celebrate")
            }

            if showToast {
                embed { Toast(message: "Saved!", onDone: { self.showToast = false }) }
            }
        }
    }

    func onAppear() {
        _ = greetingInput.wrappedValue?.focus.function?()
    }
}

/// Toast — demonstrates `exitAnimation` and `exitDuration`.
///
/// When the user clicks the toast (or the parent sets `showToast = false`),
/// the framework plays the `toast-out` keyframe for `exitDuration` seconds
/// before removing the DOM node — a smooth exit with zero JS glue.
final class Toast: Component {
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
            VNode.text(message)
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
