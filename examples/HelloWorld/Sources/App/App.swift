// Sources/App/App.swift
import Swiflow
import SwiflowWeb

/// Hello World — a Component with @State.
///
/// `final class` (not `struct`) is required: @State reactivity wires the
/// owner via Mirror after init, which needs reference semantics. See
/// Sources/Swiflow/Reactivity/Component.swift for the rationale. The
/// `final` keyword is optional but matches the framework's expectation
/// that Components aren't subclassed.
final class Counter: Component {
    @State var count: Int = 0

    var body: VNode {
        div(.class("container")) {
            h1("Hello, Swiflow!")
            p("Count: \(count)")
            button("Increment", .on(.click) { self.count += 1 })
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
