// Sources/App/App.swift

import SwiflowDOM

@MainActor @Component
final class AsyncFetch {
    // `state` is a flat status string for demo brevity:
    // "idle" | "loading…" | "loaded user #N".
    @State var userID: Int = 1
    @State var state: String = "idle"

    var body: VNode {
        div {
            h1("Async fetch demo")
            p("Status: \(state)")
            // The button is an action — clicking bumps `userID`, which is the
            // `.task`'s dependency, so the effect re-runs for the next user.
            button("Load next user", .on(.click) { self.userID += 1 })
        }
        .task(rerunOn: userID) {
            self.state = "loading…"
            try? await Task.sleep(nanoseconds: 400_000_000)   // simulate latency
            self.state = "loaded user #\(self.userID)"
        }
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { AsyncFetch() }
    }
}
