import Swiflow
import SwiflowUI

@Component
final class DataTableVirtualStory {
    var body: VNode {
        storyPage("DataTable — virtualized",
                  blurb: "Virtualized DataTable over 2,000 rows: only the rows in (and just around) "
                       + "the 440 px viewport are in the DOM. Scroll to stream rows; sorting reorders the "
                       + "whole dataset. Columns come from columnsTemplate (per-column .width is ignored "
                       + "when virtualized).") {
            variantSection("2,000 rows, fixed row height", snippet: """
            DataTable(bigPeople,
                      sortable: true,
                      maxHeight: "440px",
                      virtualization: .fixed(rowHeight: 44),
                      columnsTemplate: "2fr 80px 1fr") {
                Column("Name", value: \\.name)
                Column("Age", value: \\.age).align(.trailing)
                Column("Role") { p in Badge(p.role, variant: .accent) }
            }
            """) {
                virtualTableSection
            }
        }
    }

    /// A 2,000-row virtualized DataTable. `virtualized: .fixed(rowHeight:)` keeps only the
    /// visible window in the DOM; `columnsTemplate` gives the grid its (shared, stable) column
    /// tracks; `maxHeight` is the required scroll container. Static dataset ⇒ no `key:` needed.
    private var virtualTableSection: VNode {
        VStack(spacing: .none, align: .stretch) {
            DataTable(bigPeople,
                      sortable: true,
                      maxHeight: "440px",
                      virtualization: .fixed(rowHeight: 44),
                      columnsTemplate: "2fr 80px 1fr") {
                Column("Name", value: \.name)
                Column("Age", value: \.age).align(.trailing)
                Column("Role") { p in Badge(p.role, variant: .accent) }
            }
        }
    }
}
