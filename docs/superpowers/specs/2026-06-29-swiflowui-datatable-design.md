# SwiflowUI `DataTable` — Design

> **Date:** 2026-06-29 · **Status:** approved, ready for implementation plan
> **Milestone:** the **`DataTable`/virtualized `List`** "big rock" from the SwiflowUI 1.1+
> deferred list (`docs/future-work/swiflowui-1.0-roadmap.md`). This spec covers a **feature-rich
> DataTable** only; **virtualization is explicitly deferred** to a later pass, with v1 designed to
> keep it feasible (see §4).
> **Prior art:** the stateful-component idiom (`Sources/SwiflowUI/Autocomplete.swift` — public
> factory function + `@Component` class via `embedKeyed`), the keyed-children diff
> (`ElementData.key`), the control-styling seams (`scopedStyles` for stateful `@Component`s), the
> `inert`-for-disabled project rule, and the `Field`/`Binding` reactive idiom.

## Problem

SwiflowUI ships display and form primitives but no way to present **tabular data**: rows × typed
columns, with the everyday data-grid behaviors apps need — sort by a column, select rows, a header
that stays put while the body scrolls, and honest empty/loading states. Hand-rolling a `<table>`
with `element("table")` is possible but loses sorting/selection/accessibility and re-implements the
same chrome in every app.

## Goal

A declarative, accessible `DataTable` over a typed row model: the consumer describes **columns**
(header + how to render/sort a cell), hands in **rows**, and gets a styled, sortable, selectable
table with a sticky header and empty/loading states — using native `<table>` semantics, token-driven
styling, and **no JS driver/protocol change**. The architecture renders rows through a single
"visible-window" seam so **virtualization can be added later without reworking the column / sort /
selection / cell model**.

## Decisions (from brainstorming)

1. **Core target = feature-rich DataTable**, correctness/ergonomics over scale; modest datasets
   rendered in full. **Virtualization deferred** (1.x), but the v1 design keeps it feasible.
2. **Column model = declarative `Column` over a row model** (SwiftUI-`Table`-like), not
   children-based chrome. The component owns `<thead>/<tbody>/<tr>/<td>`, which is what makes
   sorting/selection/sticky generic.
3. **State ownership = hybrid:** selection is always a caller `Binding<Set<ID>>`; sort order and
   current page default to **internal `@Component` state** with **opt-in bindings** for control.
4. **Surface = factory function parameters + a trailing `@ColumnBuilder`** (not a postfix-modifier
   chain). Stateful SwiflowUI components are configured through their factory's parameters because a
   postfix `VNode` modifier cannot reach a `@Component`'s internal `@State`. The brainstormed
   ergonomics/semantics are preserved; only the surface syntax differs from the early preview.
5. **No driver/protocol change** — pure SwiflowUI, built on existing VNode/diff/`@Component`
   machinery.

## v1 feature triage

| Tier | Features |
|------|----------|
| **Required (v1)** | Declarative `Column` (value keypath + custom `.cell` builder); tri-state client-side sorting (`aria-sort`, keyboard-activatable header button); multi-row selection (`Set<ID>` binding, header select-all + indeterminate, `aria-selected`); sticky header; empty + loading states |
| **Nice-to-have (v1)** | Per-column alignment & width; row interaction (`onRowClick`); client-side pagination |
| **Deferred (1.x)** | **Virtualization** *(seam kept open — §4)*; density/zebra styling; column drag-resize; full ARIA-grid keyboard roving (`role=grid`); footer/totals row; controlled/server-side sort source; sticky first column / horizontal scroll |

## Public API

```swift
// Row: Identifiable overload (no `id:`)
DataTable(
    people,
    selection: $selected,          // Binding<Set<Person.ID>>? = nil → no checkbox column when nil
    sortable: true,                // Bool = false → header sorting (internal sort state)
    sortOrder: $order,             // Binding<SortOrder<Person>?>? = nil → opt-in controlled sort
    pageSize: 25,                  // Int? = nil → paginated when set (internal page state)
    page: $page,                   // Binding<Int>? = nil → opt-in controlled page
    onRowClick: { edit($0) },      // ((Person) -> Void)? = nil
    loading: isFetching,           // Bool = false
    maxHeight: .px(480),           // Spacing/length? = nil → scroll container; sticky header needs one
    emptyText: "No results"        // String = "No results" (default empty-state text)
) {
    Column("Name", value: \.name)                        // auto text cell, auto-sortable
    Column("Age",  value: \.age).align(.trailing)        // sortable by value, right-aligned
        .cell { Badge("\($0.age)") }                     // custom render, still sorts by .age
    Column("Actions") { row in Button("Edit") { edit(row) } }   // non-sortable (no value)
}

// Explicit-identity overload for non-Identifiable rows:
DataTable(rows, id: \.sku, selection: $picked) { Column("SKU", value: \.sku) }
```

- Every knob defaults off → `DataTable(rows) { Column("Name", value: \.name) }` is a plain styled
  table.
- `emptyContent` builder slot is **out of v1** (decided): `emptyText: String` covers the case;
  a builder slot can be added compatibly later if needed.
- `caller` attributes and a `key:` are accepted last, matching the other components
  (`embedKeyed(key)`; last-write-wins on attributes).

## `Column<Row>` (value type)

A plain `struct Column<Row>` — chainable config is fine here (it is *not* a component). Fields:

- `title: String` — header text (rendered in `<th scope="col">`).
- `cell: (Row) -> [VNode]` — how to render the data cell's contents.
- `comparator: ((Row, Row) -> ComparisonResult)?` — type-erased sort comparator captured from the
  value keypath. **Non-nil ⇒ this column's header is sortable** (when the table's `sortable` is on).
- `alignment: ColumnAlignment = .leading` — `.leading | .center | .trailing` (logical/RTL: maps to
  `text-align: start|center|end`, matching the house logical-CSS style).
- `width: ColumnWidth? = nil` — optional fixed/min width hint (`.px`, `.fr`, `.auto`); applied via a
  `<col>` element or inline cell style.

Constructors:

- `Column(_ title: String, value: KeyPath<Row, V>) where V: Comparable & CustomStringConvertible`
  — derives **both** the default text cell (`String(describing: row[keyPath:])` / `.description`)
  **and** the comparator (`<`-based, mapped to `ComparisonResult`).
- `Column(_ title: String, value: KeyPath<Row, V>) where V: Comparable` + `.cell { }` override —
  sortable by value, custom rendering.
- `Column(_ title: String, cell: @escaping (Row) -> [VNode])` (also the trailing-closure form
  `Column("Actions") { row in … }`) — custom cell, **no comparator** (non-sortable).

Modifiers (return a modified copy): `.cell { row in … }`, `.align(_:)`, `.width(_:)`. An explicit
`.sortable(false)` clears the comparator for a value column that should not be sortable.

`@resultBuilder ColumnBuilder` collects `[Column<Row>]` (supports `if`/`for` like `ChildrenBuilder`).

`SortOrder<Row>` is the public controlled-sort type: the column's identity (its index or a stable
column id) + direction (`.ascending` / `.descending`). Stored so the body can re-derive the active
comparator. `nil` = unsorted.

## State & the virtualization seam (§4)

`DataTableBox` is a `@MainActor @Component final class` (it owns transient sort/page state and, when
`maxHeight` is set, drives the scroll container). Per body it computes one pipeline:

```
allRows
  → sort      (apply the active column's comparator + direction; stable; identity when unsorted)
  → window    (select the visible slice)         ← THE SEAM
  → render    (one <tr> per visible row, keyed by id; <td> per column via column.cell)
```

- **`sort`** uses the active `SortOrder` — internal `@State` by default, or the `sortOrder:` binding
  when provided. Tri-state cycle on a sortable header: none → ascending → descending → none. Sorting
  is **stable** (preserve input order among equal keys) so re-sorts don't scramble equal rows.
- **`window`** is the single seam. v1's window is **the current page slice** (`pageSize`/`page`
  applied to `sortedRows`) or **all rows** when `pageSize == nil`. **Virtualization later replaces
  only this step** — a scroll-offset-driven slice plus top/bottom spacer `<tr>`s of the omitted rows'
  height — leaving columns/sort/selection/cells untouched. Page index is internal `@State` by
  default or the `page:` binding when provided; it is **clamped** to valid range when `sortedRows`
  shrinks (e.g. after a filter upstream).
- **`render`** keys each `<tr>` by the row's `id` (from `Identifiable` or the `id:` keypath) so the
  keyed-children diff **reuses `<tr>` DOM** across sort/page changes instead of rebuilding the body.

Selection lives entirely in the caller's `Binding<Set<ID>>`; the component reads it to mark rows and
writes it on checkbox toggle / select-all. There is **no internal selection state**.

## Accessibility & styling

- **Native semantics** (the deferred ARIA-grid roving is *not* required for a correct, accessible
  table): `<table>` → `<thead><tr>` of `<th scope="col">` → `<tbody>` of `<tr>` of `<td>`.
- **Sortable header** = a `<button>` inside the `<th>`; the `<th>` carries
  `aria-sort="ascending|descending|none"`. Keyboard activation is the button's native Enter/Space.
- **Selection** = a checkbox column: header checkbox = select-all with the **indeterminate** property
  when partially selected (set via a DOM property, like other controls); each row checkbox has an
  accessible label; the `<tr>` carries `aria-selected`.
- **Row interaction** (`onRowClick`): the click handler is bound on the `<tr>`; a hover affordance
  via tokens. Cells containing their own controls (buttons/links) keep working — row-click reads
  `EventInfo.isSelfTarget`/target so a button click inside a row does not double-fire row-click.
- **Sticky header**: `position: sticky; top: 0` on `<thead>`/header cells, inside the `maxHeight`
  scroll container (sticky needs a scroll ancestor; documented).
- **Disabled affordances** (e.g. prev/next pager buttons at range ends) render with **`inert`**
  (project rule), styled via `[inert]`.
- **Styling** via **`scopedStyles`** (the stateful-`@Component` styling seam), fully token-driven
  (spacing, border, surface, accent, text tokens) so it follows theming/dark-mode/media features.

## Components & boundaries

| Unit | Responsibility |
|------|----------------|
| `DataTable(_:…)` factory function(s) (`DataTable.swift`) | Public API; two overloads (`Identifiable` / explicit `id:`); captures config + columns; `embedKeyed(key) { DataTableBox(...) }` |
| `DataTableBox` `@Component` (`DataTable.swift`) | Sort/page `@State`; sort→window→render pipeline; selection read/write; ARIA wiring; scroll container; `scopedStyles` |
| `Column<Row>` + `ColumnBuilder` + `SortOrder`/`ColumnAlignment`/`ColumnWidth` (`Column.swift`) | Value-type column model: cell builder, comparator capture, alignment/width, result builder |

All in SwiflowUI. No core `Swiflow`, JS driver, patch opcode, or serializer change.

## Files

- **Create** `Sources/SwiflowUI/DataTable.swift` — factory function(s) + `DataTableBox` + pipeline + `scopedStyles`.
- **Create** `Sources/SwiflowUI/Column.swift` — `Column<Row>`, `@ColumnBuilder`, `SortOrder<Row>`, `ColumnAlignment`, `ColumnWidth`.
- **Create** `Tests/SwiflowUITests/ColumnTests.swift` — column value type + builder + comparator.
- **Create** `Tests/SwiflowUITests/DataTableTests.swift` — emitted-structure / behavior tests.
- **Modify** `examples/SwiflowUIDemo/...` — a DataTable gallery entry (build locally before merge — CI skips example builds).
- **Modify** `docs/guides/swiflowui.md` (or a component-guide section) — DataTable usage + the sticky-header scroll-container caveat + the deferred list.
- **Create** an inline Playwright spec for the demo (sort/select/page) — run inline, never in a subagent.
- **Modify** `docs/future-work/swiflowui-1.0-roadmap.md` — record DataTable shipped + that virtualization/density/etc. remain deferred (also fold in the pending PR #84 "escape hatch shipped" roadmap note).

## Testing

- **Unit (host `swift test`, against emitted VNode/structure):**
  - Default text cell renders the keypath value; `.cell { }` overrides rendering but a value column
    still sorts by the value (comparator intact).
  - `@ColumnBuilder` collects columns, including `if`/`for`.
  - Tri-state sort cycle (none → asc → desc → none); sort reorders rows by the active comparator;
    sort is stable for equal keys; `aria-sort` reflects state.
  - Row `<tr>`s are keyed by id (keyed-diff reuse — assert keys present/stable across a re-sort).
  - Selection: row checkbox toggles the bound `Set`; header select-all selects/clears the visible
    set; header checkbox is indeterminate on partial selection; `aria-selected` on rows.
  - Pagination: `pageSize` slices rows; pager advances `page`; page clamps when row count shrinks;
    disabled pager buttons emit `inert`.
  - Empty state (`emptyText`) when rows empty; loading affordance when `loading`.
  - Per-column `align`/`width` emit the expected `text-align`/width.
  - `onRowClick` fires for a row but not when an in-cell control is the event target.
- **Host `swift build`** (SwiflowUI) green.
- **Demo builds locally** (`swiflow build --path examples/SwiflowUIDemo`).
- **Playwright e2e (inline):** header-click reorders DOM rows; select-all checks every visible row;
  pager advances the page. Run after `swift build -c release --product swiflow`, via an in-place
  example config, killing leftover port-3000 processes first.

## Non-goals

- **No virtualization in v1** — only the window seam that keeps it addable later.
- **No `role=grid` / full keyboard grid roving** — native `<table>` + `aria-sort`/`aria-selected` is
  the accessible v1 baseline; grid roving is the deferred ARIA-hardening pass.
- **No density/zebra styling, column drag-resize, footer/totals, sticky first column, horizontal
  scroll, server-side/controlled sort source** — all deferred (table above).
- **No driver/protocol/core-`Swiflow` change** — built entirely on existing machinery.
- **No `emptyContent` builder slot in v1** — `emptyText: String`; a builder can be added compatibly.

## Decisions resolved during brainstorming

1. **Core target** → feature-rich DataTable; virtualization deferred but kept feasible.
2. **Column model** → declarative `Column` over a row model.
3. **v1 must-haves** → sorting, selection, sticky header, empty/loading, custom cell render.
4. **v1 nice-to-haves** → per-column align/width, row interaction, pagination (density/zebra dropped).
5. **State ownership** → hybrid (selection bound; sort/page internal-by-default + opt-in bindings).
6. **Surface** → factory parameters + `@ColumnBuilder` (not postfix modifiers — `@Component` reality).
7. **Identity** → `Row: Identifiable` overload **plus** an explicit `id:` keypath overload.
8. **Empty state** → `emptyText: String` (no builder slot in v1).
