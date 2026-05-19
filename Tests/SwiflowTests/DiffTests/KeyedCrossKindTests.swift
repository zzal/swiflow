// Tests/SwiflowTests/DiffTests/KeyedCrossKindTests.swift
import Testing
@testable import Swiflow

@Suite("Keyed cross-kind replacement detaches the old DOM node")
@MainActor
struct KeyedCrossKindTests {
    /// Two keyed siblings; the prefix scan hits a key match but the tag
    /// changes (span -> b). Without removeChild, the old <span> would stay
    /// in the live DOM even after its handle is dropped from the driver's
    /// node map.
    @Test("Keyed prefix cross-kind: emits removeChild before destroyNode")
    func keyedPrefixCrossKind() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        let initial = VNode.element(ElementData(tag: "ul", children: [
            .element(ElementData(tag: "span", key: "a")),
            .element(ElementData(tag: "i", key: "b")),
        ]))
        let next = VNode.element(ElementData(tag: "ul", children: [
            // Same key "a" but different tag forces destroy+create.
            .element(ElementData(tag: "b", key: "a")),
            .element(ElementData(tag: "i", key: "b")),
        ]))

        let m = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: next, handles: handles, handlers: handlers)

        // The exact handle numbers depend on allocation order; assert the
        // structural property: every destroyNode(h) in the patches is
        // preceded by a removeChild(_, child: h).
        var pendingDestroys: Set<Int> = []
        for patch in u.patches {
            switch patch {
            case .removeChild(_, let child):
                pendingDestroys.insert(child)
            case .destroyNode(let handle):
                #expect(
                    pendingDestroys.contains(handle),
                    "destroyNode(\(handle)) was not preceded by removeChild"
                )
                pendingDestroys.remove(handle)
            default:
                break
            }
        }
    }

    /// Same hazard in the suffix scan: pin a stable prefix, then have the
    /// suffix scan find a key match with a tag change. Verifies the suffix
    /// branch also emits removeChild ahead of destroyNode.
    @Test("Keyed suffix cross-kind: emits removeChild before destroyNode")
    func keyedSuffixCrossKind() {
        let handles = HandleAllocator()
        let handlers = HandlerRegistry()

        let initial = VNode.element(ElementData(tag: "ul", children: [
            .element(ElementData(tag: "i", key: "a")),
            .element(ElementData(tag: "span", key: "b")),
        ]))
        let next = VNode.element(ElementData(tag: "ul", children: [
            .element(ElementData(tag: "i", key: "a")),
            // Same key "b" but different tag forces destroy+create.
            .element(ElementData(tag: "b", key: "b")),
        ]))

        let m = diff(mounted: nil, next: initial, handles: handles, handlers: handlers)
        let u = diff(mounted: m.newMountTree, next: next, handles: handles, handlers: handlers)

        var pendingDestroys: Set<Int> = []
        for patch in u.patches {
            switch patch {
            case .removeChild(_, let child):
                pendingDestroys.insert(child)
            case .destroyNode(let handle):
                #expect(
                    pendingDestroys.contains(handle),
                    "destroyNode(\(handle)) was not preceded by removeChild"
                )
                pendingDestroys.remove(handle)
            default:
                break
            }
        }
    }
}
