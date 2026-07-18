// Sources/App/App.swift
//
// GridBoard — the Canadian grid, live, with no server.
// Root shell placeholder; the real dashboard lands in later tasks.
import Swiflow
import SwiflowDOM

@Component
final class GridShell {
    var body: VNode {
        element("main", attributes: [.class("gb-shell")], children: [
            element("h1", attributes: [], children: [text("Canada Grid — live")]),
        ])
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { GridShell() }
    }
}
