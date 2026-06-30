# DataTable Row Recycling (memoized window) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a moderate virtualized-DataTable drag re-render only the rows entering the window — rows that stay are neither reconstructed (`col.render`) nor re-diffed — so scroll→DOM latency drops to ≤1 frame and overscan can fall 10→3.

**Architecture:** Stay in the managed VDOM. (1) Move the scroll offset off each row onto `tbody` padding so a data row's VNode is stable across scrolls. (2) Memoize rows on `DataTableBox` via a `(id, p, selected)` token + a row-VNode cache that skips `col.render`. (3) Add a small general `.memoKey(AnyHashable)` VNode primitive + a `update()` bail so a reused row VNode also skips the subtree diff.

**Tech Stack:** Swift 6.3, swift-testing (`import Testing`), SwiftPM. Core (`Swiflow`) + `SwiflowUI` compile/test on host. `SwiflowDOM` is WASM-only (verified by the demo wasm build + browser).

**Critical context for the implementer:**
- `ElementData` (`Sources/Swiflow/VNode.swift:58`) is a struct with `tag/key/attributes/properties/style/handlers/children` plus out-of-band `refBindings`, `taskBindings`, and `managesOwnChildren: Bool = false`. Its `==` (`VNode.swift:120`) lists every field EXCEPT `refBindings`/`taskBindings`. Out-of-band fields are set post-init via postfix modifiers (see `unmanagedChildren()` in `Sources/Swiflow/DSL/VNodeModifiers.swift:84`, which does `mergeAttribute(self) { $0.managesOwnChildren = true }`).
- The element-vs-element diff arm is `case (.element(let oldData), .element(let newData)) where oldData.tag == newData.tag:` at `Sources/Swiflow/Diff/Diff.swift:354`.
- Virtualized render: `virtualScroll` (`DataTable.swift:512`) builds `tbody` with `.style("height", "\(runwayHeightPx())px")` (`DataTable.swift:519-520`); `virtualBodyRows` (`DataTable.swift:532`) maps the window through `virtualRowVNode` (`DataTable.swift:541`), which sets per-row `.style("transform", "translateY(\(absolute*rowHeight)px)")` (`DataTable.swift:551`). Rows are keyed `.key(rowKey(i))`.
- Virtual CSS block in `dataTableSheet` (`DataTable.swift:646-667`): rows are `position: absolute; inset-inline: 0; top: 0` under a `position: relative` tbody.
- The `sortedIndices` memo (added in #90) is the precedent for a non-`@State` cache on `DataTableBox` with a `#if DEBUG` probe — mirror its style.
- Host DataTable test harness (`Tests/SwiflowUITests/DataTableTests.swift`): build via `makeDataTableBox(...)`, render `building { box.body }`, inspect the VNode tree; `box.setViewportMetrics(scrollTop:viewportHeight:)` drives the window. `Person` fixture has `id/name/age`.
- Diff test harness (`Tests/SwiflowTests/Reactivity/ComponentUpdateTests.swift`): `diff(mounted:next:handles:handlers:)` → `DiffResult { patches, newMountTree }`; match patches with `if case .setText(...) = $0`.

**Branch:** `perf/datatable-row-recycling` (already created off `origin/main`; the spec lives there).

---

## Task 1: `.memoKey` VNode field + modifier

**Files:**
- Modify: `Sources/Swiflow/VNode.swift` (add field to `ElementData`)
- Modify: `Sources/Swiflow/DSL/VNodeModifiers.swift` (add modifier)
- Test: `Tests/SwiflowTests/DiffTests/MemoKeyTests.swift` (new)

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiflowTests/DiffTests/MemoKeyTests.swift`:

```swift
// Tests/SwiflowTests/DiffTests/MemoKeyTests.swift
import Testing
@testable import Swiflow

@Suite("memoKey")
@MainActor
struct MemoKeyTests {

    @Test("modifier stores the key on the element")
    func modifierSetsKey() {
        guard case .element(let d) = div().memoKey("row-1") else {
            Issue.record("expected element"); return
        }
        #expect(d.memoKey == AnyHashable("row-1"))
    }

    @Test("memoKey is excluded from ElementData equality")
    func excludedFromEquality() {
        guard case .element(let a) = div(.class("r")).memoKey("a"),
              case .element(let b) = div(.class("r")).memoKey("b") else {
            Issue.record("expected elements"); return
        }
        // Same rendered shape, different memoKey → still equal (== ignores it).
        #expect(a == b)
    }

    @Test("modifier on a non-element is a no-op passthrough")
    func nonElementPassthrough() {
        let t = VNode.text("hi").memoKey("x")
        #expect(t == .text("hi"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MemoKeyTests`
Expected: FAIL to compile — `value of type 'VNode' has no member 'memoKey'`.

- [ ] **Step 3: Add the field to `ElementData`**

In `Sources/Swiflow/VNode.swift`, after the `managesOwnChildren` property (`VNode.swift:89`), add:

```swift
    /// Optional memoization token. When two same-tag elements being diffed both
    /// carry a non-nil, EQUAL `memoKey`, the diff treats the element (and its
    /// entire subtree) as unchanged and skips all reconciliation. Caller's
    /// contract: equal key ⇒ equal rendered element + children. Swift-side only —
    /// excluded from `==` (it is metadata, not rendered shape) and never
    /// serialized into a `Patch`. Set via `VNode.memoKey(_:)`.
    public var memoKey: AnyHashable? = nil
```

Do NOT add `memoKey` to `==` (`VNode.swift:120`) — it must be excluded.

- [ ] **Step 4: Add the modifier**

In `Sources/Swiflow/DSL/VNodeModifiers.swift`, after `unmanagedChildren()` (`VNodeModifiers.swift:86`), inside the same `public extension VNode`:

```swift
    /// Tags this element with a memoization token. When the diff compares this
    /// element against a previously-mounted element of the same tag and both
    /// carry an equal, non-nil `memoKey`, the entire subtree is skipped (no
    /// reconstruction work is saved by this tag alone — pair it with caching the
    /// VNode so `body` doesn't rebuild it either). Caller's contract: equal key
    /// ⇒ equal element + children. A no-op on non-element nodes.
    func memoKey(_ key: AnyHashable) -> VNode {
        mergeAttribute(self) { $0.memoKey = key }
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter MemoKeyTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/VNode.swift Sources/Swiflow/DSL/VNodeModifiers.swift Tests/SwiflowTests/DiffTests/MemoKeyTests.swift
git commit -m "feat(diff): add .memoKey VNode field + modifier (#91)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: diff memoKey bail

**Files:**
- Modify: `Sources/Swiflow/Diff/Diff.swift` (element-vs-element arm)
- Test: `Tests/SwiflowTests/DiffTests/MemoKeyTests.swift` (append)

- [ ] **Step 1: Write the failing test**

Append inside `struct MemoKeyTests`:

```swift
    @Test("equal memoKey → diff skips the subtree (zero patches, mounted reused)")
    func equalKeyBails() {
        let h = HandleAllocator(); let hr = HandlerRegistry()
        // Mount a row whose child text is "A".
        let v1 = div(.class("row")) { p("A") }.memoKey("k1")
        let first = diff(mounted: nil, next: v1, handles: h, handlers: hr)
        // Next render: SAME memoKey but DIFFERENT child content ("B"). The bail
        // must win — equal key is the contract that content is unchanged.
        let v2 = div(.class("row")) { p("B") }.memoKey("k1")
        let second = diff(mounted: first.newMountTree, next: v2, handles: h, handlers: hr)
        #expect(second.patches.isEmpty)
        #expect(second.newMountTree === first.newMountTree)
    }

    @Test("different memoKey → normal diff (patches emitted)")
    func differentKeyDiffs() {
        let h = HandleAllocator(); let hr = HandlerRegistry()
        let first = diff(mounted: nil, next: div(.class("row")) { p("A") }.memoKey("k1"),
                         handles: h, handlers: hr)
        let second = diff(mounted: first.newMountTree, next: div(.class("row")) { p("B") }.memoKey("k2"),
                          handles: h, handlers: hr)
        let hasSetText = second.patches.contains { if case .setText(_, "B") = $0 { return true }; return false }
        #expect(hasSetText)
    }

    @Test("nil memoKey on either side → normal diff")
    func nilKeyDiffs() {
        let h = HandleAllocator(); let hr = HandlerRegistry()
        let first = diff(mounted: nil, next: div(.class("row")) { p("A") }.memoKey("k1"),
                         handles: h, handlers: hr)
        // new side has no memoKey → must not bail.
        let second = diff(mounted: first.newMountTree, next: div(.class("row")) { p("B") },
                          handles: h, handlers: hr)
        let hasSetText = second.patches.contains { if case .setText(_, "B") = $0 { return true }; return false }
        #expect(hasSetText)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MemoKeyTests`
Expected: FAIL — `equalKeyBails` fails (`second.patches` contains a `setText` to "B"; not empty).

- [ ] **Step 3: Add the bail**

In `Sources/Swiflow/Diff/Diff.swift`, as the FIRST statements inside the element-vs-element arm (immediately after `case (.element(let oldData), .element(let newData)) where oldData.tag == newData.tag:` at `Diff.swift:354`):

```swift
        // Memoization bail (#91): if both elements carry a non-nil, equal
        // memoKey, the caller declares the element + subtree unchanged. Skip all
        // reconciliation and keep the mounted node as-is. (mounted.vnode stays
        // the prior value, which equals `next` by the caller's contract.)
        if let oldKey = oldData.memoKey, let newKey = newData.memoKey, oldKey == newKey {
            return mounted
        }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MemoKeyTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Verify no patch serializes memoKey**

Run: `grep -n "memoKey" Sources/Swiflow/Patch.swift Sources/Swiflow/PatchPayload.swift Sources/Swiflow/PatchSerializer.swift`
Expected: NO matches (memoKey lives only on `ElementData`, never on a `Patch`). If any match exists, STOP and report — it must not be serialized.

- [ ] **Step 6: Run the full core suite (no regressions)**

Run: `swift test`
Expected: PASS (existing diff/keyed-children/lifecycle suites unaffected; the bail only triggers when a memoKey is present, which no existing code sets).

- [ ] **Step 7: Commit**

```bash
git add Sources/Swiflow/Diff/Diff.swift Tests/SwiflowTests/DiffTests/MemoKeyTests.swift
git commit -m "feat(diff): memoKey bail skips unchanged element subtrees (#91)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: DataTable offset → `tbody` padding-spacer

**Files:**
- Modify: `Sources/SwiflowUI/DataTable.swift` (`virtualScroll`, `virtualBodyRows`, `virtualRowVNode`, the `dataTableSheet` CSS)
- Test: `Tests/SwiflowUITests/DataTableTests.swift` (append)

- [ ] **Step 1: Write the failing test**

Add to `Tests/SwiflowUITests/DataTableTests.swift` (near the other virtualization tests). Helper to read an element's inline style by walking the tree may already exist (`el`/style helpers); if not, use the VNode directly. This test asserts the `tbody` carries padding and rows carry no transform:

```swift
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

        // Find the virtualized <tbody>.
        let tbody = firstElement(in: root) { data in
            data.tag == "tbody"
        }
        #expect(tbody != nil)
        let first = max(0, 50 - b.overscan)
        #expect(tbody?.style["padding-top"] == "\(first * 20)px")
        // No <tr> in the body carries a transform.
        let anyTransform = anyElement(in: root) { data in
            data.tag == "tr" && data.style["transform"] != nil
        }
        #expect(!anyTransform)
    }
```

If `firstElement(in:where:)` / `anyElement(in:where:)` VNode-walk helpers don't exist in this test file, add small local helpers at the top of the suite:

```swift
    private func anyElement(in node: VNode, where pred: (ElementData) -> Bool) -> Bool {
        switch node {
        case .element(let d):
            if pred(d) { return true }
            return d.children.contains { anyElement(in: $0, where: pred) }
        default: return false
        }
    }
    private func firstElement(in node: VNode, where pred: (ElementData) -> Bool) -> ElementData? {
        switch node {
        case .element(let d):
            if pred(d) { return d }
            for c in d.children { if let f = firstElement(in: c, where: pred) { return f } }
            return nil
        default: return nil
        }
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "DataTable"`
Expected: FAIL — `padding-top` is nil (tbody currently sets `height`, rows set `transform`).

- [ ] **Step 3: Rewrite `virtualScroll`'s tbody + `virtualBodyRows`/`virtualRowVNode`**

In `Sources/SwiflowUI/DataTable.swift`, change `virtualScroll` (`DataTable.swift:519-521`). Replace the `tbody` construction:

```swift
        let total = rowCount
        let end = first + window.count
        let tbody = element("tbody",
                            attributes: [
                                .style("padding-top", "\(first * rowHeight)px"),
                                .style("padding-bottom", "\(max(0, total - end) * rowHeight)px"),
                            ],
                            children: virtualBodyRows(window, first: first, rowHeight: rowHeight, gridColumns: cols))
```

(`first` is already computed at the top of `virtualScroll` as `max(0, firstVisibleIndex() - overscan)`.)

In `virtualRowVNode` (`DataTable.swift:541-558`), DELETE the transform style line:

```swift
            .style("transform", "translateY(\(absolute * rowHeight)px)"),
```

Keep `.key`, `.class`, `.style("grid-template-columns", gridColumns)`, `.style("height", "\(rowHeight)px")`, `.attr("aria-rowindex", String(absolute + 1))`, selection/onclick.

`runwayHeightPx()` (`DataTable.swift:336`) is now unused by `virtualScroll` — leave the function (it's harmless and may be referenced by tests); if the compiler warns "unused", that's fine, but do NOT delete it without checking `grep -rn runwayHeightPx`.

- [ ] **Step 4: Update the virtual CSS (rows flow instead of absolute)**

In the `dataTableSheet` raw CSS (`DataTable.swift:649,660-663`), change:

```css
    .sw-table--virtual tbody { position: relative; }
```
to (remove the rule — rows are no longer absolutely positioned):
```css
    /* (rows flow normally now; offset is tbody padding — see virtualScroll) */
```

and change:
```css
    .sw-table--virtual tbody .sw-table__tr {
      position: absolute; inset-inline: 0; top: 0;
      border-block-end: 1px solid var(--sw-border);
    }
```
to:
```css
    .sw-table--virtual tbody .sw-table__tr {
      border-block-end: 1px solid var(--sw-border);
    }
```

Leave the sticky `thead`, the `display: grid` rows, and the `.sw-table__td { border-block-end: none }` rules unchanged.

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter "DataTable"`
Expected: PASS — including existing virtualization tests (windowing, sort, etc.). The padding test passes; no row has a transform.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowUI/DataTable.swift Tests/SwiflowUITests/DataTableTests.swift
git commit -m "perf(datatable): move virtual scroll offset to tbody padding (#91)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: DataTable row token + VNode cache + memoKey tagging

**Files:**
- Modify: `Sources/SwiflowUI/DataTable.swift` (token, cache, `virtualBodyRows`, `virtualRowVNode`)
- Test: `Tests/SwiflowUITests/DataTableTests.swift` (append)

- [ ] **Step 1: Write the failing test**

Append to `Tests/SwiflowUITests/DataTableTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "DataTable"`
Expected: FAIL to compile — `DataTableBox` has no member `_rowRebuildsForTesting` / `_rowCacheCountForTesting`.

- [ ] **Step 3: Add the token, cache, and probes**

In `DataTableBox`, near the `_sortCache` fields (added in #90, around `DataTable.swift:240`), add a single `Hashable` row key used BOTH as the cache-validity token and as the `.memoKey`:

```swift
    // Row-VNode memo (#91). A virtualized row's rendered shape depends only on
    // (rowID, sorted-position, selected): row data + columns are immutable
    // post-mount, and offset now lives on tbody padding (not per-row transform).
    // The same value is the cache-validity token AND the .memoKey (it includes
    // `id`, so it is unique per row across the tbody's children). Non-@State
    // (invisible to reactivity), same pattern as the sortedIndices memo.
    private struct RowMemoKey: Hashable { let id: String; let p: Int; let selected: Bool }
    private var _rowCache: [String: (key: RowMemoKey, vnode: VNode)] = [:]
    #if DEBUG
    /// Count of rows actually built (cache misses) during the most recent body render.
    private(set) var _rowRebuildsForTesting = 0
    /// Current row-cache entry count (eviction probe).
    var _rowCacheCountForTesting: Int { _rowCache.count }
    #endif
```

Rewrite `virtualBodyRows` (`DataTable.swift:532-539`) to use the cache, build only on miss, and evict:

```swift
    private func virtualBodyRows(_ window: [Int], first: Int, rowHeight: Int, gridColumns: String) -> [VNode] {
        let colspan = columns.count + (selection != nil ? 1 : 0)
        if loading {
            _rowCache.removeAll(keepingCapacity: true)
            return [fullWidthRow(colspan, "sw-table__loading", [Spinner(label: "Loading")])]
        }
        if rowCount == 0 {
            _rowCache.removeAll(keepingCapacity: true)
            return [fullWidthRow(colspan, "sw-table__empty", [text(emptyText)])]
        }
        #if DEBUG
        _rowRebuildsForTesting = 0
        #endif
        var liveIDs = Set<String>()
        let rows: [VNode] = window.enumerated().map { offset, rowIndex in
            let absolute = first + offset
            let id = rowKey(rowIndex)
            liveIDs.insert(id)
            let key = RowMemoKey(id: id, p: absolute, selected: selection?.isSelected(rowIndex) ?? false)
            if let cached = _rowCache[id], cached.key == key {
                return cached.vnode
            }
            #if DEBUG
            _rowRebuildsForTesting += 1
            #endif
            let vnode = virtualRowVNode(rowIndex, absolute: absolute, rowHeight: rowHeight,
                                        gridColumns: gridColumns, memoKey: key)
            _rowCache[id] = (key, vnode)
            return vnode
        }
        // Evict rows no longer in the window so the cache stays ~window-sized.
        _rowCache = _rowCache.filter { liveIDs.contains($0.key) }
        return rows
    }
```

Update `virtualRowVNode`'s signature to accept the key and tag the returned `<tr>` with `.memoKey`. Replace the signature line (`DataTable.swift:541`):

```swift
    private func virtualRowVNode(_ i: Int, absolute: Int, rowHeight: Int, gridColumns: String, memoKey key: RowMemoKey) -> VNode {
```

and the return (`DataTable.swift:557`):

```swift
        return element("tr", attributes: attrs, children: cells).memoKey(key)
```

`RowMemoKey` is `Hashable`, so it satisfies `.memoKey(_ key: AnyHashable)`. Because it carries `id`, every row in the tbody has a distinct memoKey — the diff (which first matches children by `.key(rowKey)`, then compares memoKeys in `update`) bails only when the SAME row is unchanged across renders.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "DataTable"`
Expected: PASS — `rowCacheHitOnScroll` (1 rebuild on a 1-row shift), `rowCacheInvalidatesOnSelection` (1 rebuild), `rowCacheBounded` (cache ~window-sized), plus all existing virtualization/sort tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiflowUI/DataTable.swift Tests/SwiflowUITests/DataTableTests.swift
git commit -m "perf(datatable): memoize virtual rows via token cache + .memoKey (#91)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: keyed-diff patch-shape integration test

**Files:**
- Test: `Tests/SwiflowUITests/DataTableTests.swift` (append)

This is a test-only task: prove that a one-row window slide produces a minimal patch set (one row created, no spurious moves), end-to-end through the real diff.

- [ ] **Step 1: Write the test**

```swift
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

        // Exactly one new <tr> created (the entering row). Patch shape (verified):
        // `case createElement(handle: Int, tag: String)`.
        let createdRows = res.patches.filter {
            if case .createElement(_, "tr") = $0 { return true }
            return false
        }
        #expect(createdRows.count == 1)
    }
```

Note: there is no `moveChild` patch — reorders are expressed via `removeChild` + `insertBefore`/`appendChild`. A contiguous one-row window slide is "remove top + append bottom", so the reused middle rows should NOT generate `insertBefore` patches. If you want to also assert no churn on reused rows, additionally `#expect` that `createElement(_, "tr")` count is exactly 1 (already covered) — that alone proves ~28 rows were neither recreated nor re-diffed (memoKey bail).

- [ ] **Step 2: Run the test**

Run: `swift test --filter "DataTable"`
Expected: PASS — one row created on a one-row slide (the other ~28 rows hit the cache + memoKey bail; no per-row moves).

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiflowUITests/DataTableTests.swift
git commit -m "test(datatable): assert one-row slide emits a minimal patch set (#91)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Browser verification + overscan 10→3

**Files:**
- Modify: `Sources/SwiflowUI/DataTable.swift` (the `overscan` constant)
- Reference: `Tests/playwright/datatable.spec.ts`, `examples/SwiflowUIDemo`

Controller-run (e2e inline, never in a subagent), after building the release CLI.

- [ ] **Step 1: Build release CLI + wasm demo (compile gate)**

Run: `swift build -c release --product swiflow`
Then: `.build/release/swiflow build --path examples/SwiflowUIDemo`
Expected: both succeed.

- [ ] **Step 2: Run the DataTable e2e (correctness regression)**

Run (inline): `cd Tests/playwright && npx playwright test --config=playwright.swiflowui.config.ts datatable.spec.ts`
Expected: 4/4 pass (windowing, sticky header, single border, horizontal columns) — the offset→padding move preserves layout.

- [ ] **Step 3: Re-measure moderate-drag latency (release)**

Serve the release demo (`python3 -m http.server <port>` from `examples/SwiflowUIDemo`), open in chrome-devtools, and measure scroll→DOM latency with the `MutationObserver`-on-virtual-`<tbody>` method from #90, using SMALL deltas (≈2-row steps) to represent a moderate drag.
Expected: **avg ≤1 frame (~16ms)** for the window shift (down from ~23ms in #90). Record before/after in the PR.

- [ ] **Step 4: Drop overscan 10 → 3 and re-verify**

In `DataTableBox`, change `let overscan = 10` to `let overscan = 3` (`DataTable.swift:~243`). Rebuild the demo (Step 1) and repeat Step 3 plus a manual moderate drag. Expected: no visible blank. If a blank appears at 3, raise to the lowest clean value and document it.

- [ ] **Step 5: Confirm host tests still green after the overscan change**

Run: `swift test --filter "DataTable"`
Expected: PASS (tests derive window sizes from `box.overscan`, so they track the new value).

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiflowUI/DataTable.swift
git commit -m "perf(datatable): drop overscan 10→3 now that rows recycle (#91)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification (after all tasks)

- [ ] `swift test` — full host suite green (memoKey diff tests + DataTable cache/padding/patch-shape tests included).
- [ ] `swift build -c release --product swiflow` + `.build/release/swiflow build --path examples/SwiflowUIDemo` — wasm compiles.
- [ ] `datatable.spec.ts` e2e green (inline).
- [ ] Moderate-drag latency ≤1 frame (release); before/after captured.
- [ ] Overscan reduced (10→3 or lowest clean value) with no visible blank.
- [ ] Open a PR from `perf/datatable-row-recycling` → `main` referencing #91, with the latency numbers. **Do not merge** until the user says "merge it -- CI is green" (`gh pr merge <n> --admin --rebase`). Revert any build-regenerated `examples/SwiflowUIDemo/swiflow-driver.js` / `swiflow-service-worker.js` before opening the PR.

## Spec coverage check

- Offset decouple (tbody padding) → Task 3.
- Per-row token + row-VNode cache + eviction → Task 4.
- `.memoKey` field + modifier + diff bail (general primitive) → Tasks 1, 2.
- memoKey not serialized → Task 2 Step 5.
- Cache invalidation (selection, re-sort, loading/empty) → Task 4 (token + clear-on-loading/empty).
- Minimal patch shape on slide → Task 5.
- e2e correctness + moderate-drag ≤1 frame + overscan 10→3 → Task 6.
- Acceptance criteria 1–6 → Tasks 2/3/4/5 (host), Task 6 (browser).
