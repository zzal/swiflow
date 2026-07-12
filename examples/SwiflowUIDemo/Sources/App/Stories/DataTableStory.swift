import Swiflow
import SwiflowUI

@Component
final class DataTableStory {
    @State var selectedPeople: Set<Int> = []
    @State var peoplePage: Int = 0
    @State var roleFilter: String = "All"
    @ReducerState var toasts: ToastQueue

    var body: VNode {
        storyPage("DataTable",
                  blurb: "DataTable with sortable: true, pageSize: 5, and multi-select checkboxes. "
                       + "Click a header to cycle ascending → descending → unsorted. The header stays "
                       + "pinned inside the 360 px scroll container (maxHeight). The role filter changes "
                       + "rows, so a key: encoding the filter remounts the table with fresh data — embedded "
                       + "components freeze rows at first mount. Clicking a row \"opens\" it (onRowClick), "
                       + "while the row checkbox and the in-cell \"Edit\" button do NOT trigger the row "
                       + "click — container clicks ignore interactive descendants (fromInteractiveDescendant).") {
            variantSection("Paged, sortable, selectable", snippet: """
            Select("Filter by role", selection: $roleFilter,
                   options: ["All", "Engineer", "Researcher", "Inventor", "Designer"])
            DataTable(shown,
                      selection: $selectedPeople,
                      sortable: true,
                      pageSize: 5,
                      page: $peoplePage,
                      onRowClick: { p in self.$toasts.show("Opening \\(p.name)", .success) },
                      maxHeight: "360px",
                      key: "people-\\(roleFilter)-\\(shown.count)") {
                Column("Name", value: \\.name)
                Column("Age", value: \\.age).align(.trailing)
                Column("Role") { p in Badge(p.role, variant: .accent) }
                Column("") { p in
                    Button("Edit", variant: .secondary, size: .sm) {
                        self.$toasts.show("Editing \\(p.name)", .info)
                    }
                }
            }
            """) {
                dataTableSection
            }
            // Mounted once; the row-click and Edit toasts fire into this page's own queue.
            ToastStack(queue: $toasts)
        }
    }

    /// The DataTable showcase. Extracted from `body` to keep that single result-builder
    /// expression within the Swift type-checker's budget. Demonstrates the dynamic-data
    /// `key:` contract: the role filter changes `rows`, and the `key:` (encoding the filter)
    /// remounts the reused table so it re-reads fresh rows.
    private var dataTableSection: VNode {
        let shown = roleFilter == "All"
            ? samplePeople
            : samplePeople.filter { $0.role == roleFilter }
        return VStack(spacing: .md, align: .stretch) {
            Select("Filter by role", selection: $roleFilter,
                   options: ["All", "Engineer", "Researcher", "Inventor", "Designer"])
            // A keyed component can't share a parent with unkeyed siblings (Swiflow's
            // all-or-none keyed-children rule), so the keyed table lives in its own
            // single-child container rather than directly beside the h2/Select/p.
            VStack(spacing: .none, align: .stretch) {
                DataTable(shown,
                          selection: $selectedPeople,
                          sortable: true,
                          pageSize: 5,
                          page: $peoplePage,
                          onRowClick: { p in
                              self.$toasts.show("Opening \(p.name)", .success)
                          },
                          maxHeight: "360px",
                          key: "people-\(roleFilter)-\(shown.count)") {
                    Column("Name", value: \.name)
                    Column("Age", value: \.age).align(.trailing)
                    Column("Role") { p in Badge(p.role, variant: .accent) }
                    Column("") { p in
                        Button("Edit", variant: .secondary, size: .sm) {
                            self.$toasts.show("Editing \(p.name)", .info)
                        }
                    }
                }
            }
        }
    }
}
