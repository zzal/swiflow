// Tests/SwiflowTests/HMR/HMRSnapshotTests.swift
import Testing
@testable import Swiflow

@Component
private final class HMRSnap_Counter {
    @State var count: Int = 0
    @State var label: String = ""
    var body: VNode { .text("") }
}

@Component
private final class HMRSnap_Toggle {
    @State var on: Bool = false
    var body: VNode { .text("") }
}

@Suite("HMR snapshot walker")
@MainActor
struct HMRSnapshotTests {

    @Test("snapshot produces one row for a single component anchor")
    func snapshotSingleComponent() {
        let counter = HMRSnap_Counter()
        counter.count = 7
        counter.label = "hi"

        // A Component anchor has `component` set, `componentBody` set, and
        // typically no `children` of its own. We approximate the body with
        // a leaf text MountNode.
        let body = MountNode(handle: 2, vnode: .text(""))
        let anchor = MountNode(
            handle: 1,
            vnode: .component(.init(HMRSnap_Counter.self) { HMRSnap_Counter() }),
            component: AnyComponent(counter),
            componentBody: body
        )

        let snapshots = HMRWalker.snapshot(from: anchor)
        #expect(snapshots.count == 1)
        let snap = snapshots[0]
        #expect(snap.path == "")
        #expect(snap.typeName.hasSuffix(".HMRSnap_Counter"))
        #expect(snap.key == nil)
        #expect((snap.state["count"] as? Int) == 7)
        #expect((snap.state["label"] as? String) == "hi")
    }

    @Test("snapshot of a component-free tree returns empty array")
    func snapshotEmptyTree() {
        let tree = MountNode(handle: 1, vnode: .text("plain"))
        let snapshots = HMRWalker.snapshot(from: tree)
        #expect(snapshots.isEmpty)
    }

    @Test("snapshot computes nested paths correctly")
    func snapshotNestedPath() {
        let outer = HMRSnap_Counter()
        outer.count = 1
        let inner = HMRSnap_Toggle()
        inner.on = true

        // Inner component anchor — body is a leaf text node.
        let innerNode = MountNode(
            handle: 3,
            vnode: .text(""),
            component: AnyComponent(inner),
            componentBody: MountNode(handle: 4, vnode: .text(""))
        )

        // Outer's body is an element-like wrapper whose children[0] is the
        // inner anchor. MountNode doesn't differentiate kinds — it just
        // holds children.
        let outerBody = MountNode(
            handle: 2,
            vnode: .text(""),
            children: [innerNode]
        )

        // Outer component anchor.
        let outerNode = MountNode(
            handle: 1,
            vnode: .text(""),
            component: AnyComponent(outer),
            componentBody: outerBody
        )

        let snapshots = HMRWalker.snapshot(from: outerNode)
        #expect(snapshots.count == 2)
        let outerSnap = snapshots.first { $0.typeName.hasSuffix(".HMRSnap_Counter") }
        let innerSnap = snapshots.first { $0.typeName.hasSuffix(".HMRSnap_Toggle") }
        #expect(outerSnap?.path == "")
        #expect(innerSnap?.path == "0")
        #expect((innerSnap?.state["on"] as? Bool) == true)
        #expect((outerSnap?.state["count"] as? Int) == 1)
    }
}
