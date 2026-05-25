// Sources/App/App.swift
import Swiflow
import SwiflowWeb
import SwiflowRouter
import JavaScriptKit

final class HomePage: Component {
    var body: VNode {
        div {
            h1("Home")
            p("You are on the home page.")
            embed { Link("/about", "Go to About") }
        }
    }
}

final class AboutPage: Component {
    @Environment(\.router) var router

    var body: VNode {
        // Capture router.back inside body where AmbientEnvironment.current is set.
        let back = router.back
        return div {
            h1("About")
            p("You are on the about page.")
            button("Back", .on(.click) { _ in back() })
        }
    }
}

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") {
            RouterRoot(mode: .hash) {
                Route("/") { HomePage() }
                Route("/about") { AboutPage() }
            }
        }
    }
}
