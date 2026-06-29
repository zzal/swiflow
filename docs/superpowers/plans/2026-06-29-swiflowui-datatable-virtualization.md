# DataTable Virtualization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in, fixed-row-height windowed-rendering mode to `DataTable` so it stays interactive over thousands of rows, keeping only the visible window (plus overscan) in the DOM.

**Architecture:** Reuse the existing `sort → window → render` pipeline in `DataTableBox`. Add a `Virtualization` enum and a `columnsTemplate` string to both `DataTable` overloads, thread them into the box. In virtualized mode the box renders a real `<table>` with `display:block`/`grid` overrides: a shared `grid-template-columns` for stable alignment, a sized runway `<tbody>`, and each visible `<tr>` `position:absolute` + `transform: translateY(absIndex × rowHeight)`. A `Ref<JSObject>` on the scroll container + a `scroll` handler read `scrollTop`/`clientHeight` via JS interop and drive `@State`; the window step computes the slice from those metrics. An internal `setViewportMetrics` seam makes the math host-testable without a browser.

**Tech Stack:** Swift 6.3, SwiflowUI (`@Component`, `Ref`, `.on(.custom("scroll"))`, JS interop via `#if canImport(JavaScriptKit)`), Swift Testing, Playwright.

---

## Background the implementer needs

Read these before starting — they explain non-obvious constraints:

- **`Sources/SwiflowUI/DataTable.swift`** — the whole file. Key facts:
  - `DataTableBox` is a **non-generic** `@Component` (the `@Component` macro hardcodes the bare class name in its `StateCell`, so it cannot be generic). Generics live in the `DataTable<Row,ID>` factory and `makeDataTableBox`, which **erase** columns/rows/selection into index-based closures (`DataColumn`, `SelectionModel`).
  - `rows` is **frozen at first mount** (embed-reuse); only `Binding`s stay live. Not your concern for this task (no new row data), but don't add per-render row recomputation.
  - The pipeline in `body`: `let order = sortedIndices(); let page = clampedPage(); let window = visibleWindow(order, page: page)`. `visibleWindow` is **the seam** you extend.
  - Internal methods (`setSort`, `setPage`, `cycleSort`, `visibleWindow`, …) are deliberately non-`private` so tests drive them. Follow that pattern for new seams.
- **`Sources/SwiflowUI/Column.swift`** — `Column<Row>` carries `.width: ColumnWidth?` (ignored in virtualized mode). `ColumnWidth` has **no `.fr`** (dead on table cells) — but `fr` is valid inside `grid-template-columns`, which is exactly why `columnsTemplate` is a raw string.
- **`Sources/SwiflowUI/Autocomplete.swift:389-391` and `:355-358`** — the canonical `Ref<JSObject>` pattern: declare `private let xRef = Ref<JSObject>()` under `#if canImport(JavaScriptKit)`, attach with `.refBinding(AnyRefBinding(xRef))` (also `#if`-gated), and read DOM with `xRef.wrappedValue?.someProp`.
- **`Sources/Swiflow/DSL/Event.swift`** — there is **no** `.scroll` case; use `.on(.custom("scroll"))`.
- **Memory `wasm32-int-32bit`** — `Int(_:)` traps on values beyond ±2³¹ on wasm. Pixel/row math here is small, but use `Int(floor(x))` only on bounded values; never feed it an un-clamped product.
- **Memory `onchange-fires-every-render`** — `onChange()` runs on every app render. Do **not** put scroll metric reads in `onChange()`; use `onAppear()` for the initial measure and the scroll handler for updates.
- **Memory `js-driver-change-sync` (EmbeddedTemplates regen-ordering trap)** — when the demo changes, regen `EmbeddedTemplates.swift` **last, from a clean tree** (after `git checkout` of any build-minified driver/SW), or CI's bit-for-bit `TemplateEmbedderTests` fails despite passing locally.
- **Memory `run-e2e-locally-before-push`** — before Playwright, `swift build -c release --product swiflow` (the harness reuses a stale CLI). Run e2e **inline, never in a subagent** (port collisions).

**Test helpers already in `Tests/SwiflowUITests/DataTableTests.swift`:** file-scope `el`, `allText`, `allTags`, `building { }` (sets `HandlerAmbient.current`), and `private struct Person: Identifiable, Equatable`. Reuse them; do not redeclare `Person`.

**How to run one unit test:** `swift test --filter SwiflowUITests.DataTableTests/<testName>` (Swift Testing `@Test func testName`).

---

## File Structure

- **Modify `Sources/SwiflowUI/DataTable.swift`** — all production changes live here (enum, params, box state, render branch, CSS, test seam). The file grows ~120 lines; that's acceptable (it's the table's single home). Do not split.
- **Modify `Tests/SwiflowUITests/DataTableTests.swift`** — append a virtualization `@Suite` / tests.
- **Modify `Tests/playwright/datatable.spec.ts`** — append one virtualization e2e.
- **Modify `examples/SwiflowUIDemo/Sources/App/App.swift`** — add a virtualized demo section.
- **Modify `Sources/SwiflowCLI/EmbeddedTemplates.swift`** — regenerated artifact (not hand-edited).
- **Modify `docs/guides/swiflowui.md`** and **`docs/future-work/swiflowui-1.0-roadmap.md`** — docs.

---

## Task 1: `Virtualization` enum + thread `virtualized`/`columnsTemplate` through the API (no behavior yet)

**Files:**
- Modify: `Sources/SwiflowUI/DataTable.swift`
- Test: `Tests/SwiflowUITests/DataTableTests.swift`

Goal: add the API surface and store it on the box, with **no rendering change yet** (virtualized path falls through to the existing window). This keeps the diff reviewable and proves wiring before logic.

- [ ] **Step 1: Write the failing test** (append to `DataTableTests.swift`)

```swift
@MainActor
@Suite struct DataTableVirtualizationTests {
    @Test func boxStoresVirtualizationConfig() {
        let people = (0..<5).map { Person(id: $0, name: "P\($0)", age: 20 + $0, email: "p\($0)@x.io") }
        let box = makeDataTableBox(people, id: \.id, maxHeight: "300px",
                                   virtualization: .fixed(rowHeight: 40),
                                   columnsTemplate: "1fr 80px 1fr") {
            Column("Name", value: \.name)
            Column("Age", value: \.age)
            Column("Email", value: \.email)
        }
        #expect(box.virtualization == .fixed(rowHeight: 40))
        #expect(box.columnsTemplate == "1fr 80px 1fr")
    }
}
```

- [ ] **Step 2: Run it, verify it fails to compile**

Run: `swift test --filter SwiflowUITests.DataTableVirtualizationTests/boxStoresVirtualizationConfig`
Expected: FAIL — `makeDataTableBox` has no `virtualization:`/`columnsTemplate:` params; `box.virtualization` unknown.

- [ ] **Step 3: Add the enum** (top of `DataTable.swift`, after the imports / before `DataColumn`)

```swift
/// How a `DataTable` renders large datasets. `.fixed` keeps only the visible window of rows
/// in the DOM, sized by a constant row height. (`measured` variable-height is reserved for 1.x.)
public enum Virtualization: Equatable, Sendable {
    case fixed(rowHeight: Int)
    // case measured(estimated: Int)   // 1.x — not implemented
}
```

- [ ] **Step 4: Add params to both public overloads, `makeDataTableBox` (both arities), and the box**

In the `id:`-keypath `DataTable` overload, add after `maxHeight`:
```swift
        maxHeight: Spacing? = nil,
        virtualization: Virtualization? = nil,
        columnsTemplate: String? = nil,
        emptyText: String = "No results",
```
and pass them through to `makeDataTableBox(... maxHeight: maxHeight, virtualization: virtualization, columnsTemplate: columnsTemplate, emptyText: ...)`. Repeat the same two added params + pass-through in the `Row: Identifiable` overload, in the `@ColumnBuilder` `makeDataTableBox` wrapper (forward to the array form), and in the array-form `makeDataTableBox`.

In the array-form `makeDataTableBox`, pass to the `DataTableBox(...)` initializer:
```swift
        maxHeight: maxHeight?.css,
        virtualization: virtualization,
        columnsTemplate: columnsTemplate,
        emptyText: emptyText,
```

On `DataTableBox` add stored props (after `maxHeight`):
```swift
    let virtualization: Virtualization?
    let columnsTemplate: String?
```
add them to the `init` signature and body (after `maxHeight`):
```swift
         maxHeight: String?, virtualization: Virtualization?, columnsTemplate: String?,
         emptyText: String, caller: [Attribute]) {
        ...
        self.maxHeight = maxHeight
        self.virtualization = virtualization
        self.columnsTemplate = columnsTemplate
        self.emptyText = emptyText
```

> Note: the two `makeDataTableBox` signatures and the call site at the end of the `@ColumnBuilder` wrapper must all gain the params, or Swift won't compile. Search the file for `maxHeight:` to find every call site.

- [ ] **Step 5: Run the test, verify it passes**

Run: `swift test --filter SwiflowUITests.DataTableVirtualizationTests/boxStoresVirtualizationConfig`
Expected: PASS

- [ ] **Step 6: Run the full SwiflowUI suite to confirm no regressions**

Run: `swift test --filter SwiflowUITests`
Expected: PASS (existing DataTable tests unaffected — new params default to nil).

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiflowUI/DataTable.swift Tests/SwiflowUITests/DataTableTests.swift
git commit -m "feat(swiflowui): add Virtualization enum + columnsTemplate to DataTable API

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Effective-mode resolution + diagnostics (virtualization vs pagination vs maxHeight)

**Files:**
- Modify: `Sources/SwiflowUI/DataTable.swift`
- Test: `Tests/SwiflowUITests/DataTableTests.swift`

Goal: a single source of truth for "is virtualization active this render?" that enforces the spec's rules: it requires a positive `rowHeight` **and** a `maxHeight`, and it suppresses pagination.

- [ ] **Step 1: Write the failing tests**

```swift
    @Test func virtualizationInactiveWithoutMaxHeight() {
        let people = (0..<5).map { Person(id: $0, name: "P\($0)", age: $0, email: "") }
        let box = makeDataTableBox(people, id: \.id, virtualization: .fixed(rowHeight: 40),
                                   columnsTemplate: "1fr") { Column("Name", value: \.name) }
        #expect(box.activeRowHeight() == nil)   // no maxHeight ⇒ not active
    }

    @Test func virtualizationInactiveWithNonPositiveRowHeight() {
        let people = (0..<5).map { Person(id: $0, name: "P\($0)", age: $0, email: "") }
        let box = makeDataTableBox(people, id: \.id, maxHeight: "300px",
                                   virtualization: .fixed(rowHeight: 0),
                                   columnsTemplate: "1fr") { Column("Name", value: \.name) }
        #expect(box.activeRowHeight() == nil)
    }

    @Test func virtualizationActiveWithHeightAndRowHeight() {
        let people = (0..<5).map { Person(id: $0, name: "P\($0)", age: $0, email: "") }
        let box = makeDataTableBox(people, id: \.id, maxHeight: "300px",
                                   virtualization: .fixed(rowHeight: 44),
                                   columnsTemplate: "1fr") { Column("Name", value: \.name) }
        #expect(box.activeRowHeight() == 44)
    }

    @Test func virtualizationSuppressesPager() {
        let people = (0..<50).map { Person(id: $0, name: "P\($0)", age: $0, email: "") }
        let box = makeDataTableBox(people, id: \.id, pageSize: 10, maxHeight: "300px",
                                   virtualization: .fixed(rowHeight: 44),
                                   columnsTemplate: "1fr") { Column("Name", value: \.name) }
        #expect(box.activeRowHeight() == 44)
        #expect(box.paginationActive() == false)   // virtualization wins
    }

    @Test func paginationActiveWhenNotVirtualized() {
        let people = (0..<50).map { Person(id: $0, name: "P\($0)", age: $0, email: "") }
        let box = makeDataTableBox(people, id: \.id, pageSize: 10) { Column("Name", value: \.name) }
        #expect(box.activeRowHeight() == nil)
        #expect(box.paginationActive() == true)
    }
```

- [ ] **Step 2: Run them, verify they fail**

Run: `swift test --filter SwiflowUITests.DataTableVirtualizationTests`
Expected: FAIL — `activeRowHeight()`/`paginationActive()` undefined.

- [ ] **Step 3: Implement the resolvers** (in `DataTableBox`, near `pageCount()`)

```swift
    /// Resolved row height when virtualization is *active* this render, else nil.
    /// Active requires a positive rowHeight AND a bounded scroll container (`maxHeight`).
    /// Emits a one-time-ish DEBUG diagnostic when the config asked for virtualization but a
    /// precondition is missing, then falls back to a non-virtualized render.
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
```

> `swiflowDiagnostic` is already in scope (used by the pager/diff). It is a no-op-style debug trap on host/DEBUG; do not guard it further.

- [ ] **Step 4: Update the pager gate in `body`** so it uses `paginationActive()`:

Change `if pageSize != nil, pageCount() > 1 {` to `if paginationActive(), pageCount() > 1 {`.

- [ ] **Step 5: Run the tests, verify they pass**

Run: `swift test --filter SwiflowUITests.DataTableVirtualizationTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowUI/DataTable.swift Tests/SwiflowUITests/DataTableTests.swift
git commit -m "feat(swiflowui): resolve virtualization mode + diagnostics, suppress pager

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Window math + viewport metrics seam (pure, host-testable)

**Files:**
- Modify: `Sources/SwiflowUI/DataTable.swift`
- Test: `Tests/SwiflowUITests/DataTableTests.swift`

Goal: the scroll-driven window. Add scroll `@State`, a `setViewportMetrics` test seam, and make `visibleWindow` mode-aware. Overscan is the internal constant `3`.

- [ ] **Step 1: Write the failing tests**

```swift
    @Test func windowSlicesToViewportPlusOverscan() {
        let people = (0..<1000).map { Person(id: $0, name: "P\($0)", age: $0, email: "") }
        let box = makeDataTableBox(people, id: \.id, maxHeight: "400px",
                                   virtualization: .fixed(rowHeight: 40),
                                   columnsTemplate: "1fr") { Column("Name", value: \.name) }
        // 400px viewport / 40px row = 10 rows in view; overscan 3 each side.
        box.setViewportMetrics(scrollTop: 0, viewportHeight: 400)
        let order = box.sortedIndices()
        let win = box.visibleWindow(order, page: 0)
        // first = floor(0/40)=0; top clamps overscan → start 0; count = 10 + 2*3 = 16
        #expect(win.first == 0)
        #expect(win.count == 16)
    }

    @Test func windowOffsetsWhenScrolled() {
        let people = (0..<1000).map { Person(id: $0, name: "P\($0)", age: $0, email: "") }
        let box = makeDataTableBox(people, id: \.id, maxHeight: "400px",
                                   virtualization: .fixed(rowHeight: 40),
                                   columnsTemplate: "1fr") { Column("Name", value: \.name) }
        box.setViewportMetrics(scrollTop: 4000, viewportHeight: 400)   // first visible = 100
        let win = box.visibleWindow(box.sortedIndices(), page: 0)
        #expect(win.first == 100 - 3)   // 97, overscan applied
        #expect(win.count == 16)
        #expect(box.firstVisibleIndex() == 97)
    }

    @Test func windowClampsAtBottom() {
        let people = (0..<1000).map { Person(id: $0, name: "P\($0)", age: $0, email: "") }
        let box = makeDataTableBox(people, id: \.id, maxHeight: "400px",
                                   virtualization: .fixed(rowHeight: 40),
                                   columnsTemplate: "1fr") { Column("Name", value: \.name) }
        box.setViewportMetrics(scrollTop: 39_600, viewportHeight: 400)  // bottom: 1000*40 - 400
        let win = box.visibleWindow(box.sortedIndices(), page: 0)
        #expect(win.last == 999)        // never past the end
        #expect(win.allSatisfy { $0 < 1000 })
    }

    @Test func nonVirtualizedWindowUnchanged() {
        let people = (0..<30).map { Person(id: $0, name: "P\($0)", age: $0, email: "") }
        let box = makeDataTableBox(people, id: \.id, pageSize: 10) { Column("Name", value: \.name) }
        #expect(box.visibleWindow(box.sortedIndices(), page: 1).count == 10)  // page slice intact
        let all = makeDataTableBox(people, id: \.id) { Column("Name", value: \.name) }
        #expect(all.visibleWindow(all.sortedIndices(), page: 0).count == 30)  // all rows intact
    }

    @Test func runwayHeightIsTotalTimesRowHeight() {
        let people = (0..<250).map { Person(id: $0, name: "P\($0)", age: $0, email: "") }
        let box = makeDataTableBox(people, id: \.id, maxHeight: "400px",
                                   virtualization: .fixed(rowHeight: 32),
                                   columnsTemplate: "1fr") { Column("Name", value: \.name) }
        #expect(box.runwayHeightPx() == 250 * 32)
    }
```

- [ ] **Step 2: Run them, verify they fail**

Run: `swift test --filter SwiflowUITests.DataTableVirtualizationTests`
Expected: FAIL — `setViewportMetrics`, `firstVisibleIndex`, `runwayHeightPx` undefined; `visibleWindow` ignores metrics.

- [ ] **Step 3: Add scroll state + overscan constant** (with the other `@State` in `DataTableBox`)

```swift
    @State private var scrollTop: Double = 0
    @State private var viewportHeight: Double = 0
    private let overscan = 3
```

- [ ] **Step 4: Add the test seam + derived math** (near `clampedPage()`)

```swift
    /// Test/host seam: drive scroll metrics directly (the scroll handler does this from the DOM).
    func setViewportMetrics(scrollTop: Double, viewportHeight: Double) {
        if self.scrollTop != scrollTop { self.scrollTop = scrollTop }
        if self.viewportHeight != viewportHeight { self.viewportHeight = viewportHeight }
    }

    /// Index of the first row at the top edge of the viewport (no overscan), clamped to [0, count).
    func firstVisibleIndex() -> Int {
        guard let rh = activeRowHeight(), rh > 0 else { return 0 }
        let raw = Int(floor(scrollTop / Double(rh)))
        return max(0, min(raw, max(0, rowCount - 1)))
    }

    /// Runway height for the sized `<tbody>`: total rows × rowHeight. 0 when not virtualized.
    func runwayHeightPx() -> Int { (activeRowHeight()).map { rowCount * $0 } ?? 0 }
```

- [ ] **Step 5: Make `visibleWindow` mode-aware** (replace the body of the existing method)

```swift
    /// THE virtualization seam: which sorted indices are visible this render.
    /// virtualized ⇒ scroll-driven window (+overscan); paginated ⇒ page slice; else all.
    func visibleWindow(_ order: [Int], page: Int) -> [Int] {
        if let rh = activeRowHeight(), rh > 0 {
            let total = order.count
            guard total > 0 else { return [] }
            let rowsInView = viewportHeight > 0 ? Int(ceil(viewportHeight / Double(rh))) : total
            let first = max(0, firstVisibleIndex() - overscan)
            let end = min(total, first + rowsInView + 2 * overscan)
            return first < end ? Array(order[first..<end]) : []
        }
        guard let size = pageSize, size > 0 else { return order }
        let start = page * size
        guard start < order.count else { return [] }
        return Array(order[start..<min(start + size, order.count)])
    }
```

> `import` note: `floor`/`ceil` — SwiflowUI avoids Foundation. If `floor`/`ceil` aren't resolvable, replace with integer math: `let first = Int(scrollTop) / rh` (scrollTop ≥ 0) and `let rowsInView = (Int(viewportHeight) + rh - 1) / rh`. Prefer the integer form to avoid a Foundation import; adjust the code in Step 4/5 accordingly and keep the tests as written (results are identical for the test inputs).

- [ ] **Step 6: Run the tests, verify they pass**

Run: `swift test --filter SwiflowUITests.DataTableVirtualizationTests`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiflowUI/DataTable.swift Tests/SwiflowUITests/DataTableTests.swift
git commit -m "feat(swiflowui): scroll-driven window math + viewport metrics test seam

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Grid-template + render branch (block/grid + translateY DOM) and ARIA

**Files:**
- Modify: `Sources/SwiflowUI/DataTable.swift`
- Test: `Tests/SwiflowUITests/DataTableTests.swift`

Goal: the virtualized DOM — shared `--sw-table-cols`, runway `<tbody>`, absolutely-positioned translated rows, `aria-rowcount`/`aria-rowindex`. Non-virtualized markup stays byte-for-byte the same.

- [ ] **Step 1: Write the failing tests**

```swift
    @Test func gridTemplateIncludesSelectionTrack() {
        let people = (0..<3).map { Person(id: $0, name: "P\($0)", age: $0, email: "") }
        var sel: Set<Int> = []
        let box = makeDataTableBox(people, id: \.id,
                                   selection: Binding(get: { sel }, set: { sel = $0 }),
                                   maxHeight: "300px", virtualization: .fixed(rowHeight: 40),
                                   columnsTemplate: "1fr 80px") {
            Column("Name", value: \.name); Column("Age", value: \.age)
        }
        #expect(box.gridTemplate() == "min-content 1fr 80px")   // selection track prepended
    }

    @Test func gridTemplateDefaultsToRepeatWhenNoTemplate() {
        let people = (0..<3).map { Person(id: $0, name: "P\($0)", age: $0, email: "") }
        let box = makeDataTableBox(people, id: \.id, maxHeight: "300px",
                                   virtualization: .fixed(rowHeight: 40)) {
            Column("Name", value: \.name); Column("Age", value: \.age); Column("Email", value: \.email)
        }
        #expect(box.gridTemplate() == "repeat(3, minmax(0, 1fr))")
    }

    @Test func virtualBodyHasRunwayAndTranslatedRows() {
        let people = (0..<1000).map { Person(id: $0, name: "P\($0)", age: $0, email: "") }
        let box = makeDataTableBox(people, id: \.id, maxHeight: "400px",
                                   virtualization: .fixed(rowHeight: 40),
                                   columnsTemplate: "1fr") { Column("Name", value: \.name) }
        box.setViewportMetrics(scrollTop: 4000, viewportHeight: 400)
        let html = building { box.body }.debugHTML   // see helper note below
        #expect(html.contains("sw-table--virtual"))
        #expect(html.contains("height: 40000px"))                 // runway = 1000*40
        #expect(html.contains("translateY(3880px)"))              // first rendered row = 97 → 97*40
        #expect(html.contains("aria-rowcount=\"1000\""))
        #expect(html.contains("aria-rowindex=\"98\""))            // row 97, 1-based
    }

    @Test func nonVirtualizedHasNoVirtualClass() {
        let people = (0..<3).map { Person(id: $0, name: "P\($0)", age: $0, email: "") }
        let box = makeDataTableBox(people, id: \.id) { Column("Name", value: \.name) }
        let html = building { box.body }.debugHTML
        #expect(!html.contains("sw-table--virtual"))
    }
```

> **Helper note:** if `DataTableTests.swift` has no `debugHTML`/serialization helper, assert structurally instead — walk the `VNode` returned by `building { box.body }` and check the `<table>` class attr, the `<tbody>` `style` attr containing `height: 40000px`, a `<tr>` `style` containing `translateY(3880px)`, and the `aria-*` attrs — using the existing `el`/`allTags` helpers. Pick whichever style the file already uses; do **not** introduce a new serialization dependency.

- [ ] **Step 2: Run them, verify they fail**

Run: `swift test --filter SwiflowUITests.DataTableVirtualizationTests`
Expected: FAIL — `gridTemplate()` undefined; no virtual markup.

- [ ] **Step 3: Add `gridTemplate()`** (in `DataTableBox`, near the render helpers)

```swift
    /// Shared `grid-template-columns` for virtualized mode: an auto `min-content` selection
    /// track (when selection is on) + the caller's template, or an equal-fraction default.
    func gridTemplate() -> String {
        let dataCols = columnsTemplate ?? "repeat(\(columns.count), minmax(0, 1fr))"
        return selection != nil ? "min-content \(dataCols)" : dataCols
    }
```

- [ ] **Step 4: Branch the render in `body`** so virtualized mode builds the windowed table

Replace the table/scroll construction in `body` with a branch. Keep the existing non-virtualized path exactly as-is; add the virtual path:

```swift
        let order = sortedIndices()
        let page = clampedPage()
        let window = visibleWindow(order, page: page)

        let scroll: VNode
        if let rh = activeRowHeight() {
            scroll = virtualScroll(order: order, window: window, rowHeight: rh)
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
```

- [ ] **Step 5: Add the virtual render helpers** (in `DataTableBox`)

```swift
    private func virtualScroll(order: [Int], window: [Int], rowHeight: Int) -> VNode {
        // Map each windowed row to its ABSOLUTE position in `order` for translateY + aria-rowindex.
        let first = max(0, firstVisibleIndex() - overscan)
        let tableAttrs: [Attribute] = [
            .class("sw-table sw-table--virtual"),
            .style("--sw-table-cols", gridTemplate()),
            .attr("aria-rowcount", String(rowCount)),
        ]
        let tbody = element("tbody",
                            attributes: [.style("height", "\(runwayHeightPx())px")],
                            children: virtualBodyRows(window, first: first, rowHeight: rowHeight))
        let table = element("table", attributes: tableAttrs, children: [headerRow(), tbody])
        var scrollAttrs: [Attribute] = [.class("sw-table__scroll")]
        if let maxHeight { scrollAttrs.append(.style("max-height", maxHeight)) }
        scrollAttrs.append(.on(.custom("scroll")) { self.onScroll() })
        #if canImport(JavaScriptKit)
        scrollAttrs.append(.refBinding(AnyRefBinding(scrollRef)))
        #endif
        return element("div", attributes: scrollAttrs, children: [table])
    }

    private func virtualBodyRows(_ window: [Int], first: Int, rowHeight: Int) -> [VNode] {
        let colspan = columns.count + (selection != nil ? 1 : 0)
        if loading { return [fullWidthRow(colspan, "sw-table__loading", [Spinner(label: "Loading")])] }
        if rowCount == 0 { return [fullWidthRow(colspan, "sw-table__empty", [text(emptyText)])] }
        return window.enumerated().map { offset, rowIndex in
            let absolute = first + offset                     // position in sorted order
            return virtualRowVNode(rowIndex, absolute: absolute, rowHeight: rowHeight)
        }
    }

    private func virtualRowVNode(_ i: Int, absolute: Int, rowHeight: Int) -> VNode {
        var cells: [VNode] = []
        if let sel = selection { cells.append(rowSelectCell(i, sel)) }
        cells.append(contentsOf: columns.map { col in
            element("td", attributes: [.class("sw-table__td")] + alignWidth(col), children: col.render(i))
        })
        let rowClass = onRowClick != nil ? "sw-table__tr sw-table__tr--clickable" : "sw-table__tr"
        var attrs: [Attribute] = [
            .class(rowClass), .key(rowKey(i)),
            .style("transform", "translateY(\(absolute * rowHeight)px)"),
            .style("height", "\(rowHeight)px"),
            .attr("aria-rowindex", String(absolute + 1)),
        ]
        if let sel = selection { attrs.append(.attr("aria-selected", sel.isSelected(i) ? "true" : "false")) }
        if let onRowClick { attrs.append(.on(.click) { onRowClick(i) }) }
        return element("tr", attributes: attrs, children: cells)
    }
```

> `headerRow()` is reused unchanged — its `<tr>` becomes a grid row via the `.sw-table--virtual thead .sw-table__tr` CSS (Task 5). The header `<tr>` already has no `sw-table__tr` class today; **add** `.class("sw-table__tr sw-table__tr--head")` to the `element("tr", ...)` inside `headerRow()` so the grid CSS targets it. This class addition is inert for non-virtualized mode (no rule matches without `.sw-table--virtual`).

- [ ] **Step 6: Add the scroll handler + ref** (in `DataTableBox`)

```swift
    #if canImport(JavaScriptKit)
    private let scrollRef = Ref<JSObject>()
    #endif

    /// Reads scrollTop/clientHeight from the live scroll container and updates metrics only
    /// when the derived window actually shifts (avoids a render per scrolled pixel).
    private func onScroll() {
        #if canImport(JavaScriptKit)
        guard let node = scrollRef.wrappedValue else { return }
        let top = node.scrollTop.number ?? 0
        let height = node.clientHeight.number ?? 0
        let prevFirst = firstVisibleIndex()
        setViewportMetrics(scrollTop: top, viewportHeight: height)
        // setViewportMetrics already no-ops equal values; re-read guards row-internal scroll.
        _ = prevFirst
        #endif
    }

    func onAppear() {
        #if canImport(JavaScriptKit)
        guard activeRowHeight() != nil, let node = scrollRef.wrappedValue else { return }
        setViewportMetrics(scrollTop: node.scrollTop.number ?? 0,
                           viewportHeight: node.clientHeight.number ?? 0)
        #endif
    }
```

Add the JS import at the top of the file (guarded), matching `Autocomplete.swift`:
```swift
#if canImport(JavaScriptKit)
import JavaScriptKit
#endif
```

- [ ] **Step 7: Run the tests, verify they pass**

Run: `swift test --filter SwiflowUITests.DataTableVirtualizationTests`
Expected: PASS

- [ ] **Step 8: Run the whole SwiflowUI suite (regression)**

Run: `swift test --filter SwiflowUITests`
Expected: PASS — non-virtualized DataTable tests still green (header now has a class, but no test asserts its absence; if one does, update it to expect `sw-table__tr sw-table__tr--head`).

- [ ] **Step 9: Commit**

```bash
git add Sources/SwiflowUI/DataTable.swift Tests/SwiflowUITests/DataTableTests.swift
git commit -m "feat(swiflowui): virtualized DataTable render — grid template, runway, translated rows, ARIA

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Virtualized CSS

**Files:**
- Modify: `Sources/SwiflowUI/DataTable.swift` (the `dataTableSheet` raw CSS)
- Test: `Tests/SwiflowUITests/DataTableTests.swift`

Goal: the `.sw-table--virtual` style rules. Append to the existing `dataTableSheet` raw string — do not touch existing rules.

- [ ] **Step 1: Write the failing test** (cheap guard that the sheet carries the rules)

```swift
    @Test func sheetContainsVirtualRules() {
        let css = dataTableSheet.serialized   // use whatever accessor CSSSheet exposes; see note
        #expect(css.contains(".sw-table--virtual"))
        #expect(css.contains("grid-template-columns: var(--sw-table-cols)"))
    }
```

> **Note:** check how `CSSSheet` exposes its text (other SwiflowUI tests that inspect sheets show the accessor — e.g. `.css`, `.text`, or `.serialized`). If no accessor exists, **skip this test** and instead rely on the e2e/demo to validate CSS; do not add a serialization API just for this. Keep Steps 2-4.

- [ ] **Step 2: Run it (or skip per note)**

Run: `swift test --filter SwiflowUITests.DataTableVirtualizationTests/sheetContainsVirtualRules`
Expected: FAIL (rules absent) — or skipped per note.

- [ ] **Step 3: Append the rules** to the `dataTableSheet` `raw(""" … """)` block, before the closing `"""`:

```css
.sw-table--virtual { display: block; }
.sw-table--virtual thead,
.sw-table--virtual tbody { display: block; }
.sw-table--virtual tbody { position: relative; }
.sw-table--virtual .sw-table__tr {
  display: grid;
  grid-template-columns: var(--sw-table-cols);
  align-items: center;
}
.sw-table--virtual thead .sw-table__tr { position: sticky; top: 0; z-index: 1; }
.sw-table--virtual tbody .sw-table__tr {
  position: absolute; inset-inline: 0; top: 0;
  border-block-end: 1px solid var(--sw-border);
}
.sw-table--virtual .sw-table__th { position: static; }   /* sticky moves to the row in virtual mode */
```

- [ ] **Step 4: Run the test (if kept), verify it passes; then the full suite**

Run: `swift test --filter SwiflowUITests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowUI/DataTable.swift Tests/SwiflowUITests/DataTableTests.swift
git commit -m "feat(swiflowui): virtualized DataTable CSS (block/grid + sticky header row)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Demo section

**Files:**
- Modify: `examples/SwiflowUIDemo/Sources/App/App.swift`
- Modify: `Sources/SwiflowCLI/EmbeddedTemplates.swift` (regenerated)

Goal: a visible virtualized table in the demo. Keep the type-checker happy — extract a computed property (the demo `body` is at its budget; adding inline tripped "unable to type-check in reasonable time" before).

- [ ] **Step 1: Add demo state + section** (follow the existing `dataTableSection` extraction pattern)

Add near the other `@State`:
```swift
    @State var bigPeople: [Person] = (0..<2000).map {
        Person(id: $0, name: "Person \($0)", age: 18 + ($0 % 60), email: "user\($0)@example.com")
    }
```
Add a computed section (sibling of `dataTableSection`):
```swift
    var virtualTableSection: VNode {
        VStack(spacing: .none, align: .stretch) {   // single-child wrapper: keyed-sibling rule
            DataTable(bigPeople, sortable: true,
                      virtualized: .fixed(rowHeight: 44),
                      columnsTemplate: "2fr 80px 3fr",
                      maxHeight: .custom("440px"),
                      key: "big-\(bigPeople.count)") {
                Column("Name", value: \.name)
                Column("Age", value: \.age).align(.trailing)
                Column("Email", value: \.email)
            }
        }
    }
```
Insert `virtualTableSection` into the demo `body` after the existing DataTable section (with an `h2`/heading sibling at the section level, like the others — the heading is a sibling of the *wrapper*, and the keyed table is the wrapper's only child, satisfying the keyed-sibling rule).

> Reuse the demo's existing `Person` type if it has one; if the demo's `Person` lacks `email`, either add the field or map to the fields it has. Don't introduce a second `Person`.

- [ ] **Step 2: Build the demo locally** (CI skips example builds)

Run: `swift build -c release --product swiflow && .build/release/swiflow build --path examples/SwiflowUIDemo`
Expected: builds clean; no "unable to type-check" error. If type-check times out, the section is already extracted — split the columns block or the dataset map into a helper.

- [ ] **Step 3: Regen EmbeddedTemplates LAST, from a clean tree** (the regen-ordering trap)

```bash
# revert any build-minified driver/SW the demo build rewrote in place
git checkout -- examples/SwiflowUIDemo/swiflow-driver.js examples/SwiflowUIDemo/swiflow-service-worker.js 2>/dev/null || true
swift scripts/embed-templates.swift
git status --short   # expect only EmbeddedTemplates.swift (+ App.swift) changed
```

- [ ] **Step 4: Verify embed freshness**

Run: `swift test --filter TemplateEmbedderTests`
Expected: PASS (bit-for-bit).

- [ ] **Step 5: Commit**

```bash
git add examples/SwiflowUIDemo/Sources/App/App.swift Sources/SwiflowCLI/EmbeddedTemplates.swift
git commit -m "feat(demo): virtualized DataTable section (2k rows)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Playwright e2e

**Files:**
- Modify: `Tests/playwright/datatable.spec.ts`

Goal: prove the windowing in a real browser. **Run inline, never via a subagent.** Rebuild the release CLI first (the harness reuses a stale binary).

- [ ] **Step 1: Add the e2e** (append to `datatable.spec.ts`, mirroring the existing tests' setup)

```typescript
test('virtualized table renders only a window of rows and updates on scroll', async ({ page }) => {
  // selector assumptions: match the existing datatable.spec.ts selectors for the demo route.
  const scroll = page.locator('.sw-table--virtual').locator('..'); // .sw-table__scroll
  const rows = page.locator('.sw-table--virtual tbody tr');

  // Far fewer than the 2000-row dataset are in the DOM (viewport + overscan).
  const initialCount = await rows.count();
  expect(initialCount).toBeGreaterThan(0);
  expect(initialCount).toBeLessThan(60);

  // The first row is near the top of the dataset.
  await expect(rows.first()).toContainText('Person 0');

  // Scroll down; a later row appears and the top row changes.
  await scroll.evaluate((el) => { (el as HTMLElement).scrollTop = 4000; });
  await page.waitForTimeout(100); // rAF + render
  await expect(rows.first()).not.toContainText('Person 0');
  expect(await rows.count()).toBeLessThan(60);

  // Sort still works after scrolling back up.
  await scroll.evaluate((el) => { (el as HTMLElement).scrollTop = 0; });
  await page.getByRole('button', { name: /Name/ }).first().click();
  await expect(rows.first()).toBeVisible();
});
```

> Adjust selectors/route to match how `datatable.spec.ts` already targets the demo (it serves the demo via `swiflow dev` on :3004 per `playwright.swiflowui.config.ts`). If the virtualized table isn't the only `.sw-table--virtual`, scope by a section heading first.

- [ ] **Step 2: Build the release CLI** (mandatory — stale-binary trap)

Run: `swift build -c release --product swiflow`
Expected: builds.

- [ ] **Step 3: Kill leftovers, run the suite inline**

```bash
pkill -f "swiflow dev" 2>/dev/null; pkill -f "port 3004" 2>/dev/null; true
cd Tests/playwright && npx playwright test datatable.spec.ts --config=playwright.swiflowui.config.ts
```
Expected: all datatable specs PASS, including the new virtualization test.

- [ ] **Step 4: Commit**

```bash
git add Tests/playwright/datatable.spec.ts
git commit -m "test(e2e): virtualized DataTable windowing + scroll

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Docs

**Files:**
- Modify: `docs/guides/swiflowui.md`
- Modify: `docs/future-work/swiflowui-1.0-roadmap.md`

- [ ] **Step 1: Add a DataTable §Virtualization** to `docs/guides/swiflowui.md` (after the existing DataTable section). Cover, with a code sample:
  - `virtualized: .fixed(rowHeight:)` opt-in;
  - `columnsTemplate:` is **required for stable columns** and per-column `.width` is ignored when virtualized;
  - `maxHeight:` is **required** (the scroll container) — without it, the table renders all rows;
  - `virtualized:` **replaces** `pageSize:` (both set ⇒ virtualization wins);
  - the dynamic-data `key:` caveat still applies.

```markdown
### Virtualization

For large datasets, opt into windowed rendering — only the visible rows (plus a small
overscan) stay in the DOM:

\```swift
DataTable(people, sortable: true,
          virtualized: .fixed(rowHeight: 44),   // constant row height
          columnsTemplate: "2fr 80px 3fr",      // required: shared column track sizes
          maxHeight: .custom("440px")) {         // required: the scroll container
    Column("Name", value: \.name)
    Column("Age", value: \.age).align(.trailing)
    Column("Email", value: \.email)
}
\```

- **`columnsTemplate` is required for stable columns.** Virtualized rows are CSS grid rows
  sharing one `grid-template-columns`; per-column `.width` is ignored. `fr` units are valid here.
- **`maxHeight` is required.** It is the scroll container the window is measured against;
  without it the table falls back to rendering every row.
- **Virtualization replaces pagination.** If you set both `virtualized:` and `pageSize:`,
  virtualization wins and no pager is shown.
- Dynamic data still needs a changing `key:` (rows freeze at first mount).
```

- [ ] **Step 2: Update the roadmap** — in `docs/future-work/swiflowui-1.0-roadmap.md`, remove "virtualization (windowed rendering)" from the DataTable deferrals and note it shipped; keep measured/variable heights, standalone virtualized `List`, row pooling, and `role=grid` keyboard roving deferred.

- [ ] **Step 3: Commit**

```bash
git add docs/guides/swiflowui.md docs/future-work/swiflowui-1.0-roadmap.md
git commit -m "docs(swiflowui): DataTable virtualization guide + roadmap update

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification (before PR)

- [ ] `swift test --filter SwiflowUITests` — all green.
- [ ] `swift test --filter TemplateEmbedderTests` — embed freshness green.
- [ ] `swift build -c release --product swiflow && .build/release/swiflow build --path examples/SwiflowUIDemo` — demo builds.
- [ ] Playwright `datatable.spec.ts` — green (inline).
- [ ] `git log --oneline origin/main..HEAD` — clean, scoped commits; branched from `origin/main`.
- [ ] Open PR (body ends with the Claude Code footer). **Do not merge** until the user says "merge it — CI is green"; then `gh pr merge <n> --admin --rebase`.

---

## Self-review notes (author)

- **Spec coverage:** enum + API (T1), mode/diagnostics + pager suppression (T2), window math + runway + metrics seam (T3), grid template + render branch + ARIA (T4), CSS (T5), demo (T6), e2e (T7), docs+roadmap (T8). All spec sections mapped.
- **Type consistency:** `activeRowHeight() -> Int?`, `paginationActive() -> Bool`, `firstVisibleIndex() -> Int`, `runwayHeightPx() -> Int`, `gridTemplate() -> String`, `setViewportMetrics(scrollTop:viewportHeight:)`, `visibleWindow(_:page:)` (extended, same signature) — used consistently across tasks.
- **Known soft spots flagged inline:** `floor`/`ceil` vs integer-math (Foundation avoidance) in T3; `CSSSheet` text accessor maybe-absent in T5; `debugHTML` vs structural assertion in T4; demo `Person` reuse in T6; Playwright selectors in T7. Each has an explicit fallback so the implementer is never blocked.
