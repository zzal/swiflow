// Sources/App/App.swift

import SwiflowDOM
import SwiflowUI

@Component
final class AsyncFetch {
    // `state` is a flat status string for demo brevity:
    // "idle" | "loading…" | "loaded user #N".
    @State var userID: Int = 1
    @State var state: String = "idle"

    var body: VNode {
        VStack(spacing: .md, align: .start) {
            h1("Async fetch demo")
            HStack(spacing: .sm, align: .center) {
                p("Status: \(state)")
                // hasPrefix is robust to the trailing ellipsis char.
                if state.hasPrefix("loading") { Spinner(size: .sm, label: "Loading") }
            }
            // The button is an action — clicking bumps `userID`, which is the
            // `.task`'s dependency, so the effect re-runs for the next user.
            Button("Load next user") { self.userID += 1 }
        }
        .padding(.xl)
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
