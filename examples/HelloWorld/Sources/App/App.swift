// Sources/App/App.swift
import Swiflow
import SwiflowWeb

/// Phase 3 Hello World — a Component with @State.
///
/// Compared to Phase 2a:
/// - State lives on the Component (was a global `var`).
/// - No explicit Swiflow.rerender() call — mutating `@State count`
///   schedules a re-render automatically via the RAFScheduler.
/// - No [weak self] or MainActor.assumeIsolated needed — the framework
///   handles all of that inside `.on(_:perform:)`.
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
        Swiflow.render(Counter(), into: "#app")
    }
}
