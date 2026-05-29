# Stable Child Slots — Structural Reconciliation Identity

**Date:** 2026-05-29
**Status:** Design — pending implementation plan
**Area:** `Sources/Swiflow/Diff`, `Sources/Swiflow/DSL/ResultBuilder.swift`, `Sources/Swiflow/VNode.swift`

---

## 1. Motivation

A modal `<dialog>` in the HelloWorld example vanished on its own when an
unrelated toast auto-dismissed, while `showSignIn` stayed `true`. Live
investigation (Chrome, via chrome-devtools-mcp) showed the dialog DOM node was
**recreated** — `REMOVED dialog` + `ADDED dialog` with no `close()` call — and a
recreated modal `<dialog>` loses its top-layer state and disappears.

Root cause: the toast is a conditional child rendered *before* the dialog.
`ChildrenBuilder.buildOptional(nil)` returns `[]`, so when the toast unmounts the
child array **shrinks**, every later sibling shifts index, and the unkeyed
`diffChildrenIndexed` pass (which pairs `old[i]`↔`new[i]`) diffs the dialog
against the previous slot's node — a type mismatch — and replaces it.

### The lesson

This is the **same failure as React's Rules of Hooks: identity by position.**
React hooks are identified by call order; Swiflow's unkeyed children are
identified by array index. Both break the instant a position can shift (a
conditional hook; a conditional/looped child), and both fail silently. The cure
is the same: make child identity **stable** and make the contract **explicit and
teachable**.

A telling detail: in JSX, `{cond && <X/>}` evaluates to `false` when off, which
still **occupies an array slot**, so siblings never shift — which is why React
does not have this bug for conditionals. Swiflow's `buildOptional(nil) → []`
**drops the slot**. That single difference is the bug.

## 2. The rule (dev-facing mental model)

> **Every statement in a view builder is a stable child slot.** A plain
> element/component is one slot. An `if` / `if-else` / `for` is *also exactly one
> slot* — it holds its position even when empty, so it can never disturb its
> siblings. **Inside a `for`, give each item a `.key(...)`** so items keep
> identity across reorders; without keys, loop items match by position (correct
> for append-only lists, wrong for reordering).

Corollary (the property that fixes the bug): *toggling or looping a child never
disturbs a sibling, regardless of source order.* The HelloWorld "keep the
conditional toast last" workaround becomes unnecessary — order stops mattering.

This is the SwiftUI structural-identity contract, stated as plainly as the Rules
of Hooks. The only place a dev must actively think about identity is a `for`
loop — exactly one rule, exactly where React/SwiftUI also draw the line.

## 3. Design

### 3.1 `VNode.fragment` — a transparent slot

Add a case to `VNode`:

```swift
case fragment([VNode])
```

A fragment has **no DOM element of its own** (zero DOM nodes — "pure-virtual").
Its children render directly into the fragment's nearest real DOM ancestor,
interleaved with siblings. It is a structural node, like the existing
`.environmentOverride` (which already has a structural handle the JS driver never
sees). Because it is pure-virtual, **no new patch type and no driver changes are
required** — fragments reuse the existing `appendChild` / `insertBefore` /
`removeChild` / `destroyNode` patches.

### 3.2 `ChildrenBuilder` — one slot per statement

Wrap every *variable-length* construct in exactly one fragment so each source
statement contributes a fixed number of slots:

```swift
static func buildOptional(_ c: [VNode]?) -> [VNode] { [.fragment(c ?? [])] }   // empty slot survives
static func buildEither(first c: [VNode]) -> [VNode]  { [.fragment(c)] }
static func buildEither(second c: [VNode]) -> [VNode] { [.fragment(c)] }
static func buildArray(_ items: [[VNode]]) -> [VNode] { [.fragment(items.flatMap { $0 })] }
```

`buildExpression(VNode)` / `buildExpression([VNode])` / `buildBlock` are
unchanged. After this change, an element's top-level child list has **one entry
per statement** — a statically fixed count, and each statement's slot *kind* is
fixed too (an `if` is always a fragment there, full or empty). Top-level
reconciliation is therefore positionally stable **by construction**.

The only remaining place a child count varies is *inside* a `for`-fragment
(`buildArray`) — which is precisely where keyed reconciliation applies. Clean
story: **keyed diffing == loop reconciliation.**

### 3.3 The reconciler — three pure primitives + two invariants

A fragment maps to 0..N DOM nodes, but patches reference single real handles. To
keep this rock-solid we funnel **all** DOM placement through three pure, total
functions over the mount tree, and never compute anchors ad-hoc at call sites.

```
firstDOMHandle(node) -> Int?
    element / text / rawHTML        → node's own handle
    component-anchor / env-override → firstDOMHandle(body)            (nil if body empty)
    fragment                        → first child with non-nil firstDOMHandle, in order
                                      (nil if all children empty/absent)

nextDOMAnchor(slot) -> Int?
    scan siblings AFTER `slot` at this level, calling firstDOMHandle, until one
    is non-nil. If none, ascend to the enclosing fragment (if this level is a
    fragment) and continue among ITS siblings. Reaching a real element parent
    with nothing after → nil (== append). This is the `beforeChild` for EVERY
    insert.

collectDOMRoots(node) -> [Int]
    all top-level real DOM nodes of a subtree, descending through structural
    nodes. Used to append (mount) and to remove a subtree. For a single-node
    slot this is just [domHandle], so existing call sites generalize cleanly.
```

**Invariant A — place right-to-left.** Process new children last→first so that
when placing node `i`, everything to its right already sits in its final DOM
position; `nextDOMAnchor(i)` therefore reads *settled* state and is never stale.
(`KeyedChildrenDiff.swift` step 9 already walks the middle right-to-left for this
exact reason.)

**Invariant B — one rule everywhere.** Every insert is
`insertBefore(parent, node, nextDOMAnchor(slot))`; every removal is
`collectDOMRoots(subtree).forEach { removeChild(parent, $0) }`. No call site
invents its own anchor. The real DOM parent is `domAncestorHandle` (already
exists; extend it to skip `.fragment`).

#### Why this is provably sound

- **Totality** — empty/nested fragments return `nil` from `firstDOMHandle` and
  are skipped; nothing can dereference a missing handle.
- **Termination** — descent strictly decreases depth, sibling scans strictly
  advance index, the tree is finite.
- **Position correctness** — by induction under Invariant A: placing
  right-to-left, all DOM after node `i` is final, so its computed successor is
  the true one and `insertBefore` lands it exactly. Target DOM order is a total
  order fully determined by the new VNode tree; the algorithm only realizes it.

The engine already has the *upward* half of this symmetry (`domAncestorHandle`
skips structural nodes going up). Pure-virtual adds the *downward* half
(`firstDOMHandle`) plus the forward scan. The three functions are pure over the
mount tree, so they are unit/property-testable in isolation from the patch
stream. **That trio is the entire anchoring risk surface** — the "subtle bugs"
this approach is known for occur precisely when Invariants A/B are skipped and
anchor reads are scattered; enforcing them collapses the surface to three tested
functions.

> Note on matching vs. anchoring: *which* node keeps identity when same-type
> **unkeyed** siblings reorder is a separate concern (the keys rule), not an
> anchoring one. Anchoring is deterministic and complete on its own.

### 3.4 Reuse of the existing keyed diff

A `for`-fragment's children reconcile through the **existing** `diffChildren`
dispatch (keyed LIS when items carry keys; positional otherwise). Two small
fixes land alongside:

1. Route the keyed/indexed passes' `insertBefore` anchors through
   `nextDOMAnchor` / `firstDOMHandle` so a fragment sibling (zero/multi-root)
   is handled (today they read `sibling.domHandle` directly).
2. Close the `keyOf`-ignores-`.component` gap so component children can be
   matched by an explicit key inside a loop.

## 4. File-by-file changes

- **`Sources/Swiflow/VNode.swift`** — add `case fragment([VNode])`; update
  exhaustive switches and any key/diagnostic helpers (`diagKeyAndIsKeyable`
  recurses into fragment children like it does for `.environmentOverride`).
- **`Sources/Swiflow/DSL/ResultBuilder.swift`** — wrap `buildOptional` /
  `buildEither` / `buildArray` outputs in `.fragment(...)`.
- **`Sources/Swiflow/Diff/Diff.swift`**
  - `mount(.fragment)`: structural handle (no `createElement`/`appendChild` for
    the fragment itself); mount children into the fragment MountNode.
  - element `mount` append loop: append `collectDOMRoots(childMount)` per child
    (generalizes the current single-`domHandle` append).
  - `update`: add `(.fragment, .fragment)` arm → `diffChildren` over the
    fragment's children.
  - `destroy(.fragment)`: recurse children, no `destroyNode` for the structural
    handle (mirror `.environmentOverride`).
  - `domAncestorHandle`: add `.fragment` to skipped structural kinds.
  - add `firstDOMHandle`, `nextDOMAnchor`, `collectDOMRoots`.
- **`Sources/Swiflow/Diff/KeyedChildrenDiff.swift`** — replace direct
  `sibling.domHandle` anchor reads with `nextDOMAnchor`; fix `keyOf` to honor
  `.component` keys.
- **`MountNode`** — no structural change expected; `domHandle` semantics for a
  fragment are superseded by `collectDOMRoots`/`firstDOMHandle` at call sites.

No changes to `PatchSerializer`, the JS driver, or `EmbeddedDriver` (pure-virtual
adds no patch type). This keeps the js-driver ↔ EmbeddedDriver bit-for-bit
contract untouched.

## 5. Invariants & edge cases

- **Component bodies stay single-rooted.** `body: VNode` returns one node;
  fragments appear only as element *children*, never as a body. So the app/root
  mount and `replaceMount` remain single-rooted. (If a body is ever authored as
  a bare fragment, document it as unsupported / wrap in an element.)
- **Empty fragment** contributes no DOM and no anchor — handled by
  `firstDOMHandle → nil`.
- **Nested fragments** (`for` of `if`, `if` of `for`) — descent is recursive.
- **Fragment at head / tail / only child** — covered by the forward-scan +
  ascend-at-boundary rule.
- **Two adjacent fragments** — emptying one must not touch the other; guaranteed
  because each owns a disjoint subtree and removal uses `collectDOMRoots` of that
  subtree only.
- **Raw dynamic arrays** spread via `buildExpression([VNode])` outside an
  `if`/`for` are the one way a dev can still create an unstable slot count.
  Document: wrap dynamic content in a construct, or accept positional matching.

## 6. Testing

Pure-function unit/property tests (no patch stream) for the trio:
`firstDOMHandle`, `nextDOMAnchor`, `collectDOMRoots` over: empty fragment,
nested-empty, fragment-at-tail, fragment-as-only-child, two adjacent fragments,
`for`-of-`if`.

Diff-level tests (assert patch stream + mount-tree handles):
- **Regression:** a mid-list conditional toggling off leaves a later stateful
  sibling's handle **unchanged** (the dialog/toast bug, at the unit level).
- empty→full and full→empty fragment transitions place/remove correctly.
- `for` reorder *with* keys preserves item handles (LIS moves only).
- `for` append/remove without keys behaves positionally.
- nested fragments mount/patch in correct DOM order.

End-to-end: full Playwright suite, plus the existing
"Toast auto-dismiss does not close an open dialog" e2e (should pass with the
example's conditional restored to the middle, proving order-independence).

## 7. Out of scope

- Full keyed matching of arbitrary heterogeneous siblings (the type+occurrence
  "React-like" model) — not adopted; structural slots make it unnecessary.
- Marker/comment-node fragments — rejected in favor of pure-virtual.
- A `key` requirement *enforcement* for loops (we warn via existing diagnostics,
  not error).

## 8. Migration / blast radius

Every existing render gains fragment slots around its conditionals and loops —
broad but mechanical. No public API breaks (`.fragment` is builder-internal;
`.key(...)` already exists). Verified via the full unit + Playwright suites.
After landing, the HelloWorld example's "keep the toast last" comment and reorder
can be reverted to demonstrate order-independence (optional, in the
implementation plan).
