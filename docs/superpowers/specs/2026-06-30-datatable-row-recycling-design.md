# DataTable Row Recycling (memoized window) — Design

**Issue:** #91 — the virtualized `DataTable`'s dominant per-scroll cost is re-rendering its OWN body: `body` reconstructs all ~30 windowed row VNodes every scroll tick (`col.render` per cell) and the diff walks all of them. Measured ~20ms / ~1116 patches on a full-window change in a release build (follow-up from #89 / PR #90, where scoped re-render removed the *rest-of-tree* cost but not this).

**Goal:** A moderate drag re-renders only the rows entering the window; rows that stay are neither reconstructed nor re-diffed. Target: moderate-drag scroll→DOM latency ≤1 frame (release), after which overscan can drop from 10 toward ~3.

**Approach:** Stay in the managed VDOM (keep keys, lifecycle, refs, declarative cells). Two cooperating changes plus one small general primitive:
1. **Decouple the scroll offset** off each row onto `tbody` padding, so a given data row's VNode is stable across scrolls.
2. **Memoize rows**: a per-row token + a row-VNode cache on `DataTableBox` skips `col.render` reconstruction for unchanged rows.
3. **`.memoKey` VNode primitive**: a small, general diff bail so the reused (cached) row VNode also skips the subtree diff.

---

## Root cause (confirmed in code)

`DataTableBox.body` (`Sources/SwiflowUI/DataTable.swift:382`) calls `visibleWindow(...)` then `virtualScroll` → `virtualBodyRows` → `window.enumerated().map { virtualRowVNode(...) }` (`DataTable.swift:532-558`). Every tick:
- Every windowed row VNode is **reconstructed**, invoking `col.render(i)` for every cell (`DataTable.swift:544-546`).
- Each row carries `transform: translateY(absolute * rowHeight)` (`DataTable.swift:551`), so even an otherwise-unchanged row's VNode **differs every scroll** (the offset moves) — blocking naive memoization.
- The diff `update()` has **no unchanged-subtree short-circuit** — it always walks. (`VNode`/`ElementData` are `Equatable`, but nothing in `update()` uses it to bail.)

Rows are already keyed by `rowKey(i)` (`DataTable.swift:549`), so the keyed-children diff already *reuses* rows whose key stays in the window — imperative pooling is not the gap. The gap is **VNode reconstruction + diff-walk of the whole window every tick**.

## Why the offset is the blocker

`absolute` (a row's index in the sorted `order`) is actually **stable per data row across scrolls** — for a data row at sorted position `P`, `first + offset == P` whenever it's in the window. It changes only on re-sort. So once the per-row `transform` is removed, a given data row's VNode depends only on render-varying inputs `(rowID, P, isSelected)`. Row *data* is immutable post-mount (the `key:` re-mount contract documented at `DataTable.swift:~50`), and columns/`gridColumns`/`rowHeight` are fixed per mount.

---

## Design

### 1. Offset decouple — `tbody` padding-spacer

Replace per-row `transform` with padding on the (already `display:block`) `tbody`:
- `padding-top = first * rowHeight`
- `padding-bottom = (total - end) * rowHeight`  (where `end = first + window.count`)
- Each row keeps `height`, `grid-template-columns`, `aria-rowindex` (= `absolute + 1`, stable per row) — but **drops `transform`**.

Rows render in normal flow as direct `tbody` grid children. Total scroll extent `= padding-top + window*rowHeight + padding-bottom = total*rowHeight` (unchanged). The explicit `tbody { height }` runway (`DataTable.swift:520`) is removed — padding now defines the extent.

A window shift becomes **2 style patches on `tbody`** (padding-top/bottom) + the keyed add/remove of edge rows. No wrapper element is introduced (keeps the `table > thead/tbody > tr` structure the existing CSS and e2e assert).

Both padding values are standard kebab properties, so `.style()` applies them correctly (the `--var` driver limitation does not apply).

### 2. Per-row memo token + row-VNode cache

**Token** (cheap, `Equatable`):
```swift
private struct RowToken: Equatable { let id: String; let p: Int; let selected: Bool }
```
- `id` = `rowKey(i)`; `p` = absolute sorted position; `selected` = `selection?.isSelected(i) ?? false`.
- On scroll: all three stable → token unchanged.
- On re-sort: `p` changes → rebuild. On selection toggle: `selected` changes → rebuild just that row.

**Cache** on `DataTableBox` (non-`@State`, same pattern as the `sortedIndices` memo at `DataTable.swift:~244`):
```swift
private var _rowCache: [String: (token: RowToken, vnode: VNode)] = [:]
```
Per windowed row in `virtualBodyRows`:
- compute `token`; if `_rowCache[id]?.token == token`, reuse `.vnode` (**skips `col.render`**);
- else build via `virtualRowVNode(...)` (now without `transform`, with `.memoKey(token)`) and store.

After building the window, **evict** `_rowCache` keys not in the current window so it stays ~window-sized.

`RowToken` and the cache are correct because a row's rendered content is a pure function of `(data[id], p, selected, columns)`, and data/columns are immutable post-mount — identical token ⇒ identical content (no false positives).

### 3. `.memoKey` — general diff bail (the one core/general addition)

Reusing the cached VNode skips reconstruction, but the diff still walks it unless it can bail. Add a small, general primitive:

- **Carrier:** an optional `memoKey: AnyHashable?` field on `ElementData` (`Sources/Swiflow/VNode.swift`), set via a `VNode` modifier `.memoKey(_ key: AnyHashable) -> VNode` (`Sources/Swiflow/DSL/VNodeModifiers.swift`). Swift-side only: **excluded from `ElementData.==`** and **never serialized into a `Patch`** (mirrors the existing `unmanagedChildren` generation field).
- **Bail:** in `update()`'s element-vs-element arm (`Sources/Swiflow/Diff/Diff.swift`), before structural work: if `mounted` and `next` are both `.element` with non-nil, equal `memoKey`, return `mounted` unchanged (no patches, no descent).

Safe because a bailed row's event handlers capture the stable data index `i` (the same row), so skipping the update cannot mis-target.

DataTable tags each row `.memoKey(RowToken(...))`. A cache hit returns a VNode already carrying the matching token, so the diff also bails — both costs eliminated for unchanged rows.

### Net behavior

| Action | Work |
|---|---|
| Moderate 1-row scroll | 2 `tbody` padding patches + 1 row removed + 1 row built/added; ~28 rows cache-hit (no rebuild) + diff-bail (no walk) |
| Big thumb-jump (full window replace) | full window rebuilt — one expensive frame (acceptable; lag complaint is continuous drags) |
| Toggle one row's selection | that row rebuilt; others cache-hit |
| Re-sort | window rebuilt (new `order` + new `p`s) |
| Select-all / none | visible window rebuilt (one frame) |

---

## Files touched

- `Sources/Swiflow/VNode.swift` — add `memoKey: AnyHashable?` to `ElementData` (excluded from `==`).
- `Sources/Swiflow/DSL/VNodeModifiers.swift` — add `.memoKey(_:)` modifier.
- `Sources/Swiflow/Diff/Diff.swift` — `update()` element-vs-element memoKey bail.
- `Sources/Swiflow/PatchSerializer.swift` / patch encoding — confirm `memoKey` is never emitted (no change expected; it lives only on `ElementData`, not on any `Patch`).
- `Sources/SwiflowUI/DataTable.swift` — `RowToken`, `_rowCache`, padding-spacer in `virtualScroll`/`virtualBodyRows`, `virtualRowVNode` drops `transform` + adds `.memoKey`, cache lookup + eviction; remove the `tbody { height }` runway.
- Docs: `.memoKey` documented as a general performance primitive (DataTable as first consumer).

---

## Testing

### Host unit — diff core (the general primitive)

In `Tests/SwiflowTests/DiffTests/` (new file, e.g. `MemoKeyTests.swift`):
- Two `.element` VNodes with **equal** `memoKey` but **different children/attrs** → `update()` returns the mounted node and emits **zero patches** (the bail wins; equal token is the contract that content is equal).
- **Differing** `memoKey` → diffs normally (patches emitted).
- **`nil`** `memoKey` on either side → diffs normally (no bail).
- `memoKey` does not affect `ElementData.==` and is not present in any serialized patch.

### Host unit — DataTableBox (via `makeDataTableBox` + `building { box.body }`)

- **Rebuild counter** (`#if DEBUG` probe, like `_sortCacheHitForTesting`): a 1-row scroll (`setViewportMetrics`) rebuilds only the entering row; the rest are cache hits.
- **Selection invalidation:** toggling one visible row's selection rebuilds only that row.
- **Re-sort invalidation:** changing sort rebuilds the window.
- **Padding correctness:** `tbody` `padding-top == first*rowHeight`, `padding-bottom == (total-end)*rowHeight`.
- **No per-row transform:** windowed `<tr>`s have no `transform` style.
- **memoKey present:** each windowed row carries a `memoKey`.
- **Cache bounded:** after scrolling across many windows, `_rowCache` size stays ~window-sized (eviction works).

### Host unit — keyed-diff patch shape

- A 1-row window slide (drive two `body` renders through `diff`) emits a minimal patch set: 1 remove + 1 create/append for the edge rows + 2 `tbody` padding updates, with **no spurious row-move patches**.

### Browser (release) — the acceptance gate

- Re-run `Tests/playwright/datatable.spec.ts` inline (windowing, sticky header, single border, horizontal columns) — must stay green after the offset→padding move.
- Re-measure scroll→DOM latency in `SwiflowUIDemo` (release build, `MutationObserver` method from #88/#90), focusing on a **moderate drag**. **Acceptance: ≤1 frame.**
- Drop DataTable overscan **10 → 3**; rebuild; confirm no visible blank on a moderate drag.

### CI note (project memory)

CI skips example builds — the demo build + e2e + latency re-measurement are **local**; host unit tests are what CI runs.

---

## Acceptance criteria

1. A moderate 1-row scroll rebuilds only the entering row (host rebuild-counter) and emits a minimal patch set (host patch-shape test).
2. `.memoKey` bail: equal key → zero patches; differing/nil → normal diff (host).
3. Offset lives on `tbody` padding; windowed rows carry no `transform` (host).
4. Re-measured moderate-drag scroll→DOM latency ≤1 frame (release).
5. Overscan reduced 10 → 3 with no visible blank on a moderate drag.
6. All existing host tests and `datatable.spec.ts` pass unchanged.

## Out of scope

- Variable / measured row heights (still fixed `rowHeight`).
- Memoizing the non-virtualized (paged) table (its page is small; rebuild is cheap).
- A full hook-based `useMemo`/memo-storage system — `.memoKey` is a stateless tag; the cache lives on `DataTableBox`.
- Horizontal virtualization.
