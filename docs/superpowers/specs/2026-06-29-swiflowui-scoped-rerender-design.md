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
- the anchor **is** the root component (full render is already minimal for the root), or
- the anchor has an `environmentOverride` **ancestor** (a scoped diff starting at the anchor would reset `EnvironmentValues` to `.init()` and lose the ambient overrides). Detected by walking `parent` pointers from the anchor to the root and checking for any `MountNode` whose `vnode` is `.environmentOverride`. Note: `Theme {}` / `ThemeScope` is **not** an environment override (it is a `display:contents` div with inline custom-property styles), so it never triggers this fallback. Overrides *inside* the subtree are fine — the scoped diff threads environment through them normally.

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

### Anchor location: pure tree walk (v1)

v1 uses a stateless `package func findComponentAnchor(in:matching:) -> MountNode?` that walks a `MountNode` tree (`componentBody` + `children`) and returns the anchor whose `component?.instance === target`. Chosen over a mutable `[ObjectIdentifier: MountNode]` index because:

- it cannot go stale (no mount/destroy/HMR/teardown bookkeeping to keep in sync — the very kind of cross-cutting core change to avoid);
- it is a pure function, trivially host-testable;
- traversal cost is negligible relative to `body` + diff (pointer `===` compares only), and the fast path runs at most once per frame;
- the fallback predicate already needs a parent-pointer walk (the `environmentOverride`-ancestor check), so a tree walk is consistent with the rest of the path.

A `[ObjectIdentifier: MountNode]` index is a possible future optimization if profiling ever shows the walk to matter; it does not for v1.

### Complementary cheap win: `sortedIndices()` memoization (direction #2)

`DataTableBox.sortedIndices()` rebuilds `Array(0..<rowCount)` (2000 elements in the demo) and re-sorts it with a closure comparator on **every** `body` call. After scoped re-render, a scroll tick re-renders only `DataTableBox`'s subtree, but `body` still re-sorts all rows every tick though only the window slice changed.

- `@Component` types are classes and the instance persists across renders, so a non-`@State` stored cache is safe and invisible to reactivity:
  - `private var _sortCache: [Int]?`
  - `private var _sortCacheKey: (columnID: String?, ascending: Bool, rowCount: Int)?`
- `sortedIndices()` derives the key from `activeSort()` + `rowCount`; on a key match it returns the cached order, else recomputes and stores. Scroll changes neither sort nor count → cache hit → no rebuild/re-sort.
- Pure memo, no behavior change. Bundled because it's the same hot path; otherwise independent of the scoped-render core.

---

## Files touched

- `Sources/Swiflow/Diff/ScopedRerender.swift` **(new, core, host-testable)** — the entire decision + execution surface, behind host tests:
  - `findComponentAnchor(in:matching:) -> MountNode?` — locate the anchor for an `ObjectIdentifier` by tree walk.
  - `hasEnvironmentOverrideAncestor(_:) -> Bool` — parent-pointer walk.
  - `RerenderPlan` (`.full` | `.scoped(MountNode)`) and `planRerender(root:dirtyIDs:) -> RerenderPlan` — the **fallback predicate as a pure function** (so the decision is host-tested, not buried in the WASM renderer).
  - `scopedRerender(anchor:handles:handlers:scheduler:) -> [Patch]` — capture subtree IDs → rebuild the anchor's component VNode preserving typeID+key → `diff(mounted: anchor, …)` → `firePostRenderLifecycle(anchor, preExistingIDs:)` → return patches.
- `Sources/SwiflowDOM/RAFScheduler.swift` — `onFlushBatch` becomes `(Set<ObjectIdentifier>) -> Void`; `flush()` passes the snapshot before clearing.
- `Sources/SwiflowDOM/Renderer.swift` — `flushDirty(_:)` (thin: call `planRerender`, then either `renderOnce()` or core `scopedRerender(...)` + ship), an extracted `shipPatches(_:)` helper shared with `renderOnce()`; the `RAFScheduler` closure becomes `{ [weak self] ids in self?.flushDirty(ids) }`.
- `Sources/SwiflowUI/DataTable.swift` — `sortedIndices()` memoization fields + logic.

The `Scheduler` protocol (`Sources/Swiflow/Reactivity/Scheduler.swift`) is unchanged; only `RAFScheduler`'s internal callback shape changes. `SyncScheduler` (tests/headless) already dispatches per-component and needs no change.

---

## Testing

### Host unit tests (run in `swift test`, what CI actually executes)

The `MountTree`/diff core is host-compilable.

- **Anchor location:** `findComponentAnchor(in:matching:)` returns the correct nested anchor for a given instance, the root anchor when the root matches, and `nil` for an instance absent from the tree.
- **Environment-override ancestor guard:** `hasEnvironmentOverrideAncestor` is true for an anchor mounted beneath `.environment(...)` and false for one under `Theme {}` / no override.
- **Scoped subtree diff + lifecycle (the heart):** build a parent→child(→grandchild) tree; mutate the child's `@State`; call `scopedRerender(anchor: childAnchor, …)`; assert (a) the emitted patches touch only the child subtree (parent/siblings untouched), (b) the reused instance is identical (`newMountTree.component?.instance === childAnchor.component?.instance`), (c) the child's `onChange` fired while the parent's did **not**, and (d) a child mounted *during* the scoped diff fires `onAppear`, not `onChange`.
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
