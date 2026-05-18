// Sources/App/App.swift
import SwiflowWeb

// Mutable counter shared with the click handler. Phase 3 will replace this
// with `@State`; for Phase 2a the spec's Hello World uses an explicit
// `Swiflow.rerender()` call so the bridge path is exercised end-to-end.
//
// `@MainActor` keeps Swift 6's strict-concurrency check happy: the browser
// runs everything on a single thread, so pinning this to MainActor reflects
// reality and silences `#MutableGlobalVariable`.
@MainActor
var count = 0

@MainActor
func view() -> VNode {
    div(.class("container")) {
        h1("Hello, Swiflow!")
        p("Count: \(count)")
        button(
            "Increment",
            // `MainActor.assumeIsolated` is safe here: the JS driver invokes
            // every event listener synchronously on the only thread the WASM
            // runtime owns, which the Swift runtime treats as the main actor.
            // Using `Task { @MainActor in ... }` would defer the increment to
            // a later event-loop turn and break the synchronous `rerender()`
            // expectation.
            .on("click", Swiflow.handlers.register { _ in
                MainActor.assumeIsolated {
                    count += 1
                    Swiflow.rerender()
                }
            })
        )
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(view, into: "#app")
    }
}
