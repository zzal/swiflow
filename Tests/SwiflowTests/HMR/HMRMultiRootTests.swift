// Tests/SwiflowTests/HMR/HMRMultiRootTests.swift
import Testing
@testable import Swiflow

@MainActor @Component
private final class HMRMulti_Counter {
    @State var count: Int = 0
    var body: VNode { .text("") }
}

@MainActor @Component
private final class HMRMulti_Toggle {
    @State var on: Bool = false
    var body: VNode { .text("") }
}

@Suite("HMR multi-root snapshot aggregation")
@MainActor
struct HMRMultiRootTests {

    @Test("snapshot(fromRoots:) concatenates every root's snapshot, dropping none")
    func snapshotFromRootsConcatenatesPerRootSnapshots() {
        // Tree A: a single Counter anchor (mirrors HMRSnapshotTests setup).
        let counterA = HMRMulti_Counter()
        counterA.count = 3
        let bodyA = MountNode(handle: 10, vnode: .text(""))
        let treeA = MountNode(
            handle: 11,
            vnode: .component(.init(HMRMulti_Counter.self) { HMRMulti_Counter() }),
            component: AnyComponent(counterA),
            componentBody: bodyA
        )

        // Tree B: a single Toggle anchor at a different root.
        let toggleB = HMRMulti_Toggle()
        toggleB.on = true
        let bodyB = MountNode(handle: 20, vnode: .text(""))
        let treeB = MountNode(
            handle: 21,
            vnode: .component(.init(HMRMulti_Toggle.self) { HMRMulti_Toggle() }),
            component: AnyComponent(toggleB),
            componentBody: bodyB
        )

        let individual = HMRWalker.snapshot(from: treeA) + HMRWalker.snapshot(from: treeB)
        let aggregated = HMRWalker.snapshot(fromRoots: [treeA, treeB])

        #expect(aggregated.count == individual.count)
        #expect(aggregated.map(\.path) == individual.map(\.path))
        #expect(aggregated.count == 2)   // both roots contributed

        // State values survive the walk — not just the structural paths. A
        // bug that dropped one root, or discarded state maps while keeping
        // paths, would fail here.
        #expect(aggregated[0].state["count"] as? Int == 3)
        #expect(aggregated[1].state["on"] as? Bool == true)
    }

    @Test("snapshot(fromRoots:) of no roots is empty")
    func snapshotFromEmptyRootsIsEmpty() {
        #expect(HMRWalker.snapshot(fromRoots: []).isEmpty)
    }
}
