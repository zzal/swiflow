import Swiflow
import SwiflowUI

@Component
final class TextLinkStory {
    var body: VNode {
        storyPage("TextLink",
                  blurb: "A token-styled inline hyperlink — a plain <a>, not in-app routing. Named TextLink "
                       + "(not Link) because SwiflowRouter.Link already owns in-app navigation; reach for "
                       + "TextLink for external or non-routed destinations. The href is sanitized "
                       + "automatically via URLSanitizer.") {
            variantSection("Inline", snippet: """
            p { text("Read the "); TextLink("documentation", href: "https://example.com/docs"); text(" before you start.") }
            """) {
                Card(variant: .plain) {
                    p {
                        text("Read the ")
                        TextLink("documentation", href: "https://example.com/docs")
                        text(" before you start.")
                    }
                }
            }
            variantSection("External", snippet: """
            TextLink("View on GitHub", href: "https://github.com", external: true)
            """) {
                Card(variant: .plain) {
                    TextLink("View on GitHub", href: "https://github.com", external: true)
                }
            }
        }
    }
}
