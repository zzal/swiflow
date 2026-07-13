import Swiflow
import SwiflowUI

@Component
final class PaginationStory {
    @State var page: Int = 0

    var body: VNode {
        storyPage("Pagination",
                  blurb: "Previous/Next buttons flanking a \"Page X of N\" indicator, bound "
                       + "to a 0-based page index. This is the same control DataTable renders "
                       + "for its own pager — extracted here so any paginated view can share "
                       + "it. Previous is inert on the first page, Next is inert on the last "
                       + "(project rule: inert, not disabled — an inert button carries no "
                       + "click handler at all).") {
            variantSection("Five pages", snippet: """
            @State var page = 0
            …
            Pagination(page: $page, pageCount: 5)
            """) {
                VStack(spacing: .md, align: .stretch) {
                    Pagination(page: $page, pageCount: 5)
                    p("Current page: \(page + 1) of 5")
                }
            }
        }
    }
}
