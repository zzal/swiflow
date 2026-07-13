import Swiflow
import SwiflowUI

@Component
final class ContainerStory {
    var body: VNode {
        storyPage("Container",
                  blurb: "The simplest layout primitive: a stateless centered max-width div over the "
                       + "--sw-container-{sm,md,lg,xl} tokens (character-measure widths for readable "
                       + "line lengths) — the page shell most apps wrap their content in. margin-inline: "
                       + "auto centers it once it hits its max-width. Default size is .lg.") {
            variantSection("Widths", snippet: """
            Container(size: .sm) { tintedCard("sm — 30ch") }
            Container(size: .md) { tintedCard("md — 60ch") }
            Container(size: .lg) { tintedCard("lg — 90ch (default)") }
            Container(size: .xl) { tintedCard("xl — 120ch") }
            """) {
                VStack(spacing: .md, align: .stretch) {
                    Container(size: .sm) { tintedCard("sm — 30ch") }
                    Container(size: .md) { tintedCard("md — 60ch") }
                    Container(size: .lg) { tintedCard("lg — 90ch (default)") }
                    Container(size: .xl) { tintedCard("xl — 120ch") }
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
