import Swiflow
import SwiflowDOM
import SwiflowRouter
import JavaScriptKit

@main
struct App {
    @MainActor
    static func main() {
        Swiflow.render(into: "#app") {
            RouterRoot {
                Route("/") { HomePage() }
                Route("/about") { AboutPage() }
                Route("/users/:id") { ctx in
                    UsersPage(userId: ctx.param("id"))
                }
            } notFound: { ctx in
                NotFoundPage(path: ctx.path)
            }
        }
    }
}
