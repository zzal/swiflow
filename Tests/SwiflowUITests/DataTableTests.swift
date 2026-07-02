// Tests/SwiflowUITests/DataTableTests.swift
// DataTable is a STATEFUL @Component (DataTableBox) behind a generic factory that erases
// rows/columns into index closures. Host tests render `makeDataTableBox(...).body` inside
// `building { }` (handler-ambient) and inspect the VNode tree. The internal-@State default
// sort/page path is exercised via controlled bindings here and end-to-end in the demo e2e.
import Testing
@testable import Swiflow
@testable import SwiflowUI

private struct Person: Identifiable, Equatable { let id: Int; let name: String; let age: Int }

@MainActor private func el(_ node: VNode?) -> ElementData? {
    if case .element(let d)? = node { return d }
    return nil
}
@MainActor private func allText(_ node: VNode) -> String {
    switch node {
    case .text(let s): return s
    case .element(let d): return d.children.map(allText).joined()
    case .fragment(let xs): return xs.map(allText).joined()
    case .environmentOverride(_, let c): return allText(c)
    default: return ""
    }
}
/// Depth-first collect every element with the given tag.
@MainActor private func allTags(_ node: VNode, _ tag: String) -> [ElementData] {
    var out: [ElementData] = []
    func walk(_ n: VNode) {
        if case .element(let d) = n {
            if d.tag == tag { out.append(d) }
            for c in d.children { walk(c) }
        } else if case .fragment(let xs) = n { xs.forEach(walk) }
    }
    walk(node); return out
}
@MainActor private func building<T>(_ body: () -> T) -> T {
    let prev = HandlerAmbient.current
    HandlerAmbient.current = HandlerRegistry()
    defer { HandlerAmbient.current = prev }
    return body()
}

private let people = [Person(id: 1, name: "Ada", age: 36),
                      Person(id: 2, name: "Bob", age: 28),
                      Person(id: 3, name: "Cy",  age: 41)]

@Suite("DataTable — base render")
@MainActor
struct DataTableBaseTests {
    private func box(_ rows: [Person] = people) -> DataTableBox {
        makeDataTableBox(rows, id: \.id) {
            Column("Name", value: \.name)
            Column("Age", value: \.age).align(.trailing).width(.px(80))
        }
    }

    @Test("renders table > thead/tbody with a header row of <th scope=col>") func structure() {
        let root = building { box().body }
        let table = allTags(root, "table").first!
        #expect(table.attributes["class"]?.contains("sw-table") == true)
        let ths = allTags(root, "th")
        #expect(ths.map { allText(.element($0)) } == ["Name", "Age"])
        #expect(ths.allSatisfy { $0.attributes["scope"] == "col" })
    }

    @Test("a <tr> per row, keyed by id, with default text cells") func rows() {
        let root = building { box().body }
        let bodyRows = allTags(root, "tbody").first.map { allTags(.element($0), "tr") } ?? []
        #expect(bodyRows.count == 3)
        #expect(bodyRows.map(\.key) == ["1", "2", "3"])           // keyed by id for diff reuse
        let firstCells = allTags(.element(bodyRows[0]), "td")
        #expect(firstCells.map { allText(.element($0)) } == ["Ada", "36"])
    }

    @Test("custom .cell overrides rendering") func customCell() {
        let b = makeDataTableBox(people, id: \.id) {
            Column("Age", value: \.age).cell { p in [text("#\(p.age)")] }
        }
        let root = building { b.body }
        let firstTd = allTags(.element(allTags(root, "tbody").first!), "td").first!
        #expect(allText(.element(firstTd)) == "#36")
    }

    @Test("alignment + width emit inline styles on header and cells") func alignWidth() {
        let root = building { box().body }
        let ageTh = allTags(root, "th").first { allText(.element($0)) == "Age" }!
        #expect(ageTh.style["text-align"] == "end")
        #expect(ageTh.style["width"] == "80px")
        let ageTd = allTags(.element(allTags(root, "tbody").first!), "td")[1]
        #expect(ageTd.style["text-align"] == "end")
        #expect(ageTd.style["width"] == "80px")
    }

    @Test("table sits inside a scroll container; maxHeight sets max-height") func scrollContainer() {
        let b = makeDataTableBox(people, id: \.id, maxHeight: .custom("480px")) { Column("Name", value: \.name) }
        let root = building { b.body }
        let scroll = allTags(root, "div").first { $0.attributes["class"]?.contains("sw-table__scroll") == true }!
        #expect(scroll.style["max-height"] == "480px")
    }
}

@Suite("DataTable — sorting")
@MainActor
struct DataTableSortTests {
    private let people = [Person(id: 1, name: "Ada", age: 36),
                          Person(id: 2, name: "Bob", age: 28),
                          Person(id: 3, name: "Cy",  age: 41)]

    private func box(_ order: Binding<SortOrder?>) -> DataTableBox {
        makeDataTableBox(people, id: \.id, sortable: true, sortOrder: order) {
            Column("Name", value: \.name)
            Column("Age", value: \.age)
        }
    }
    private func rowKeys(_ root: VNode) -> [String] {
        guard let tbody = allTags(root, "tbody").first else { return [] }
        return allTags(.element(tbody), "tr").map { $0.key ?? "" }
    }

    @Test("ascending sort by Age reorders rows; aria-sort reflects it") func ascending() {
        let order = Binding<SortOrder?>(get: { SortOrder(columnID: "Age", ascending: true) }, set: { _ in })
        let root = building { box(order).body }
        #expect(rowKeys(root) == ["2", "1", "3"])   // 28, 36, 41
        let ageTh = allTags(root, "th").first { allText(.element($0)).contains("Age") }!
        #expect(ageTh.attributes["aria-sort"] == "ascending")
    }

    @Test("descending sort reverses order") func descending() {
        let order = Binding<SortOrder?>(get: { SortOrder(columnID: "Age", ascending: false) }, set: { _ in })
        #expect(rowKeys(building { box(order).body }) == ["3", "1", "2"])
    }

    @Test("unsorted keeps input order") func unsorted() {
        let order = Binding<SortOrder?>(get: { nil }, set: { _ in })
        #expect(rowKeys(building { box(order).body }) == ["1", "2", "3"])
    }

    @Test("sort is stable for equal keys (tie-break on original order)") func stable() {
        let dup = [Person(id: 1, name: "A", age: 5), Person(id: 2, name: "B", age: 5), Person(id: 3, name: "C", age: 1)]
        let order = Binding<SortOrder?>(get: { SortOrder(columnID: "Age", ascending: true) }, set: { _ in })
        let b = makeDataTableBox(dup, id: \.id, sortable: true, sortOrder: order) { Column("Age", value: \.age) }
        let keys = { () -> [String] in
            let root = building { b.body }
            return allTags(.element(allTags(root, "tbody").first!), "tr").map { $0.key ?? "" }
        }()
        #expect(keys == ["3", "1", "2"])   // 1 first, then the two 5s in original order
    }

    @Test("non-sortable column gets no aria-sort/button") func nonSortable() {
        let order = Binding<SortOrder?>(get: { nil }, set: { _ in })
        let b = makeDataTableBox(people, id: \.id, sortable: true, sortOrder: order) {
            Column("Actions") { _ in [text("x")] }
        }
        let root = building { b.body }
        let th = allTags(root, "th").first!
        #expect(th.attributes["aria-sort"] == nil)
        #expect(allTags(.element(th), "button").isEmpty)
    }

    @Test("cycleSort goes none → asc → desc → none") func cycle() {
        var current: SortOrder? = nil
        let order = Binding<SortOrder?>(get: { current }, set: { current = $0 })
        let b = box(order)
        b.cycleSort("Age"); #expect(current == SortOrder(columnID: "Age", ascending: true))
        b.cycleSort("Age"); #expect(current == SortOrder(columnID: "Age", ascending: false))
        b.cycleSort("Age"); #expect(current == nil)
    }

    @Test("clicking a different column starts ascending on it") func switchColumn() {
        var current: SortOrder? = SortOrder(columnID: "Age", ascending: false)
        let order = Binding<SortOrder?>(get: { current }, set: { current = $0 })
        box(order).cycleSort("Name")
        #expect(current == SortOrder(columnID: "Name", ascending: true))
    }

    @Test("sortable:false on the table renders plain headers") func tableNotSortable() {
        let order = Binding<SortOrder?>(get: { nil }, set: { _ in })
        let b = makeDataTableBox(people, id: \.id, sortable: false, sortOrder: order) { Column("Age", value: \.age) }
        let root = building { b.body }
        #expect(allTags(root, "button").isEmpty)
    }

    @Test("sortedIndices caches across a scroll-only re-render and recomputes on sort change")
    func sortedIndicesCache() {
        let order = Binding<SortOrder?>(get: { SortOrder(columnID: "Age", ascending: true) }, set: { _ in })
        let b = makeDataTableBox(people, id: \.id, sortable: true, sortOrder: order,
                                 maxHeight: .custom("100px"),
                                 virtualization: .fixed(rowHeight: 20)) {
            Column("Name", value: \.name)
            Column("Age", value: \.age)
        }
        // Prime the cache.
        let first = b.sortedIndices()
        // A scroll-only change must not invalidate the cache → same contents + cache hit.
        b.setViewportMetrics(scrollTop: 40, viewportHeight: 100)
        let afterScroll = b.sortedIndices()
        #expect(afterScroll == first)
        // The hit probe is DEBUG-only (matches the `#if DEBUG` gate on the
        // property in DataTable.swift), so `swift test -c release` still compiles.
        #if DEBUG
        #expect(b._sortCacheHitForTesting == true)
        #endif
    }
}

@Suite("DataTable — selection")
@MainActor
struct DataTableSelectionTests {
    private let people = [Person(id: 1, name: "Ada", age: 36),
                          Person(id: 2, name: "Bob", age: 28),
                          Person(id: 3, name: "Cy",  age: 41)]

    private func box(_ sel: Binding<Set<Int>>) -> DataTableBox {
        makeDataTableBox(people, id: \.id, selection: sel) { Column("Name", value: \.name) }
    }
    @MainActor private func checkboxes(_ root: VNode) -> [ElementData] {
        allTags(root, "input").filter { $0.attributes["type"] == "checkbox" }
    }
    private func boolProp(_ d: ElementData, _ name: String) -> Bool? {
        if case .bool(let b)? = d.properties[name] { return b }
        return nil
    }

    @Test("a checkbox column appears (header + one per row)") func hasColumn() {
        let sel = Binding<Set<Int>>(get: { [] }, set: { _ in })
        let root = building { box(sel).body }
        #expect(checkboxes(root).count == 4)   // 1 header + 3 rows
    }

    @Test("no selection binding ⇒ no checkbox column") func noColumn() {
        let b = makeDataTableBox(people, id: \.id) { Column("Name", value: \.name) }
        let root = building { b.body }
        #expect(checkboxes(root).isEmpty)
    }

    @Test("row checkbox reflects selected state; toggle adds/removes the id") func toggle() {
        var set: Set<Int> = [2]
        let sel = Binding<Set<Int>>(get: { set }, set: { set = $0 })
        let b = box(sel)
        var root = building { b.body }
        // header is checkboxes[0]; row order is 1,2,3 → row 2 is checkboxes[2]
        #expect(boolProp(checkboxes(root)[2], "checked") == true)
        b.selection!.toggle(0)            // row index 0 = id 1
        #expect(set == [1, 2])
        b.selection!.toggle(1)            // row index 1 = id 2 → removed
        #expect(set == [1])
        root = building { b.body }
        #expect(boolProp(checkboxes(root)[1], "checked") == true)   // id 1 now checked
    }

    @Test("rows carry aria-selected") func ariaSelected() {
        var set: Set<Int> = [1]
        let sel = Binding<Set<Int>>(get: { set }, set: { set = $0 })
        let root = building { box(sel).body }
        let trs = allTags(.element(allTags(root, "tbody").first!), "tr")
        #expect(trs[0].attributes["aria-selected"] == "true")
        #expect(trs[1].attributes["aria-selected"] == "false")
    }

    @Test("header is indeterminate on partial, checked on full") func selectAllStates() {
        var set: Set<Int> = []
        let sel = Binding<Set<Int>>(get: { set }, set: { set = $0 })
        let b = box(sel)
        // none selected
        var header = checkboxes(building { b.body })[0]
        #expect(boolProp(header, "checked") == false)
        #expect(boolProp(header, "indeterminate") == false)
        // partial
        set = [1]
        header = checkboxes(building { b.body })[0]
        #expect(boolProp(header, "indeterminate") == true)
        // full
        set = [1, 2, 3]
        header = checkboxes(building { b.body })[0]
        #expect(boolProp(header, "checked") == true)
        #expect(boolProp(header, "indeterminate") == false)
    }

    @Test("setAll selects every row then clears") func setAll() {
        var set: Set<Int> = []
        let sel = Binding<Set<Int>>(get: { set }, set: { set = $0 })
        let b = box(sel)
        b.selection!.setAll(true);  #expect(set == [1, 2, 3])
        b.selection!.setAll(false); #expect(set.isEmpty)
    }
}

@Suite("DataTable — pagination")
@MainActor
struct DataTablePaginationTests {
    private let many = (1...10).map { Person(id: $0, name: "P\($0)", age: $0) }

    private func box(pageSize: Int, page: Binding<Int>) -> DataTableBox {
        makeDataTableBox(many, id: \.id, pageSize: pageSize, page: page) { Column("Name", value: \.name) }
    }
    private func rowKeys(_ root: VNode) -> [String] {
        allTags(.element(allTags(root, "tbody").first!), "tr").map { $0.key ?? "" }
    }
    private func pagerButtons(_ root: VNode) -> [ElementData] {
        guard let pager = allTags(root, "div").first(where: { $0.attributes["class"] == "sw-table__pager" }) else { return [] }
        return allTags(.element(pager), "button")
    }

    @Test("first page shows the first slice") func firstSlice() {
        let page = Binding<Int>(get: { 0 }, set: { _ in })
        #expect(rowKeys(building { box(pageSize: 4, page: page).body }) == ["1", "2", "3", "4"])
    }

    @Test("second page shows the next slice") func secondSlice() {
        let page = Binding<Int>(get: { 1 }, set: { _ in })
        #expect(rowKeys(building { box(pageSize: 4, page: page).body }) == ["5", "6", "7", "8"])
    }

    @Test("last partial page shows the remainder") func lastSlice() {
        let page = Binding<Int>(get: { 2 }, set: { _ in })
        #expect(rowKeys(building { box(pageSize: 4, page: page).body }) == ["9", "10"])
    }

    @Test("page index is clamped when it exceeds the range") func clamp() {
        let page = Binding<Int>(get: { 99 }, set: { _ in })
        #expect(rowKeys(building { box(pageSize: 4, page: page).body }) == ["9", "10"])   // clamped to page 2
    }

    @Test("Previous is inert on the first page; Next on the last") func inertEnds() {
        let first = Binding<Int>(get: { 0 }, set: { _ in })
        let btnsFirst = pagerButtons(building { box(pageSize: 4, page: first).body })
        #expect(btnsFirst.first!.attributes["inert"] == "")        // Previous inert
        #expect(btnsFirst.last!.attributes["inert"] == nil)        // Next active

        let last = Binding<Int>(get: { 2 }, set: { _ in })
        let btnsLast = pagerButtons(building { box(pageSize: 4, page: last).body })
        #expect(btnsLast.first!.attributes["inert"] == nil)
        #expect(btnsLast.last!.attributes["inert"] == "")          // Next inert
    }

    @Test("Next advances the bound page") func next() {
        var p = 0
        let page = Binding<Int>(get: { p }, set: { p = $0 })
        let b = box(pageSize: 4, page: page)
        b.setPage(1)
        #expect(p == 1)
    }

    @Test("no pager when everything fits on one page") func noPager() {
        let page = Binding<Int>(get: { 0 }, set: { _ in })
        let small = makeDataTableBox(Array(many.prefix(3)), id: \.id, pageSize: 10, page: page) { Column("Name", value: \.name) }
        #expect(pagerButtons(building { small.body }).isEmpty)
    }
}

@Suite("DataTable — empty & loading")
@MainActor
struct DataTableStateTests {
    private let people = [Person(id: 1, name: "Ada", age: 36)]

    @Test("empty rows render the empty-state cell spanning all columns") func empty() {
        let b = makeDataTableBox([Person](), id: \.id, selection: Binding<Set<Int>>(get: { [] }, set: { _ in }),
                                 emptyText: "Nothing here") {
            Column("Name", value: \.name); Column("Age", value: \.age)
        }
        let root = building { b.body }
        let tds = allTags(.element(allTags(root, "tbody").first!), "td")
        #expect(tds.count == 1)
        #expect(tds[0].attributes["class"] == "sw-table__empty")
        #expect(tds[0].attributes["colspan"] == "3")   // 2 columns + selection
        #expect(allText(.element(tds[0])) == "Nothing here")
    }

    @Test("loading renders a spinner row spanning all columns (rows hidden)") func loading() {
        let b = makeDataTableBox(people, id: \.id, loading: true) { Column("Name", value: \.name) }
        let root = building { b.body }
        let tds = allTags(.element(allTags(root, "tbody").first!), "td")
        #expect(tds.count == 1)
        #expect(tds[0].attributes["class"] == "sw-table__loading")
        #expect(tds[0].attributes["colspan"] == "1")
        #expect(allTags(.element(tds[0]), "span").contains { $0.attributes["role"] == "status" })  // Spinner
    }

    @Test("loading takes precedence over having rows") func loadingPrecedence() {
        let b = makeDataTableBox(people, id: \.id, loading: true) { Column("Name", value: \.name) }
        let root = building { b.body }
        let trs = allTags(.element(allTags(root, "tbody").first!), "tr")
        #expect(trs.count == 1)   // the loading row, not the data row
    }

    @Test func windowSlicesToViewportPlusOverscan() {
        let people = (0..<1000).map { Person(id: $0, name: "P\($0)", age: $0) }
        let box = makeDataTableBox(people, id: \.id, maxHeight: .custom("400px"),
                                   virtualization: .fixed(rowHeight: 40),
                                   columnsTemplate: "1fr") { Column("Name", value: \.name) }
        // 400px viewport / 40px row = 10 rows in view; overscan 3 each side.
        box.setViewportMetrics(scrollTop: 0, viewportHeight: 400)
        let win = box.visibleWindow(box.sortedIndices(), page: 0)
        #expect(win.first == 0)                       // top clamps overscan
        #expect(win.count == 10 + 2 * box.overscan)   // rowsInView(400/40) + overscan both sides
        #expect(box.firstVisibleIndex() == 0)
    }

    @Test func windowOffsetsWhenScrolled() {
        let people = (0..<1000).map { Person(id: $0, name: "P\($0)", age: $0) }
        let box = makeDataTableBox(people, id: \.id, maxHeight: .custom("400px"),
                                   virtualization: .fixed(rowHeight: 40),
                                   columnsTemplate: "1fr") { Column("Name", value: \.name) }
        box.setViewportMetrics(scrollTop: 4000, viewportHeight: 400)   // viewport-top row = 100
        let win = box.visibleWindow(box.sortedIndices(), page: 0)
        #expect(box.firstVisibleIndex() == 100)          // no overscan
        #expect(win.first == 100 - box.overscan)         // window start = firstVisible - overscan
        #expect(win.count == 10 + 2 * box.overscan)
    }

    @Test func windowClampsAtBottom() {
        let people = (0..<1000).map { Person(id: $0, name: "P\($0)", age: $0) }
        let box = makeDataTableBox(people, id: \.id, maxHeight: .custom("400px"),
                                   virtualization: .fixed(rowHeight: 40),
                                   columnsTemplate: "1fr") { Column("Name", value: \.name) }
        box.setViewportMetrics(scrollTop: 39_600, viewportHeight: 400)  // bottom: 1000*40 - 400
        let win = box.visibleWindow(box.sortedIndices(), page: 0)
        #expect(win.last == 999)                  // never past the end
        #expect(win.allSatisfy { $0 < 1000 })
    }

    @Test func nonVirtualizedWindowUnchanged() {
        let people = (0..<30).map { Person(id: $0, name: "P\($0)", age: $0) }
        let paged = makeDataTableBox(people, id: \.id, pageSize: 10) { Column("Name", value: \.name) }
        #expect(paged.visibleWindow(paged.sortedIndices(), page: 1).count == 10)  // page slice intact
        let all = makeDataTableBox(people, id: \.id) { Column("Name", value: \.name) }
        #expect(all.visibleWindow(all.sortedIndices(), page: 0).count == 30)      // all rows intact
    }

    @Test func runwayHeightIsTotalTimesRowHeight() {
        let people = (0..<250).map { Person(id: $0, name: "P\($0)", age: $0) }
        let box = makeDataTableBox(people, id: \.id, maxHeight: .custom("400px"),
                                   virtualization: .fixed(rowHeight: 32),
                                   columnsTemplate: "1fr") { Column("Name", value: \.name) }
        #expect(box.runwayHeightPx() == 250 * 32)
    }

    @Test func gridTemplateIncludesSelectionTrack() {
        let rows = (0..<3).map { Person(id: $0, name: "P\($0)", age: $0) }
        let sel = Binding<Set<Int>>(get: { [] }, set: { _ in })
        let box = makeDataTableBox(rows, id: \.id, selection: sel,
                                   maxHeight: .custom("300px"), virtualization: .fixed(rowHeight: 40),
                                   columnsTemplate: "1fr 80px") {
            Column("Name", value: \.name); Column("Age", value: \.age)
        }
        #expect(box.gridTemplate() == "min-content 1fr 80px")
    }

    @Test func gridTemplateDefaultsToRepeatWhenNoTemplate() {
        let rows = (0..<3).map { Person(id: $0, name: "P\($0)", age: $0) }
        let box = makeDataTableBox(rows, id: \.id, maxHeight: .custom("300px"),
                                   virtualization: .fixed(rowHeight: 40)) {
            Column("Name", value: \.name); Column("Age", value: \.age)
        }
        #expect(box.gridTemplate() == "repeat(2, minmax(0, 1fr))")
    }

    @Test func virtualBodyHasPaddingSpacerAndRows() {
        let rows = (0..<1000).map { Person(id: $0, name: "P\($0)", age: $0) }
        let box = makeDataTableBox(rows, id: \.id, maxHeight: .custom("400px"),
                                   virtualization: .fixed(rowHeight: 40),
                                   columnsTemplate: "1fr") { Column("Name", value: \.name) }
        box.setViewportMetrics(scrollTop: 4000, viewportHeight: 400)
        let root = building { box.body }
        let table = allTags(root, "table").first!
        #expect(table.attributes["class"]?.contains("sw-table--virtual") == true)
        #expect(table.attributes["aria-rowcount"] == "1000")
        // grid-template-columns is inline on each row (NOT a `--var` — Swiflow's .style() can't
        // set custom properties on the DOM), so header + body rows must carry it directly.
        let headTr = allTags(.element(allTags(root, "thead").first!), "tr").first!
        #expect(headTr.style["grid-template-columns"] == "1fr")
        let tbody = allTags(root, "tbody").first!
        let start = 100 - box.overscan                       // window start (firstVisible 100)
        let end = start + (10 + 2 * box.overscan)
        // Scroll offset is now carried by tbody padding, not row transforms.
        #expect(tbody.style["padding-top"] == "\(start * 40)px")
        #expect(tbody.style["padding-bottom"] == "\(max(0, 1000 - end) * 40)px")
        let trs = allTags(.element(tbody), "tr")
        #expect(trs.count == 10 + 2 * box.overscan)
        #expect(trs.first!.style["grid-template-columns"] == "1fr")
        #expect(trs.first!.style["transform"] == nil)        // no per-row transform in padding model
        #expect(trs.first!.attributes["aria-rowindex"] == "\(start + 1)")
    }

    @Test func nonVirtualizedHasNoVirtualClass() {
        let rows = (0..<3).map { Person(id: $0, name: "P\($0)", age: $0) }
        let box = makeDataTableBox(rows, id: \.id) { Column("Name", value: \.name) }
        let root = building { box.body }
        let table = allTags(root, "table").first!
        #expect(table.attributes["class"]?.contains("sw-table--virtual") != true)
    }
}

@MainActor
@Suite struct DataTableVirtualizationTests {
    @Test func boxStoresVirtualizationConfig() {
        let people = (0..<5).map { Person(id: $0, name: "P\($0)", age: 20 + $0) }
        let box = makeDataTableBox(people, id: \.id, maxHeight: .custom("300px"),
                                   virtualization: .fixed(rowHeight: 40),
                                   columnsTemplate: "1fr 80px 1fr") {
            Column("Name", value: \.name)
            Column("Age", value: \.age)
            Column("Name2", value: \.name)
        }
        #expect(box.virtualization == .fixed(rowHeight: 40))
        #expect(box.columnsTemplate == "1fr 80px 1fr")
    }

    @Test func virtualizationInactiveWithoutMaxHeight() {
        let people = (0..<5).map { Person(id: $0, name: "P\($0)", age: $0) }
        let box = makeDataTableBox(people, id: \.id, virtualization: .fixed(rowHeight: 40),
                                   columnsTemplate: "1fr") { Column("Name", value: \.name) }
        #if DEBUG
        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }
        #expect(box.activeRowHeight() == nil)   // no maxHeight ⇒ not active
        #expect(captured.contains { $0.contains("maxHeight") })
        #else
        #expect(box.activeRowHeight() == nil)
        #endif
    }

    @Test func virtualizationInactiveWithNonPositiveRowHeight() {
        let people = (0..<5).map { Person(id: $0, name: "P\($0)", age: $0) }
        let box = makeDataTableBox(people, id: \.id, maxHeight: .custom("300px"),
                                   virtualization: .fixed(rowHeight: 0),
                                   columnsTemplate: "1fr") { Column("Name", value: \.name) }
        #if DEBUG
        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }
        #expect(box.activeRowHeight() == nil)
        #expect(captured.contains { $0.contains("rowHeight") })
        #else
        #expect(box.activeRowHeight() == nil)
        #endif
    }

    @Test func virtualizationActiveWithHeightAndRowHeight() {
        let people = (0..<5).map { Person(id: $0, name: "P\($0)", age: $0) }
        let box = makeDataTableBox(people, id: \.id, maxHeight: .custom("300px"),
                                   virtualization: .fixed(rowHeight: 44),
                                   columnsTemplate: "1fr") { Column("Name", value: \.name) }
        #expect(box.activeRowHeight() == 44)
    }

    @Test func virtualizationSuppressesPager() {
        let people = (0..<50).map { Person(id: $0, name: "P\($0)", age: $0) }
        let box = makeDataTableBox(people, id: \.id, pageSize: 10, maxHeight: .custom("300px"),
                                   virtualization: .fixed(rowHeight: 44),
                                   columnsTemplate: "1fr") { Column("Name", value: \.name) }
        #expect(box.activeRowHeight() == 44)
        #expect(box.paginationActive() == false)   // virtualization wins
    }

    @Test func paginationActiveWhenNotVirtualized() {
        let people = (0..<50).map { Person(id: $0, name: "P\($0)", age: $0) }
        let box = makeDataTableBox(people, id: \.id, pageSize: 10) { Column("Name", value: \.name) }
        #expect(box.activeRowHeight() == nil)
        #expect(box.paginationActive() == true)
    }
}

@Suite("DataTable — row interaction")
@MainActor
struct DataTableRowClickTests {
    private let people = [Person(id: 1, name: "Ada", age: 36), Person(id: 2, name: "Bob", age: 28)]

    @Test("onRowClick fires with the row's index→row, and rows get the clickable class") func rowClick() {
        var clicked: [Int] = []
        let b = makeDataTableBox(people, id: \.id, onRowClick: { clicked.append($0.id) }) {
            Column("Name", value: \.name)
        }
        let root = building { b.body }
        let trs = allTags(.element(allTags(root, "tbody").first!), "tr")
        #expect(trs.allSatisfy { $0.attributes["class"]?.contains("sw-table__tr--clickable") == true })
        // invoke the row-0 click handler through the ambient registry
        // NOTE: HandlerRegistry accessor is `handler(forID:)` (not `handler(for:)` as the plan says)
        let reg = HandlerRegistry()
        HandlerAmbient.current = reg
        let node = b.body
        let tr0 = allTags(.element(allTags(node, "tbody").first!), "tr")[0]
        let handlerID = tr0.handlers["click"]!.id
        reg.handler(forID: handlerID)!.invoke(EventInfo(type: "click"))
        #expect(clicked == [1])
    }

    @Test("onRowClick ignores clicks from interactive descendants (checkbox / action buttons)")
    func rowClickIgnoresInteractiveDescendants() {
        var clicked: [Int] = []
        let b = makeDataTableBox(people, id: \.id, onRowClick: { clicked.append($0.id) }) {
            Column("Name", value: \.name)
        }
        let reg = HandlerRegistry()
        HandlerAmbient.current = reg
        let node = b.body
        let tr0 = allTags(.element(allTags(node, "tbody").first!), "tr")[0]
        let handler = reg.handler(forID: tr0.handlers["click"]!.id)!
        // A click that bubbled from a control inside the row (row-select
        // checkbox, an Actions-column Button) must NOT fire row navigation.
        handler.invoke(EventInfo(type: "click", fromInteractiveDescendant: true))
        #expect(clicked.isEmpty)
        // A plain cell click still navigates.
        handler.invoke(EventInfo(type: "click"))
        #expect(clicked == [1])
    }

    @Test("no onRowClick ⇒ no click handler and no clickable class") func noRowClick() {
        let b = makeDataTableBox(people, id: \.id) { Column("Name", value: \.name) }
        let root = building { b.body }
        let tr = allTags(.element(allTags(root, "tbody").first!), "tr")[0]
        #expect(tr.handlers["click"] == nil)
        #expect(tr.attributes["class"]?.contains("clickable") != true)
    }
}

// MARK: VNode-walk helpers for padding-spacer tests

@MainActor private func anyElement(in node: VNode, where pred: (ElementData) -> Bool) -> Bool {
    switch node {
    case .element(let d):
        if pred(d) { return true }
        return d.children.contains { anyElement(in: $0, where: pred) }
    default: return false
    }
}
@MainActor private func firstElement(in node: VNode, where pred: (ElementData) -> Bool) -> ElementData? {
    switch node {
    case .element(let d):
        if pred(d) { return d }
        for c in d.children { if let f = firstElement(in: c, where: pred) { return f } }
        return nil
    default: return nil
    }
}

extension DataTableStateTests {
    @Test("virtualized tbody uses padding spacer; rows carry no transform")
    func virtualPaddingSpacer() {
        let b = makeDataTableBox(Array(0..<100).map { Person(id: $0, name: "P\($0)", age: $0) },
                                 id: \.id, maxHeight: .custom("220px"),
                                 virtualization: .fixed(rowHeight: 20)) {
            Column("Name", value: \.name)
        }
        // viewport 220 / row 20 = 11 rows in view; scroll to row 50.
        b.setViewportMetrics(scrollTop: 50 * 20, viewportHeight: 220)
        let root = building { b.body }

        let tbody = firstElement(in: root) { $0.tag == "tbody" }
        #expect(tbody != nil)
        let first = max(0, 50 - b.overscan)
        #expect(tbody?.style["padding-top"] == "\(first * 20)px")
        // No <tr> in the body carries a transform.
        let anyTransform = anyElement(in: root) { $0.tag == "tr" && $0.style["transform"] != nil }
        #expect(!anyTransform)
    }
}

extension DataTableStateTests {
    @Test func sheetContainsVirtualRules() {
        let css = dataTableSheet.cssString(scopeClass: "")
        #expect(css.contains(".sw-table--virtual"))
        #expect(css.contains("display: grid"))       // rows are grid containers (template is inline per row)
        #expect(css.contains("position: sticky"))   // header row pins in virtual mode
    }
}

@Suite("DataTable — row memo cache")
@MainActor
struct DataTableRowCacheTests {
    @Test("scrolling one row rebuilds only the entering row; others are cache hits")
    func rowCacheHitOnScroll() {
        let b = makeDataTableBox(Array(0..<200).map { Person(id: $0, name: "P\($0)", age: $0) },
                                 id: \.id, maxHeight: .custom("220px"),
                                 virtualization: .fixed(rowHeight: 20)) {
            Column("Name", value: \.name)
        }
        b.setViewportMetrics(scrollTop: 1000, viewportHeight: 220)   // window around row 50
        _ = building { b.body }                                      // prime: all windowed rows built
        let builtFirstPass = b._rowRebuildsForTesting
        #expect(builtFirstPass > 0)

        // Shift the window down by exactly one row.
        b.setViewportMetrics(scrollTop: 1000 + 20, viewportHeight: 220)
        _ = building { b.body }
        #expect(b._rowRebuildsForTesting == 1)   // only the newly-entering row rebuilt
    }

    @Test("toggling one row's selection rebuilds only that row")
    func rowCacheInvalidatesOnSelection() {
        var selected: Set<Int> = []
        let sel = Binding<Set<Int>>(get: { selected }, set: { selected = $0 })
        let b = makeDataTableBox(Array(0..<200).map { Person(id: $0, name: "P\($0)", age: $0) },
                                 id: \.id, selection: sel, maxHeight: .custom("220px"),
                                 virtualization: .fixed(rowHeight: 20)) {
            Column("Name", value: \.name)
        }
        b.setViewportMetrics(scrollTop: 1000, viewportHeight: 220)
        _ = building { b.body }                  // prime
        selected = [50]                          // toggle one visible row
        _ = building { b.body }
        #expect(b._rowRebuildsForTesting == 1)
    }

    @Test("row cache stays window-sized after scrolling across many windows")
    func rowCacheBounded() {
        let b = makeDataTableBox(Array(0..<2000).map { Person(id: $0, name: "P\($0)", age: $0) },
                                 id: \.id, maxHeight: .custom("220px"),
                                 virtualization: .fixed(rowHeight: 20)) {
            Column("Name", value: \.name)
        }
        for top in stride(from: 0, to: 20000, by: 400) {
            b.setViewportMetrics(scrollTop: Double(top), viewportHeight: 220)
            _ = building { b.body }
        }
        // viewport 11 + 2*overscan; cache must not grow unbounded toward 2000.
        #expect(b._rowCacheCountForTesting <= 11 + 2 * b.overscan + 4)
    }

    @Test("one-row window slide emits a minimal patch set (one row created, no moves)")
    func windowSlideMinimalPatches() {
        let b = makeDataTableBox(Array(0..<300).map { Person(id: $0, name: "P\($0)", age: $0) },
                                 id: \.id, maxHeight: .custom("220px"),
                                 virtualization: .fixed(rowHeight: 20)) {
            Column("Name", value: \.name)
        }
        let h = HandleAllocator(); let hr = HandlerRegistry()
        b.setViewportMetrics(scrollTop: 2000, viewportHeight: 220)
        let v1 = building { b.body }
        let m1 = diff(mounted: nil, next: v1, handles: h, handlers: hr).newMountTree

        b.setViewportMetrics(scrollTop: 2000 + 20, viewportHeight: 220)   // slide one row
        let v2 = building { b.body }
        let res = diff(mounted: m1, next: v2, handles: h, handlers: hr)

        // Exactly one new <tr> created (the entering row). Patch shape:
        // `case createElement(handle: Int, tag: String)`.
        let createdRows = res.patches.filter {
            if case .createElement(_, "tr") = $0 { return true }
            return false
        }
        #expect(createdRows.count == 1)
    }
}

@MainActor
@Suite("DataTable — virtualized column widths")
struct DataTableVirtualWidthTests {
    private let people = [Person(id: 1, name: "Ada", age: 36),
                          Person(id: 2, name: "Linus", age: 54)]

    @Test("gridTemplate synthesizes tracks from per-column .width (nil → flexible)")
    func synthesizesFromColumnWidths() {
        let b = makeDataTableBox(people, id: \.id,
                                 maxHeight: .custom("200px"),
                                 virtualization: .fixed(rowHeight: 20)) {
            Column("Name", value: \.name)                 // no width → minmax(0, 1fr)
            Column("Age", value: \.age).width(.px(80))    // fixed track
        }
        #expect(b.gridTemplate() == "minmax(0, 1fr) 80px")
    }

    @Test("selection prepends a min-content track to the synthesized template")
    func selectionPrependsMinContent() {
        var sel: Set<Int> = []
        let b = makeDataTableBox(people, id: \.id,
                                 selection: Binding(get: { sel }, set: { sel = $0 }),
                                 maxHeight: .custom("200px"),
                                 virtualization: .fixed(rowHeight: 20)) {
            Column("Name", value: \.name).width(.px(120))
            Column("Age", value: \.age)
        }
        #expect(b.gridTemplate() == "min-content 120px minmax(0, 1fr)")
    }

    @Test("explicit columnsTemplate wins; diagnostic fires when per-column .width is also set")
    func columnsTemplateWinsWithDiagnostic() {
        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        let b = makeDataTableBox(people, id: \.id,
                                 maxHeight: .custom("200px"),
                                 virtualization: .fixed(rowHeight: 20),
                                 columnsTemplate: "2fr 1fr") {
            Column("Name", value: \.name).width(.px(80))  // conflicts with columnsTemplate
            Column("Age", value: \.age)
        }
        #expect(b.gridTemplate() == "2fr 1fr")
        #expect(captured.contains { $0.contains("columnsTemplate") && $0.contains("width") })
    }

    @Test("columnsTemplate with no per-column width does not warn")
    func columnsTemplateNoWidthNoWarn() {
        var captured: [String] = []
        let prior = _swiflowDiagnosticOverride
        _swiflowDiagnosticOverride = { captured.append($0) }
        defer { _swiflowDiagnosticOverride = prior }

        let b = makeDataTableBox(people, id: \.id,
                                 maxHeight: .custom("200px"),
                                 virtualization: .fixed(rowHeight: 20),
                                 columnsTemplate: "2fr 1fr") {
            Column("Name", value: \.name)
            Column("Age", value: \.age)
        }
        #expect(b.gridTemplate() == "2fr 1fr")
        #expect(captured.isEmpty)
    }
}
