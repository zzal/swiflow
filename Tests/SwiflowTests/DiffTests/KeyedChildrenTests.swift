// Tests/SwiflowTests/DiffTests/KeyedChildrenTests.swift
import Testing
@testable import Swiflow

@Suite("Diff — children (keyed)")
struct KeyedChildrenTests {
    /// Builds `<ul><li key=K>K</li>...</ul>` for the given keys.
    private func ul(_ keys: [String]) -> VNode {
        .element(ElementData(
            tag: "ul",
            children: keys.map {
                .element(ElementData(tag: "li", key: $0, children: [.text($0)]))
            }
        ))
    }

    private func diffPair(_ a: VNode, _ b: VNode) -> DiffResult {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()
        let m = diff(mounted: nil, next: a, handles: handles, handlers: handlers)
        return diff(mounted: m.newMountTree, next: b, handles: handles, handlers: handlers)
    }

    /// Returns only the structural opcodes (insertBefore, removeChild,
    /// destroyNode, appendChild, createElement, createText). Ignores
    /// attribute/property/style/handler/text patches, which can drift.
    private func structuralPatches(_ patches: [Patch]) -> [Patch] {
        patches.filter { patch in
            switch patch {
            case .insertBefore, .removeChild, .destroyNode,
                 .appendChild, .createElement, .createText:
                return true
            default:
                return false
            }
        }
    }

    @Test("Reordering keyed items emits only insertBefore patches (no destroys)")
    func reorderEmitsInsertBefore() {
        let u = diffPair(ul(["a", "b", "c"]), ul(["c", "a", "b"]))
        // Existing handles: ul=0, li-a=1, "a"-text=2, li-b=3, "b"=4, li-c=5, "c"=6.
        // c was last, now first → insertBefore c before a.
        let s = structuralPatches(u.patches)
        #expect(s == [.insertBefore(parent: 0, child: 5, beforeChild: 1)])
    }

    @Test("Removing a keyed item emits removeChild + destroyNode for that key only")
    func removeKeyedItem() {
        let u = diffPair(ul(["a", "b", "c"]), ul(["a", "c"]))
        // Drop "b" (li handle 3, text handle 4).
        let s = structuralPatches(u.patches)
        #expect(s == [
            .removeChild(parent: 0, child: 3),
            .destroyNode(handle: 4),
            .destroyNode(handle: 3),
        ])
    }

    @Test("Inserting a keyed item in the middle emits insertBefore for the new node")
    func insertKeyedItemMiddle() {
        let u = diffPair(ul(["a", "c"]), ul(["a", "b", "c"]))
        // New li for "b". After mount, existing handles: ul=0, li-a=1, "a"=2,
        // li-c=3, "c"=4. New li-b uses handles 5,6 (or two fresh handles).
        let s = structuralPatches(u.patches)
        // Find the createElement (for the new li) and the createText (for "b").
        guard let firstCreate = s.first, case .createElement(let liHandle, "li") = firstCreate else {
            Issue.record("expected first structural patch to be createElement(li)")
            return
        }
        // Then a createText for "b".
        let textHandle = liHandle + 1
        #expect(s == [
            .createElement(handle: liHandle, tag: "li"),
            .createText(handle: textHandle, text: "b"),
            .appendChild(parent: liHandle, child: textHandle),
            .insertBefore(parent: 0, child: liHandle, beforeChild: 3),
        ])
    }

    @Test("Full reverse [a,b,c] → [c,b,a] emits two insertBefore patches")
    func fullReverse() {
        let u = diffPair(ul(["a", "b", "c"]), ul(["c", "b", "a"]))
        let s = structuralPatches(u.patches)
        // li-a=1, li-b=3, li-c=5.
        // After moving c to front: [c,a,b]. Then move b before a → [c,b,a].
        // That's two insertBefores; concrete ordering depends on algorithm
        // direction. Both of these are acceptable; assert on count + content.
        #expect(s.count == 2)
        #expect(s.allSatisfy {
            if case .insertBefore = $0 { return true } else { return false }
        })
    }

    @Test("Swap of adjacent keyed items emits one insertBefore")
    func swapAdjacent() {
        let u = diffPair(ul(["a", "b"]), ul(["b", "a"]))
        let s = structuralPatches(u.patches)
        // li-a=1, li-b=3. Move b before a → insertBefore(0, 3, 1).
        #expect(s == [.insertBefore(parent: 0, child: 3, beforeChild: 1)])
    }

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
        //   2. e (a fresh key) gets a createElement + a placement patch
        //   3. d gets at most one move (the LIS will pick either b or d as the
        //      stable point — the implementation may legitimately move either b
        //      or d; we don't pin which).
        //   4. Every destroyNode(h) is preceded by removeChild(_, child: h).
        //   5. Mounted children after the diff: exactly 3, with keys d, e, b in
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
        // a (handle 1) and c (handle 3) were the destroyed keys; assert by
        // exact handle set. (Initial allocation: 0=ul, 1=a, 2=b, 3=c, 4=d;
        // e gets a fresh handle in the second diff pass.)
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
}
