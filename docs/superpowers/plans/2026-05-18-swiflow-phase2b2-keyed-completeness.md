# Swiflow Phase 2b.2 — Keyed Diff Map-Middle Completeness

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the residual keyed-diff `removeChild` correctness gap that the Phase 2b.1 final cross-task review surfaced (the map-middle has the same bug Phase 2b.1 fixed for prefix/suffix), add the previously-deferred map-middle LIS coverage test that would have caught it, and pick up the three trivial follow-ups noted in the final review.

**Architecture:** Phase 2b.1 fixed the indexed cross-kind replace bug and the keyed prefix/suffix scan instances of the same root cause. It did not touch the keyed map-middle reuse loop in `diffChildrenKeyed`. The map-middle has the *identical* bug, with one extra twist: when `update()` returns a fresh node, the position is wrongly treated as "reused" by the LIS/placement loop, so the new DOM node is never attached at all. This plan applies the same `patches.insert(.removeChild(...), at: updatePatchStart)` fix AND sets `newToOldIndex[i] = -1` so the placement loop treats the slot as a fresh mount.

**Tech Stack:** Swift 6 strict concurrency, Swift Testing. No new dependencies.

---

## File Structure (touched by this plan)

**Phase 1 — VDOM Brain:**
- Modify: `Sources/Swiflow/Diff/KeyedChildrenDiff.swift` — map-middle cross-kind fix; `#if DEBUG` alignment for the old-side duplicate-key assertion

**Tests:**
- Add: `Tests/SwiflowTests/DiffTests/KeyedMapMiddleCrossKindTests.swift` — structural invariant test for the map-middle bug
- Modify: `Tests/SwiflowTests/DiffTests/KeyedChildrenTests.swift` — Phase 1 I3 LIS coverage (`[a,b,c,d] → [d,e,b]`)
- Modify: `Tests/SwiflowTests/MountTreeTests.swift` — Phase 1 I5 keyed empty↔populated `MountTreeConsistencyTests` arms
- Modify: `Tests/SwiflowTests/PatchTests.swift` — add `setRawHTML` to `mutationEquality`

---

## Task 1: Map-middle cross-kind correctness fix

**Why:** Two-part bug in `Sources/Swiflow/Diff/KeyedChildrenDiff.swift` map-middle reuse loop (lines ~195-220):

1. When `update()` returns `updated !== reused` (cross-kind: same key, different tag/kind), the `destroy()` call inside `update()` emits `destroyNode(reused.handle)` — but no `removeChild` is inserted ahead of it. The old DOM node stays attached to its parent. Same bug Phase 2b.1 Task 2 fixed in the prefix/suffix scans.

2. The position's `newToOldIndex[i]` is set to `oldIndex` (treating the slot as reused), but the actual DOM operation is a fresh mount (`mount()` returned a new handle). The downstream LIS step decides "reused, in LIS, no patch needed" — so the new node is never `insertBefore`/`appendChild`'d into the DOM. The old node stays attached AND the new node never appears.

Worst-case visible: a keyed item that changes kind mid-list (e.g. `(m, span) → (m, b)` where `m` is in the map-middle) leaves the old span visible and the new b element completely missing from the DOM.

The fix mirrors the prefix/suffix Phase 2b.1 pattern + sets `newToOldIndex[i] = -1` so the placement loop treats the slot as a fresh mount.

**Files:**
- Modify: `Sources/Swiflow/Diff/KeyedChildrenDiff.swift` (lines ~195-220, the reuse-loop branch)
- Add: `Tests/SwiflowTests/DiffTests/KeyedMapMiddleCrossKindTests.swift`

- [ ] **Step 1: Write the failing structural invariant test**

Create `Tests/SwiflowTests/DiffTests/KeyedMapMiddleCrossKindTests.swift`:

```swift
// Tests/SwiflowTests/DiffTests/KeyedMapMiddleCrossKindTests.swift
import Testing
@testable import Swiflow

@Suite("Keyed map-middle cross-kind replacement")
struct KeyedMapMiddleCrossKindTests {
    /// A keyed list where the prefix and suffix are stable, the middle has
    /// one position whose key matches but tag changes. The map-based reuse
    /// loop must:
    ///   - Emit removeChild BEFORE destroyNode for the old DOM node
    ///   - Treat the slot as a fresh mount in the placement walk so the new
    ///     element actually appears in the DOM
    @Test("Map-middle cross-kind: removeChild + destroyNode + create + place")
    func mapMiddleCrossKindAttachesNew() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        let initial = VNode.element(ElementData(tag: "ul", children: [
            .element(ElementData(tag: "li", key: "a")),
            .element(ElementData(tag: "span", key: "m")),
            .element(ElementData(tag: "li", key: "z")),
        ]))
        let next = VNode.element(ElementData(tag: "ul", children: [
            .element(ElementData(tag: "li", key: "a")),
            .element(ElementData(tag: "b", key: "m")),  // tag change in middle
            .element(ElementData(tag: "li", key: "z")),
        ]))

        let m = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: next, handles: handles, handlers: handlers)

        // Invariant 1: every destroyNode(h) is preceded by removeChild(_, child: h)
        var pendingDestroys: Set<Int> = []
        for patch in u.patches {
            switch patch {
            case .removeChild(_, let child):
                pendingDestroys.insert(child)
            case .destroyNode(let handle):
                #expect(pendingDestroys.contains(handle),
                        "destroyNode(\(handle)) was not preceded by removeChild")
                pendingDestroys.remove(handle)
            default:
                break
            }
        }

        // Invariant 2: a createElement for the new tag exists AND has a
        // placement patch (appendChild or insertBefore) targeting the same
        // handle. The replacement node MUST be attached to the DOM.
        var freshElementHandles: Set<Int> = []
        for patch in u.patches {
            if case .createElement(let h, let tag) = patch, tag == "b" {
                freshElementHandles.insert(h)
            }
        }
        #expect(!freshElementHandles.isEmpty,
                "expected at least one createElement(_, tag: \"b\") for the new <b key=\"m\">")

        var placedHandles: Set<Int> = []
        for patch in u.patches {
            switch patch {
            case .appendChild(_, let child):
                placedHandles.insert(child)
            case .insertBefore(_, let child, _):
                placedHandles.insert(child)
            default:
                break
            }
        }
        for h in freshElementHandles {
            #expect(placedHandles.contains(h),
                    "freshly created <b> (handle \(h)) was never placed into the DOM")
        }
    }
}
```

- [ ] **Step 2: Run the test — verify it fails**

```bash
swift test --filter KeyedMapMiddleCrossKindTests 2>&1 | tail -30
```

Expected: BOTH invariants fail —
- The destroyNode for the old span has no preceding removeChild
- The fresh `<b>` createElement has no corresponding append/insertBefore (the LIS treats it as "reused in correct position")

- [ ] **Step 3: Fix `KeyedChildrenDiff.swift` map-middle reuse loop**

In `Sources/Swiflow/Diff/KeyedChildrenDiff.swift`, locate the reuse loop (around lines 195-220). The current shape:

```swift
for i in 0..<newMiddleCount {
    let newChild = newChildren[newStart + i]
    let key = keyOf(newChild)
    if let oldIndex = keyToOldIndex.removeValue(forKey: key) {
        let reused = mounted.children[oldIndex]
        let updated = update(
            mounted: reused,
            next: newChild,
            into: &patches,
            handles: handles,
            handlers: handlers
        )
        newSlice[i] = updated
        newToOldIndex[i] = oldIndex
        reusedOldIndices.insert(oldIndex)
    } else {
        // ... fresh mount branch unchanged
    }
}
```

Replace the `if let oldIndex = ...` block with:

```swift
if let oldIndex = keyToOldIndex.removeValue(forKey: key) {
    let reused = mounted.children[oldIndex]
    let updatePatchStart = patches.count
    let updated = update(
        mounted: reused,
        next: newChild,
        into: &patches,
        handles: handles,
        handlers: handlers
    )
    if updated !== reused {
        // Cross-kind replacement: same key but different tag/kind. update()
        // destroyed the old subtree (destroyNode patches already in
        // `patches`) but did NOT detach the old DOM node from its parent.
        // Insert removeChild ahead of the destroy patches.
        patches.insert(
            .removeChild(parent: mounted.handle, child: reused.handle),
            at: updatePatchStart
        )
        newSlice[i] = updated
        // Critical: leave newToOldIndex[i] == -1 so the LIS / placement
        // loop below treats this slot as a fresh mount. The new node's
        // handle was never attached anywhere — it MUST be placed via
        // insertBefore/appendChild like any other fresh mount. Marking it
        // as "reused" (newToOldIndex[i] = oldIndex) would let the LIS
        // decide "in correct position, no patch" and the new node would
        // never appear in the DOM.
        reusedOldIndices.insert(oldIndex)
    } else {
        newSlice[i] = updated
        newToOldIndex[i] = oldIndex
        reusedOldIndices.insert(oldIndex)
    }
}
```

Note: `newToOldIndex` is initialized to `-1` everywhere (line ~191), so leaving it untouched in the cross-kind branch keeps it at `-1` — which is exactly the "fresh mount" sentinel the placement loop already handles. `reusedOldIndices.insert(oldIndex)` is still called so step 7 (destroy non-reused leftovers) doesn't double-destroy.

- [ ] **Step 4: Run the test — verify it passes**

```bash
swift test --filter KeyedMapMiddleCrossKindTests 2>&1 | tail -10
```

Expected: both invariants pass.

- [ ] **Step 5: Run the full diff test suite — no regression**

```bash
swift test --filter DiffTests 2>&1 | tail -10
```

Expected: 0 failures across indexed, keyed, attribute, property, style, handler, text, raw-HTML, tag-replace, and the new map-middle test.

- [ ] **Step 6: Run the full test suite**

```bash
swift test 2>&1 | tail -10
```

Expected: 0 failures. Test count grows by +1 (the new test).

- [ ] **Step 7: Commit**

```bash
git add Sources/Swiflow/Diff/KeyedChildrenDiff.swift Tests/SwiflowTests/DiffTests/KeyedMapMiddleCrossKindTests.swift
git commit -m "$(cat <<'COMMIT_EOF'
fix(diff): close map-middle cross-kind gap left by Phase 2b.1

Phase 2b.1 Task 2 fixed the missing removeChild-before-destroyNode bug
in the keyed prefix/suffix scans, but the cross-task review surfaced the
same root cause in the map-middle reuse loop — plus a second, worse,
symptom: when the key-matched pair triggers a cross-kind replace, the
position was being marked as reused (newToOldIndex[i] = oldIndex), so
the LIS placement walk decided "in correct order, no patch" and the
freshly mounted node was never attached. Old node stayed visible, new
node never appeared.

The fix inserts removeChild ahead of the destroy patches (mirroring the
prefix/suffix fix) AND leaves newToOldIndex[i] at -1 so the placement
walk treats the slot as a fresh mount. reusedOldIndices.insert is still
called so step 7 doesn't double-destroy the same old child.

A new KeyedMapMiddleCrossKindTests asserts both invariants:
  - every destroyNode(h) preceded by removeChild(_, child: h)
  - every freshly created element has a placement patch targeting its
    handle

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
COMMIT_EOF
)"
```

---

## Task 2: Keyed map-middle LIS coverage test (Phase 1 I3)

**Why:** The Phase 1 exhaustive review's deferred I3 finding: no test exercises the map-based keyed middle (LIS path) with simultaneous insert + delete + LIS-stable reuse + LIS-moved reuse. The suggested case `[a,b,c,d] → [d,e,b]` covers all four code branches inside the placement walk:
- `a` and `c` are removed (step 7 destroys non-reused leftovers)
- `b` is kept and in the LIS (`newToOldIndex` increasing → stable, no patch)
- `d` is kept but out of LIS (must move via insertBefore)
- `e` is a fresh mount (must insert)

After Task 1 lands, the map-middle is correct for the cross-kind case. This test now also locks in the LIS arithmetic, anchor selection, and step-7 destroy behavior. Future map-middle regressions surface here instead of via DOM corruption in production.

**Files:**
- Modify: `Tests/SwiflowTests/DiffTests/KeyedChildrenTests.swift`

- [ ] **Step 1: Add the LIS coverage test**

In `Tests/SwiflowTests/DiffTests/KeyedChildrenTests.swift`, add inside the existing `@Suite`:

```swift
@Test("Map-middle LIS: simultaneous insert + delete + stable + move")
func mapMiddleLISCoverage() {
    // [a, b, c, d] → [d, e, b]
    //   - a, c: removed (step 7 destroys non-reused leftovers)
    //   - b: kept, in LIS (newToOldIndex sequence implies "in order")
    //   - d: kept but out of LIS → must move (insertBefore)
    //   - e: fresh mount (insertBefore against the next sibling)
    let handles = HandleAllocator()
    let handlers = HandlerRegistry()

    let initial = VNode.element(ElementData(tag: "ul", children: [
        .element(ElementData(tag: "li", key: "a")),
        .element(ElementData(tag: "li", key: "b")),
        .element(ElementData(tag: "li", key: "c")),
        .element(ElementData(tag: "li", key: "d")),
    ]))
    let next = VNode.element(ElementData(tag: "ul", children: [
        .element(ElementData(tag: "li", key: "d")),
        .element(ElementData(tag: "li", key: "e")),
        .element(ElementData(tag: "li", key: "b")),
    ]))

    let m = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
    let u = diff(mounted: m.newMountTree, next: next, handles: handles, handlers: handlers)

    // Structural invariants:
    //   1. a and c are removed from the DOM (one removeChild + destroyNode each)
    //   2. e (a fresh tag) gets a createElement + a placement patch
    //   3. d gets at most one move (the LIS will pick either b or d as the
    //      stable point — Vue 3 / Inferno LIS picks the longer increasing
    //      subsequence, which here is just one element either way; the
    //      implementation may legitimately move either b or d).
    //   4. Every destroyNode(h) is preceded by removeChild(_, child: h).
    //   5. mounted children after the diff: exactly 3, with keys d, e, b in
    //      that order.

    // (1) and (4): structural invariant walk.
    var pendingDestroys: Set<Int> = []
    var destroyedHandles: Set<Int> = []
    for patch in u.patches {
        switch patch {
        case .removeChild(_, let child):
            pendingDestroys.insert(child)
        case .destroyNode(let handle):
            #expect(pendingDestroys.contains(handle),
                    "destroyNode(\(handle)) was not preceded by removeChild")
            pendingDestroys.remove(handle)
            destroyedHandles.insert(handle)
        default:
            break
        }
    }
    // a (handle 1) and c (handle 3) were the destroyed keys; assert by count.
    // (Handles 0=ul, 1=a, 2=b, 3=c, 4=d; e gets a fresh handle in the diff.)
    #expect(destroyedHandles == [1, 3], "expected exactly a (1) and c (3) destroyed")

    // (2): fresh e creation + placement.
    var freshElementCount = 0
    var freshHandles: Set<Int> = []
    for patch in u.patches {
        if case .createElement(let h, let tag) = patch, tag == "li" {
            // h > 4 means freshly allocated for e (initial used 0..4).
            if h > 4 {
                freshElementCount += 1
                freshHandles.insert(h)
            }
        }
    }
    #expect(freshElementCount == 1, "expected exactly one fresh createElement for e")
    var placedHandles: Set<Int> = []
    for patch in u.patches {
        switch patch {
        case .appendChild(_, let child), .insertBefore(_, let child, _):
            placedHandles.insert(child)
        default:
            break
        }
    }
    for h in freshHandles {
        #expect(placedHandles.contains(h), "fresh e (handle \(h)) not placed")
    }

    // (5): final mount tree shape.
    let finalKeys: [String] = u.newMountTree.children.map { keyOf($0) }
    #expect(finalKeys == ["d", "e", "b"])
}
```

- [ ] **Step 2: Run the test — confirm it passes after Task 1's fix**

```bash
swift test --filter KeyedChildrenTests 2>&1 | tail -10
```

Expected: pass. (If it fails, debug the LIS / placement logic — the existing prefix/suffix tests should still pass, isolating the issue to the map-middle path.)

- [ ] **Step 3: Run the full test suite**

```bash
swift test 2>&1 | tail -10
```

Expected: 0 failures. Test count grows by +1.

- [ ] **Step 4: Commit**

```bash
git add Tests/SwiflowTests/DiffTests/KeyedChildrenTests.swift
git commit -m "$(cat <<'COMMIT_EOF'
test(diff): keyed map-middle LIS coverage (Phase 1 I3 followup)

Adds the [a,b,c,d] → [d,e,b] regression test the Phase 1 exhaustive
review flagged as missing. Exercises all four placement-loop branches
in a single diff: pure removes (a, c), LIS-stable reuse (b), out-of-LIS
move (d), fresh mount (e). Pairs naturally with the map-middle
cross-kind fix landed in the previous commit — together they lock in
the map-middle's correctness surface.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
COMMIT_EOF
)"
```

---

## Task 3: Trivial follow-ups bundle

**Why:** Three small items the Phase 2b.1 final review noted as worth folding into a single cleanup commit:

1. `Tests/SwiflowTests/PatchTests.swift` `mutationEquality` does not include `setRawHTML`. Functionally redundant (other tests exercise `==`) but a real consistency gap.
2. `Sources/Swiflow/Diff/KeyedChildrenDiff.swift` duplicate-key detection is asymmetric: the new-side assertion is wrapped in `#if DEBUG` but the old-side uses a bare `assert`. (Phase 1 I2.) Both vanish in Release builds, but the asymmetry is misleading — align them.
3. `Tests/SwiflowTests/MountTreeTests.swift` `MountTreeConsistencyTests` does not cover keyed empty↔populated transitions. (Phase 1 I5.) Add two short arms that diff `[]→[keyed children]` and `[keyed children]→[]`.

**Files:**
- Modify: `Tests/SwiflowTests/PatchTests.swift`
- Modify: `Sources/Swiflow/Diff/KeyedChildrenDiff.swift`
- Modify: `Tests/SwiflowTests/MountTreeTests.swift`

- [ ] **Step 1: Add `setRawHTML` to `PatchTests.mutationEquality`**

In `Tests/SwiflowTests/PatchTests.swift`, in the `mutationEquality` function (around line 34), add (placed next to the other text-bearing mutations like `setText`):

```swift
#expect(Patch.setRawHTML(handle: 1, html: "<b/>")
     == Patch.setRawHTML(handle: 1, html: "<b/>"))
```

- [ ] **Step 2: Align the old-side duplicate-key detection in `KeyedChildrenDiff.swift`**

In `Sources/Swiflow/Diff/KeyedChildrenDiff.swift`, the old-side duplicate-key check (around lines 162-172) uses a bare `assert(...)`. The new-side check (lines 176-186) is wrapped in `#if DEBUG`. Wrap the old-side check the same way:

```swift
// Bucket old-side middle children by key (used by the reuse loop below).
// Detect duplicate keys defensively in debug builds — same gating as the
// new-side check at lines ~176-186 so both sites have identical behavior
// across configurations.
var keyToOldIndex: [String: Int] = [:]
#if DEBUG
for i in oldStart...oldEnd {
    let key = keyOf(mounted.children[i])
    assert(
        keyToOldIndex[key] == nil,
        "Swiflow: duplicate key '\(key)' in keyed children list. " +
        "Each child's `.key(_:)` must be unique within its parent — " +
        "the diff will silently destroy one of the duplicates."
    )
    keyToOldIndex[key] = i
}
#else
for i in oldStart...oldEnd {
    keyToOldIndex[keyOf(mounted.children[i])] = i
}
#endif
```

(The non-DEBUG branch keeps the bucketing — it's load-bearing for the reuse loop — but skips the assertion. The DEBUG branch keeps the diagnostic.)

- [ ] **Step 3: Add keyed empty↔populated `MountTreeConsistencyTests` arms**

In `Tests/SwiflowTests/MountTreeTests.swift`, find the `MountTreeConsistencyTests` suite. Add two arms next to the existing keyed-reorder test:

```swift
@Test("Mount tree consistency: keyed empty → populated")
func keyedEmptyToPopulated() {
    let handles = HandleAllocator()
    let handlers = HandlerRegistry()
    let initial = VNode.element(ElementData(tag: "ul", children: []))
    let next = VNode.element(ElementData(tag: "ul", children: [
        .element(ElementData(tag: "li", key: "a")),
        .element(ElementData(tag: "li", key: "b")),
    ]))
    let m = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
    let u = diff(mounted: m.newMountTree, next: next, handles: handles, handlers: handlers)
    // Mount tree structurally equals the new VNode (modulo handles).
    let finalKeys: [String] = u.newMountTree.children.map { keyOf($0) }
    #expect(finalKeys == ["a", "b"])
    // Each child's parent pointer references the root.
    for child in u.newMountTree.children {
        #expect(child.parent === u.newMountTree)
    }
}

@Test("Mount tree consistency: keyed populated → empty")
func keyedPopulatedToEmpty() {
    let handles = HandleAllocator()
    let handlers = HandlerRegistry()
    let initial = VNode.element(ElementData(tag: "ul", children: [
        .element(ElementData(tag: "li", key: "a")),
        .element(ElementData(tag: "li", key: "b")),
    ]))
    let next = VNode.element(ElementData(tag: "ul", children: []))
    let m = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
    let u = diff(mounted: m.newMountTree, next: next, handles: handles, handlers: handlers)
    #expect(u.newMountTree.children.isEmpty)
}
```

(`keyOf` is internal to the Swiflow module — these tests need `@testable import Swiflow` to call it, which `MountTreeTests.swift` already does.)

- [ ] **Step 4: Run the full test suite**

```bash
swift test 2>&1 | tail -10
```

Expected: 0 failures. Test count grows by +3 (1 PatchTests + 2 MountTreeConsistencyTests). Combined with Tasks 1 and 2, total delta is +5 (171 → 176).

- [ ] **Step 5: Commit**

```bash
git add Tests/SwiflowTests/PatchTests.swift Sources/Swiflow/Diff/KeyedChildrenDiff.swift Tests/SwiflowTests/MountTreeTests.swift
git commit -m "$(cat <<'COMMIT_EOF'
test+chore: trio of small followups from Phase 2b.1 final review

- PatchTests.mutationEquality covers setRawHTML (was the only mutation
  opcode missing from the equality block).
- KeyedChildrenDiff's old-side duplicate-key detection now wrapped in
  #if DEBUG so it matches the new-side check exactly (was a bare assert
  before — same Release-build effect, but the visible asymmetry was
  misleading). Phase 1 I2.
- MountTreeConsistencyTests now covers keyed empty↔populated transitions
  — the keyed empty↔populated paths exercise mounted.removeChild(at:)
  and mounted.insertChild(:at:) under real diff conditions, which the
  prior coverage missed. Phase 1 I5.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
COMMIT_EOF
)"
```

---

## Verification (after all 3 tasks)

```bash
swift test 2>&1 | tail -10
```

Expected: 176 tests, 0 failures (171 baseline + 5 new: KeyedMapMiddleCrossKind + mapMiddleLISCoverage + setRawHTML equality + 2 MountTreeConsistency arms).

Cumulative diff:

```bash
git log --oneline cbb87c0..HEAD     # 3 commits
git diff cbb87c0..HEAD --stat
```

Smoke check (no SDK needed):

```bash
swift test --filter "KeyedMapMiddleCrossKindTests|KeyedChildrenTests|MountTreeTests|PatchTests" 2>&1 | tail -20
```

---

## Out of Scope

These remain deferred (call out if anything new surfaces):
- Phase 2a #3 — Stand up `Tests/SwiflowWebTests/` (its own plan)
- Phase 2a #4 — Verify JavaScriptKit 0.53 `.object(closure)` callable contract
- Phase 2a #5 — Renderer force-unwraps + diagnostic surfacing (Phase 2c)
- Phase 2a #6 — Document handler re-registration leak in Hello World (Phase 3 fixes root cause)
- Phase 2b cosmetics — `rawAppSwift` path comment, `DriverEmbedder` public access, `WasmSDKProbe` stderr swallow
- Phase 4 — `--swiflow-source` UX flip to git URL after publish
- CI Linux WASM SDK fallback — contingent on first GitHub Actions run
