# Phase 18 — `onChange` for Nested Components

**Status:** Approved
**Date:** 2026-05-27
**Predecessor:** Phase 17 (lifecycle / DOM-sync fixes)

## Problem

`Component.onChange()` is documented as "called after every re-render's patches
have been applied" (`Sources/Swiflow/Reactivity/Component.swift:28-33`). The
Web renderer honors this contract only for the **root** component:

```swift
// Sources/SwiflowWeb/Renderer.swift:216-221
} else {
    // Lifecycle: fire onChange on the root component.
    if let root = rootComponent {
        root.instance.onChange()
    }
}
```

Nested components never see `onChange()` regardless of whether their body
re-ran. Users who override the hook on a non-root component get silent
no-ops — the same shape of gap that Phase 17 fixed for `onAppear`.

There is a **sibling gap** in the same surface: when a component is mounted
mid-render (an `if`/`else` branch flips, a list grows), its `onAppear()`
never fires. `fireOnAppearTree(_:)` is invoked only from the Renderer's
first-mount branch (`Renderer.swift:215`); the diff's `mount()` does not
fire `onAppear` on anchors it creates during a re-render.

Both gaps are closed by the same primitive: per-render, distinguish
**reused** component anchors (alive before this diff) from **freshly
mounted** anchors (created during this diff) so we can fire the correct
hook on each.

## Semantic Model

The raw hook fires on every component instance that produced patches
this render:

| Situation                                  | Hook fired   |
| ------------------------------------------ | ------------ |
| First mount of a component                 | `onAppear()` |
| Mid-render mount (new branch / list grow)  | `onAppear()` |
| Reused instance, post-re-render commit     | `onChange()` |
| Destroyed instance                         | `onDisappear()` (unchanged) |

This is **React `componentDidUpdate` semantics** — fires every re-render
of that instance, independent of whether body output actually changed.
The choice is forced by what already ships:

- `Component.swift` documents this contract in prose ("after every
  re-render's patches have been applied").
- `OnChangeStorage.swift` defines `onChange(of: T, perform:)` as a
  convenience users call **from** `onChange()` — that extension only
  makes sense if `onChange()` fires unconditionally and the user filters
  inside it. SwiftUI-style value-diffing is what `onChange(of:)`
  already provides.

No public API changes. No behavior change for existing users who only
override `onChange()` on the root (it still fires there, same conditions).
The only observable difference: nested overrides now fire too, and
mid-render-mounted components now see `onAppear`.

## Architecture

Replace the two-branch lifecycle dispatch in the Renderer with one walker
that handles both first-mount and re-render uniformly.

### New helpers (in `Sources/Swiflow/Diff/Diff.swift`)

```swift
/// Collects the `ObjectIdentifier` of every live component instance
/// reachable from `node`. Returns an empty set if `node` is nil
/// (used to seed the first-mount case where every component is "new").
@MainActor
package func collectComponentIDs(_ node: MountNode?) -> Set<ObjectIdentifier>

/// Children-first walk over `node` and its entire subtree. For each
/// component anchor encountered:
///   - if its instance's ObjectIdentifier is in `preExistingIDs`, fire `onChange()`
///   - otherwise, fire `onAppear()`
///
/// Children-first ordering means a parent's hook observes a fully
/// mounted/committed subtree (matches React's commit-phase semantics and
/// the existing `fireOnAppearTree` invariant being replaced).
@MainActor
package func firePostRenderLifecycle(_ node: MountNode, preExistingIDs: Set<ObjectIdentifier>)
```

### Removed helper

`fireOnAppearTree(_:)` is deleted. Its single caller (the Renderer's
first-mount path) becomes `firePostRenderLifecycle(node, preExistingIDs: [])`,
which is observably identical: every component is absent from the empty
set so every component gets `onAppear()`, children-first.

### Renderer change

`renderOnce()` collapses its two-branch lifecycle block into one call:

```swift
// Sources/SwiflowWeb/Renderer.swift — replaces lines 195–221

let preExistingIDs = collectComponentIDs(mountTree)
let isFirstMount = (mountTree == nil)
mountTree = result.newMountTree

if isFirstMount {
    let mountHandle = result.newMountTree.domHandle
    _ = swiflowGlobal.mount!(
        JSValue.number(Double(mountHandle)),
        JSValue.string(selector)
    )
}
firePostRenderLifecycle(result.newMountTree, preExistingIDs: preExistingIDs)
```

`preExistingIDs` is computed **before** `mountTree` is reassigned so it
reflects the previous-render state. On first render `mountTree` is nil
and `collectComponentIDs(nil)` returns `[]`, so every component in the
new tree is treated as freshly mounted — identical to today's
`fireOnAppearTree` behavior.

### Ordering with mixed trees

When a reused parent has a freshly-mounted child (e.g. parent re-rendered
and conditionally introduced a new nested component), children-first
order produces:

1. New child's subtree mounts → child's `onAppear()` fires
2. Reused parent's `onChange()` fires

This matches React: `componentDidMount` on the child runs before
`componentDidUpdate` on the parent. A parent's `onChange()` can rely on
all newly-mounted descendants having completed their `onAppear()`.

## Files Modified

| File                                                            | Change                                                       |
| --------------------------------------------------------------- | ------------------------------------------------------------ |
| `Sources/Swiflow/Diff/Diff.swift`                                | Add `collectComponentIDs`, add `firePostRenderLifecycle`, remove `fireOnAppearTree` |
| `Sources/SwiflowWeb/Renderer.swift`                              | Replace two-branch lifecycle dispatch with single walker call |
| `Tests/SwiflowTests/Reactivity/RendererComponentTests.swift`    | New test suites (below)                                       |

No public API changes. No JS driver changes. No patch protocol changes.

## Test Plan

### `NestedOnChangeTests`
- **Re-render fires onChange on nested component.** Root re-render → assert child's `onChange()` call count goes 0 → 1.
- **Children-first ordering.** Shared call-order array recorded by parent and child `onChange()` overrides; assert child entry precedes parent entry.
- **Multi-level nesting.** Grandchild → child → parent fire order on a 3-deep re-render.

### `MidRenderMountTests`
- **Conditional mount fires onAppear, not onChange.** Component with `@State var show: Bool`; flip false → true; assert the newly-revealed child sees `onAppear()` exactly once and `onChange()` zero times in the same render.
- **Conditional mount + parent still gets onChange.** Same render: parent (reused) sees `onChange()` once.
- **Mount inside a list growth.** Push a new keyed item; assert the new item's `onAppear()` fires once; existing items see `onChange()` once.

### `FirstMountInvariantTests`
- **First mount fires onAppear on every component, none fire onChange.** Three-deep nested tree on initial render; assert each instance sees onAppear:1, onChange:0.
- **First-mount ordering unchanged.** Same children-first invariant as Phase 17's `OnAppearTreeWalkTests` (port that test forward — `fireOnAppearTree` is gone but the behavior it tested still holds via the unified walker).

### `OnChangeOfConvenienceTests` (sanity)
- **`onChange(of: value)` still fires its `perform` only on actual changes.** End-to-end: nested component overrides `onChange()`, calls `onChange(of: someState) { newValue in ... }`; assert `perform` fires only when `someState` actually changes between renders, even though `onChange()` itself fires every render.

### Existing tests
- `OnAppearTreeWalkTests` → rename / port. Behavior preserved (every component fires onAppear at first mount, children-first).
- `ComponentTypeSwapTests` (Phase 17) unaffected — no DOM-identity logic changes.
- Playwright `counter.spec.ts`, `router.spec.ts`, `progress.spec.ts` — must remain green; this change is observable only to user code that overrides `onChange()` on non-root components, and no example app does today.

## Risks & Mitigations

- **Risk:** Existing user code overrides `onChange()` on a nested
  component expecting it to never fire (current buggy behavior), and
  relies on that no-op. **Mitigation:** Pre-1.0; behavior explicitly
  documented as "called after every re-render's patches have been
  applied" — any code relying on the silent no-op is misusing a
  documented hook. Document in CHANGELOG under "Behavior changes".

- **Risk:** `collectComponentIDs` adds a tree walk per render.
  **Mitigation:** Mount trees in practice are well under 100 nodes; the
  walk is a single `Set.insert` per node with no allocations beyond the
  set itself. The diff's existing per-render work is orders of magnitude
  larger.

- **Risk:** Mid-render-mounted components seeing `onAppear` for the
  first time may invoke user code that mutates state synchronously,
  triggering an unexpected re-render. **Mitigation:** This is the same
  contract `onAppear` already has at first mount; users who guarded
  against re-entrancy at first-mount are covered. Document under
  "Behavior changes".

## Out of Scope

- Memoization / shouldComponentUpdate / "only re-render dirty subtrees"
  — a much larger architectural change reserved for its own phase.
- Diffing the rendered body to suppress `onChange()` when output is
  byte-identical — users opt into that via `onChange(of:_:perform:)`.
- An `onWillRender` / pre-commit hook — speculative; no demand yet.
- Async lifecycle hooks (`task { }`-style) — already tracked under the
  "Async testing deferred to pre-1.0" project memory.
