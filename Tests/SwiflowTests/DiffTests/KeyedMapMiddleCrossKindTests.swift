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

        // Construct the lists so neither prefix nor suffix matches at the
        // ends — the cross-kind pair must land inside the map-based middle
        // loop, not the prefix/suffix scans (those were fixed in Phase 2b.1).
        let initial = VNode.element(ElementData(tag: "ul", children: [
            .element(ElementData(tag: "span", key: "p")),
            .element(ElementData(tag: "span", key: "m")),
            .element(ElementData(tag: "li", key: "s")),
        ]))
        let next = VNode.element(ElementData(tag: "ul", children: [
            .element(ElementData(tag: "li", key: "q")),
            .element(ElementData(tag: "b", key: "m")),   // tag change in middle
            .element(ElementData(tag: "span", key: "t")),
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
        var destroyCount = 0
        for patch in u.patches {
            if case .destroyNode = patch { destroyCount += 1 }
        }
        #expect(destroyCount > 0, "expected at least one destroyNode for the replaced <span key=\"m\">")

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
