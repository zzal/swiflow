// Sources/SwiflowUI/DataTable.swift
import Swiflow
#if canImport(JavaScriptKit)
import JavaScriptKit
#endif

// MARK: - Virtualization config

/// How a `DataTable` renders large datasets. `.fixed` keeps only the visible window of rows
/// in the DOM, sized by a constant row height. (`measured` variable-height is reserved for 1.x.)
public enum Virtualization: Equatable, Sendable {
    case fixed(rowHeight: Int)
    // case measured(estimated: Int)   // 1.x — not implemented
}

// MARK: - Erased descriptors (the box is non-generic — see plan header for why)

/// A column erased to operate on row INDICES (the box never sees `Row`). Built by
/// `makeDataTableBox` from a typed `Column<Row>` + the rows array.
struct DataColumn {
    let id: String
    let title: String
    let alignment: ColumnAlignment
    let width: ColumnWidth?
    let render: (Int) -> [VNode]                       // cell content for row index
    let comparator: ((Int, Int) -> SortComparison)?    // nil ⇒ not sortable
}

/// Selection erased over the caller's `Binding<Set<ID>>`. All closures are index-based.
struct SelectionModel {
    let isSelected: (Int) -> Bool
    let toggle: (Int) -> Void
    let selectedCount: () -> Int          // among the dataset's rows
    let total: Int                        // dataset row count (for all/indeterminate)
    let setAll: (Bool) -> Void            // select (true) / clear (false) all dataset rows
}

// MARK: - Public factory

/// A declarative, accessible data table over a typed row model. See the SwiflowUI guide.
///
///     DataTable(people, selection: $selected, sortable: true, pageSize: 25) {
///         Column("Name", value: \.name)
///         Column("Age", value: \.age).align(.trailing).cell { Badge("\($0.age)") }
///         Column("Actions") { p in Button("Edit") { edit(p) } }
///     }
///
/// `selection`/`sortOrder`/`page` are opt-in bindings; sort & page otherwise self-manage.
/// `maxHeight` provides the scroll container the sticky header needs.
///
/// > **Dynamic data — pass a `key:`.** Like every embedded component, the table is reused across
/// > renders, so `rows` (and `loading`, `pageSize`, the columns) are captured at **first mount** —
/// > only `selection`/`sortOrder`/`page` stay live. If your `rows` or `loading` change at runtime
/// > (filtering, fetching, upstream re-sort), pass a `key:` that changes with them so the table
/// > remounts with fresh data, e.g. `key: "people-\(filtered.count)"`. Remounting resets the
/// > self-managed sort/page state; drive `sortOrder:`/`page:` bindings if you need it preserved.
@MainActor
public func DataTable<Row, ID: Hashable>(
    _ rows: [Row],
    id: KeyPath<Row, ID>,
    selection: Binding<Set<ID>>? = nil,
    sortable: Bool = false,
    sortOrder: Binding<SortOrder?>? = nil,
    pageSize: Int? = nil,
    page: Binding<Int>? = nil,
    onRowClick: ((Row) -> Void)? = nil,
    loading: Bool = false,
    maxHeight: Spacing? = nil,
    virtualization: Virtualization? = nil,
    columnsTemplate: String? = nil,
    emptyText: String = "No results",
    _ attributes: Attribute...,
    key: String? = nil,
    @ColumnBuilder<Row> columns: () -> [Column<Row>]
) -> VNode {
    let cols = columns()
    let caller = attributes
    return embedKeyed(key) {
        makeDataTableBox(rows, id: id, selection: selection, sortable: sortable,
                         sortOrder: sortOrder, pageSize: pageSize, page: page,
                         onRowClick: onRowClick, loading: loading, maxHeight: maxHeight,
                         virtualization: virtualization, columnsTemplate: columnsTemplate,
                         emptyText: emptyText, caller: caller, columnsList: cols)
    }
}

/// `Row: Identifiable` convenience — drops the `id:` keypath.
@MainActor
public func DataTable<Row: Identifiable>(
    _ rows: [Row],
    selection: Binding<Set<Row.ID>>? = nil,
    sortable: Bool = false,
    sortOrder: Binding<SortOrder?>? = nil,
    pageSize: Int? = nil,
    page: Binding<Int>? = nil,
    onRowClick: ((Row) -> Void)? = nil,
    loading: Bool = false,
    maxHeight: Spacing? = nil,
    virtualization: Virtualization? = nil,
    columnsTemplate: String? = nil,
    emptyText: String = "No results",
    _ attributes: Attribute...,
    key: String? = nil,
    @ColumnBuilder<Row> columns: () -> [Column<Row>]
) -> VNode {
    let cols = columns()
    let caller = attributes
    return embedKeyed(key) {
        makeDataTableBox(rows, id: \.id, selection: selection, sortable: sortable,
                         sortOrder: sortOrder, pageSize: pageSize, page: page,
                         onRowClick: onRowClick, loading: loading, maxHeight: maxHeight,
                         virtualization: virtualization, columnsTemplate: columnsTemplate,
                         emptyText: emptyText, caller: caller, columnsList: cols)
    }
}

// MARK: - Erasure (also the test seam)

/// Builds the concrete `DataTableBox` from typed inputs. Internal so tests can construct a
/// box directly and read `.body` (the public facade returns a `.component` VNode).
@MainActor
func makeDataTableBox<Row, ID: Hashable>(
    _ rows: [Row],
    id: KeyPath<Row, ID>,
    selection: Binding<Set<ID>>? = nil,
    sortable: Bool = false,
    sortOrder: Binding<SortOrder?>? = nil,
    pageSize: Int? = nil,
    page: Binding<Int>? = nil,
    onRowClick: ((Row) -> Void)? = nil,
    loading: Bool = false,
    maxHeight: Spacing? = nil,
    virtualization: Virtualization? = nil,
    columnsTemplate: String? = nil,
    emptyText: String = "No results",
    caller: [Attribute] = [],
    @ColumnBuilder<Row> columnsList: () -> [Column<Row>]
) -> DataTableBox {
    makeDataTableBox(rows, id: id, selection: selection, sortable: sortable, sortOrder: sortOrder,
                     pageSize: pageSize, page: page, onRowClick: onRowClick, loading: loading,
                     maxHeight: maxHeight, virtualization: virtualization, columnsTemplate: columnsTemplate,
                     emptyText: emptyText, caller: caller, columnsList: columnsList())
}

@MainActor
func makeDataTableBox<Row, ID: Hashable>(
    _ rows: [Row],
    id: KeyPath<Row, ID>,
    selection: Binding<Set<ID>>?,
    sortable: Bool,
    sortOrder: Binding<SortOrder?>?,
    pageSize: Int?,
    page: Binding<Int>?,
    onRowClick: ((Row) -> Void)?,
    loading: Bool,
    maxHeight: Spacing?,
    virtualization: Virtualization?,
    columnsTemplate: String?,
    emptyText: String,
    caller: [Attribute],
    columnsList cols: [Column<Row>]
) -> DataTableBox {
    let idOf: (Row) -> ID = { $0[keyPath: id] }

    let dataColumns: [DataColumn] = cols.map { col in
        DataColumn(
            id: col.id, title: col.title, alignment: col.alignment, width: col.width,
            render: { col.render(rows[$0]) },
            comparator: col.comparator.map { cmp in { i, j in cmp(rows[i], rows[j]) } }
        )
    }

    let selModel: SelectionModel? = selection.map { sel in
        // `rows` is frozen for the box's life (embed-reuse), so its id set is computed once
        // here rather than rebuilt on every render/click.
        let allIDs = rows.map(idOf)
        let allIDSet = Set(allIDs)
        return SelectionModel(
            isSelected: { sel.get().contains(idOf(rows[$0])) },
            toggle: { i in
                var s = sel.get(); let k = idOf(rows[i])
                if s.contains(k) { s.remove(k) } else { s.insert(k) }
                sel.set(s)
            },
            selectedCount: { sel.get().intersection(allIDSet).count },
            total: rows.count,
            setAll: { on in sel.set(on ? sel.get().union(allIDs) : sel.get().subtracting(allIDs)) }
        )
    }

    let onClick: ((Int) -> Void)? = onRowClick.map { cb in { cb(rows[$0]) } }

    return DataTableBox(
        rowCount: rows.count,
        columns: dataColumns,
        rowKey: { String(describing: idOf(rows[$0])) },
        selection: selModel,
        sortable: sortable,
        sortOrder: sortOrder,
        pageSize: pageSize,
        page: page,
        onRowClick: onClick,
        loading: loading,
        maxHeight: maxHeight?.css,
        virtualization: virtualization,
        columnsTemplate: columnsTemplate,
        emptyText: emptyText,
        caller: caller
    )
}

// MARK: - The stateful box

/// Concrete (non-generic) `@Component` behind every `DataTable`. Owns transient sort/page
/// `@State` (overridable by bindings) and renders `sort → window → render` each body.
@MainActor @Component
final class DataTableBox {
    let rowCount: Int
    let columns: [DataColumn]
    let rowKey: (Int) -> String
    let selection: SelectionModel?
    let sortable: Bool
    let sortOrderBinding: Binding<SortOrder?>?
    let pageSize: Int?
    let pageBinding: Binding<Int>?
    let onRowClick: ((Int) -> Void)?
    let loading: Bool
    let maxHeight: String?
    let virtualization: Virtualization?
    let columnsTemplate: String?
    let emptyText: String
    let caller: [Attribute]

    @State private var internalSort: SortOrder? = nil
    @State private var internalPage: Int = 0
    @State private var scrollTop: Double = 0
    @State private var viewportHeight: Double = 0
    private let overscan = 3

    init(rowCount: Int, columns: [DataColumn], rowKey: @escaping (Int) -> String,
         selection: SelectionModel?, sortable: Bool, sortOrder: Binding<SortOrder?>?,
         pageSize: Int?, page: Binding<Int>?, onRowClick: ((Int) -> Void)?,
         loading: Bool, maxHeight: String?, virtualization: Virtualization?, columnsTemplate: String?,
         emptyText: String, caller: [Attribute]) {
        self.rowCount = rowCount; self.columns = columns; self.rowKey = rowKey
        self.selection = selection; self.sortable = sortable; self.sortOrderBinding = sortOrder
        self.pageSize = pageSize; self.pageBinding = page; self.onRowClick = onRowClick
        self.loading = loading; self.maxHeight = maxHeight
        self.virtualization = virtualization; self.columnsTemplate = columnsTemplate
        self.emptyText = emptyText; self.caller = caller
    }

    // MARK: sort/page state (internal so controlled-binding tests can drive them)

    func activeSort() -> SortOrder? { sortOrderBinding?.get() ?? internalSort }
    func setSort(_ order: SortOrder?) {
        if let b = sortOrderBinding { b.set(order) } else { internalSort = order }
    }
    func currentPage() -> Int { pageBinding?.get() ?? internalPage }
    func setPage(_ p: Int) { if let b = pageBinding { b.set(p) } else { internalPage = p } }

    // MARK: pipeline

    /// Stable sort of row indices by the active column's comparator; identity when unsorted.
    func sortedIndices() -> [Int] {
        let base = Array(0..<rowCount)
        guard let order = activeSort(),
              let col = columns.first(where: { $0.id == order.columnID }),
              let cmp = col.comparator else { return base }
        return base.sorted { i, j in
            switch cmp(i, j) {
            case .ascending:  return order.ascending
            case .descending: return !order.ascending
            case .same:       return i < j   // stable: tie-break on original order
            }
        }
    }

    func pageCount() -> Int {
        guard let size = pageSize, size > 0, rowCount > 0 else { return 1 }
        return (rowCount + size - 1) / size
    }
    func clampedPage() -> Int { max(0, min(currentPage(), pageCount() - 1)) }

    /// Test/host seam: drive scroll metrics directly (the scroll handler does this from the DOM).
    func setViewportMetrics(scrollTop: Double, viewportHeight: Double) {
        if self.scrollTop != scrollTop { self.scrollTop = scrollTop }
        if self.viewportHeight != viewportHeight { self.viewportHeight = viewportHeight }
    }

    /// Row at the TOP edge of the viewport (no overscan), clamped to [0, count). 0 when not virtualized.
    func firstVisibleIndex() -> Int {
        guard let rh = activeRowHeight(), rh > 0 else { return 0 }
        let raw = Int(scrollTop) / rh        // floor for scrollTop ≥ 0; Foundation-free
        return max(0, min(raw, max(0, rowCount - 1)))
    }

    /// Runway height for the sized `<tbody>`: total rows × rowHeight. 0 when not virtualized.
    func runwayHeightPx() -> Int { activeRowHeight().map { rowCount * $0 } ?? 0 }

    /// Resolved row height when virtualization is *active* this render, else nil.
    /// Active requires a positive rowHeight AND a bounded scroll container (`maxHeight`).
    /// Emits a DEBUG diagnostic when the config asked for virtualization but a precondition
    /// is missing, then falls back to a non-virtualized render.
    func activeRowHeight() -> Int? {
        guard case let .fixed(rowHeight)? = virtualization else { return nil }
        guard rowHeight > 0 else {
            swiflowDiagnostic("DataTable: virtualized rowHeight must be > 0; rendering all rows.")
            return nil
        }
        guard maxHeight != nil else {
            swiflowDiagnostic("DataTable: virtualization needs maxHeight (the scroll container); rendering all rows.")
            return nil
        }
        return rowHeight
    }

    /// Pagination renders only when a pageSize is set AND virtualization is not active.
    func paginationActive() -> Bool { pageSize != nil && activeRowHeight() == nil }

    /// Shared `grid-template-columns` for virtualized mode: an auto `min-content` selection
    /// track (when selection is on) + the caller's template, or an equal-fraction default.
    func gridTemplate() -> String {
        let dataCols = columnsTemplate ?? "repeat(\(columns.count), minmax(0, 1fr))"
        return selection != nil ? "min-content \(dataCols)" : dataCols
    }

    /// THE virtualization seam: which sorted indices are visible this render.
    /// virtualized ⇒ scroll-driven window (+overscan); paginated ⇒ page slice; else all rows.
    func visibleWindow(_ order: [Int], page: Int) -> [Int] {
        if let rh = activeRowHeight(), rh > 0 {
            let total = order.count
            guard total > 0 else { return [] }
            let rowsInView = viewportHeight > 0 ? (Int(viewportHeight) + rh - 1) / rh : total  // ceil, Foundation-free
            let first = max(0, firstVisibleIndex() - overscan)
            let end = min(total, first + rowsInView + 2 * overscan)
            return first < end ? Array(order[first..<end]) : []
        }
        guard let size = pageSize, size > 0 else { return order }
        let start = page * size
        guard start < order.count else { return [] }
        return Array(order[start..<min(start + size, order.count)])
    }

    var body: VNode {
        ensureBaseStyles()
        installDataTableStyles()

        let order = sortedIndices()
        let page = clampedPage()
        let window = visibleWindow(order, page: page)

        let scroll: VNode
        if let rh = activeRowHeight() {
            scroll = virtualScroll(window: window, rowHeight: rh)
        } else {
            let table = element("table", attributes: [.class("sw-table")],
                                children: [headerRow(), element("tbody", children: bodyRows(window))])
            var scrollAttrs: [Attribute] = [.class("sw-table__scroll")]
            if let maxHeight { scrollAttrs.append(.style("max-height", maxHeight)) }
            scroll = element("div", attributes: scrollAttrs, children: [table])
        }

        var rootChildren: [VNode] = [scroll]
        if paginationActive(), pageCount() > 1 { rootChildren.append(pager(page: page)) }
        return element("div", attributes: [.class("sw-table-wrap")] + caller, children: rootChildren)
    }

    // MARK: header

    /// `gridColumns` (virtualized mode only) is applied INLINE as `grid-template-columns` on the
    /// header row — NOT via a CSS custom property: Swiflow's `.style()` can't set `--vars` on the
    /// DOM (the driver assigns `element.style[name]`, which silently no-ops for custom properties),
    /// so a `var(--…)` template would resolve empty and collapse the grid to one column.
    private func headerRow(gridColumns: String? = nil) -> VNode {
        var cells: [VNode] = []
        if selection != nil { cells.append(selectAllCell()) }
        cells.append(contentsOf: columns.map(headerCell))
        var trAttrs: [Attribute] = [.class("sw-table__tr sw-table__tr--head")]
        if let gridColumns { trAttrs.append(.style("grid-template-columns", gridColumns)) }
        return element("thead", children: [element("tr", attributes: trAttrs, children: cells)])
    }

    private func alignWidth(_ col: DataColumn) -> [Attribute] {
        var a: [Attribute] = [.style("text-align", col.alignment.cssTextAlign)]
        if let w = col.width { a.append(.style("width", w.css)) }
        return a
    }

    private func headerCell(_ col: DataColumn) -> VNode {
        var attrs: [Attribute] = [.class("sw-table__th"), .attr("scope", "col")] + alignWidth(col)
        let isSortable = sortable && col.comparator != nil
        let children: [VNode]
        if isSortable {
            let s = activeSort()
            let dir = s?.columnID == col.id ? (s!.ascending ? "ascending" : "descending") : "none"
            attrs.append(.attr("aria-sort", dir))
            let indicator = dir == "ascending" ? " \u{25B2}" : dir == "descending" ? " \u{25BC}" : ""
            children = [element("button",
                                attributes: [.class("sw-table__sort"), .attr("type", "button"),
                                             .on(.click) { self.cycleSort(col.id) }],
                                children: [text(col.title + indicator)])]
        } else {
            children = [text(col.title)]
        }
        return element("th", attributes: attrs, children: children)
    }

    /// Tri-state: not-this-column → ascending → descending → unsorted. Internal for tests.
    func cycleSort(_ columnID: String) {
        let cur = activeSort()
        if cur?.columnID != columnID { setSort(SortOrder(columnID: columnID, ascending: true)) }
        else if cur?.ascending == true { setSort(SortOrder(columnID: columnID, ascending: false)) }
        else { setSort(nil) }
    }

    private func selectAllCell() -> VNode {
        let sel = selection!
        let count = sel.selectedCount()
        let allOn = sel.total > 0 && count == sel.total
        let indeterminate = count > 0 && count < sel.total
        let input = element("input", attributes: [
            .attr("type", "checkbox"), .attr("aria-label", "Select all rows"),
            .prop("checked", .bool(allOn)), .prop("indeterminate", .bool(indeterminate)),
            .on(.change) { _ in sel.setAll(!allOn) },
        ])
        return element("th", attributes: [.class("sw-table__th sw-table__select"), .attr("scope", "col")],
                       children: [input])
    }

    // MARK: body

    private func bodyRows(_ window: [Int]) -> [VNode] {
        let colspan = columns.count + (selection != nil ? 1 : 0)
        if loading { return [fullWidthRow(colspan, "sw-table__loading", [Spinner(label: "Loading")]) ] }
        if rowCount == 0 { return [fullWidthRow(colspan, "sw-table__empty", [text(emptyText)])] }
        return window.map(rowVNode)
    }

    private func fullWidthRow(_ colspan: Int, _ cls: String, _ children: [VNode]) -> VNode {
        element("tr", children: [
            element("td", attributes: [.class(cls), .attr("colspan", colspan)], children: children),
        ])
    }

    private func rowVNode(_ i: Int) -> VNode {
        var cells: [VNode] = []
        if let sel = selection { cells.append(rowSelectCell(i, sel)) }
        cells.append(contentsOf: columns.map { col in
            element("td", attributes: [.class("sw-table__td")] + alignWidth(col), children: col.render(i))
        })
        var attrs: [Attribute] = [.key(rowKey(i))]
        let rowClass = onRowClick != nil ? "sw-table__tr sw-table__tr--clickable" : "sw-table__tr"
        attrs.insert(.class(rowClass), at: 0)
        if let sel = selection { attrs.append(.attr("aria-selected", sel.isSelected(i) ? "true" : "false")) }
        if let onRowClick { attrs.append(.on(.click) { onRowClick(i) }) }
        return element("tr", attributes: attrs, children: cells)
    }

    private func rowSelectCell(_ i: Int, _ sel: SelectionModel) -> VNode {
        let input = element("input", attributes: [
            .attr("type", "checkbox"), .attr("aria-label", "Select row"),
            .prop("checked", .bool(sel.isSelected(i))),
            .on(.change) { _ in sel.toggle(i) },
        ])
        return element("td", attributes: [.class("sw-table__td sw-table__select")], children: [input])
    }

    // MARK: virtual render

    #if canImport(JavaScriptKit)
    private let scrollRef = Ref<JSObject>()
    #endif

    private func virtualScroll(window: [Int], rowHeight: Int) -> VNode {
        let first = max(0, firstVisibleIndex() - overscan)   // window start = same as visibleWindow's start
        let cols = gridTemplate()
        let tableAttrs: [Attribute] = [
            .class("sw-table sw-table--virtual"),
            .attr("aria-rowcount", String(rowCount)),
        ]
        let tbody = element("tbody",
                            attributes: [.style("height", "\(runwayHeightPx())px")],
                            children: virtualBodyRows(window, first: first, rowHeight: rowHeight, gridColumns: cols))
        let table = element("table", attributes: tableAttrs, children: [headerRow(gridColumns: cols), tbody])
        var scrollAttrs: [Attribute] = [.class("sw-table__scroll")]
        if let maxHeight { scrollAttrs.append(.style("max-height", maxHeight)) }
        scrollAttrs.append(.on(.custom("scroll")) { self.onScroll() })
        #if canImport(JavaScriptKit)
        scrollAttrs.append(.refBinding(AnyRefBinding(scrollRef)))
        #endif
        return element("div", attributes: scrollAttrs, children: [table])
    }

    private func virtualBodyRows(_ window: [Int], first: Int, rowHeight: Int, gridColumns: String) -> [VNode] {
        let colspan = columns.count + (selection != nil ? 1 : 0)
        if loading { return [fullWidthRow(colspan, "sw-table__loading", [Spinner(label: "Loading")])] }
        if rowCount == 0 { return [fullWidthRow(colspan, "sw-table__empty", [text(emptyText)])] }
        return window.enumerated().map { offset, rowIndex in
            virtualRowVNode(rowIndex, absolute: first + offset, rowHeight: rowHeight, gridColumns: gridColumns)
        }
    }

    private func virtualRowVNode(_ i: Int, absolute: Int, rowHeight: Int, gridColumns: String) -> VNode {
        var cells: [VNode] = []
        if let sel = selection { cells.append(rowSelectCell(i, sel)) }
        cells.append(contentsOf: columns.map { col in
            element("td", attributes: [.class("sw-table__td")] + alignWidth(col), children: col.render(i))
        })
        let rowClass = onRowClick != nil ? "sw-table__tr sw-table__tr--clickable" : "sw-table__tr"
        var attrs: [Attribute] = [
            .class(rowClass), .key(rowKey(i)),
            .style("grid-template-columns", gridColumns),   // inline, not a CSS var — see headerRow note
            .style("transform", "translateY(\(absolute * rowHeight)px)"),
            .style("height", "\(rowHeight)px"),
            .attr("aria-rowindex", String(absolute + 1)),
        ]
        if let sel = selection { attrs.append(.attr("aria-selected", sel.isSelected(i) ? "true" : "false")) }
        if let onRowClick { attrs.append(.on(.click) { onRowClick(i) }) }
        return element("tr", attributes: attrs, children: cells)
    }

    /// Reads scrollTop/clientHeight from the live container and updates metrics ONLY when the
    /// rendered window would actually shift — avoids a re-render per scrolled pixel.
    private func onScroll() {
        #if canImport(JavaScriptKit)
        guard let node = scrollRef.wrappedValue, let rh = activeRowHeight(), rh > 0 else { return }
        let top = node.scrollTop.number ?? 0
        let height = node.clientHeight.number ?? 0
        let newFirst = max(0, Int(top) / rh)
        let newRowsInView = (Int(height) + rh - 1) / rh
        let oldRowsInView = viewportHeight > 0 ? (Int(viewportHeight) + rh - 1) / rh : -1
        if newFirst != firstVisibleIndex() || newRowsInView != oldRowsInView {
            setViewportMetrics(scrollTop: top, viewportHeight: height)
        }
        #endif
    }

    func onAppear() {
        #if canImport(JavaScriptKit)
        guard activeRowHeight() != nil, let node = scrollRef.wrappedValue else { return }
        setViewportMetrics(scrollTop: node.scrollTop.number ?? 0,
                           viewportHeight: node.clientHeight.number ?? 0)
        #endif
    }

    // MARK: pager

    private func pager(page: Int) -> VNode {
        let count = pageCount()
        func navBtn(_ label: String, _ target: Int, disabled: Bool) -> VNode {
            var attrs: [Attribute] = [.class("sw-table__pagebtn"), .attr("type", "button"), .attr("aria-label", label)]
            if disabled { attrs.append(.attr("inert", true)) }     // project rule: inert, not disabled
            else { attrs.append(.on(.click) { self.setPage(target) }) }
            return element("button", attributes: attrs, children: [text(label)])
        }
        return element("div", attributes: [.class("sw-table__pager")], children: [
            navBtn("Previous", page - 1, disabled: page <= 0),
            element("span", attributes: [.class("sw-table__pageinfo")],
                    children: [text("Page \(page + 1) of \(count)")]),
            navBtn("Next", page + 1, disabled: page >= count - 1),
        ])
    }
}

// MARK: - Styles

/// Token-driven table chrome injected once. Sticky header needs the `.sw-table__scroll`
/// ancestor (an `overflow:auto` box); without a `maxHeight` the box doesn't scroll and the
/// header simply sits at the top — documented in the guide.
let dataTableSheet: CSSSheet = css {
    raw("""
    .sw-table-wrap { display: flex; flex-direction: column; gap: var(--sw-space-sm); }
    .sw-table__scroll { overflow: auto; border: 1px solid var(--sw-border); border-radius: var(--sw-radius); }
    .sw-table { width: 100%; border-collapse: collapse; color: var(--sw-text); font-size: 0.9375rem; }
    .sw-table__th {
      position: sticky; top: 0; z-index: 1;
      background-color: var(--sw-surface);
      text-align: start; font-weight: 600;
      padding: var(--sw-space-sm) var(--sw-space-md);
      border-block-end: 1px solid var(--sw-border);
      white-space: nowrap;
    }
    .sw-table__td {
      padding: var(--sw-space-sm) var(--sw-space-md);
      border-block-end: 1px solid var(--sw-border);
    }
    .sw-table__tr[aria-selected="true"] { background-color: var(--sw-accent-soft, color-mix(in oklab, var(--sw-accent) 12%, transparent)); }
    .sw-table__tr--clickable { cursor: pointer; }
    .sw-table__tr--clickable:hover { background-color: var(--sw-surface-hover, color-mix(in oklab, var(--sw-text) 5%, transparent)); }
    .sw-table__sort {
      all: unset; cursor: pointer; font: inherit; font-weight: inherit;
      display: inline-flex; align-items: center; gap: 0.25em; width: 100%;
    }
    .sw-table__sort:focus-visible { outline: 2px solid var(--sw-accent); outline-offset: 2px; }
    .sw-table__select { width: 1px; white-space: nowrap; text-align: center; }
    .sw-table__empty, .sw-table__loading {
      padding: var(--sw-space-lg); text-align: center; color: var(--sw-text-muted);
    }
    .sw-table__pager { display: flex; align-items: center; justify-content: flex-end; gap: var(--sw-space-sm); }
    .sw-table__pageinfo { color: var(--sw-text-muted); font-size: 0.875rem; }
    .sw-table__pagebtn {
      all: unset; cursor: pointer; font: inherit;
      padding: var(--sw-space-xs) var(--sw-space-sm);
      border: 1px solid var(--sw-border); border-radius: var(--sw-radius);
    }
    .sw-table__pagebtn[inert] { opacity: 0.5; cursor: default; }
    .sw-table__pagebtn:focus-visible { outline: 2px solid var(--sw-accent); outline-offset: 2px; }
    .sw-table--virtual { display: block; }
    .sw-table--virtual thead,
    .sw-table--virtual tbody { display: block; }
    .sw-table--virtual tbody { position: relative; }
    .sw-table--virtual .sw-table__tr {
      display: grid;
      align-items: center;
    }
    /* Sticky on the <thead> (parent = the full-height <table>), NOT the header <tr> (parent =
       the short <thead>): a sticky element only pins within its parent's box. */
    .sw-table--virtual thead {
      position: sticky; top: 0; z-index: 1;
      background-color: var(--sw-surface);
    }
    .sw-table--virtual tbody .sw-table__tr {
      position: absolute; inset-inline: 0; top: 0;
      border-block-end: 1px solid var(--sw-border);
    }
    /* The row carries the separator; drop the per-cell border so rows aren't double-lined
       (cells are centered, so their border-block-end would sit mid-row, not at the edge). */
    .sw-table--virtual .sw-table__td { border-block-end: none; }
    .sw-table--virtual .sw-table__th { position: static; }
    """)
}

@MainActor
func installDataTableStyles() { installControlSheet(id: "sw-datatable", dataTableSheet) }
