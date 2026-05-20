// Sources/App/App.swift
import Swiflow
import SwiflowWeb
import JavaScriptKit

/// Hello World — a Component with @State, two-way bindings, and a Ref.
///
/// `final class` (not `struct`) is required: @State reactivity wires the
/// owner via Mirror after init, which needs reference semantics. See
/// Sources/Swiflow/Reactivity/Component.swift for the rationale. The
/// `final` keyword is optional but matches the framework's expectation
/// that Components aren't subclassed.
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
