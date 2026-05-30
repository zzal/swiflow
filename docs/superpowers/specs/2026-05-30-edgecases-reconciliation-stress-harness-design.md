# EdgeCases — Adversarial Reconciliation Stress Harness

**Date:** 2026-05-30
**Status:** Design — pending implementation plan
**Area:** new `examples/EdgeCases/`, `Sources/SwiflowCLI/EmbeddedTemplates.swift` (regenerated), `Tests/playwright/`

---

## 1. Goal

Find edge-case bugs in the just-shipped **stable child slots** reconciler (and the diff engine generally) by building a deliberately adversarial example whose only job is to make reconciliation fail if it can. Each "trap" isolates one tricky nesting/identity scenario behind its own controls, with a **stateful sentinel** placed exactly where a bug would corrupt it. A Playwright spec drives one knob at a time and asserts the sentinel survived.

**Finding a failing invariant is success** — it's a real bug. The deliverable is the example + spec **plus a triage report**: each failure is fixed in the framework (or logged if non-trivial), and the example/spec become permanent regression coverage.

### Non-goals
- Not a user "getting-started" template — it is deliberately ugly. (It *is* embedded as a template; see §6, but labeled as an edge-case harness.)
- Not a visual showcase (that is HelloWorld's job).
- Not a microbenchmark suite, though Trap 11 surfaces gross perf regressions via patch-count.

## 2. Verification strategy (the crux)

Spurious node recreation is frequently **invisible** to naive checks — the original dialog bug kept `.open === true` while the element visually vanished. So every sentinel carries **interactive state that exists only on the live DOM node and is destroyed on recreation**. After mutating a *sibling/structure*, we assert the sentinel's state survived; if it did, the node was reused, not recreated.

Detection signals, in order of preference:
1. **Input focus + typed value + caret** — type into an `<input>`, mutate elsewhere, assert `document.activeElement` is still that input and `.value`/`selectionStart` are intact. (Focus survives only same-node.)
2. **`<details open>` / native open-state** — toggle structure, assert `open` unchanged.
3. **Manually-tagged DOM property** — `el.__sentinel = N` set via `evaluate`; re-query and assert the property persists (proves same node object).
4. **`@State`-backed counter inside a child component** — a component's own counter; recreation resets it to 0, reuse keeps it.
5. **Computed visibility / rect** — catch "in DOM but rendered gone" (the dialog-vanish signature): assert `getBoundingClientRect()` non-zero / `visibility !== hidden` when state says visible.

Patch-stream sanity (Trap 11): read Swiflow's `window.__swiflow.perf()` (`lastPatchCount`) to assert a bulk op emitted a *minimal* patch count, catching non-minimal diffs that still render correctly.

## 3. Architecture

- One root component **`EdgeLab`** (`@MainActor @Component`) renders a vertical list of `<section>`s, one per trap.
- **Each trap is its own component** in its own file (HelloWorld-split convention), fully self-contained: it owns the `@State` for its knobs, renders its controls + trap structure + sentinel(s). The root just `embed`s them in order. This keeps each trap independently understandable and testable, and means a bug in one trap can't mask another.
- **Addressability:** every section carries `data-testid="trapN"`; every control/sentinel a stable `data-testid` (e.g. `trap1-toggle`, `trap1-input`). The Playwright spec locates by `getByTestId`. (Swiflow `.attr("data-testid", …)`.)
- **Styling:** minimal shared `scopedStyles` on `EdgeLab` (legible, no animation noise that could confound assertions). Each trap may add a tiny scoped sheet if needed.

## 4. Trap inventory

Each entry: **structure** (what it nests) → **control** (what mutates it) → **sentinel** (what must survive) → **assertion**.

1. **Conditional before a focused sibling.** `if showA { … }` rendered *before* a sentinel `<input>`. → toggle `showA`. → input focus + typed value. → after toggle, input still `document.activeElement` with same value. (Generalized original dialog bug.)
2. **`for`-of-`if`.** A keyed list where each item conditionally renders an inner node (`for item { if item.flag { … } }`). → toggle one middle item's flag. → a *sibling* item's tagged DOM node + an input in a later item. → sibling node identity + value unchanged.
3. **`for`-of-`if`-of-`for`.** Three-level imbrication: outer keyed list → per-item conditional → inner keyed sub-list. → mutate the innermost sub-list of one item (add/remove). → outer siblings' tagged nodes. → outer structure & identities intact; only the targeted inner list changes.
4. **Loop inside a conditional.** `if show { for … }` with a stateful sentinel *after* the block. → toggle `show` (whole loop appears/disappears). → sentinel `<details open>` after the block. → `open` survives both directions; on refill, loop items appear in correct order before the sentinel.
5. **Keyed reorder with interspersed fragments.** Children `[li(key:a), if x {}, li(key:b), for {}]`. → reorder the keyed `li`s (swap a/b) and toggle `x`. → tagged DOM props on the `li`s. → no `createElement` for the `li`s (reused); fragments hold position.
6. **Two adjacent conditionals (`bucketKey` collision case).** `if a {}; if b {}` both before a sentinel input, inside a list that also has a keyed sibling (forces the keyed path). → toggle a/b across all four combinations. → sentinel input focus+value. → survives every combination (exercises the structural position-key fix).
7. **Component in an emptying fragment + lifecycle.** `if showChild { embed { LifecycleChild } }` beside a second `embed { Keeper }` whose `@State` counter is bumped by a button. `LifecycleChild` increments visible onAppear/onDisappear counters. → toggle `showChild` off then on. → onAppear/onDisappear counts + `Keeper`'s counter. → onDisappear fires exactly once on hide, onAppear exactly once on show; `Keeper`'s `@State` is never reset (its node/instance reused across the sibling's churn).
8. **Empty→full→empty rapid cycle.** A fragment toggled many times in quick succession (a "cycle ×N" button). → click cycle. → a tagged sentinel after the fragment + child count. → no duplicated/leaked children, sentinel intact, final state matches parity.
9. **Keyed list whose items each contain their own `if`/`for`.** Outer keyed list; each item has an internal collapsible (`if expanded`) and a per-item input. → expand one item, type in its input, then reorder the outer list. → the expanded state + typed value. → they move *with* the item (identity preserved), not stranded at the old index.
10. **`buildExpression([VNode])` raw-spread (known limitation).** A clearly-labeled section that splices a dynamically-sized `[VNode]` array *not* wrapped in `if`/`for`, with a sentinel after it. → change the array length. → sentinel. → documents that the spread *does* shift the sentinel (the known footgun) **but** asserts no crash and no cross-contamination beyond the documented shift. (Serves as living documentation of the limitation; may be cut if undesired.)
11. **Dynamic keyed list — `Add +1` / `Add +100` / `Remove 1` / `Clear` / `Swap`.** A keyed `for` list (one fragment slot) with controls to add one or 100 rows **at the front** (the real stressor — forces `insertBefore` + LIS) and **at the back** (trivial append, for contrast), remove the first row, clear all, and swap two rows. Each row has a sentinel `<input>` and a tagged DOM property. → run a bulk `Add +100` at front, type into a known row, then `Swap`/`Remove`. → the typed row keeps its value + identity; `window.__swiflow.perf().lastPatchCount` after `Add +100`-front is within a minimal bound (≈ proportional to added rows, not to total rows²). → catches identity bugs under bulk churn **and** the `nextDOMAnchor` `O(siblings)` / `firstIndex(===)` perf caveat at scale.

## 5. What a failure means

A red assertion = a discovered reconciler bug. Process: triage (is it correctness or perf?), reproduce at the **unit** level (a focused diff test mirroring the trap — these also become permanent), fix in the framework, re-run. If a fix is non-trivial or a deliberate limitation (e.g. Trap 10), log it in the triage report and (if a limitation) document it rather than fix.

## 6. Wiring

- **`examples/EdgeCases/`**: standard example layout — `Package.swift` (`.package(path: "../..")`), `index.html` (minimal mount point + loading indicator), `Sources/App/App.swift` (the `EdgeLab` root + `@main`), one file per trap component (+ optional per-trap styles).
- **Embedding:** regenerate `Sources/SwiflowCLI/EmbeddedTemplates.swift` via `swift scripts/embed-templates.swift`; the freshness test pins it. `EdgeCases` becomes a `swiflow init --template EdgeCases` option (consistent with how the Playwright configs scaffold counter/router; doubles as edge-case documentation for contributors).
- **Playwright:** new `Tests/playwright/playwright.edgecases.config.ts` (mirrors `playwright.counter.config.ts`: scaffold a demo via `swiflow init … --template EdgeCases --swiflow-source REPO`, run `swiflow dev` on port 3003 — next free after counter:3000, router:3001, sw:3002) + `edgecases.spec.ts` (one `test` per trap, driving controls and asserting sentinels per §2). Add an `npm` script `test:edgecases`.

## 7. Out of scope
- Changing the reconciler itself (this spec only *finds* bugs; fixes are separate follow-up commits, tracked in the triage report).
- CI wiring for the new Playwright config (Playwright remains PR-only / manual per existing project setup).
- Mobile/responsive layout, theming, accessibility polish — the harness is functional, not pretty.

## 8. Build sequence (high level — detailed in the plan)
1. Scaffold `examples/EdgeCases/` skeleton (Package.swift, index.html, `EdgeLab` root, addressability conventions) + a trivial first trap; get it building to WASM and serving.
2. Implement traps 1–11 (each its own component + a matching `edgecases.spec.ts` test), incrementally.
3. Regenerate EmbeddedTemplates + freshness; add the Playwright config + npm script.
4. Run `test:edgecases`; triage failures → unit-repro + framework fix (or log) per §5; re-run to green.
