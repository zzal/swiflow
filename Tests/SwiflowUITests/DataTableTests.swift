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
}
