import Swiflow
import SwiflowUI

@Component
final class TextStory {
    var body: VNode {
        storyPage("Text",
                  blurb: "A stateless typography primitive over the type-scale tokens. Each variant "
                       + "renders its own semantic tag by default (title→h1, heading→h2, subheading→h3, "
                       + "body/caption→p, label→span) — pass tag: to keep the styling but render a "
                       + "different element.") {
            variantSection("Variants", snippet: """
            Text("Page title", variant: .title)
            Text("Section heading", variant: .heading)
            Text("Subsection", variant: .subheading)
            Text("Body copy reads at the default size and weight.", variant: .body)
            Text("Caption text is smaller, for supporting detail.", variant: .caption)
            Text("Label text", variant: .label)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .sm, align: .stretch) {
                        Text("Page title", variant: .title)
                        Text("Section heading", variant: .heading)
                        Text("Subsection", variant: .subheading)
                        Text("Body copy reads at the default size and weight.", variant: .body)
                        Text("Caption text is smaller, for supporting detail.", variant: .caption)
                        Text("Label text", variant: .label)
                    }
                }
            }
            variantSection("tag: override", snippet: """
            Text("Styled as a heading, but the page's only h1", variant: .heading, tag: "h1")
            """) {
                Card(variant: .plain) {
                    Text("Styled as a heading, but the page's only h1", variant: .heading, tag: "h1")
                }
            }
            variantSection("Weight & color", snippet: """
            Text("Muted caption", variant: .caption, color: .muted)
            Text("Semibold body", weight: .semibold)
            Text("Danger", color: .danger)
            Text("Success", color: .success)
            Text("Warning", color: .warning)
            Text("Accent", color: .accent)
            """) {
                Card(variant: .plain) {
                    VStack(spacing: .sm, align: .stretch) {
                        Text("Muted caption", variant: .caption, color: .muted)
                        Text("Semibold body", weight: .semibold)
                        Text("Danger", color: .danger)
                        Text("Success", color: .success)
                        Text("Warning", color: .warning)
                        Text("Accent", color: .accent)
                    }
                }
            }
        }
    }
}
