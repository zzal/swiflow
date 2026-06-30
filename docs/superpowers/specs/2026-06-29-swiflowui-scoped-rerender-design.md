# Scoped Re-render (Staged Fast-Path) — Design

**Issue:** #89 — a reactive `@State` change costs ~48ms (≈3 frames) end-to-end because every change re-renders and diffs the **whole component tree from the root**. Surfaced as visible lag when dragging the virtualized `DataTable` scrollbar (#88 masked it by raising overscan 3→10).

**Goal:** A reactive `@State` change that affects one small subtree should re-render and diff **only that subtree**, not the whole tree. Target: ≤1 frame (~16ms) for the virtualized-table window shift, down from ~48ms.

**Approach:** Staged — a **fast path** that scopes re-render to the dirty subtree when the frame's dirty set is the common, unambiguous single-component case, and a **fallback** to the existing, proven full-root render for everything else.

---

## Root cause (confirmed in code)

- `RAFScheduler.markDirty(_:)` already records the dirty component instance (`dirty.insert(ObjectIdentifier(component.instance))`), but `flush()` then **discards that information**: it calls a no-argument `onFlushBatch()`, which calls `Renderer.renderOnce()`.
- `Renderer.renderOnce()` always diffs from the root: `diff(mounted: mountTree, next: rootVNode, …)`. The `RAFScheduler` doc comment states it outright: *"the Renderer always rerenders the entire tree from the root component."*
- So a single `@State` change anywhere triggers a full-tree `body` re-evaluation + diff. The ~48ms is ~1 frame of rAF latency plus ~30ms of whole-tree Wasm compute, independent of how few rows actually changed.

## Why scoped invalidation is sound

Reactivity is already component-granular. Everything a component's `body` can depend on is, transitively, a `@State` whose mutation marks **some** owning component dirty:
- own `@State` → marks self dirty;
- props from a parent → only change when the parent re-renders (parent was marked dirty);
- environment values → propagate via parent re-render;
- a `Binding` to a parent's `@State` → the setter writes the parent's cell, marking the **parent** dirty, so the parent's subtree (including this child) re-renders.

Therefore re-rendering only the dirty component's subtree cannot miss an update.

## Why the subtree mechanism already exists

- `Diff.swift`'s `update()` has the arm `case (.component(let oldDesc), .component(let newDesc)) where oldDesc == newDesc`: it reuses the live instance, re-evaluates `body` under the component's own `scopeID` (`handlers.withScope(mounted.scopeID)`), and reconciles the body subtree **in place** (mutating the `MountNode`). Scoped invalidation is "start that arm at the dirty anchor instead of at the root" — no new diff logic.
- `MountNode` is a class graph with `component` (live instance), `componentBody` (rendered subtree), `parent` pointers, and `scopeID` — everything needed to locate an anchor and re-diff its body.
- An **inner** anchor has a real `parent` MountNode, so a structural body swap inside the subtree reconciles through normal `insertBefore` / `removeChild`. The `replaceMount` special-case in `renderOnce()` exists **only** because the root's parent is the bare `#app` selector target; it never applies to a scoped subtree render.

## Lifecycle / `onChange` contract change (decided)

`firePostRenderLifecycle(node, preExistingIDs:)` already partitions any subtree into `onChange` (instance survived) vs `onAppear` (freshly mounted). Rooting it at the dirty subtree gives the new, agreed contract:

> **`onChange()` fires for a component only when its subtree is actually re-rendered.**

Today every component's `onChange()` fires on every app render (whole-tree). Under scoped re-render, an un-re-rendered component's `onChange()` does not run that frame. This is direction #3 of the issue and is the natural, more-correct (SwiftUI-like) outcome. The full-render fallback path retains its current whole-subtree lifecycle walk unchanged.

---

## Design

### Data flow (changed pieces in **bold**)

1. `@State` setter → `scheduler.markDirty(component)` → `RAFScheduler` inserts `ObjectIdentifier(instance)`, schedules a rAF. *(unchanged)*
2. rAF fires → `flush()` snapshots the dirty set, clears it, and **passes the set to the callback**. `onFlushBatch` changes from `() -> Void` to `(Set<ObjectIdentifier>) -> Void`.
3. New `Renderer.flushDirty(_ dirtyIDs: Set<ObjectIdentifier>)` chooses fast path vs fallback.

### Fallback predicate — take the full `renderOnce()` when ANY of:

- first mount (`mountTree == nil`), or
- `dirtyIDs.count != 1` (multi-dirty / possible ancestor-overlap → out of scope for v1), or
- the single dirty instance's anchor cannot be located, or
- the anchor **is** the root component (full render is already minimal for the root).

Otherwise → fast path `scopedRender(anchor:)`.

The fallback is the **current code path, unchanged** — it carries zero new risk on the hard cases.

### `scopedRender(anchor:)`

Mirrors `renderOnce()` but rooted at the dirty anchor instead of `mountTree`:

1. Build a component VNode for the live instance, using the same factory trick `renderOnce()` uses for the root: a `ComponentDescription(typeID: instance.typeID, key: nil, factory: { instance })` so the diff's reuse arm gets the existing instance rather than constructing a fresh one.
2. Capture `preExistingIDs` from the **subtree** (`collectComponentIDs(anchor)`) before the diff, so the scoped lifecycle walk partitions onChange vs onAppear correctly.
3. `diff(mounted: anchor, next: thatVNode, handles:, handlers:, scheduler:, environment:)` → fires the component-reuse arm → re-evaluates `body`, reconciles the subtree **in place**. Because the anchor object is mutated in place, the parent's `children` array still references it — no re-splicing of the parent is required.
4. Encode + ship patches and update `renderCount` / `lastPatchCount` / `lastRenderMs` via a helper extracted from `renderOnce()` (`shipPatches(_:)`) so both paths share patch serialization + bridge dispatch.
5. `firePostRenderLifecycle(anchor, preExistingIDs:)` → only this subtree's `onChange` / `onAppear` fire.

No `replaceMount` handling here (see "Why the subtree mechanism already exists").

### Anchor location: instance → anchor index

A `[ObjectIdentifier: MountNode]` index mapping `ObjectIdentifier(instance)` → its component-anchor `MountNode`, maintained at the natural lifecycle points:

- **mount** of a component anchor → register;
- **destroy/unmount** of a component anchor → remove.

Gives O(1) lookup in `flushDirty`. If wiring the index into `mount`/`destroy` proves awkward, the acceptable fallback is a one-time pointer walk from the root to find the anchor whose `component?.instance === dirtyInstance` — traversal is cheap (the cost is `body` + diff, not pointer-walking). Start with the index.

### Complementary cheap win: `sortedIndices()` memoization (direction #2)

`DataTableBox.sortedIndices()` rebuilds `Array(0..<rowCount)` (2000 elements in the demo) and re-sorts it with a closure comparator on **every** `body` call. After scoped re-render, a scroll tick re-renders only `DataTableBox`'s subtree, but `body` still re-sorts all rows every tick though only the window slice changed.

- `@Component` types are classes and the instance persists across renders, so a non-`@State` stored cache is safe and invisible to reactivity:
  - `private var _sortCache: [Int]?`
  - `private var _sortCacheKey: (columnID: String?, ascending: Bool, rowCount: Int)?`
- `sortedIndices()` derives the key from `activeSort()` + `rowCount`; on a key match it returns the cached order, else recomputes and stores. Scroll changes neither sort nor count → cache hit → no rebuild/re-sort.
- Pure memo, no behavior change. Bundled because it's the same hot path; otherwise independent of the scoped-render core.

---

## Files touched

- `Sources/SwiflowDOM/RAFScheduler.swift` — `onFlushBatch` becomes `(Set<ObjectIdentifier>) -> Void`; `flush()` passes the snapshot before clearing.
- `Sources/SwiflowDOM/Renderer.swift` — `flushDirty(_:)` (predicate), `scopedRender(anchor:)`, extracted `shipPatches(_:)` helper shared with `renderOnce()`, and anchor-index upkeep wiring; the `RAFScheduler` closure becomes `{ [weak self] ids in self?.flushDirty(ids) }`.
- `Sources/Swiflow/MountTree.swift` (or a small new type in the same file) — the instance→anchor index type and the register/remove hooks called from `mount`/`destroy`.
- `Sources/SwiflowUI/DataTable.swift` — `sortedIndices()` memoization fields + logic.

The `Scheduler` protocol (`Sources/Swiflow/Reactivity/Scheduler.swift`) is unchanged; only `RAFScheduler`'s internal callback shape changes. `SyncScheduler` (tests/headless) already dispatches per-component and needs no change.

---

## Testing

### Host unit tests (run in `swift test`, what CI actually executes)

The `MountTree`/diff core is host-compilable.

- **Anchor index:** mounting a component anchor registers it; unmount removes it; lookup returns the correct anchor for a given instance.
- **Scoped subtree diff:** build a tree with a nested component; call `diff(mounted: anchor, next: anchorVNode)`; assert the emitted patches touch only that subtree and that parent/sibling nodes are untouched.
- **`sortedIndices()` cache** (via the existing `makeDataTableBox` seam, rendering `building { box.body }`): inject a comparator that counts invocations; assert a scroll-only re-render (`setViewportMetrics`) does **not** re-invoke the comparator, that changing the sort **does** re-sort, and that the resulting order is correct.

### Browser verification (the `Renderer`/`RAFScheduler` wiring is WASM-only and cannot be host-tested)

- **Latency re-measurement:** in `SwiflowUIDemo`, instrument scroll→DOM latency with the same `MutationObserver`-on-`<tbody>` method used during #88. **Acceptance: ≤1 frame** for the window shift (down from avg ~46ms / max ~50ms). Cross-check `__swiflow.perf()` — `lastRenderMs` drops; `lastPatchCount` stays small.
- **Correctness regression:** run the existing `Tests/playwright/datatable.spec.ts` inline (windowing, sticky header, single border, horizontal columns), after `swift build -c release --product swiflow`. Never run e2e in a subagent.
- **`onChange`-contract audit:** confirm `Demo.onChange → syncColorScheme` still works under the new contract (it simply won't fire on table-scroll frames); grep for anything else relying on every-render `onChange`.
- **Overscan rollback (bonus acceptance):** once the win is confirmed, drop the DataTable overscan **10 → 3** and verify no blank on a moderate drag.

### CI note (project memory)

CI **skips example builds**, so the demo build + e2e + latency re-measurement are **local** steps; the host unit tests are what CI runs.

---

## Acceptance criteria

1. A single-component `@State` change re-renders and diffs only that component's subtree (verified: scoped patches in host tests; `lastPatchCount`/`lastRenderMs` in the browser).
2. Re-measured demo scroll→DOM latency ≤1 frame for the window shift.
3. `onChange()` fires only for components whose subtree actually re-rendered; the demo's color-scheme sync still works.
4. All existing host tests and the `datatable.spec.ts` e2e pass unchanged.
5. Multi-dirty / first-mount / root-dirty frames correctly take the unchanged full-render fallback.
6. (Bonus) DataTable overscan reduced 10 → 3 with no visible blank on a moderate drag.

## Out of scope (v1)

- Scoping frames with more than one dirty component (multi-dirty, ancestor/descendant overlap) — these take the full-render fallback. Widening the predicate to N non-overlapping dirty anchors is follow-on work, each step independently verifiable against the now-known-good baseline.
- Component-level memoization / `shouldComponentUpdate`-style body bailout.
- Any change to the `Scheduler` protocol surface or `SyncScheduler`.
