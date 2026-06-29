# SwiflowUI DataTable Virtualization — Design

**Status:** Approved (brainstorm 2026-06-29)
**Builds on:** `2026-06-29-swiflowui-datatable-design.md` (shipped, PR #85)

## Goal

Render large `DataTable` datasets (thousands of rows) at interactive speed by keeping
only the visible window of rows in the DOM. Opt-in, fixed-row-height, table-only this
round. The existing `visibleWindow` seam becomes scroll-driven.

## Scope

**In:** A `virtualized:` mode on `DataTable` that windows rendered rows to the scroll
viewport (plus overscan), with stable columns via a shared grid template, a sticky header,
preserved sort + selection, and `aria-rowcount`/`aria-rowindex` for assistive tech.

**Out (this round):** measured/variable row heights, the standalone virtualized `List`
(reuses this engine later), row pooling/recycling, `role=grid` keyboard roving, frozen
columns, horizontal virtualization.

## Decisions (locked in brainstorm)

1. **Row-height model — "fixed now, measured later".** A new `Virtualization` enum with a
   single `case fixed(rowHeight: Int)`. A `// case measured(estimated:)` slot is reserved
   for 1.x but not implemented.
2. **Layout — block/grid + transform (was "Option 2").** Keep a real `<table>` (semantics +
   a11y), but in virtualized mode override display: the table and `<tbody>` are
   `display: block`, each header/body row is `display: grid` over a **shared
   `grid-template-columns`** (rock-stable column alignment), `<tbody>` is a sized runway, and
   each visible `<tr>` is `position: absolute` + `transform: translateY(absIndex × rowHeight)`.
   Trade-off accepted: loses native column auto-sizing; columns come from the template.
3. **Column widths — single table-level template.** Caller passes one `columnsTemplate`
   string (`"1fr 80px 1fr"`); per-column `.width` is ignored in virtualized mode. When the
   selection checkbox column is present, the table auto-prepends a `min-content` track, so the
   template describes only the data columns. Omitting `columnsTemplate` defaults to
   `repeat(<dataColumnCount>, minmax(0, 1fr))`.
4. **Mode exclusivity.** Virtualization replaces pagination. If both `virtualized:` and
   `pageSize:` are set, a DEBUG `swiflowDiagnostic` fires and virtualization wins (`pageSize`
   ignored, no pager rendered).
5. **Bounded height required.** Virtualization needs a scroll container. If `virtualized:` is
   set but `maxHeight:` is nil, a DEBUG `swiflowDiagnostic` fires and the table falls back to
   a non-virtualized full render (correct, just unwindowed).

## API

```swift
public enum Virtualization: Equatable, Sendable {
    case fixed(rowHeight: Int)
    // case measured(estimated: Int)   // 1.x — not implemented
}

DataTable(people,
          selection: $selected,
          sortable: true,
          virtualized: .fixed(rowHeight: 44),   // new; nil ⇒ today's full / paged render
          columnsTemplate: "1fr 80px 1fr",      // new; shared grid-template-columns (data cols)
          maxHeight: .custom("480px")) {         // required when virtualized
    Column("Name", value: \.name)
    Column("Age",  value: \.age).align(.trailing)
    Column("Email", value: \.email)
}
```

`virtualized:` and `columnsTemplate:` are added to **both** public `DataTable` overloads
(the `id:`-keypath form and the `Identifiable` form) and threaded through `makeDataTableBox`
into `DataTableBox`. Overscan is an internal constant (`3`), not public API (YAGNI).

## Architecture

The pipeline is unchanged in shape — `sort → window → render` — but the **window** step
becomes mode-aware:

- **virtualized:** window = `order[(first−overscan) ..< (first + rowsInView + overscan)]`,
  where `first = floor(scrollTop / rowHeight)` and `rowsInView = ceil(viewportHeight / rowHeight)`.
- **paginated:** today's page slice (unchanged).
- **neither:** all rows (unchanged).

### Scroll engine

- A `Ref<JSObject>` (`scrollRef`) is bound to the `.sw-table__scroll` div via
  `.refBinding(AnyRefBinding(scrollRef))`, `#if canImport(JavaScriptKit)`-gated (mirrors
  `Autocomplete`/`Alert`).
- A `.on(.custom("scroll"))` handler on that div reads `scrollRef.wrappedValue?.scrollTop`
  and `.clientHeight` via JS interop (`EventInfo` carries no scroll data), and writes them to
  `@State scrollTop: Double` / `@State viewportHeight: Double` — **only when the derived
  first-visible index or rows-in-view actually changes**, so scrolling within a single row
  does not re-render.
- `onAppear()` reads the initial `clientHeight` (and `scrollTop`) from the ref once the
  element is mounted, seeding `viewportHeight` so the first paint windows correctly.
- Renders coalesce through Swiflow's existing `RAFScheduler` (one render per frame); no manual
  rAF throttle is added. `onChange()` is **not** used for scroll (it fires every render).
- Rows stay keyed by id (existing `rowKey`), so rows entering/leaving the window
  create/destroy through the normal diff.

### DOM & CSS (virtualized mode only)

```
<div class="sw-table-wrap">
  <div class="sw-table__scroll" style="max-height:480px" ref=scrollRef on:scroll>
    <table class="sw-table sw-table--virtual" style="--sw-table-cols: min-content 1fr 80px 1fr"
           role-ish aria-rowcount=<total>>
      <thead><tr class="sw-table__tr sw-table__tr--head">…th…</tr></thead>
      <tbody style="height: <total×rowHeight>px">           <!-- runway -->
        <tr class="sw-table__tr" style="transform: translateY(<absIndex×rowHeight>px)"
            aria-rowindex=<absIndex+1>>…td…</tr>            <!-- one per visible row -->
        …
      </tbody>
    </table>
  </div>
</div>
```

CSS added to `dataTableSheet` under a `.sw-table--virtual` scope (non-virtualized markup is
untouched):

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
```

- `--sw-table-cols` is set inline on the `<table>` (auto-prepended `min-content` selection
  track + the caller's template, or the `repeat(...)` default).
- The runway `<tbody>` height (`total × rowHeight`) is an inline style; each visible `<tr>`'s
  `translateY` is an inline style.
- The sticky header row pins inside the one scroll container; that single container scrolls
  header and body together horizontally (shared grid template ⇒ no desync).

### Test seam

Host tests can't scroll a real DOM. Mirror the existing `setSort`/`setPage` pattern with an
internal `setViewportMetrics(scrollTop:viewportHeight:)` that writes the two `@State`
values. `visibleWindow(_:page:)` is extended (or paired with a `virtualWindow(_:)`) so that,
given driven metrics, the windowed slice and the per-row absolute indices are computable and
assertable without a browser. The runway height and `--sw-table-cols` string are derived by
pure functions that tests call directly.

## Components / files

- **`Sources/SwiflowUI/DataTable.swift`** — `Virtualization` enum; `virtualized` +
  `columnsTemplate` params on both overloads + `makeDataTableBox` + `DataTableBox.init`; the
  `scrollRef`, scroll `@State`, `onAppear`, scroll handler; mode-aware window; the
  `.sw-table--virtual` branch in `body`/`bodyRows`/`headerRow` (inline `--sw-table-cols`,
  runway height, per-row `translateY`, `aria-rowcount`/`aria-rowindex`); the
  `setViewportMetrics` test seam; CSS additions to `dataTableSheet`.
- **`Tests/SwiflowUITests/DataTableTests.swift`** — virtualization unit tests (window math,
  overscan clamping at both ends, runway height, grid-template string incl. selection track
  and the `repeat(...)` default, aria attributes, mode-exclusivity + missing-height
  diagnostics fall-through, sort still orders the window, keyed rows).
- **`Tests/playwright/datatable.spec.ts`** — an e2e that scrolls a large table and asserts
  only a window of `<tr>`s is in the DOM, the right rows render at the right offset, sort
  reorders, and selection persists across scroll.
- **`examples/SwiflowUIDemo/Sources/App/App.swift`** — a virtualized table section (large
  generated dataset) demonstrating the feature; regen `EmbeddedTemplates.swift` **last, from a
  clean tree** (the regen-ordering trap).
- **`docs/guides/swiflowui.md`** — DataTable §Virtualization: the `virtualized:` +
  `columnsTemplate:` API, the `maxHeight` requirement, the `pageSize` mutual-exclusion, and
  the "per-column `.width` ignored when virtualized" caveat.
- **`docs/future-work/swiflowui-1.0-roadmap.md`** — move virtualization out of "deferred";
  keep measured-height / standalone `List` / pooling / `role=grid` roving deferred.

## Error handling

- `virtualized:` + `pageSize:` → DEBUG diagnostic, virtualization wins.
- `virtualized:` + nil `maxHeight:` → DEBUG diagnostic, non-virtualized fallback.
- `rowHeight <= 0` → DEBUG diagnostic, non-virtualized fallback (guards the divide).
- `columnsTemplate` track count not matching column count is **not** enforced (CSS grid
  tolerates mismatch); documented, not diagnosed.
- All JS-interop reads are `#if canImport(JavaScriptKit)`-guarded; on host they no-op and the
  window falls back to driven/default metrics.

## Testing strategy

- **Unit (host, deterministic):** drive `setViewportMetrics`, assert window slice + absolute
  indices; overscan clamp at top (index 0) and bottom (last rows); runway height = total ×
  rowHeight; `--sw-table-cols` = `min-content ` + template (and `repeat` default); aria
  attributes; both diagnostics fall back to full render; sorted order respected inside the
  window; rows keyed.
- **e2e (Playwright, inline — never a subagent; rebuild release CLI first):** 1k-row table,
  assert DOM holds only ~window rows, scroll changes which rows show, sort + selection persist.
- **Demo build:** `swiflow build --path examples/SwiflowUIDemo` locally before merge (CI skips
  example builds).
