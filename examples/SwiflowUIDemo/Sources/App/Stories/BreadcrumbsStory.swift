import Swiflow
import SwiflowUI

@Component
final class BreadcrumbsStory {
    var body: VNode {
        storyPage("Breadcrumbs",
                  blurb: "A stateless <nav aria-label=\"Breadcrumb\"> + <ol> trail. The last crumb is "
                       + "always the current page — plain text with aria-current=\"page\", never a link, "
                       + "even if given an href. Renders plain sanitized <a> anchors (never SwiflowRouter "
                       + "Link), so it stays usable with or without a router.") {
            variantSection("Trail", snippet: """
            Breadcrumbs([
                Crumb("Home", href: "/"),
                Crumb("Products", href: "/products"),
                Crumb("Widgets", href: "/products/widgets"),
                Crumb("Blue Widget"),
            ])
            """) {
                Card(variant: .plain) {
                    Breadcrumbs([
                        Crumb("Home", href: "/"),
                        Crumb("Products", href: "/products"),
                        Crumb("Widgets", href: "/products/widgets"),
                        Crumb("Blue Widget"),
                    ])
                }
            }
        }
    }
}
