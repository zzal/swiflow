import Swiflow
import SwiflowDOM
import SwiflowUI

@MainActor @Component
final class Demo {
    var body: VNode {
        VStack(spacing: .lg, align: .stretch) {
            h1("SwiflowUI — Layout primitives")

            // --- Stacks --------------------------------------------------
            h2("Stacks")
            HStack(spacing: .md, align: .center) {
                button("One"); button("Two"); button("Three")
            }
            .padding(.md)
            .style("background", "var(--sw-surface)")
            .style("border-radius", "var(--sw-radius)")

            p("The row above uses HStack(spacing: .md). Change --sw-space-md "
              + "in index.html's <style> to reskin every gap at once.")

            Divider()

            // --- Grid ----------------------------------------------------
            h2("Grid")
            Grid(columns: 3, spacing: .md) {
                for n in 1...6 { card("Cell \(n)") }
            }
            p("Grid(columns: 3, spacing: .md) — equal columns via "
              + "repeat(3, minmax(0, 1fr)).")

            Divider()

            // --- Spacer --------------------------------------------------
            h2("Spacer")
            HStack(align: .center) {
                button("Leading")
                Spacer()
                button("Trailing")
            }
            .padding(.md)
            .style("background", "var(--sw-surface)")
            .style("border-radius", "var(--sw-radius)")
            p("A Spacer() between the buttons pushes them to opposite ends.")
        }
        .padding(.xl)
    }

    /// A small surfaced tile used to fill the grid demo.
    private func card(_ title: String) -> VNode {
        div { text(title) }
            .padding(.md)
            .style("background", "var(--sw-surface)")
            .style("border", "var(--sw-border-width) solid var(--sw-border)")
            .style("border-radius", "var(--sw-radius)")
            .style("text-align", "center")
    }
}

@main
struct App {
    @MainActor static func main() { Swiflow.render(into: "#app") { Demo() } }
}
