import Swiflow
import SwiflowUI
import SwiflowRouter

@Component
final class IndexStory {
    var body: VNode {
        storyPage("SwiflowUI Catalog",
                  blurb: "Every SwiflowUI component, one page each: live variants, "
                       + "code snippets, and knobs. Pick a component from the navbar.") {
            Grid(columns: 3, spacing: .md) {
                for entry in Catalog.stories {
                    Card(variant: .outlined) {
                        h3(entry.title)
                        p(entry.category.rawValue)
                        embed { Link(Catalog.path(entry.slug), "Open") }
                    }
                }
            }
        }
    }
}
