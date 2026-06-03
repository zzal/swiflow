import Swiflow
import SwiflowWeb
import SwiflowUI

@MainActor @Component
final class Demo {
    var body: VNode {
        VStack(spacing: .lg, align: .stretch) {
            h1("SwiflowUI — Stacks")
            HStack(spacing: .md, align: .center) {
                button("One"); button("Two"); button("Three")
            }
            .padding(.md)
            .style("background", "var(--sw-surface)")
            .style("border-radius", "var(--sw-radius)")

            p("The row above uses HStack(spacing: .md). Change --sw-space-md "
              + "in index.html's <style> to reskin every gap at once.")
        }
        .padding(.xl)
    }
}

@main
struct App {
    @MainActor static func main() { Swiflow.render(into: "#app") { Demo() } }
}
