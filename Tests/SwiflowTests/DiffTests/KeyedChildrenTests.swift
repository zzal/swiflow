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
}
