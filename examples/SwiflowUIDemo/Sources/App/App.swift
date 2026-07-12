import Swiflow
import SwiflowDOM

@main
struct App {
    @MainActor static func main() { Swiflow.render(into: "#app") { Shell() } }
}
