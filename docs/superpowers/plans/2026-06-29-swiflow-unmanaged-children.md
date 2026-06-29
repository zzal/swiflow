# Swiflow `.unmanagedChildren()` escape hatch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A first-class escape hatch — `VNode.unmanagedChildren()` — that marks an element so Swiflow mounts its initial children once, then never reconciles inside it again (the element shell stays reactive), for integrating foreign-owned DOM (custom elements, a WASM `<canvas>`, third-party widgets).

**Architecture:** A `managesOwnChildren` flag on `ElementData` (set by the postfix modifier `unmanagedChildren()`), and a single guard on the `diffChildren` call in the same-tag `.element` update arm of `Diff.swift`. Mount is unchanged (initial children mount once); on update the four bags still diff but children are skipped. **No JS driver / patch-protocol change** — the diff merely emits fewer patches.

**Tech Stack:** Swift 6.3, core `Swiflow` (`VNode`/`ElementData`, the `Diff`/mount machinery), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-06-29-swiflow-unmanaged-children-design.md`

---

## File Structure

- **Modify** `Sources/Swiflow/VNode.swift` — add `ElementData.managesOwnChildren: Bool = false`; include it in `ElementData.==`.
- **Modify** `Sources/Swiflow/DSL/VNodeModifiers.swift` — add the `VNode.unmanagedChildren()` postfix modifier.
- **Modify** `Sources/Swiflow/Diff/Diff.swift` — guard the `diffChildren(...)` call in the same-tag `.element` update arm on `!newData.managesOwnChildren`.
- **Create** `Tests/SwiflowTests/DiffTests/UnmanagedChildrenTests.swift` — patch-level + modifier + equality tests.
- **Create** `docs/guides/dom-interop.md` — short escape-hatch guide with `<canvas>`/custom-element examples.

---

## Reference facts (verified against current code)

- `ElementData` (`Sources/Swiflow/VNode.swift:58`) is a `struct` with bags `attributes`/`properties`/`style`/`handlers`, `children: [VNode]`, out-of-band `refBindings`/`taskBindings` (the latter has a default `= []` and a custom `==` that excludes refBindings/taskBindings). The custom `==` is at lines ~113-121.
- The public `init` lists every bag with defaults. A new stored `var managesOwnChildren: Bool = false` does **not** need an init parameter — the default applies for init-constructed nodes, and the modifier sets it post-construction (same shape as how `refBindings` is appended by `.ref`).
- VNode postfix modifiers live in `Sources/Swiflow/DSL/VNodeModifiers.swift`; the file-private helper `mergeAttribute(_:_:)` mutates `ElementData` and emits the standard DEBUG diagnostic + passthrough on non-element nodes.
- `Diff.swift` same-tag `.element` update arm (`case (.element(let oldData), .element(let newData)) where oldData.tag == newData.tag:`, ~line 354) diffs the four bags then calls `diffChildren(mounted:newChildren:handles:handlers:into:scheduler:parentPath:environment:)` (~line 379). `diffChildren` is the ONLY path that touches a plain element's children. The mount path (`mount()` `.element`, ~line 115) mounts declared children in a loop — left unchanged.
- Tests drive the diff via `diff(mounted:next:handles:handlers:) -> DiffResult` (`DiffResult.patches: [Patch]`, `.newMountTree: MountNode`). `diff(mounted: nil, …)` mounts; `diff(mounted: prior.newMountTree, …)` updates. Pattern: see `Tests/SwiflowTests/DiffTests/FragmentChildrenTests.swift`.
- `HandleAllocator` assigns handles sequentially from 0 in document order (parent before children).

---

## Task 1: `managesOwnChildren` flag + `.unmanagedChildren()` modifier

**Files:**
- Modify: `Sources/Swiflow/VNode.swift` (`ElementData` property + `==`)
- Modify: `Sources/Swiflow/DSL/VNodeModifiers.swift` (new modifier)
- Test: `Tests/SwiflowTests/DiffTests/UnmanagedChildrenTests.swift` (new file)

- [ ] **Step 1: Write the failing tests (new file)**

Create `Tests/SwiflowTests/DiffTests/UnmanagedChildrenTests.swift`:

```swift
// Tests/SwiflowTests/DiffTests/UnmanagedChildrenTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — unmanaged children escape hatch")
@MainActor
struct UnmanagedChildrenTests {
    private func data(_ node: VNode) -> ElementData? {
        if case .element(let d) = node { return d }
        return nil
    }

    @Test(".unmanagedChildren() sets the flag on an element") func modifierSetsFlag() {
        let node = VNode.element(ElementData(tag: "div")).unmanagedChildren()
        #expect(data(node)?.managesOwnChildren == true)
    }

    @Test("a plain element does not have the flag") func defaultIsFalse() {
        #expect(data(.element(ElementData(tag: "div")))?.managesOwnChildren == false)
    }

    @Test(".unmanagedChildren() on a non-element node is a no-op") func nonElementNoOp() {
        let node = VNode.text("x").unmanagedChildren()
        if case .text(let s) = node { #expect(s == "x") } else { Issue.record("expected .text") }
    }

    @Test("equality distinguishes the flag") func equalityDistinguishesFlag() {
        let plain = VNode.element(ElementData(tag: "div"))
        let flagged = VNode.element(ElementData(tag: "div")).unmanagedChildren()
        #expect(plain != flagged)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail to compile**

Run: `swift test --filter UnmanagedChildrenTests`
Expected: COMPILE FAILURE — `managesOwnChildren` and `unmanagedChildren()` don't exist yet.

- [ ] **Step 3: Add the stored flag to `ElementData`**

In `Sources/Swiflow/VNode.swift`, in `struct ElementData`, add the property after `taskBindings` (the last stored property, ~line 82):

```swift
    /// When true, Swiflow mounts this element's initially-declared children once, then NEVER
    /// reconciles inside it again — an escape hatch for elements that own their own DOM subtree
    /// (custom elements with self-managed light/shadow children, a foreign-painted `<canvas>`, a
    /// third-party widget). The element shell (tag + attributes/properties/style/handlers) is still
    /// reactively reconciled; only the children are left alone. Never serialized — it gates patch
    /// generation on the Swift side only. Set via `VNode.unmanagedChildren()`.
    public var managesOwnChildren: Bool = false
```

- [ ] **Step 4: Include the flag in `ElementData.==`**

In the custom `static func == ` (~lines 113-121), add the flag to the conjunction (it IS part of the rendered shape, unlike refBindings/taskBindings):

```swift
    public static func == (lhs: ElementData, rhs: ElementData) -> Bool {
        lhs.tag == rhs.tag
            && lhs.key == rhs.key
            && lhs.attributes == rhs.attributes
            && lhs.properties == rhs.properties
            && lhs.style == rhs.style
            && lhs.handlers == rhs.handlers
            && lhs.managesOwnChildren == rhs.managesOwnChildren
            && lhs.children == rhs.children
    }
```

- [ ] **Step 5: Add the `unmanagedChildren()` modifier**

In `Sources/Swiflow/DSL/VNodeModifiers.swift`, inside `public extension VNode { … }` (beside the other postfix modifiers), add:

```swift
    /// Marks this element as managing its own children: Swiflow mounts the initially-declared
    /// children once, then never reconciles inside it again (the element shell — attributes,
    /// properties, style, handlers — is still reconciled). Pair with `.ref(_:)` to populate the
    /// element imperatively (custom elements, a foreign-painted `<canvas>`, third-party widgets).
    /// A no-op on non-element nodes (the standard postfix-modifier diagnostic path).
    func unmanagedChildren() -> VNode {
        mergeAttribute(self) { $0.managesOwnChildren = true }
    }
```

- [ ] **Step 6: Run the tests and confirm green**

Run: `swift test --filter UnmanagedChildrenTests`
Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
git add Sources/Swiflow/VNode.swift Sources/Swiflow/DSL/VNodeModifiers.swift Tests/SwiflowTests/DiffTests/UnmanagedChildrenTests.swift
git commit -m "feat(core): ElementData.managesOwnChildren + .unmanagedChildren() modifier

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Skip child reconciliation for unmanaged elements

**Files:**
- Modify: `Sources/Swiflow/Diff/Diff.swift` (guard `diffChildren` in the same-tag `.element` update arm)
- Test: `Tests/SwiflowTests/DiffTests/UnmanagedChildrenTests.swift` (append behavior tests)

- [ ] **Step 1: Write the failing behavior tests (append to the suite)**

Append these tests inside `struct UnmanagedChildrenTests` (after the Task 1 tests):

```swift
    private func diffPair(_ a: VNode, _ b: VNode) -> (mount: DiffResult, update: DiffResult) {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: a, handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: b, handles: handles, handlers: handlers)
        return (m, u)
    }

    @Test("initial children mount once (same patches as a managed element)") func mountsInitialChildrenOnce() {
        let r = diff(mounted: nil,
                     next: VNode.element(ElementData(tag: "div", children: [.text("a")])).unmanagedChildren(),
                     handles: HandleAllocator(), handlers: HandlerRegistry())
        #expect(r.patches == [
            .createElement(handle: 0, tag: "div"),
            .createText(handle: 1, text: "a"),
            .appendChild(parent: 0, child: 1),
        ])
    }

    @Test("a re-render with different children emits NO child patches") func reRenderSkipsChildren() {
        let a = VNode.element(ElementData(tag: "div", children: [.text("a")])).unmanagedChildren()
        let b = VNode.element(ElementData(tag: "div", children: [.text("b"), .text("c")])).unmanagedChildren()
        let (_, u) = diffPair(a, b)
        #expect(u.patches == [])   // shell unchanged, children left alone
    }

    @Test("the element shell stays reactive (its own attributes still diff)") func shellStaysReactive() {
        let a = VNode.element(ElementData(tag: "div", attributes: ["class": "x"], children: [.text("a")])).unmanagedChildren()
        let b = VNode.element(ElementData(tag: "div", attributes: ["class": "y"], children: [.text("a")])).unmanagedChildren()
        let (_, u) = diffPair(a, b)
        #expect(u.patches == [.setAttribute(handle: 0, name: "class", value: "y")])
    }

    @Test("regression: a managed element still reconciles its children") func managedStillReconciles() {
        let a = VNode.element(ElementData(tag: "div", children: [.text("a")]))
        let b = VNode.element(ElementData(tag: "div", children: [.text("b")]))
        let (_, u) = diffPair(a, b)
        #expect(u.patches == [.setText(handle: 1, text: "b")])
    }
```

- [ ] **Step 2: Run them and confirm `reRenderSkipsChildren` / `shellStaysReactive` fail**

Run: `swift test --filter UnmanagedChildrenTests`
Expected: `mountsInitialChildrenOnce` and `managedStillReconciles` PASS (mount path + managed path unchanged); `reRenderSkipsChildren` FAILS (the diff currently reconciles children — emits `.setText(handle: 1, text: "b")`, `.createText…`, etc.) and `shellStaysReactive` FAILS (emits the class patch PLUS child patches).

- [ ] **Step 3: Guard the `diffChildren` call**

In `Sources/Swiflow/Diff/Diff.swift`, in the same-tag `.element` update arm (after the four bag diffs, ~line 379), wrap the `diffChildren(...)` call:

```swift
        // Escape hatch: an `.unmanagedChildren()` element owns its own subtree — Swiflow mounted
        // its initial children once and never reconciles inside it again. The shell (the four bags,
        // diffed above) stays reactive; only children are left alone, so foreign-managed DOM
        // (custom-element shadow/light children, a WASM-painted <canvas>, third-party widgets)
        // survives every re-render.
        if !newData.managesOwnChildren {
            diffChildren(
                mounted: mounted,
                newChildren: newData.children,
                handles: handles,
                handlers: handlers,
                into: &patches,
                scheduler: scheduler,
                parentPath: path,
                environment: environment
            )
        }
        mounted.vnode = next
        return mounted
```

- [ ] **Step 4: Run the suite and confirm green**

Run: `swift test --filter UnmanagedChildrenTests`
Expected: PASS (all 9 tests).

- [ ] **Step 5: Run the full core suite (no regression — this touches the diff hot path)**

Run: `swift test`
Expected: full suite green.

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/Diff/Diff.swift Tests/SwiflowTests/DiffTests/UnmanagedChildrenTests.swift
git commit -m "feat(core): diff skips children of .unmanagedChildren() elements

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: DOM-interop guide

**Files:**
- Create: `docs/guides/dom-interop.md`

- [ ] **Step 1: Write the guide**

Create `docs/guides/dom-interop.md`:

```markdown
# DOM interop: unmanaged children

Swiflow reconciles every element's children against its own virtual tree on each render. When an
element's interior is owned by *something else* — a custom element that builds its own shadow/light
DOM, a `<canvas>` painted by a foreign WASM module, or a third-party widget (chart, date picker,
map) that injects nodes — that reconciliation would stomp the foreign DOM. `.unmanagedChildren()`
is the escape hatch.

```swift
// A <canvas> a foreign module paints. Swiflow owns the element; the module owns the pixels.
let canvas = Ref<JSObject>()
element("canvas", attributes: [.attr("width", 640), .attr("height", 480)])
    .ref(canvas)
    .unmanagedChildren()
// in onAppear: hand `canvas.wrappedValue` to the draw loop.

// A custom element that builds its own shadow DOM.
element("my-widget", attributes: [.attr("kind", kind)]).unmanagedChildren()

// A third-party widget, with a placeholder until it loads.
element("div", children: [Spinner()]).ref(host).unmanagedChildren()
// in onAppear: thirdPartyChart(host.wrappedValue)  — replaces the spinner; Swiflow won't touch it.
```

## Semantics

Swiflow mounts the element and any **initially-declared** children exactly once. After that it keeps
reconciling the element **shell** — its attributes, properties, style, and handlers update reactively
— but **never reconciles the children** again. Foreign-added DOM is invisible to the diff and
survives every re-render. Unmounting the element removes the whole subtree natively.

## Contract

- **Keep it stable.** Give an unmanaged element a stable position (and a `key:` among siblings) so a
  sibling diff never destroys and remounts it — a remount re-runs your foreign init and loses foreign
  state.
- **Re-declared children are ignored.** Only the first mount's children are placed by Swiflow;
  everything after is the foreign owner's responsibility.
- **Don't toggle the flag** for an element position; keep it constant.
- **The shell stays reactive** — only the children are hands-off.
```

- [ ] **Step 2: Commit**

```bash
git add docs/guides/dom-interop.md
git commit -m "docs: DOM-interop guide for .unmanagedChildren()

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4 (OPTIONAL): Playwright e2e

> **Recommendation: skip unless the user wants browser-level proof.** The patch-level unit tests in
> Task 2 are the authoritative gate — "a re-render emits **no** child patches" means the browser
> physically cannot touch foreign children (the driver only acts on patches). An e2e would need a new
> example app (imperative DOM injection + a re-render trigger) + a Playwright config — disproportionate
> cost for a contract already fully captured at the patch level. If the user wants it, scope it as: a
> small example whose `onAppear` injects a marked-element child via JSObject, a button that bumps
> `@State` to force a re-render, and a spec asserting the injected node still exists after the click;
> run inline via an in-place config (edgecases-style) to avoid the `.e2e-cache/sw` race.

- [ ] (Only if requested) Build the example + config + spec; run inline after `swift build -c release --product swiflow`.

---

## Final verification (controller, after all tasks)

- [ ] `swift build` — clean.
- [ ] `swift test --filter UnmanagedChildrenTests` — green (9 tests).
- [ ] `swift test` — full core suite green (diff hot path untouched for managed elements).
- [ ] Dispatch a final code reviewer over the branch diff (this is a core diff change — worth a review pass).
- [ ] Use superpowers:finishing-a-development-branch → open PR from `feat/swiflow-unmanaged-children` (branched from origin/main) → **hold merge** until the user says "merge it — CI is green", then `gh pr merge <n> --admin --rebase`.

---

## Self-Review

- **Spec coverage:** flag on `ElementData` + `==` (T1); `.unmanagedChildren()` modifier + non-element no-op (T1); mount-once (T2 `mountsInitialChildrenOnce`); never-reconcile-children-on-update (T2 `reRenderSkipsChildren`); shell stays reactive (T2 `shellStaysReactive`); managed regression (T2 `managedStillReconciles`); no driver change (only `Diff.swift`/`VNode.swift`/`VNodeModifiers.swift` touched — no `js-driver/**`, no `Patch*`/serializer); contract + examples (T3). All covered.
- **Placeholder scan:** none — every code/test/doc block is complete.
- **Type/name consistency:** `managesOwnChildren` and `unmanagedChildren()` used identically across the data model, modifier, diff guard, and every test. Patch shapes (`.createElement`/`.createText`/`.appendChild`/`.setText`/`.setAttribute`) match the existing `Patch` API used in `FragmentChildrenTests`. Handle numbering (div=0, first child=1) matches `HandleAllocator`'s document-order allocation.
