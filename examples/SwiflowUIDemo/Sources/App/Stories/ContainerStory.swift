import Swiflow
import SwiflowUI

@Component
final class ContainerStory {
    var body: VNode {
        storyPage("Container",
                  blurb: "The simplest layout primitive: a stateless centered max-width div over the "
                       + "--sw-container-{sm,md,lg} tokens — the page shell most apps wrap their content "
                       + "in. margin-inline: auto centers it once it hits its max-width.") {
            variantSection("Widths", snippet: """
            Container(size: .sm) { tintedCard("sm — 40rem") }
            Container(size: .md) { tintedCard("md — 60rem (default)") }
            Container(size: .lg) { tintedCard("lg — 80rem") }
            """) {
                VStack(spacing: .md, align: .stretch) {
                    Container(size: .sm) { tintedCard("sm — 40rem") }
                    Container(size: .md) { tintedCard("md — 60rem (default)") }
                    Container(size: .lg) { tintedCard("lg — 80rem") }
                }
            }
        }
    }

    /// A Card tinted with the accent color (rather than its default plain surface)
    /// so it visibly fills the Container's width — makes the max-width read at a
    /// glance against the story page (which is itself unconstrained width).
    private func tintedCard(_ label: String) -> VNode {
        Card(variant: .outlined, .style("background-color", "color-mix(in oklab, var(--sw-accent) 8%, var(--sw-surface))")) {
            Text(label)
        }
    }
}
