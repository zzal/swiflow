import Swiflow
import SwiflowDOM
import SwiflowUI
import JavaScriptKit

struct GoLProps: Encodable { var speed: Int; var cellSize: Int; var reset: Int }
struct GoLEvent: RegionEvent { let kind: String; let value: Int }
enum GameOfLife: RegionGuest {
    typealias Props = GoLProps
    typealias Event = GoLEvent
    static let source = "regions/game-of-life/adapter.js"
}

@MainActor @Component
final class Demo {
    @State var generation: Int = 0
    @State var failed: Bool = false
    @State var resetToken: Int = 0

    var body: VNode {
        div {
            h1("Swiflow Regions — Game of Life")
            p("Generation: \(generation)")
            Button("Reset") { self.resetToken += 1 }
            if failed {
                p("guest failed to load")
            } else {
                // `resetToken` rides in the props; bumping it signals the guest
                // (the wasm) to re-seed a fresh board. See adapter.js onProps.
                region(GameOfLife.self, key: "gol", props: GoLProps(speed: 1, cellSize: 6, reset: resetToken))
                    .onEvent { e in self.generation = e.value }
                    .onError { _ in self.failed = true }
                    .aspectRatio(2, 1) // responsive: fills available width, 2:1 strip
            }
        }
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") { Demo() }
    }
}
