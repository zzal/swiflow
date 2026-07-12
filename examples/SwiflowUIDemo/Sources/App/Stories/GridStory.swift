import Swiflow
import SwiflowUI

@Component
final class GridStory {
    var body: VNode {
        storyPage("Grid",
                  blurb: "Grid(columns: 3, spacing: .md) — equal columns via "
                       + "repeat(3, minmax(0, 1fr)).") {
            variantSection("3 equal columns", snippet: """
            Grid(columns: 3, spacing: .md) {
                for n in 1...6 { card("Cell \\(n)") }
            }
            """) {
                Grid(columns: 3, spacing: .md) {
                    for n in 1...6 { card("Cell \(n)") }
                }
            }
        }
    }

    /// A small surfaced tile used to fill the grid demo.
    private func card(_ title: String) -> VNode {
        // Typed token spellings: single-token values take a Token directly;
        // composites interpolate .css. A typo'd Token fails at compile time —
        // a typo'd var() string fails silent.
        div { text(title) }
            .padding(.md)
            .style("background", Token.surface)
            .style("border", "\(Token.borderWidth.css) solid \(Token.border.css)")
            .style("border-radius", Token.radius)
            .style("text-align", "center")
    }
}
