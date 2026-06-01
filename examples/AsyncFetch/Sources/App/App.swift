import SwiflowWeb

@MainActor @Component
final class AsyncFetch {
    @State var userID: Int = 1
    @State var state: String = "idle"

    var body: VNode {
        div {
            h1("Async fetch demo")
            p("Status: \(state)")
            button("Load user \(userID)", .on(.click) { self.userID += 1 })
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
