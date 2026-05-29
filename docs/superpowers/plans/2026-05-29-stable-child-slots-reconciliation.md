# Stable Child Slots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every view-builder statement a stable child slot — `if`/`else`/`for` become a single transparent `.fragment` slot that holds its position even when empty — so toggling or looping a child can never recreate a sibling (the root of the "dialog vanishes when the toast auto-dismisses" bug).

**Architecture:** Add a pure-virtual `VNode.fragment([VNode])` (zero DOM nodes, structural handle, like `.environmentOverride`). `ChildrenBuilder` wraps `buildOptional`/`buildEither`/`buildArray` in one fragment each, making an element's top-level child count statically fixed. All DOM placement routes through three pure, total mount-tree functions — `firstDOMHandle`, `nextDOMAnchor`, `collectDOMRoots` — under two invariants (place right-to-left; one anchor rule everywhere). No new patch type, no JS-driver change.

**Tech Stack:** Swift, Swift Testing (`@Test`/`#expect`/`@Suite`), the existing Swiflow diff engine (`Sources/Swiflow/Diff`).

**Spec:** `docs/superpowers/specs/2026-05-29-stable-child-slots-reconciliation-design.md`

---

## Preamble — working-tree baseline

The working tree currently holds an **interim mitigation** (uncommitted): `examples/HelloWorld/Sources/App/App.swift` with the toast moved to the last child, a new Playwright test `Toast auto-dismiss does not close an open dialog` in `Tests/playwright/counter.spec.ts`, and a regenerated `Sources/SwiflowCLI/EmbeddedTemplates.swift`.

- [ ] **Commit the interim state as a clean baseline** so task execution starts from a clean tree (the framework fix will later move the toast back to the middle to *prove* order-independence — Task 6):

```bash
git add examples/HelloWorld/Sources/App/App.swift Tests/playwright/counter.spec.ts Sources/SwiflowCLI/EmbeddedTemplates.swift
git commit -m "fix(examples): interim — keep conditional toast last so it can't shift the dialog slot

Superseded by the stable-child-slots framework fix; kept as a baseline. The
new e2e regression test stays permanently."
```

---

## File Structure

**Create:**
- `Tests/SwiflowTests/DiffTests/DOMAnchorPrimitivesTests.swift` — unit tests for `firstDOMHandle` / `nextDOMAnchor` / `collectDOMRoots`.
- `Tests/SwiflowTests/DiffTests/FragmentChildrenTests.swift` — mount/update/destroy behavior for fragment slots, incl. the sibling-preservation regression.
- `Tests/SwiflowTests/DSLTests/FragmentBuilderTests.swift` — `ChildrenBuilder` emits one fragment slot per `if`/`for`.

**Modify:**
- `Sources/Swiflow/VNode.swift` — add `.fragment` case + `Equatable` arm.
- `Sources/Swiflow/Diff/DOMAnchors.swift` — **new file** for the three primitives (keeps `Diff.swift` focused).
- `Sources/Swiflow/Diff/Diff.swift` — `mount`/`update`/`destroy`/`diagKeyAndIsKeyable`/`domAncestorHandle` fragment arms; element-append via `collectDOMRoots`.
- `Sources/Swiflow/Diff/IndexedChildrenDiff.swift` — route placement through primitives.
- `Sources/Swiflow/Diff/KeyedChildrenDiff.swift` — route placement through primitives; fix `keyOf` to honor component keys.
- `Sources/Swiflow/DSL/ResultBuilder.swift` — wrap dynamic constructs in `.fragment`.
- `examples/HelloWorld/Sources/App/App.swift` — move toast back to the middle (Task 6).
- `CHANGELOG.md` — Unreleased entry.

---

## Task 1: Add `.fragment` VNode case + DOM-anchor primitives + mount/destroy support

**Files:**
- Modify: `Sources/Swiflow/VNode.swift`
- Create: `Sources/Swiflow/Diff/DOMAnchors.swift`
- Modify: `Sources/Swiflow/Diff/Diff.swift`
- Create: `Tests/SwiflowTests/DiffTests/DOMAnchorPrimitivesTests.swift`
- Create: `Tests/SwiflowTests/DiffTests/FragmentChildrenTests.swift`

Swift's exhaustiveness forces every `VNode` switch to handle the new case in the same commit. This task adds the case, the primitives, first-mount support, and destroy support. `ChildrenBuilder` is NOT changed yet, so nothing auto-produces fragments — behavior is unchanged for existing trees and tested via directly-constructed `.fragment` VNodes.

- [ ] **Step 1: Add the `.fragment` case and its `Equatable` arm**

In `Sources/Swiflow/VNode.swift`, add to the enum (after `.environmentOverride`):

```swift
    /// A transparent grouping of children with no DOM element of its own — the
    /// runtime form of a builder `if` / `if-else` / `for`. It occupies exactly
    /// one stable child slot among its siblings (so toggling/looping never
    /// shifts a sibling) while its children render directly into the nearest
    /// real DOM ancestor. Produced only by `ChildrenBuilder`; pure-virtual
    /// (emits no create/destroy patch — like `.environmentOverride`).
    case fragment([VNode])
```

And in the `Equatable` switch, add before `default`:

```swift
        case (.fragment(let a), .fragment(let b)): return a == b
```

- [ ] **Step 2: Run the build to find every non-exhaustive switch**

Run: `swift build 2>&1 | grep -v "Internal Error: DecodingError" | grep -iE "error|switch must be exhaustive" | head`
Expected: errors in `Diff.swift` (`mount`, `update`, `destroy`, `diagKeyAndIsKeyable`) — these are filled in below. (`VNodeModifiers.swift` uses `if case .element`, so it needs no change. `keyOf`/`hasAnyKey` use `if case .element`, no change.)

- [ ] **Step 3: Write the failing primitives unit test**

Create `Tests/SwiflowTests/DiffTests/DOMAnchorPrimitivesTests.swift`:

```swift
// Tests/SwiflowTests/DiffTests/DOMAnchorPrimitivesTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — DOM-anchor primitives")
@MainActor
struct DOMAnchorPrimitivesTests {
    // Mount a VNode to a real MountNode tree so primitives have something to walk.
    private func mountTree(_ v: VNode) -> MountNode {
        var patches: [Patch] = []
        return mount(v, into: &patches, handles: HandleAllocator(), handlers: HandlerRegistry())
    }

    @Test("collectDOMRoots of an element is its own handle")
    func rootsOfElement() {
        let n = mountTree(.element(ElementData(tag: "div")))
        #expect(collectDOMRoots(n) == [n.handle])
    }

    @Test("collectDOMRoots descends through a fragment to its children")
    func rootsThroughFragment() {
        // ul(handle 0) > fragment(handle 1) > [text"a"(2), text"b"(3)]
        let ul = mountTree(.element(ElementData(tag: "ul", children: [
            .fragment([.text("a"), .text("b")])
        ])))
        #expect(collectDOMRoots(ul) == [ul.handle])
        let frag = ul.children[0]
        #expect(collectDOMRoots(frag) == [2, 3])
    }

    @Test("firstDOMHandle of an empty fragment is nil")
    func firstOfEmptyFragment() {
        let ul = mountTree(.element(ElementData(tag: "ul", children: [.fragment([])])))
        #expect(firstDOMHandle(ul.children[0]) == nil)
    }

    @Test("nextDOMAnchor after a fragment's last child ascends to the next real sibling")
    func anchorAscendsAcrossFragmentBoundary() {
        // ul > [ fragment[textA(2)], div(3) ]
        let ul = mountTree(.element(ElementData(tag: "ul", children: [
            .fragment([.text("a")]),
            .element(ElementData(tag: "div")),
        ])))
        let frag = ul.children[0]
        let textA = frag.children[0]
        // After textA (last in fragment) the next DOM node is the div (handle 3).
        #expect(nextDOMAnchor(after: textA) == 3)
    }

    @Test("nextDOMAnchor returns nil (append) at the true tail across an empty trailing fragment")
    func anchorTailWithEmptyFragment() {
        // ul > [ div(1), fragment[](2) ]
        let ul = mountTree(.element(ElementData(tag: "ul", children: [
            .element(ElementData(tag: "div")),
            .fragment([]),
        ])))
        let div = ul.children[0]
        #expect(nextDOMAnchor(after: div) == nil)  // empty fragment after → append
    }
}
```

- [ ] **Step 4: Run it to confirm it fails to compile (primitives undefined)**

Run: `swift test --filter DOMAnchorPrimitivesTests 2>&1 | grep -iE "error|cannot find" | head`
Expected: "cannot find 'collectDOMRoots'/'firstDOMHandle'/'nextDOMAnchor' in scope".

- [ ] **Step 5: Implement the three primitives**

Create `Sources/Swiflow/Diff/DOMAnchors.swift`:

```swift
// Sources/Swiflow/Diff/DOMAnchors.swift
//
// The three pure, total functions through which ALL fragment-aware DOM
// placement flows. Keeping placement behind these (and always placing
// right-to-left — see KeyedChildrenDiff/IndexedChildrenDiff) is what makes
// pure-virtual fragments rock-solid: empty/nested fragments simply yield no
// handle and are skipped, never mispositioned. See the design spec §3.3.

/// True for structural mount nodes that have NO DOM element of their own:
/// component anchors, environment-override anchors, and fragments. Their DOM
/// presence is their descendants'.
@MainActor
func isStructural(_ node: MountNode) -> Bool {
    if node.component != nil { return true }
    switch node.vnode {
    case .environmentOverride, .fragment: return true
    case .element, .text, .rawHTML, .component: return false
    }
}

/// All top-level real DOM-node handles of a subtree, in document order,
/// descending through structural nodes. For a single-node slot this is just
/// `[node.handle]`, so existing single-root call sites generalize unchanged.
@MainActor
func collectDOMRoots(_ node: MountNode) -> [Int] {
    switch node.vnode {
    case .element, .text, .rawHTML:
        return [node.handle]
    case .component, .environmentOverride:
        // Single-rooted body lives in the componentBody slot.
        return node.componentBody.map(collectDOMRoots) ?? []
    case .fragment:
        return node.children.flatMap(collectDOMRoots)
    }
}

/// First real DOM-node handle of a subtree, or nil if it contributes none
/// (e.g. an empty fragment). Short-circuits without building the full list.
@MainActor
func firstDOMHandle(_ node: MountNode) -> Int? {
    switch node.vnode {
    case .element, .text, .rawHTML:
        return node.handle
    case .component, .environmentOverride:
        return node.componentBody.flatMap(firstDOMHandle)
    case .fragment:
        for child in node.children {
            if let h = firstDOMHandle(child) { return h }
        }
        return nil
    }
}

/// The handle that should come immediately AFTER everything `node` owns — the
/// `beforeChild` for an `insertBefore`, or nil to append. Scans forward among
/// `node`'s siblings; if none yields a DOM node and the parent is itself
/// structural (a fragment), ascends and continues among the parent's siblings.
/// Stops (returns nil = append) on reaching a real-element parent with nothing
/// after it. Relies on callers placing right-to-left so siblings to the right
/// are already in their final DOM position.
@MainActor
func nextDOMAnchor(after node: MountNode) -> Int? {
    var current = node
    while let parent = current.parent {
        guard let idx = parent.children.firstIndex(where: { $0 === current }) else { return nil }
        var i = idx + 1
        while i < parent.children.count {
            if let h = firstDOMHandle(parent.children[i]) { return h }
            i += 1
        }
        // Nothing after `current` at this level. A fragment parent is
        // transparent, so the search continues among the fragment's siblings.
        if case .fragment = parent.vnode {
            current = parent
            continue
        }
        return nil   // real-element (or other single-root) parent → append
    }
    return nil
}
```

- [ ] **Step 6: Add `mount`/`destroy`/`diag`/`domAncestor` fragment arms + element-append via `collectDOMRoots`**

In `Sources/Swiflow/Diff/Diff.swift`:

(a) `diagKeyAndIsKeyable` — add a `.fragment` arm (a fragment is a structural slot, never keyed at its own level):

```swift
    case .fragment: return (nil, false)
```

(b) `mount` — add a `.fragment` case (after the `.environmentOverride` case). It allocates a structural handle, mounts children into the fragment node, and emits **no create/append for itself** (the parent's append loop places its DOM roots):

```swift
    case .fragment(let children):
        let h = handles.next()                       // structural handle (never sent to driver)
        let node = MountNode(handle: h, vnode: vnode)
        for (i, childVNode) in children.enumerated() {
            let childPath = path.isEmpty ? String(i) : "\(path).\(i)"
            let childMount = mount(
                childVNode, into: &patches, handles: handles, handlers: handlers,
                scheduler: scheduler, depth: depth, path: childPath, environment: environment
            )
            node.addChild(childMount)
        }
        return node
```

(c) `mount` element child-append loop — replace the single-handle append (currently `patches.append(.appendChild(parent: h, child: childMount.domHandle))`) with a fragment-aware append:

```swift
            for root in collectDOMRoots(childMount) {
                patches.append(.appendChild(parent: h, child: root))
            }
            mountNode.addChild(childMount)
```

(d) `destroy` — fragments emit no `destroyNode` for their structural handle (mirror `.environmentOverride`). In the final emit guard, extend the structural check:

```swift
        } else if case .fragment = node.vnode {
            // Structural handle — no destroyNode patch; children handled below.
        } else if node.handle != skipDestroyForHandle {
```

(`destroy` already recurses `node.children`, which holds the fragment's children, so they are torn down.)

(e) `domAncestorHandle` — add fragments to the skipped structural kinds. In the `while` body, alongside the `environmentOverride` skip:

```swift
        } else if case .fragment = candidate.vnode {
            // Fragment — structural handle, skip.
```

- [ ] **Step 7: Add the `update(.fragment, .fragment)` arm**

In `Sources/Swiflow/Diff/Diff.swift` `update(...)`, add an arm before `default:`. It reconciles the fragment's children through the existing `diffChildren` dispatch:

```swift
    // Fragment → fragment: reconcile the held children. The fragment itself is
    // a structural slot with no DOM node, so there is nothing to patch at this
    // level; child placement flows through the DOM-anchor primitives.
    case (.fragment, .fragment(let newChildren)):
        diffChildren(
            mounted: mounted,
            newChildren: newChildren,
            handles: handles,
            handlers: handlers,
            into: &patches,
            scheduler: scheduler,
            parentPath: path,
            environment: environment
        )
        mounted.vnode = next
        return mounted
```

(Cross-kind transitions like element↔fragment fall through to the existing `default:` destroy+remount arm — correct, because a slot's *kind* never changes across renders once the builder is in place, but the safety net stays valid.)

- [ ] **Step 8: Write the first-mount fragment test**

Create `Tests/SwiflowTests/DiffTests/FragmentChildrenTests.swift`:

```swift
// Tests/SwiflowTests/DiffTests/FragmentChildrenTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — fragment children")
@MainActor
struct FragmentChildrenTests {
    private func diffPair(_ a: VNode, _ b: VNode) -> DiffResult {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: a, handles: handles, handlers: handlers)
        return diff(mounted: m.newMountTree, next: b, handles: handles, handlers: handlers)
    }
    private func mountOnly(_ a: VNode) -> DiffResult {
        diff(mounted: nil, next: a, handles: HandleAllocator(), handlers: HandlerRegistry())
    }

    @Test("First mount: a fragment child's nodes append to the fragment's real parent")
    func firstMountFragment() {
        // div(0) > fragment(1) > [text"a"(2), text"b"(3)]
        let r = mountOnly(.element(ElementData(tag: "div", children: [
            .fragment([.text("a"), .text("b")])
        ])))
        #expect(r.patches == [
            .createElement(handle: 0, tag: "div"),
            .createText(handle: 2, text: "a"),
            .createText(handle: 3, text: "b"),
            .appendChild(parent: 0, child: 2),
            .appendChild(parent: 0, child: 3),
        ])
    }
}
```

- [ ] **Step 9: Run the tests**

Run: `swift test --filter "DOMAnchorPrimitivesTests|FragmentChildrenTests" 2>&1 | grep -v "Internal Error: DecodingError" | grep -iE "Test run|✘|passed|failed"`
Expected: all pass.

- [ ] **Step 10: Full build + existing diff suite (no regressions)**

Run: `swift build 2>&1 | grep -v "Internal Error: DecodingError" | tail -2 && swift test --filter DiffTests 2>&1 | grep -v "Internal Error: DecodingError" | grep -iE "Test run|✘|failed"`
Expected: build complete; all DiffTests pass (existing trees never contain fragments, so unaffected).

- [ ] **Step 11: Commit**

```bash
git add Sources/Swiflow/VNode.swift Sources/Swiflow/Diff/DOMAnchors.swift Sources/Swiflow/Diff/Diff.swift Tests/SwiflowTests/DiffTests/DOMAnchorPrimitivesTests.swift Tests/SwiflowTests/DiffTests/FragmentChildrenTests.swift
git commit -m "feat(diff): add VNode.fragment + DOM-anchor primitives + mount/destroy support"
```

---

## Task 2: Route the indexed child-diff through the primitives

**Files:**
- Modify: `Sources/Swiflow/Diff/IndexedChildrenDiff.swift`
- Modify: `Tests/SwiflowTests/DiffTests/FragmentChildrenTests.swift`

Makes empty↔full fragment transitions and a mid-list fragment slot correct under the indexed path, including the sibling-preservation regression.

- [ ] **Step 1: Write the failing regression + transition tests**

Append to `Tests/SwiflowTests/DiffTests/FragmentChildrenTests.swift` (inside the suite):

```swift
    @Test("Mid-list fragment emptying preserves a later sibling's handle (the dialog/toast bug)")
    func midListFragmentEmptyingPreservesSibling() {
        // div > [ p(stable), fragment[span], p(stable-after) ]  →  fragment goes empty
        let full = VNode.element(ElementData(tag: "div", children: [
            .element(ElementData(tag: "p")),
            .fragment([.element(ElementData(tag: "span"))]),
            .element(ElementData(tag: "p", key: "after")),
        ]))
        let empty = VNode.element(ElementData(tag: "div", children: [
            .element(ElementData(tag: "p")),
            .fragment([]),
            .element(ElementData(tag: "p", key: "after")),
        ]))
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: full, handles: handles, handlers: handlers)
        // Handles: div0, p1, frag2, span3, p("after")4.
        let afterBefore = m.newMountTree.children[2].handle
        let u = diff(mounted: m.newMountTree, next: empty, handles: handles, handlers: handlers)
        // The span (3) is removed; the trailing <p> keeps handle 4 — NOT recreated.
        #expect(u.patches == [
            .removeChild(parent: 0, child: 3),
            .destroyNode(handle: 3),
        ])
        #expect(u.newMountTree.children[2].handle == afterBefore)
        #expect(u.newMountTree.children[2].handle == 4)
    }

    @Test("Empty fragment refilling inserts before the correct following sibling")
    func emptyFragmentRefilling() {
        // div > [ fragment[](1), div"tail"(2) ]  →  fragment gains a span
        let empty = VNode.element(ElementData(tag: "div", children: [
            .fragment([]),
            .element(ElementData(tag: "div", key: "tail")),
        ]))
        let full = VNode.element(ElementData(tag: "div", children: [
            .fragment([.element(ElementData(tag: "span"))]),
            .element(ElementData(tag: "div", key: "tail")),
        ]))
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: empty, handles: handles, handlers: handlers)
        // Handles: div0, frag1, divtail2.
        let u = diff(mounted: m.newMountTree, next: full, handles: handles, handlers: handlers)
        // New span (handle 3) must insertBefore the tail div (2), not append.
        #expect(u.patches == [
            .createElement(handle: 3, tag: "span"),
            .insertBefore(parent: 0, child: 3, beforeChild: 2),
        ])
    }
```

- [ ] **Step 2: Run to confirm failure**

Run: `swift test --filter FragmentChildrenTests 2>&1 | grep -v "Internal Error: DecodingError" | grep -iE "✘|failed|expectation"`
Expected: both new tests fail — the indexed diff currently reads `fragment.domHandle` (the structural handle) for placement, producing wrong anchors / extra patches.

- [ ] **Step 3: Rewrite `diffChildrenIndexed` to route through the primitives**

Replace the body of `diffChildrenIndexed` in `Sources/Swiflow/Diff/IndexedChildrenDiff.swift` with the fragment-aware version. Key changes: cross-kind replacement detaches via `collectDOMRoots(oldChild)` and re-places via `nextDOMAnchor`; surplus appends use `nextDOMAnchor` + per-root placement; surplus removals use `collectDOMRoots`.

```swift
@MainActor
func diffChildrenIndexed(
    mounted: MountNode,
    newChildren: [VNode],
    handles: HandleAllocator,
    handlers: HandlerRegistry,
    into patches: inout [Patch],
    scheduler: Scheduler? = nil,
    parentPath: String = "",
    environment: EnvironmentValues = .init()
) {
    let oldCount = mounted.children.count
    let newCount = newChildren.count
    let commonCount = min(oldCount, newCount)

    // 1. Reconcile common prefix (left-to-right is safe here: a same-kind
    //    update never changes a node's position; only a cross-kind replace
    //    re-places, and it re-places against the already-correct next sibling).
    for i in 0..<commonCount {
        let oldChild = mounted.children[i]
        let oldRoots = collectDOMRoots(oldChild)
        let updatePatchStart = patches.count
        let childPath = parentPath.isEmpty ? String(i) : "\(parentPath).\(i)"
        let newChild = update(
            mounted: oldChild, next: newChildren[i], into: &patches,
            handles: handles, handlers: handlers, scheduler: scheduler,
            path: childPath, environment: environment
        )
        if newChild !== oldChild {
            // Cross-kind replace: detach every old DOM root before its handle is
            // dropped, swap the slot, then place the new node's roots before the
            // next sibling's first DOM node (or append).
            for root in oldRoots {
                patches.insert(.removeChild(parent: mounted.handle, child: root), at: updatePatchStart)
            }
            mounted.replaceChild(at: i, with: newChild)
            let anchor = nextDOMAnchor(after: newChild)
            for root in collectDOMRoots(newChild) {
                if let before = anchor {
                    patches.append(.insertBefore(parent: mounted.handle, child: root, beforeChild: before))
                } else {
                    patches.append(.appendChild(parent: mounted.handle, child: root))
                }
            }
        }
    }

    // 2. Append surplus new children.
    if newCount > oldCount {
        for i in oldCount..<newCount {
            let childPath = parentPath.isEmpty ? String(i) : "\(parentPath).\(i)"
            let childMount = mount(
                newChildren[i], into: &patches, handles: handles,
                handlers: handlers, scheduler: scheduler, path: childPath,
                environment: environment
            )
            mounted.addChild(childMount)
            let anchor = nextDOMAnchor(after: childMount)
            for root in collectDOMRoots(childMount) {
                if let before = anchor {
                    patches.append(.insertBefore(parent: mounted.handle, child: root, beforeChild: before))
                } else {
                    patches.append(.appendChild(parent: mounted.handle, child: root))
                }
            }
        }
    }

    // 3. Remove surplus old children (forward document order).
    if oldCount > newCount {
        for _ in newCount..<oldCount {
            let removed = mounted.children[newCount]
            if let comp = removed.component,
               let anim = type(of: comp.instance).exitAnimation {
                let durMs = (type(of: comp.instance).exitDuration ?? 0) * 1000
                patches.append(.animateExit(
                    handle: removed.domHandle, parentHandle: mounted.handle,
                    animation: anim, durationMs: durMs))
                destroy(removed, into: &patches, handlers: handlers, skipDestroyForHandle: removed.domHandle)
            } else {
                for root in collectDOMRoots(removed) {
                    patches.append(.removeChild(parent: mounted.handle, child: root))
                }
                destroy(removed, into: &patches, handlers: handlers)
            }
            mounted.removeChild(at: newCount)
        }
    }
}
```

> Note: `nextDOMAnchor(after:)` requires the node to already be in `mounted.children` with its parent pointer set — `addChild`/`replaceChild` do this before the anchor is computed above, which is why placement follows mutation.

- [ ] **Step 4: Run the fragment tests**

Run: `swift test --filter FragmentChildrenTests 2>&1 | grep -v "Internal Error: DecodingError" | grep -iE "Test run|✘|failed"`
Expected: all pass.

- [ ] **Step 5: Run the full indexed suite (no regressions)**

Run: `swift test --filter "IndexedChildrenTests|FirstMountTests|TagReplaceTests" 2>&1 | grep -v "Internal Error: DecodingError" | grep -iE "Test run|✘|failed"`
Expected: all pass (non-fragment children: `collectDOMRoots` returns `[domHandle]`, so emitted patches are identical to before).

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/Diff/IndexedChildrenDiff.swift Tests/SwiflowTests/DiffTests/FragmentChildrenTests.swift
git commit -m "feat(diff): route indexed child diff through DOM-anchor primitives (fragment-safe)"
```

---

## Task 3: Route the keyed child-diff through the primitives + honor component keys

**Files:**
- Modify: `Sources/Swiflow/Diff/KeyedChildrenDiff.swift`
- Modify: `Tests/SwiflowTests/DiffTests/FragmentChildrenTests.swift`

A `for`-fragment's children use the keyed path; it must position fragment-bearing siblings correctly and match keyed components.

- [ ] **Step 1: Write failing tests — fragment inside a keyed list, and component-key matching**

Append to `FragmentChildrenTests.swift`:

```swift
    @Test("Keyed list with a fragment sibling: reordering keyed elements keeps handles")
    func keyedListWithFragmentSibling() {
        // ul > [ li#a(key a), fragment[li x], li#b(key b) ] → swap a and b
        func tree(_ order: [String]) -> VNode {
            .element(ElementData(tag: "ul", children: [
                .element(ElementData(tag: "li", key: order[0])),
                .fragment([.element(ElementData(tag: "li"))]),
                .element(ElementData(tag: "li", key: order[1])),
            ]))
        }
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: tree(["a", "b"]), handles: handles, handlers: handlers)
        // ul0, li#a 1, frag2, li(x)3, li#b 4
        let u = diff(mounted: m.newMountTree, next: tree(["b", "a"]), handles: handles, handlers: handlers)
        // No createElement — both keyed <li>s are reused (handles 1 and 4 preserved).
        #expect(!u.patches.contains { if case .createElement = $0 { return true }; return false })
    }
```

- [ ] **Step 2: Confirm failure**

Run: `swift test --filter "keyedListWithFragmentSibling" 2>&1 | grep -v "Internal Error: DecodingError" | grep -iE "✘|failed"`
Expected: fails — keyed diff reads `mounted.children[oldEnd + 1].domHandle` and `newSlice[i+1]!.domHandle` directly, mis-anchoring around the fragment.

- [ ] **Step 3: Replace `.domHandle` anchor reads with the primitives in `KeyedChildrenDiff.swift`**

Make these edits in `Sources/Swiflow/Diff/KeyedChildrenDiff.swift`:

(a) **Prefix scan cross-kind replace** (~lines 85-102): replace the `removeChild(child: oldHandle)` + `insertBefore/appendChild` block. Capture `let oldRoots = collectDOMRoots(oldChild)` before `update`, then:

```swift
            for root in oldRoots {
                patches.insert(.removeChild(parent: mounted.handle, child: root), at: updatePatchStart)
            }
            mounted.replaceChild(at: oldStart, with: updated)
            let anchor = nextDOMAnchor(after: updated)
            for root in collectDOMRoots(updated) {
                if let before = anchor {
                    patches.append(.insertBefore(parent: mounted.handle, child: root, beforeChild: before))
                } else {
                    patches.append(.appendChild(parent: mounted.handle, child: root))
                }
            }
```

(b) **Suffix scan cross-kind replace** (~lines 126-147): same transformation, capturing `oldRoots` from `mounted.children[oldEnd]` before `update` and placing via `nextDOMAnchor(after: updated)`.

(c) **Pure inserts** (~lines 159-186): the block computes `beforeHandle` from `mounted.children[oldStart].domHandle`. Replace per-insert placement with the primitive. After `mounted.insertChild(child, at: insertIndex)`, place:

```swift
            let anchor = nextDOMAnchor(after: child)
            for root in collectDOMRoots(child) {
                if let before = anchor {
                    patches.append(.insertBefore(parent: mounted.handle, child: root, beforeChild: before))
                } else {
                    patches.append(.appendChild(parent: mounted.handle, child: root))
                }
            }
```

(delete the now-unused `beforeHandle`/`insertIndex` anchor logic; keep `insertIndex` only for the `insertChild(at:)` position.)

(d) **Pure removes** (~lines 190-211) and **map-middle leftover destroy** (~lines 292-310): replace `removeChild(child: removed.domHandle)` / `removeChild(child: leftover.domHandle)` with a per-root loop:

```swift
                for root in collectDOMRoots(removed) {
                    patches.append(.removeChild(parent: mounted.handle, child: root))
                }
```

(Leave the `animateExit` branches keyed on `removed.domHandle` — exit animation targets a single component body, which is single-rooted.)

(e) **Map-middle placement loop** (~lines 322-349): the right-to-left loop computes `anchor` from `newSlice[i + 1]!.domHandle` / `mounted.children[oldEnd + 1].domHandle`. Replace both placement branches' anchor with `nextDOMAnchor(after: node)` and place each root:

```swift
        let anchor = nextDOMAnchor(after: node)
        let mustPlace = (newToOldIndex[i] == -1) || !lisSet.contains(i)
        if mustPlace {
            for root in collectDOMRoots(node) {
                if let before = anchor {
                    patches.append(.insertBefore(parent: mounted.handle, child: root, beforeChild: before))
                } else {
                    patches.append(.appendChild(parent: mounted.handle, child: root))
                }
            }
        }
```

(This preserves the existing "fresh mount OR out-of-LIS → place; in-LIS → skip" logic; only the anchor source and per-root placement change. The right-to-left walk already satisfies Invariant A.)

- [ ] **Step 4: Fix `keyOf` to honor component keys**

In `KeyedChildrenDiff.swift`, update both `keyOf` overloads so a keyed `.component` matches across renders:

```swift
func keyOf(_ node: MountNode) -> String {
    switch node.vnode {
    case .element(let data): if let k = data.key { return k }
    case .component(let desc): if let k = desc.key { return k }
    default: break
    }
    return "__noKey_\(node.handle)"
}

func keyOf(_ vnode: VNode) -> String {
    switch vnode {
    case .element(let data): if let k = data.key { return k }
    case .component(let desc): if let k = desc.key { return k }
    default: break
    }
    return "__noKey_unkeyed"
}
```

Also update `hasAnyKey([VNode])` and `hasAnyKey([MountNode])` in `Diff.swift` to count `.component` keys, so a keyed-component list takes the keyed path:

```swift
func hasAnyKey(_ vnodes: [VNode]) -> Bool {
    for v in vnodes {
        if case .element(let d) = v, d.key != nil { return true }
        if case .component(let d) = v, d.key != nil { return true }
    }
    return false
}
```
(and the symmetric `MountNode` overload, switching on `n.vnode`.)

- [ ] **Step 5: Run keyed + fragment tests**

Run: `swift test --filter "KeyedChildrenTests|KeyedCrossKindTests|KeyedMapMiddleCrossKindTests|FragmentChildrenTests" 2>&1 | grep -v "Internal Error: DecodingError" | grep -iE "Test run|✘|failed"`
Expected: all pass.

- [ ] **Step 6: Full unit suite**

Run: `swift test 2>&1 | grep -v "Internal Error: DecodingError" | grep -iE "Test run with|✘|failed" | tail`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/Swiflow/Diff/KeyedChildrenDiff.swift Sources/Swiflow/Diff/Diff.swift Tests/SwiflowTests/DiffTests/FragmentChildrenTests.swift
git commit -m "feat(diff): route keyed child diff through DOM-anchor primitives; match component keys"
```

---

## Task 4: Flip `ChildrenBuilder` to emit fragment slots

**Files:**
- Modify: `Sources/Swiflow/DSL/ResultBuilder.swift`
- Create: `Tests/SwiflowTests/DSLTests/FragmentBuilderTests.swift`

Now the DSL produces fragments: `if`/`else`/`for` each become exactly one `.fragment` slot.

- [ ] **Step 1: Write the failing builder tests**

Create `Tests/SwiflowTests/DSLTests/FragmentBuilderTests.swift`:

```swift
// Tests/SwiflowTests/DSLTests/FragmentBuilderTests.swift
import Testing
@testable import Swiflow

@Suite("DSL — fragment slots")
@MainActor
struct FragmentBuilderTests {
    @Test("A false `if` produces one empty fragment slot, not zero children")
    func falseIfIsOneEmptySlot() {
        let show = false
        let v: VNode = div {
            p("always")
            if show { p("maybe") }
        }
        guard case .element(let data) = v else { Issue.record("expected element"); return }
        #expect(data.children.count == 2)              // <p> + fragment slot
        guard case .fragment(let inner) = data.children[1] else { Issue.record("slot 1 not a fragment"); return }
        #expect(inner.isEmpty)
    }

    @Test("A true `if` produces one fragment slot holding its content")
    func trueIfIsOneFullSlot() {
        let show = true
        let v: VNode = div {
            p("always")
            if show { p("maybe") }
        }
        guard case .element(let data) = v, case .fragment(let inner) = data.children[1] else {
            Issue.record("expected element with fragment slot"); return
        }
        #expect(inner.count == 1)
        #expect(data.children.count == 2)
    }

    @Test("A for-loop produces one fragment slot holding all items")
    func forLoopIsOneSlot() {
        let v: VNode = ul {
            for i in 0..<3 { li("\(i)") }
        }
        guard case .element(let data) = v else { Issue.record("expected element"); return }
        #expect(data.children.count == 1)             // one fragment slot for the loop
        guard case .fragment(let inner) = data.children[0] else { Issue.record("not a fragment"); return }
        #expect(inner.count == 3)
    }
}
```

(Confirm the helper factory names `div`/`p`/`ul`/`li` exist in `Sources/Swiflow/DSL/Elements.swift`; they do.)

- [ ] **Step 2: Confirm failure**

Run: `swift test --filter FragmentBuilderTests 2>&1 | grep -v "Internal Error: DecodingError" | grep -iE "✘|failed|expectation"`
Expected: fails — `buildOptional`/`buildArray` currently flatten, so `children.count`/`.fragment` expectations don't hold.

- [ ] **Step 3: Wrap dynamic constructs in `.fragment`**

In `Sources/Swiflow/DSL/ResultBuilder.swift`, change four methods:

```swift
    public static func buildOptional(_ component: [VNode]?) -> [VNode] {
        [.fragment(component ?? [])]
    }

    public static func buildEither(first component: [VNode]) -> [VNode] {
        [.fragment(component)]
    }

    public static func buildEither(second component: [VNode]) -> [VNode] {
        [.fragment(component)]
    }

    public static func buildArray(_ children: [[VNode]]) -> [VNode] {
        [.fragment(children.flatMap { $0 })]
    }
```

Update the doc comments to state the slot-stability contract (one slot per construct).

- [ ] **Step 4: Run builder tests**

Run: `swift test --filter FragmentBuilderTests 2>&1 | grep -v "Internal Error: DecodingError" | grep -iE "Test run|✘|failed"`
Expected: all pass.

- [ ] **Step 5: Full unit suite — fix any DSL-driven handle expectations**

Run: `swift test 2>&1 | grep -v "Internal Error: DecodingError" | grep -iE "Test run with|✘|failed" | tail -20`
Expected: all pass. **If** any test that builds trees via the DSL (not via direct `ElementData`) asserts exact handles or child counts, it now sees fragment slots — update those expectations to account for one fragment slot per `if`/`for` (a fragment consumes one handle and adds one child-array entry). Direct-`ElementData` tests are unaffected.

- [ ] **Step 6: Commit**

```bash
git add Sources/Swiflow/DSL/ResultBuilder.swift Tests/SwiflowTests/DSLTests/FragmentBuilderTests.swift
git commit -m "feat(dsl): ChildrenBuilder emits one stable fragment slot per if/else/for"
```

---

## Task 5: Prove order-independence end-to-end + docs

> **No runtime loop-keys diagnostic.** We considered firing `swiflowDiagnostic`
> when an unkeyed fragment changes child count, but `swiflowDiagnostic`
> `preconditionFailure`s in DEBUG (it is a crash, not a soft warning), and an
> unkeyed *append-only* loop is perfectly valid — a count-change signal cannot
> distinguish legitimate append from identity-losing reorder without keys, so it
> would crash well-formed apps. The "key your `for` items" rule is taught via the
> CHANGELOG entry below and the spec; the genuinely-wrong case (mixing keyed and
> unkeyed siblings) is already caught by the existing `diffChildren` diagnostic.

**Files:**
- Modify: `examples/HelloWorld/Sources/App/App.swift`
- Modify: `Sources/SwiflowCLI/EmbeddedTemplates.swift` (regenerated)
- Modify: `CHANGELOG.md`

The interim mitigation moved the toast last. With the framework fix, move it back to the middle — the existing e2e regression test ("Toast auto-dismiss does not close an open dialog") now passes *because of the framework*, proving order-independence.

- [ ] **Step 1: Move the conditional toast back to the middle**

In `examples/HelloWorld/Sources/App/App.swift`, move the `if showToast { embed { Toast(...) } }` block back to its original position (between the `details` inspector and `embed { AboutPopover() }`), and replace the "keep it last" comment with:

```swift
            // The toast is a conditional child; it can sit anywhere now. Stable
            // child slots (ChildrenBuilder wraps each `if`/`for` in one
            // `.fragment` slot) mean toggling it off never shifts the dialog's
            // slot, so the dialog is never recreated. See
            // docs/superpowers/specs/2026-05-29-stable-child-slots-reconciliation-design.md
            if showToast {
                embed { Toast(message: "Saved!", onDone: { self.showToast = false }) }
            }
```

- [ ] **Step 2: Regenerate embedded templates + verify freshness**

```bash
swift scripts/embed-templates.swift
swift test --filter TemplateEmbedder 2>&1 | grep -v "Internal Error: DecodingError" | grep -iE "Test run|bit-for-bit|✘|failed"
```
Expected: regenerated; freshness test passes.

- [ ] **Step 3: Rebuild the release CLI and run the counter e2e**

Port 3000 must be free (stop any dev server). Then:

```bash
swift build -c release --product swiflow 2>&1 | grep -v "Internal Error: DecodingError" | tail -2
cd Tests/playwright && npm run test:counter 2>&1 | tail -20; cd ../..
```
Expected: 12/12 pass — including "Toast auto-dismiss does not close an open dialog" with the toast back in the middle (proves the framework fix, not the ordering, is what protects the dialog).

- [ ] **Step 4: Add the CHANGELOG entry**

In `CHANGELOG.md` under `## [Unreleased]` → `### Fixed`, add:

```markdown
- **Stable child slots — conditional/looped children no longer corrupt siblings.** Each view-builder statement is now one stable child slot: `if`/`else`/`for` compile to a single transparent `.fragment` that holds its position even when empty. Previously a conditional child rendered *before* a stateful sibling (e.g. a `<dialog>`) would shift sibling indices when it unmounted, recreating the sibling — which is why the Sign In dialog vanished when the toast auto-dismissed. The dev-facing rule, as plain as the Rules of Hooks: *every statement is a stable slot; key your `for` items.* Reconciliation routes all DOM placement through three pure primitives (`firstDOMHandle` / `nextDOMAnchor` / `collectDOMRoots`); no new patch type, no JS-driver change.
```

- [ ] **Step 5: Commit**

```bash
git add examples/HelloWorld/Sources/App/App.swift Sources/SwiflowCLI/EmbeddedTemplates.swift CHANGELOG.md
git commit -m "fix(examples): toast back to mid-list — stable child slots make order irrelevant; changelog"
```

---

## Self-Review (completed during planning)

- **Spec coverage:** §3.1 fragment VNode → Task 1; §3.2 builder wrapping → Task 4; §3.3 three primitives + invariants → Task 1 (primitives) + Tasks 2/3 (right-to-left placement, one-rule routing); §3.4 keyed reuse + `keyOf` component fix → Task 3; §4 file-by-file → Tasks 1-4; §5 edge cases → DOMAnchorPrimitives/FragmentChildren tests; §6 testing → Tasks 1-3, 5; §8 example revert → Task 5. The "key your loop items" rule is taught via the CHANGELOG/spec, not a runtime diagnostic (see the note under Task 5 — `swiflowDiagnostic` crashes in DEBUG and unkeyed append loops are legitimate).
- **Placeholder scan:** none — every step has real code/commands/expected output.
- **Type consistency:** `firstDOMHandle` / `nextDOMAnchor(after:)` / `collectDOMRoots` / `isStructural` signatures are identical across Tasks 1-3; `keyOf` overloads and `hasAnyKey` overloads match Task 3 usage; `.fragment([VNode])` shape consistent throughout.
- **Invariant cross-check:** placement always follows `addChild`/`replaceChild`/`insertChild` (so `nextDOMAnchor(after:)` sees correct parent/index), and keyed/indexed placement walks right-to-left (Invariant A) — required for `nextDOMAnchor` to read settled positions.
```
