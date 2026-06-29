# SwiflowUI DataTable Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a feature-rich, accessible SwiflowUI `DataTable` over a typed row model — declarative columns (keypath + custom cell), client-side tri-state sorting, multi-row selection, sticky header, empty/loading states, per-column alignment/width, row-click, and client-side pagination.

**Architecture:** A generic public `DataTable<Row, ID: Hashable>` factory captures rows + a `@ColumnBuilder` list of `Column<Row>` and **erases** them into index-based closures (`DataColumn`, `SelectionModel`, a `rowKey`), then constructs a **concrete, non-generic** `@Component final class DataTableBox` via `embedKeyed`. The box owns transient sort/page `@State` (with opt-in bindings) and renders one pipeline per body: `sort → window → render`. The **window** step is the single seam (page-slice in v1) that keeps virtualization addable later. Selection lives entirely in the caller's `Binding<Set<ID>>`.

**Why erased/non-generic box:** `@Component`'s MemberMacro emits `StateCell<DataTableBox>` using the **bare class name** (`Sources/SwiflowMacrosPlugin/ComponentMacro.swift:107`), so a generic `@Component` class fails to compile. Erasure in the factory is the deterministic path and gives a clean, testable boundary.

**Tech Stack:** Swift 6.3, SwiflowUI (built on core `Swiflow` VNode/diff/`@Component`), Swift Testing (`@Test`/`#expect`), the existing `installControlSheet` CSS seam, Playwright for e2e. No JS driver / patch-protocol / core-`Swiflow` change.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Sources/SwiflowUI/Column.swift` (create) | `SortComparison`, `ColumnAlignment`, `ColumnWidth`, `SortOrder`, `Column<Row>` (value type: cell builder, comparator capture, alignment/width/id, modifiers), `@ColumnBuilder` |
| `Sources/SwiflowUI/DataTable.swift` (create) | Public `DataTable<Row,ID>` factory overloads; `makeDataTableBox` (test seam, does the erasure); internal `DataColumn`/`SelectionModel`; `DataTableBox` `@Component`; the sort/window/render pipeline; `dataTableSheet` + `installDataTableStyles()` |
| `Tests/SwiflowUITests/ColumnTests.swift` (create) | `Column<Row>` + `@ColumnBuilder` unit tests |
| `Tests/SwiflowUITests/DataTableTests.swift` (create) | Render/behavior tests against the box's VNode tree |
| `examples/SwiflowUIDemo/Sources/SwiflowUIDemo/...` (modify) | DataTable gallery entry |
| `docs/guides/swiflowui.md` (modify) | DataTable usage + sticky-header scroll-container caveat + row-click caveat + deferred list |
| `docs/future-work/swiflowui-1.0-roadmap.md` (modify) | Record DataTable shipped; fold in the pending PR #84 escape-hatch note |
| `examples/SwiflowUIDemo/e2e/datatable.spec.ts` (create) | Playwright: sort reorders, select-all, paging (run inline) |

**Branch:** already on `feat/swiflowui-datatable` (off `origin/main`), spec committed at `61e9fcf`. Do all work here.

---

## Task 1: Column model (`Column.swift`)

**Files:**
- Create: `Sources/SwiflowUI/Column.swift`
- Create: `Tests/SwiflowUITests/ColumnTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiflowUITests/ColumnTests.swift`:

```swift
// Tests/SwiflowUITests/ColumnTests.swift
import Testing
@testable import Swiflow
@testable import SwiflowUI

private struct Person: Identifiable { let id: Int; let name: String; let age: Int }

@MainActor private func textOf(_ nodes: [VNode]) -> String {
    nodes.map { node -> String in
        switch node {
        case .text(let s): return s
        case .element(let d): return d.children.map { textOf([$0]) }.joined()
        default: return ""
        }
    }.joined()
}

@Suite("Column model")
@MainActor
struct ColumnTests {
    private let ada = Person(id: 1, name: "Ada", age: 36)
    private let bob = Person(id: 2, name: "Bob", age: 28)

    @Test("value column derives a text cell from the keypath") func valueCell() {
        let col = Column<Person>("Name", value: \.name)
        #expect(textOf(col.render(ada)) == "Ada")
    }

    @Test("value column derives a comparator (ascending by value)") func valueComparator() {
        let col = Column<Person>("Age", value: \.age)
        #expect(col.comparator != nil)
        #expect(col.comparator!(bob, ada) == .ascending)   // 28 < 36
        #expect(col.comparator!(ada, bob) == .descending)
        #expect(col.comparator!(ada, ada) == .same)
    }

    @Test(".cell overrides rendering but keeps the comparator") func cellOverride() {
        let col = Column<Person>("Age", value: \.age).cell { p in [text("#\(p.age)")] }
        #expect(textOf(col.render(ada)) == "#36")
        #expect(col.comparator != nil)   // still sortable by .age
    }

    @Test("custom-cell column has no comparator (not sortable)") func customNotSortable() {
        let col = Column<Person>("Actions") { _ in [text("edit")] }
        #expect(col.comparator == nil)
    }

    @Test(".sortable(false) drops the comparator") func optOut() {
        let col = Column<Person>("Age", value: \.age).sortable(false)
        #expect(col.comparator == nil)
    }

    @Test("alignment and width modifiers set the fields") func alignWidth() {
        let col = Column<Person>("Age", value: \.age).align(.trailing).width(.px(80))
        #expect(col.alignment == .trailing)
        #expect(col.width == .px(80))
    }

    @Test("default id is the title; explicit id wins") func ids() {
        #expect(Column<Person>("Age", value: \.age).id == "Age")
        #expect(Column<Person>("Age", value: \.age, id: "age-col").id == "age-col")
    }

    @Test("ColumnBuilder collects columns including if/for") func builder() {
        let show = true
        let cols: [Column<Person>] = buildColumns {
            Column("Name", value: \.name)
            if show { Column("Age", value: \.age) }
            for label in ["X", "Y"] { Column(label) { _ in [text(label)] } }
        }
        #expect(cols.map(\.title) == ["Name", "Age", "X", "Y"])
    }

    @Test("ColumnWidth/Alignment css") func css() {
        #expect(ColumnAlignment.leading.cssTextAlign == "start")
        #expect(ColumnAlignment.center.cssTextAlign == "center")
        #expect(ColumnAlignment.trailing.cssTextAlign == "end")
        #expect(ColumnWidth.px(80).css == "80px")
        #expect(ColumnWidth.fr(2).css == "2fr")
        #expect(ColumnWidth.custom("10ch").css == "10ch")
    }
}

// Local helper to exercise @ColumnBuilder (the real one is consumed by DataTable factories).
@MainActor private func buildColumns<Row>(@ColumnBuilder _ make: () -> [Column<Row>]) -> [Column<Row>] { make() }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ColumnTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'Column' in scope` (type not defined yet).

- [ ] **Step 3: Implement `Column.swift`**

Create `Sources/SwiflowUI/Column.swift`:

```swift
// Sources/SwiflowUI/Column.swift
import Swiflow

/// Three-way comparison result for a column's sort comparator. Defined locally so
/// SwiflowUI need not import Foundation (`ComparisonResult`) — the `.same` case is what
/// lets the table keep sorting **stable** (ties fall back to original row order).
public enum SortComparison: Equatable, Sendable { case ascending, same, descending }

/// Per-column text alignment. Logical/RTL-aware: maps to `text-align: start|center|end`
/// (matching the house logical-CSS style — see `Edge` in Tokens.swift).
public enum ColumnAlignment: Equatable, Sendable {
    case leading, center, trailing
    var cssTextAlign: String {
        switch self {
        case .leading:  return "start"
        case .center:   return "center"
        case .trailing: return "end"
        }
    }
}

/// A column width hint, written as an inline `width` on the column's cells.
public enum ColumnWidth: Equatable, Sendable {
    case px(Int), fr(Int), auto, custom(String)
    var css: String {
        switch self {
        case .px(let n):     return "\(n)px"
        case .fr(let n):     return "\(n)fr"
        case .auto:          return "auto"
        case .custom(let v): return v
        }
    }
}

/// The active sort: which column (by its stable `id`) and direction. Non-generic — the
/// table's stateful core is type-erased over `Row`, so a column id + direction is the
/// portable identity. `nil` (in the controlled binding) means unsorted.
public struct SortOrder: Equatable, Sendable {
    public var columnID: String
    public var ascending: Bool
    public init(columnID: String, ascending: Bool) {
        self.columnID = columnID
        self.ascending = ascending
    }
}

/// One column of a `DataTable`, generic over the row type. A plain value type (no macro),
/// so chained configuration is fine. Carries the header title, a stable `id`, how to render
/// a cell (`render`), an optional sort `comparator` (non-nil ⇒ sortable), and alignment/width.
public struct Column<Row> {
    /// Stable identity used by sorting + the controlled `SortOrder`. Defaults to `title`.
    public let id: String
    public let title: String
    public internal(set) var alignment: ColumnAlignment
    public internal(set) var width: ColumnWidth?
    /// Renders the cell contents for a row.
    public internal(set) var render: (Row) -> [VNode]
    /// Three-way comparator; `nil` ⇒ this column is not sortable.
    public internal(set) var comparator: ((Row, Row) -> SortComparison)?

    private init(id: String, title: String, alignment: ColumnAlignment, width: ColumnWidth?,
                 render: @escaping (Row) -> [VNode], comparator: ((Row, Row) -> SortComparison)?) {
        self.id = id; self.title = title; self.alignment = alignment; self.width = width
        self.render = render; self.comparator = comparator
    }

    /// A value column: derives BOTH a default text cell (`String(describing:)`) AND an
    /// ascending comparator from the keypath. Override rendering with `.cell { }` while
    /// keeping the comparator; drop sorting with `.sortable(false)`.
    public init<V: Comparable & CustomStringConvertible>(
        _ title: String, value keyPath: KeyPath<Row, V>, id: String? = nil
    ) {
        self.init(
            id: id ?? title, title: title, alignment: .leading, width: nil,
            render: { [text(String(describing: $0[keyPath: keyPath]))] },
            comparator: { a, b in
                let va = a[keyPath: keyPath], vb = b[keyPath: keyPath]
                if va < vb { return .ascending }
                if vb < va { return .descending }
                return .same
            }
        )
    }

    /// A custom-cell column with NO comparator (not sortable). Trailing-closure form:
    /// `Column("Actions") { row in [Button(...)] }`.
    public init(_ title: String, id: String? = nil, @ChildrenBuilder cell: @escaping (Row) -> [VNode]) {
        self.init(id: id ?? title, title: title, alignment: .leading, width: nil,
                  render: cell, comparator: nil)
    }

    /// Override how the cell renders (keeps the comparator, if any).
    public func cell(@ChildrenBuilder _ make: @escaping (Row) -> [VNode]) -> Column {
        var c = self; c.render = make; return c
    }

    public func align(_ alignment: ColumnAlignment) -> Column {
        var c = self; c.alignment = alignment; return c
    }

    public func width(_ width: ColumnWidth) -> Column {
        var c = self; c.width = width; return c
    }

    /// Force a value column non-sortable (clears the comparator).
    public func sortable(_ enabled: Bool) -> Column {
        var c = self; if !enabled { c.comparator = nil }; return c
    }
}

/// Collects `[Column<Row>]` from a trailing-closure block, supporting `if`/`else`/`for`
/// (mirrors `ChildrenBuilder`). Columns are a config list rebuilt each render, so plain
/// flattening is correct — no stable-slot/fragment semantics needed.
@resultBuilder
public enum ColumnBuilder {
    public static func buildExpression<Row>(_ column: Column<Row>) -> [Column<Row>] { [column] }
    public static func buildExpression<Row>(_ columns: [Column<Row>]) -> [Column<Row>] { columns }
    public static func buildBlock<Row>(_ parts: [Column<Row>]...) -> [Column<Row>] { parts.flatMap { $0 } }
    public static func buildOptional<Row>(_ part: [Column<Row>]?) -> [Column<Row>] { part ?? [] }
    public static func buildEither<Row>(first: [Column<Row>]) -> [Column<Row>] { first }
    public static func buildEither<Row>(second: [Column<Row>]) -> [Column<Row>] { second }
    public static func buildArray<Row>(_ parts: [[Column<Row>]]) -> [Column<Row>] { parts.flatMap { $0 } }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ColumnTests 2>&1 | tail -20`
Expected: PASS (all ColumnTests green).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowUI/Column.swift Tests/SwiflowUITests/ColumnTests.swift
git commit -m "feat(swiflowui): Column<Row> model + @ColumnBuilder for DataTable

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: DataTable factory + box base render (no sort/select/page yet)

Renders a styled `<table>` (scroll container + sticky header CSS, `<thead>` of `<th scope=col>`, `<tbody>` of keyed `<tr>` with `<td>`s), default + custom cells, per-column alignment/width. Sorting/selection/pagination/empty-loading land in later tasks.

**Files:**
- Create: `Sources/SwiflowUI/DataTable.swift`
- Create: `Tests/SwiflowUITests/DataTableTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiflowUITests/DataTableTests.swift`:

```swift
// Tests/SwiflowUITests/DataTableTests.swift
// DataTable is a STATEFUL @Component (DataTableBox) behind a generic factory that erases
// rows/columns into index closures. Host tests render `makeDataTableBox(...).body` inside
// `building { }` (handler-ambient) and inspect the VNode tree. The internal-@State default
// sort/page path is exercised via controlled bindings here and end-to-end in the demo e2e.
import Testing
@testable import Swiflow
@testable import SwiflowUI

struct Person: Identifiable, Equatable { let id: Int; let name: String; let age: Int }

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DataTableBaseTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'makeDataTableBox' in scope`.

- [ ] **Step 3: Implement `DataTable.swift` (factory + erased box base)**

Create `Sources/SwiflowUI/DataTable.swift`:

```swift
// Sources/SwiflowUI/DataTable.swift
import Swiflow

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
    emptyText: String = "No results",
    _ attributes: Attribute...,
    key: String? = nil,
    @ColumnBuilder columns: () -> [Column<Row>]
) -> VNode {
    let cols = columns()
    let caller = attributes
    return embedKeyed(key) {
        makeDataTableBox(rows, id: id, selection: selection, sortable: sortable,
                         sortOrder: sortOrder, pageSize: pageSize, page: page,
                         onRowClick: onRowClick, loading: loading, maxHeight: maxHeight,
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
    emptyText: String = "No results",
    _ attributes: Attribute...,
    key: String? = nil,
    @ColumnBuilder columns: () -> [Column<Row>]
) -> VNode {
    let cols = columns()
    let caller = attributes
    return embedKeyed(key) {
        makeDataTableBox(rows, id: \.id, selection: selection, sortable: sortable,
                         sortOrder: sortOrder, pageSize: pageSize, page: page,
                         onRowClick: onRowClick, loading: loading, maxHeight: maxHeight,
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
    emptyText: String = "No results",
    caller: [Attribute] = [],
    @ColumnBuilder columnsList: () -> [Column<Row>]
) -> DataTableBox {
    makeDataTableBox(rows, id: id, selection: selection, sortable: sortable, sortOrder: sortOrder,
                     pageSize: pageSize, page: page, onRowClick: onRowClick, loading: loading,
                     maxHeight: maxHeight, emptyText: emptyText, caller: caller, columnsList: columnsList())
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
        SelectionModel(
            isSelected: { sel.get().contains(idOf(rows[$0])) },
            toggle: { i in
                var s = sel.get(); let k = idOf(rows[i])
                if s.contains(k) { s.remove(k) } else { s.insert(k) }
                sel.set(s)
            },
            selectedCount: { let ids = Set(rows.map(idOf)); return sel.get().intersection(ids).count },
            total: rows.count,
            setAll: { on in
                let ids = rows.map(idOf)
                sel.set(on ? sel.get().union(ids) : sel.get().subtracting(ids))
            }
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
    let emptyText: String
    let caller: [Attribute]

    @State private var internalSort: SortOrder? = nil
    @State private var internalPage: Int = 0

    init(rowCount: Int, columns: [DataColumn], rowKey: @escaping (Int) -> String,
         selection: SelectionModel?, sortable: Bool, sortOrder: Binding<SortOrder?>?,
         pageSize: Int?, page: Binding<Int>?, onRowClick: ((Int) -> Void)?,
         loading: Bool, maxHeight: String?, emptyText: String, caller: [Attribute]) {
        self.rowCount = rowCount; self.columns = columns; self.rowKey = rowKey
        self.selection = selection; self.sortable = sortable; self.sortOrderBinding = sortOrder
        self.pageSize = pageSize; self.pageBinding = page; self.onRowClick = onRowClick
        self.loading = loading; self.maxHeight = maxHeight; self.emptyText = emptyText
        self.caller = caller
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

    /// THE virtualization seam: which sorted indices are visible this render. v1 = page slice
    /// (or all rows when unpaginated). A future virtualizer replaces only this method.
    func visibleWindow(_ order: [Int], page: Int) -> [Int] {
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

        let table = element("table", attributes: [.class("sw-table")],
                            children: [headerRow(), element("tbody", children: bodyRows(window))])

        var scrollAttrs: [Attribute] = [.class("sw-table__scroll")]
        if let maxHeight { scrollAttrs.append(.style("max-height", maxHeight)) }
        let scroll = element("div", attributes: scrollAttrs, children: [table])

        var rootChildren: [VNode] = [scroll]
        if pageSize != nil, pageCount() > 1 { rootChildren.append(pager(page: page)) }
        return element("div", attributes: [.class("sw-table-wrap")] + caller, children: rootChildren)
    }

    // MARK: header

    private func headerRow() -> VNode {
        var cells: [VNode] = []
        if selection != nil { cells.append(selectAllCell()) }
        cells.append(contentsOf: columns.map(headerCell))
        return element("thead", children: [element("tr", children: cells)])
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
            .on(.change) { _ in self.selection!.setAll(!allOn) },
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
        var attrs: [Attribute] = [.class("sw-table__tr"), .key(rowKey(i))]
        if let sel = selection { attrs.append(.attr("aria-selected", sel.isSelected(i) ? "true" : "false")) }
        if let onRowClick { attrs.append(.on(.click) { onRowClick(i) }) }
        return element("tr", attributes: attrs, children: cells)
    }

    private func rowSelectCell(_ i: Int, _ sel: SelectionModel) -> VNode {
        let input = element("input", attributes: [
            .attr("type", "checkbox"), .attr("aria-label", "Select row"),
            .prop("checked", .bool(sel.isSelected(i))),
            .on(.change) { _ in self.selection!.toggle(i) },
        ])
        return element("td", attributes: [.class("sw-table__td sw-table__select")], children: [input])
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
    """)
}

@MainActor
func installDataTableStyles() { installControlSheet(id: "sw-datatable", dataTableSheet) }
```

> NOTE on the two `makeDataTableBox` overloads: the first (with `@ColumnBuilder columnsList:`) is the ergonomic builder entry the factories call; it delegates to the array-taking overload. Both are needed — the public factories pass an already-evaluated `[Column<Row>]` via `columnsList: cols`, so they call the **array** overload. Tests use the **builder** overload. Verify both resolve (no ambiguity) during the host build; if the compiler flags ambiguity, rename the builder one `makeDataTableBoxBuilding`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DataTableBaseTests 2>&1 | tail -30`
Expected: PASS. If a `cannot find X in scope` error appears for a new file, run `swift package clean` first (SwiftPM new-file cache — known gotcha).

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowUI/DataTable.swift Tests/SwiflowUITests/DataTableTests.swift
git commit -m "feat(swiflowui): DataTable factory + erased DataTableBox base render

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Sorting

Wire tri-state header sorting through a controlled `sortOrder:` binding (deterministic on host) and verify the rendered order, `aria-sort`, stability, and the `cycleSort` transition. (The base render from Task 2 already emits the sortable header button + `aria-sort`; this task proves the behavior and adds the sorting tests.)

**Files:**
- Modify: `Tests/SwiflowUITests/DataTableTests.swift` (add a suite)
- (No `DataTable.swift` change expected — the pipeline shipped in Task 2. If a test fails, fix `sortedIndices`/`headerCell`/`cycleSort`.)

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SwiflowUITests/DataTableTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail (or pass)**

Run: `swift test --filter DataTableSortTests 2>&1 | tail -30`
Expected: PASS if Task 2's pipeline is correct. If any FAIL, fix the corresponding method in `DataTable.swift` (`sortedIndices`, `headerCell`, `cycleSort`) and re-run.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiflowUITests/DataTableTests.swift Sources/SwiflowUI/DataTable.swift
git commit -m "test(swiflowui): DataTable tri-state sorting (order, aria-sort, stability, cycle)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Selection

Verify the checkbox column, per-row toggle, select-all + indeterminate, and `aria-selected`. (The render shipped in Task 2; this task proves behavior via the always-bound `Binding<Set<ID>>`.)

**Files:**
- Modify: `Tests/SwiflowUITests/DataTableTests.swift`
- (Fix `DataTable.swift` selection methods only if a test fails.)

- [ ] **Step 1: Write the failing tests**

Append:

```swift
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
```

- [ ] **Step 2: Run tests**

Run: `swift test --filter DataTableSelectionTests 2>&1 | tail -30`
Expected: PASS. Fix `selectAllCell`/`rowSelectCell`/`SelectionModel` wiring in `DataTable.swift` if any FAIL.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiflowUITests/DataTableTests.swift Sources/SwiflowUI/DataTable.swift
git commit -m "test(swiflowui): DataTable selection (toggle, select-all, indeterminate, aria-selected)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Pagination

Verify slicing, the pager control, page clamping, and `inert` at the ends — via the controlled `page:` binding.

**Files:**
- Modify: `Tests/SwiflowUITests/DataTableTests.swift`
- (Fix `DataTable.swift` pager/window methods only if a test fails.)

- [ ] **Step 1: Write the failing tests**

Append:

```swift
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
```

- [ ] **Step 2: Run tests**

Run: `swift test --filter DataTablePaginationTests 2>&1 | tail -30`
Expected: PASS. Fix `visibleWindow`/`clampedPage`/`pager`/`pageCount` if any FAIL.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiflowUITests/DataTableTests.swift Sources/SwiflowUI/DataTable.swift
git commit -m "test(swiflowui): DataTable pagination (slicing, clamp, inert ends, pager)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Empty & loading states

**Files:**
- Modify: `Tests/SwiflowUITests/DataTableTests.swift`
- (Fix `bodyRows`/`fullWidthRow` only if a test fails.)

- [ ] **Step 1: Write the failing tests**

Append:

```swift
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
```

- [ ] **Step 2: Run tests**

Run: `swift test --filter DataTableStateTests 2>&1 | tail -30`
Expected: PASS. Fix `bodyRows` ordering (loading before empty before data) / `fullWidthRow` colspan if any FAIL.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiflowUITests/DataTableTests.swift Sources/SwiflowUI/DataTable.swift
git commit -m "test(swiflowui): DataTable empty + loading states

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Row interaction (`onRowClick`)

**Files:**
- Modify: `Tests/SwiflowUITests/DataTableTests.swift`
- Modify: `Sources/SwiflowUI/DataTable.swift` (add a `.sw-table__tr--clickable` hover affordance class when `onRowClick` is set)

- [ ] **Step 1: Write the failing test**

Append:

```swift
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
        let reg = HandlerRegistry()
        HandlerAmbient.current = reg
        let node = b.body
        let tr0 = allTags(.element(allTags(node, "tbody").first!), "tr")[0]
        let handlerID = tr0.handlers["click"]!.id
        reg.handler(for: handlerID)!.invoke(EventInfo(type: "click"))
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
```

> NOTE: confirm the `HandlerRegistry` lookup method name. Inspect `Sources/Swiflow/.../HandlerRegistry.swift` (e.g. `grep -n "func handler" Sources/Swiflow/**/*.swift`). If the accessor is named differently (e.g. `lookup(_:)`), use that. If handler invocation proves awkward on host, replace this half of the test with the structural checks (clickable class + `tr.handlers["click"] != nil`) and rely on the e2e (Task 9) for the actual click behavior.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DataTableRowClickTests 2>&1 | tail -20`
Expected: FAIL — rows lack `sw-table__tr--clickable`.

- [ ] **Step 3: Add the clickable class**

In `Sources/SwiflowUI/DataTable.swift`, in `rowVNode`, change the class attribute when clickable:

```swift
        var attrs: [Attribute] = [.key(rowKey(i))]
        let rowClass = onRowClick != nil ? "sw-table__tr sw-table__tr--clickable" : "sw-table__tr"
        attrs.insert(.class(rowClass), at: 0)
        if let sel = selection { attrs.append(.attr("aria-selected", sel.isSelected(i) ? "true" : "false")) }
        if let onRowClick { attrs.append(.on(.click) { onRowClick(i) }) }
```

Add to `dataTableSheet` (inside the `raw("""..."""`), after the `.sw-table__tr[aria-selected...]` rule):

```css
    .sw-table__tr--clickable { cursor: pointer; }
    .sw-table__tr--clickable:hover { background-color: var(--sw-surface-hover, color-mix(in oklab, var(--sw-text) 5%, transparent)); }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DataTableRowClickTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowUI/DataTable.swift Tests/SwiflowUITests/DataTableTests.swift
git commit -m "feat(swiflowui): DataTable onRowClick + clickable-row affordance

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Full suite + demo gallery + docs + roadmap

**Files:**
- Modify: `examples/SwiflowUIDemo/Sources/SwiflowUIDemo/...` (the gallery entry point — find with `grep -rln "Card(\|gallery\|section" examples/SwiflowUIDemo/Sources`)
- Modify: `docs/guides/swiflowui.md`
- Modify: `docs/future-work/swiflowui-1.0-roadmap.md`

- [ ] **Step 1: Run the entire SwiflowUI suite + host build**

```bash
swift build 2>&1 | tail -5
swift test --filter SwiflowUITests 2>&1 | tail -15
```
Expected: build succeeds; all Column/DataTable suites pass alongside the existing tests.

- [ ] **Step 2: Add a DataTable demo to the gallery**

Locate the demo's component sections (`grep -rn "func .*Section\|Card(" examples/SwiflowUIDemo/Sources | head`). Add a section that exercises sorting + selection + pagination, e.g.:

```swift
// In the demo body, alongside the other component sections:
@State var selectedPeople: Set<Int> = []
@State var peoplePage: Int = 0
// ...
DataTable(demoPeople, selection: $selectedPeople, sortable: true,
          pageSize: 5, page: $peoplePage, maxHeight: .custom("360px")) {
    Column("Name", value: \.name)
    Column("Age", value: \.age).align(.trailing)
    Column("Role") { p in [Badge(p.role)] }
    Column("") { p in [Button("Edit", variant: .secondary, size: .sm) { /* demo */ }] }
}
```

where `demoPeople` is a small `[DemoPerson]` (≥12 rows so pagination is visible) and `DemoPerson: Identifiable`. Place it in its own `Card`/section consistent with neighbors.

- [ ] **Step 3: Build the demo locally (CI skips example builds)**

```bash
swift build -c release --product swiflow
swiflow build --path examples/SwiflowUIDemo 2>&1 | tail -15
```
Expected: the demo compiles to wasm with no errors. If "cannot find DataTable in scope", run `swift package clean` inside the example dir (SwiftPM new-file cache gotcha) and rebuild.

- [ ] **Step 4: Document DataTable in the guide**

In `docs/guides/swiflowui.md`, add a `DataTable` section covering: the `Column` model + `.cell`/`.align`/`.width`/`.sortable(false)`; `sortable`/`selection`/`pageSize` and the opt-in `sortOrder`/`page` bindings; the **sticky-header caveat** (the header pins only inside a scrolling `maxHeight` container); the **row-click caveat** (Swiflow handlers can't stop propagation — a click on an in-cell button ALSO fires `onRowClick`, so don't combine `onRowClick` with interactive cells; see `[[no-event-preventdefault]]`); and the **deferred** list (virtualization, density/zebra, column resize, full grid roving, totals row, server-side sort).

- [ ] **Step 5: Update the roadmap**

In `docs/future-work/swiflowui-1.0-roadmap.md`:
- Move `DataTable`/virtualized `List` out of the "Deferred to 1.1+" line into a "Shipped since" note: DataTable shipped (declarative columns, sort/select/sticky/pagination/empty-loading); **virtualization, density/zebra, column resize, full ARIA-grid roving, totals row, server-side sort remain deferred**.
- Fold in the pending **PR #84** note: the richer element-model escape hatch (`.unmanagedChildren()`) shipped, so roadmap #2 is complete — remove it from the deferred line if still listed.

- [ ] **Step 6: Commit**

```bash
git add examples/SwiflowUIDemo docs/guides/swiflowui.md docs/future-work/swiflowui-1.0-roadmap.md
git commit -m "docs(swiflowui): DataTable demo gallery, guide section, roadmap update

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: Playwright e2e (run inline — never in a subagent)

**Files:**
- Create: `examples/SwiflowUIDemo/e2e/datatable.spec.ts` (match the existing demo e2e layout — find with `ls examples/SwiflowUIDemo/e2e 2>/dev/null` or `grep -rln "test(" examples/SwiflowUIDemo`)

- [ ] **Step 1: Write the spec**

Create a Playwright spec that drives the demo DataTable. Adapt selectors/serving to the demo's existing e2e harness (read a sibling `*.spec.ts` first for the base URL / server fixture). Cover:

```ts
import { test, expect } from "@playwright/test";

test.describe("DataTable", () => {
  test("clicking a sortable header reorders rows", async ({ page }) => {
    await page.goto("/");
    const table = page.locator(".sw-table");
    const firstCellBefore = await table.locator("tbody tr td").first().innerText();
    await table.getByRole("button", { name: /Age/ }).click();
    const th = table.locator('th[aria-sort]').filter({ hasText: "Age" });
    await expect(th).toHaveAttribute("aria-sort", "ascending");
    const firstCellAfter = await table.locator("tbody tr td").first().innerText();
    expect(firstCellAfter).not.toBe(firstCellBefore);
  });

  test("select-all checks every visible row", async ({ page }) => {
    await page.goto("/");
    const table = page.locator(".sw-table");
    await table.locator('thead input[type=checkbox]').check();
    const rowBoxes = table.locator('tbody input[type=checkbox]');
    const n = await rowBoxes.count();
    for (let i = 0; i < n; i++) await expect(rowBoxes.nth(i)).toBeChecked();
  });

  test("pager advances to the next page", async ({ page }) => {
    await page.goto("/");
    const table = page.locator(".sw-table");
    const before = await table.locator("tbody tr").first().innerText();
    await page.getByRole("button", { name: "Next" }).click();
    await expect(table.locator("tbody tr").first()).not.toHaveText(before);
  });
});
```

- [ ] **Step 2: Build the release CLI, then run the suite INLINE (detached), after killing leftover servers**

```bash
swift build -c release --product swiflow
# kill anything on :3000 first (per project rule), then run the demo suite inline:
lsof -ti tcp:3000 | xargs kill -9 2>/dev/null; true
cd examples/SwiflowUIDemo && npx playwright test e2e/datatable.spec.ts 2>&1 | tail -30
```
Expected: 3 passing. If the demo e2e uses a dedicated config to dodge the `.e2e-cache/sw` LSP race, use `--config=<that>.config.ts` (read the sibling spec/configs first). Do NOT delegate this run to a background subagent.

- [ ] **Step 3: Commit**

```bash
git add examples/SwiflowUIDemo/e2e/datatable.spec.ts
git commit -m "test(e2e): DataTable sort/select/paginate in the SwiflowUI demo

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final steps (after all tasks)

- [ ] Run the full host suite once more: `swift test 2>&1 | tail -15` — expect green.
- [ ] Confirm the demo wasm build is clean (Task 8 Step 3).
- [ ] Use **superpowers:finishing-a-development-branch** to open the PR (base `main`). HOLD the merge until the user says "merge it -- CI is green"; then `gh pr merge <n> --admin --rebase`.

---

## Notes / deviations from the spec (flag at handoff)

1. **`SortOrder` is non-generic** (`{ columnID, ascending }`), not `SortOrder<Row>` — forced by the type-erased box. Functionally identical for the controlled-sort use case.
2. **`onRowClick` does not de-dupe in-cell control clicks** (the spec's `isSelfTarget` idea doesn't work — Swiflow can't stop propagation, and a cell click targets the `<td>`, not the `<tr>`). Documented as a caveat instead; combine `onRowClick` with action-button columns at your own risk.
3. **Sort/pagination host tests drive the controlled bindings**; the internal-`@State` default path is covered by the demo + e2e (host `@State` writes outside a mounted runtime aren't a reliable test surface — mirrors `AlertTests`).
4. **No Comparable-without-`CustomStringConvertible` value column** in v1 (YAGNI) — such a type needs a custom `.cell` and then can't auto-sort. Note in the guide if it ever bites.
```
