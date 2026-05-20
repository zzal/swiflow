// Sources/App/App.swift
import Swiflow
import SwiflowWeb
import JavaScriptKit

/// Counter — the Phase 7 demo component.
///
/// `final class` (not `struct`) is required: @State reactivity wires the
/// owner via Mirror after init, which needs reference semantics. See
/// Sources/Swiflow/Reactivity/Component.swift for the rationale. The
/// `final` keyword is optional but matches the framework's expectation
/// that Components aren't subclassed.
///
/// **Hot reload preserves `@State`.** When you save this file while
/// `swiflow dev` is running, the runtime captures the current values
/// of `count`, `greeting`, and `celebrate`, re-imports the rebuilt
/// WASM, and restores them into the new module — so editing a
/// rendering tweak (e.g. changing the button label) does NOT reset
/// the counter back to zero. State preservation matches by
/// (component type name, @State field name); rename `Counter` and
/// the subtree starts fresh, which is the expected escape hatch
/// when you want a clean slate.
final class Counter: Component {
    @State var count: Int = 0
    @State var greeting: String = "Swiflow"
    @State var celebrate: Bool = false
    let greetingInput = Ref<JSObject>()

    var body: VNode {
        div(.class("container")) {
            h1("Hello, \(greeting)!\(celebrate ? " \u{1F389}" : "")")
            p("Count: \(count)")
            button("Increment", .on(.click) { self.count += 1 })

            div(.class("greeting-row")) {
                label("Greeting", .attr("for", "g"))
                input(.id("g"), .value($greeting), .ref(greetingInput))
            }

            label(.class("checkbox-row")) {
                input(.attr("type", "checkbox"), .checked($celebrate))
                VNode.text(" Celebrate")
            }
        }
    }

    func onAppear() {
        _ = greetingInput.wrappedValue?.focus.function?()
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { Counter() }
    }
}
