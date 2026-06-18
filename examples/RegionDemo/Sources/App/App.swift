import Swiflow
import SwiflowDOM
import SwiflowUI
import JavaScriptKit

struct GoLProps: Encodable { var speed: Int; var cellSize: Int }
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

    var body: VNode {
        div {
            h1("Swiflow Regions — Game of Life")
            p("Generation: \(generation)")
            if failed {
                p("guest failed to load")
            } else {
                region(GameOfLife.self, key: "gol", props: GoLProps(speed: 1, cellSize: 6))
                    .onEvent { e in self.generation = e.value }
                    .onError { _ in self.failed = true }
                    .aspectRatio(1, 1) // responsive: fills available width, stays square
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
