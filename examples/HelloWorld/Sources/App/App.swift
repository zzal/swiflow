// Sources/App/App.swift
import Swiflow
import SwiflowWeb

/// Phase 3 Hello World — a Component with @State.
///
/// Compared to Phase 2a:
/// - State lives on the Component (was a global `var`).
/// - No explicit Swiflow.rerender() call — mutating `@State count`
///   schedules a re-render automatically via the RAFScheduler.
// @unchecked Sendable: WASM runs on a single thread; there are no real
// concurrent accesses. This annotation silences Swift 6's transfer
// checker so the `[weak self]` capture inside `MainActor.assumeIsolated`
// is accepted without unsafe workarounds.
final class Counter: Component, @unchecked Sendable {
    @State var count: Int = 0

    var body: VNode {
        div(.class("container")) {
            h1("Hello, Swiflow!")
            p("Count: \(count)")
            button(
                "Increment",
                // `MainActor.assumeIsolated` is safe here: the JS driver
                // invokes every event listener synchronously on the only
                // thread the WASM runtime owns, which the Swift runtime
                // treats as the main actor.
                .on("click", Swiflow.handlers.register { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.count += 1
                    }
                })
            )
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
