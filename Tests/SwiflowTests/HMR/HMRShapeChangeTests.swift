import Testing
@testable import Swiflow

@MainActor
@Suite("HMR shape change")
struct HMRShapeChangeTests {

    final class Foo: Component {
        @State var x: Int = 0
        var body: VNode { .text("") }
    }

    final class Bar: Component {
        @State var x: Int = 0
        var body: VNode { .text("") }
    }

    @Test("type-name mismatch at the same path skips restore entirely")
    func typeNameMismatchSkipsRestore() {
        // Snapshot is for Foo, new tree has Bar at the same path.
        let snap = ComponentSnapshot(
            path: "",
            typeName: String(reflecting: Foo.self),
            key: nil,
            state: ["x": 99]
        )
        let index = HMRWalker.indexSnapshots([snap])

        let fresh = Bar()
        HMRWalker.applyRestore(index: index, to: AnyComponent(fresh), at: "")

        #expect(fresh.x == 0)  // declared initial, not 99
    }

    @Test("snapshot with unmatched path is dropped silently")
    func unmatchedPathDropped() {
        let snap = ComponentSnapshot(
            path: "5",  // doesn't match where we mount
            typeName: String(reflecting: Foo.self),
            key: nil,
            state: ["x": 17]
        )
        let index = HMRWalker.indexSnapshots([snap])

        let fresh = Foo()
        HMRWalker.applyRestore(index: index, to: AnyComponent(fresh), at: "")

        #expect(fresh.x == 0)  // declared initial, not 17
    }

    // EXTRA TEST — addresses Task B reviewer's "Important" finding.
    // Walker logic at HMR.swift puts a Component whose componentBody
    // is itself a Component at the SAME path. Pin that invariant down
    // so a future refactor doesn't silently break it.
    @Test("chained components: outer.componentBody = inner anchor → both emit at path ''")
    func chainedComponentsSamePath() {
        final class Outer: Component {
            @State var n: Int = 0
            var body: VNode { .text("") }
        }
        final class Inner: Component {
            @State var m: Int = 0
            var body: VNode { .text("") }
        }

        let outer = Outer()
        outer.n = 1
        let inner = Inner()
        inner.m = 9

        // Outer's componentBody IS the inner Component anchor directly
        // (no element wrapper). Each anchor has its own leaf body to
        // satisfy MountNode shape requirements.
        let innerNode = MountNode(
            handle: 3,
            vnode: .text(""),
            component: AnyComponent(inner),
            componentBody: MountNode(handle: 4, vnode: .text(""))
        )
        let outerNode = MountNode(
            handle: 1,
            vnode: .text(""),
            component: AnyComponent(outer),
            componentBody: innerNode
        )

        let snaps = HMRWalker.snapshot(from: outerNode)
        #expect(snaps.count == 2)
        // Both at path "" — componentBody is the same path as its parent.
        let allPathsEmpty = snaps.allSatisfy { $0.path == "" }
        #expect(allPathsEmpty == true)
        // Distinguishable by typeName.
        let outerSnap = snaps.first { $0.typeName.hasSuffix(".Outer") }
        let innerSnap = snaps.first { $0.typeName.hasSuffix(".Inner") }
        #expect((outerSnap?.state["n"] as? Int) == 1)
        #expect((innerSnap?.state["m"] as? Int) == 9)
    }
}
